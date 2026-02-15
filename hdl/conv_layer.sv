module conv_layer #(
    parameter WEIGHT_DEPTH    = 4096,
    parameter MAX_CI_GROUPS   = 128      // max supported C_in/8
)(
    input  logic        clk,
    input  logic        rst,

    // Layer Configuration (stable for entire layer)
    input  logic [15:0] cfg_img_width,
    input  logic [15:0] cfg_img_height,
    input  logic [15:0] cfg_in_channels,
    input  logic [9:0]  cfg_ci_groups,      // C_in  / 8
    input  logic [9:0]  cfg_co_groups,      // C_out / 8
    input  logic        cfg_use_relu,
    input  logic        cfg_use_maxpool,
    input  logic [31:0] cfg_quant_M,
    input  logic [4:0]  cfg_quant_n,

    // Weight Loading Port
    input  logic        weight_wr_mode,
    input  logic        weight_wr_valid,
    input  logic [71:0] weight_wr_data,
    output logic        weight_wr_done,

    // Bias Loading Port
    input  logic        bias_wr_mode,
    input  logic        bias_wr_valid,
    input  logic [31:0] bias_wr_data,
    output logic        bias_wr_done,

    // Pixel Input Stream (AXI-Stream style)
    input  logic [63:0] pixel_in,
    input  logic        pixel_valid,
    output logic        pixel_ready,        // backpressure

    // Output Stream
    output logic [63:0] data_out,
    output logic        data_valid_out,

    // Status
    output logic        layer_done
);

// ═════════════════════════════════════════════
//  Bias Register File  (up to 128 groups × 8 = 1024 biases)
// ═════════════════════════════════════════════
logic [31:0] bias_mem [0:1023];
logic [9:0]  bias_wr_addr;
logic [31:0] biases [0:7];
logic [9:0]  bias_group_sel;           // set by alignment pipeline

always_ff @(posedge clk) begin
    if (rst) begin
        bias_wr_addr <= '0;
        bias_wr_done <= 1'b0;
    end else if (bias_wr_mode) begin
        bias_wr_done <= 1'b0;
        if (bias_wr_valid) begin
            bias_mem[bias_wr_addr] <= bias_wr_data;
            if (bias_wr_addr == 10'({cfg_co_groups, 3'b0} - 13'd1)) begin
                bias_wr_addr <= '0;
                bias_wr_done <= 1'b1;
            end else begin
                bias_wr_addr <= bias_wr_addr + 1;
            end
        end
    end else begin
        bias_wr_addr <= '0;
        bias_wr_done <= 1'b0;
    end
end

always_comb begin
    for (int i = 0; i < 8; i++)
        biases[i] = bias_mem[{bias_group_sel[6:0], 3'(i)}];
end

// ═════════════════════════════════════════════
//  Kernel Window Generator
// ═════════════════════════════════════════════
logic [63:0] window [0:2][0:2];
logic        window_valid;
logic        kw_data_valid;

assign kw_data_valid = pixel_valid && pixel_ready;

kernelWindow KernelWindow (
    .clk         (clk),
    .rst         (rst),
    .data_valid  (kw_data_valid),
    .in_channels (cfg_in_channels),
    .img_width   (cfg_img_width),
    .pixel_in    (pixel_in),
    .window      (window),
    .dout_valid  (window_valid)
);

// ═════════════════════════════════════════════
//  Weight Manager
// ═════════════════════════════════════════════
logic [575:0] weights [0:7];
logic         weights_ready;
logic         weights_read_complete;
logic         fsm_read_en;

weight_manager #(
    .DEPTH (WEIGHT_DEPTH)
) WeightManager (
    .clk            (clk),
    .rst            (rst),
    .write_mode     (weight_wr_mode),
    .data_valid     (weight_wr_valid),
    .data_in        (weight_wr_data),
    .write_complete (weight_wr_done),
    .cfg_ci_groups  (cfg_ci_groups),
    .cfg_co_groups  (cfg_co_groups),
    .read_en        (fsm_read_en),
    .data_ready     (weights_ready),
    .data_out       (weights),
    .read_complete  (weights_read_complete)
);

// ═════════════════════════════════════════════
//  Window Buffer  (replay stored windows for co_groups > 1)
//
//  During STREAM: write each channel-group's window into buffer
//  During REPLAY: read back the buffered windows
//  Depth  = MAX_CI_GROUPS, Width = 9 × 64 = 576 bits
// ═════════════════════════════════════════════
(* ram_style = "distributed" *)
logic [575:0] window_buf [0:MAX_CI_GROUPS-1];
logic [575:0] window_packed;
logic [575:0] buf_rd_data;
logic [63:0]  buf_window [0:2][0:2];

// Pack live window → 576-bit word
always_comb begin
    for (int r = 0; r < 3; r++)
        for (int c = 0; c < 3; c++)
            window_packed[(r*3+c)*64 +: 64] = window[r][c];
end

// Unpack buffer read → 3×3 window
always_comb begin
    for (int r = 0; r < 3; r++)
        for (int c = 0; c < 3; c++)
            buf_window[r][c] = buf_rd_data[(r*3+c)*64 +: 64];
end

// ═════════════════════════════════════════════
//  Output-Group FSM   (STREAM / REPLAY)
//
//  STREAM : accept pixels, buffer windows, process output-group 0
//  REPLAY : stall pixels, replay buffer for output-groups 1..co-1
//
//  Weight manager's internal read order:
//    inner: input_ch_gr  0 → ci_groups-1
//    outer: output_ch_gr 0 → co_groups-1
//  One full sweep = ci_groups × co_groups read_en pulses = one pixel
// ═════════════════════════════════════════════
typedef enum logic {STREAM, REPLAY} state_t;
state_t state;

logic [9:0] ch_cnt;             // input channel group (0 .. ci_groups-1)
logic [9:0] co_cnt;             // output group        (0 .. co_groups-1)
logic       last_channel_raw;

assign last_channel_raw = (ch_cnt == cfg_ci_groups - 1);
assign pixel_ready      = (state == STREAM);

always_ff @(posedge clk) begin
    if (rst) begin
        state  <= STREAM;
        ch_cnt <= '0;
        co_cnt <= '0;
    end else begin
        case (state)
            STREAM: begin
                if (window_valid) begin
                    // Buffer the window for potential replay
                    window_buf[ch_cnt] <= window_packed;

                    if (last_channel_raw) begin
                        ch_cnt <= '0;
                        if (cfg_co_groups > 1) begin
                            co_cnt <= 10'd1;
                            state  <= REPLAY;
                        end else begin
                            co_cnt <= '0;   // single output group
                        end
                    end else begin
                        ch_cnt <= ch_cnt + 1;
                    end
                end
            end

            REPLAY: begin
                // Advance every cycle (no external dependency)
                if (last_channel_raw) begin
                    ch_cnt <= '0;
                    if (co_cnt == cfg_co_groups - 1) begin
                        co_cnt <= '0;
                        state  <= STREAM;
                    end else begin
                        co_cnt <= co_cnt + 1;
                    end
                end else begin
                    ch_cnt <= ch_cnt + 1;
                end
            end
        endcase
    end
end

// Buffer async read
assign buf_rd_data = window_buf[ch_cnt];

// read_en to weight manager
assign fsm_read_en = (state == STREAM) ? window_valid : 1'b1;

// Mux: live window (STREAM) vs buffered window (REPLAY)
logic [63:0] pipe_window [0:2][0:2];

always_comb begin
    for (int r = 0; r < 3; r++)
        for (int c = 0; c < 3; c++)
            pipe_window[r][c] = (state == STREAM) ? window[r][c]
                                                   : buf_window[r][c];
end

// ═════════════════════════════════════════════
//  Alignment Pipeline  (3-cycle weight-manager read latency)
//
//  Delays: window data, valid, last_channel, co_cnt
//  so they arrive at conv_3x3 in sync with weights
// ═════════════════════════════════════════════
logic [63:0] window_d [0:2][0:2][0:2];     // 3 delay stages
logic [2:0]  valid_pipe;
logic [2:0]  last_ch_pipe;
logic [9:0]  co_cnt_d [0:2];

always_ff @(posedge clk) begin
    if (rst) begin
        valid_pipe   <= '0;
        last_ch_pipe <= '0;
        co_cnt_d[0]  <= '0;
        co_cnt_d[1]  <= '0;
        co_cnt_d[2]  <= '0;
    end else begin
        valid_pipe   <= {valid_pipe[1:0],   fsm_read_en};
        last_ch_pipe <= {last_ch_pipe[1:0], last_channel_raw & fsm_read_en};
        co_cnt_d[0]  <= co_cnt;
        co_cnt_d[1]  <= co_cnt_d[0];
        co_cnt_d[2]  <= co_cnt_d[1];
    end
end

always_ff @(posedge clk) begin
    for (int r = 0; r < 3; r++)
        for (int c = 0; c < 3; c++) begin
            window_d[0][r][c] <= pipe_window[r][c];
            window_d[1][r][c] <= window_d[0][r][c];
            window_d[2][r][c] <= window_d[1][r][c];
        end
end

// Aligned signals → conv_3x3
logic [63:0] aligned_window [0:2][0:2];
logic        aligned_valid;
logic        aligned_last_ch;

always_comb begin
    for (int r = 0; r < 3; r++)
        for (int c = 0; c < 3; c++)
            aligned_window[r][c] = window_d[2][r][c];
end

assign aligned_valid   = valid_pipe[2];
assign aligned_last_ch = last_ch_pipe[2];
assign bias_group_sel  = co_cnt_d[2];

// ═════════════════════════════════════════════
//  Conv 3×3  (8 parallel filter PEs)
// ═════════════════════════════════════════════
logic [31:0] conv_outs [0:7];
logic        conv_valid;

conv_3x3 Conv3x3 (
    .clk          (clk),
    .rst          (rst),
    .valid_in     (aligned_valid),
    .last_channel (aligned_last_ch),
    .pixels       (aligned_window),
    .weights      (weights),
    .biases       (biases),
    .outs         (conv_outs),
    .data_valid   (conv_valid)
);

// ═════════════════════════════════════════════
//  Quantizers  (8 parallel)
// ═════════════════════════════════════════════
logic [7:0]  quant_outs [0:7];
logic        quant_valid;

genvar g;
generate
    for (g = 0; g < 8; g++) begin : quant_gen
        logic qv;
        quantizer Quantizer (
            .clk       (clk),
            .rst       (rst),
            .data_in   (conv_outs[g]),
            .valid_in  (conv_valid),
            .M         (cfg_quant_M),
            .n         (cfg_quant_n),
            .use_relu  (cfg_use_relu),
            .data_out  (quant_outs[g]),
            .valid_out (qv)
        );
        if (g == 0) assign quant_valid = qv;
    end
endgenerate

// Pack 8 × INT8 → 64-bit
logic [63:0] quant_packed;
always_comb begin
    for (int i = 0; i < 8; i++)
        quant_packed[i*8 +: 8] = quant_outs[i];
end

// ═════════════════════════════════════════════
//  MaxPool  (fused, optional)
// ═════════════════════════════════════════════
logic [63:0] pool_out;
logic        pool_valid;

logic [15:0] out_channels;
assign out_channels = {6'b0, cfg_co_groups} << 3;

maxPool MaxPool (
    .clk       (clk),
    .rst       (rst),
    .img_width (cfg_img_width),
    .channels  (out_channels),
    .stride_2  (1'b1),
    .data_in   (quant_packed),
    .valid_in  (quant_valid),
    .data_out  (pool_out),
    .valid_out (pool_valid)
);

// ═════════════════════════════════════════════
//  Output Mux
// ═════════════════════════════════════════════
assign data_out       = cfg_use_maxpool ? pool_out  : quant_packed;
assign data_valid_out = cfg_use_maxpool ? pool_valid : quant_valid;

// ═════════════════════════════════════════════
//  Layer Done  (count output-valid pulses)
//
//  Expected outputs:
//    no pool  : img_w × img_h × co_groups
//    stride-2 : (img_w/2) × (img_h/2) × co_groups
// ═════════════════════════════════════════════
logic [31:0] spatial_pixels;
logic [31:0] expected_outputs;
logic [31:0] output_cnt;

assign spatial_pixels = cfg_use_maxpool
    ? (32'(cfg_img_width >> 1) * 32'(cfg_img_height >> 1))
    : (32'(cfg_img_width)      * 32'(cfg_img_height));

assign expected_outputs = spatial_pixels * 32'(cfg_co_groups);

always_ff @(posedge clk) begin
    if (rst) begin
        output_cnt <= '0;
        layer_done <= 1'b0;
    end else if (!layer_done) begin
        if (data_valid_out) begin
            if (output_cnt == expected_outputs - 1)
                layer_done <= 1'b1;
            else
                output_cnt <= output_cnt + 1;
        end
    end
end

endmodule
