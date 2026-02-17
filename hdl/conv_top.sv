module conv_top #(
    parameter WT_DEPTH        = 4096,
    parameter WT_ADDR_WIDTH   = $clog2(WT_DEPTH),
    parameter BIAS_DEPTH      = 256,
    parameter BIAS_GROUP_BITS = $clog2(BIAS_DEPTH) - 1,
    parameter WT_LATENCY      = 3,
    parameter CONV_PE_PIPE    = 4  // 4 stages: multiply → partial_sum → spatial_sum/cycle_sum → acc
)(
    input  logic        clk,
    input  logic        rst,

    // ── CPU configuration ──
    input  logic [9:0]                    cfg_ci_groups,
    input  logic [BIAS_GROUP_BITS-1:0]    cfg_output_group,
    input  logic [WT_ADDR_WIDTH-1:0]      cfg_wt_base_addr,
    input  logic [15:0]                   cfg_in_channels,
    input  logic [15:0]                   cfg_img_width,
    input  logic                          cfg_use_maxpool,
    input  logic                          cfg_stride_2,
    input  logic [31:0]                   cfg_quant_m,
    input  logic [4:0]                    cfg_quant_n,
    input  logic                          cfg_use_relu,
    input  logic                          cfg_kernel_1x1,   // 0=3x3, 1=1x1
    input  logic                          go,
    output logic                          busy,
    output logic                          done,

    // ── Bias write port (CPU DMA) ──
    input  logic                          bias_wr_en,
    input  logic [127:0]                  bias_wr_data,
    input  logic                          bias_wr_addr_rst,

    // ── Weight write port (CPU DMA) ──
    input  logic                          wt_wr_en,
    input  logic [71:0]                   wt_wr_data,
    input  logic                          wt_wr_addr_rst,

    // ── Pixel input (Input DMA) ──
    input  logic [63:0]                   pixel_in,
    input  logic                          pixel_in_valid,
    input  logic                          pixel_in_last,

    // ── Output (Output DMA) ──
    output logic [63:0]                   data_out,
    output logic                          data_out_valid
);

// ════════════════════════════════════════════════════════════════
//  Internal wires: controller ↔ bias_store
// ════════════════════════════════════════════════════════════════
logic                        bias_rd_en;
logic [BIAS_GROUP_BITS-1:0]  bias_rd_group;
logic                        bias_valid;
logic [31:0]                 bias_out [0:7];

// ════════════════════════════════════════════════════════════════
//  Internal wires: controller ↔ weight_manager
// ════════════════════════════════════════════════════════════════
logic                        wt_rd_en;
logic [WT_ADDR_WIDTH-1:0]    wt_rd_addr;
logic                        wt_data_ready;
logic [575:0]                wt_data_out [0:7];

// ════════════════════════════════════════════════════════════════
//  Internal wires: controller → conv datapath
// ════════════════════════════════════════════════════════════════
logic                        conv_valid_in;
logic                        conv_last_channel;

// ════════════════════════════════════════════════════════════════
//  Internal wires: conv_3x3 outputs
// ════════════════════════════════════════════════════════════════
logic [31:0]                 conv_3x3_outs [0:7];
logic                        conv_3x3_data_valid;

// ════════════════════════════════════════════════════════════════
//  Conv outputs (conv_3x3 handles both 3x3 and 1x1 modes)
// ════════════════════════════════════════════════════════════════
logic [31:0]                 conv_outs [0:7];
logic                        conv_data_valid;

assign conv_outs      = conv_3x3_outs;
assign conv_data_valid = conv_3x3_data_valid;

// ════════════════════════════════════════════════════════════════
//  Internal wires: kernel window → pixel delay (3x3 path)
// ════════════════════════════════════════════════════════════════
logic [63:0]                 kw_window [0:2][0:2];
logic                        kw_dout_valid;

// ════════════════════════════════════════════════════════════════
//  Pixel valid / last_pixel mux based on kernel type
//  - 3x3: uses kernel_window output (with priming delay)
//  - 1x1: uses pixel_in directly (no window needed)
// ════════════════════════════════════════════════════════════════
logic                        pixel_valid_mux;
logic                        last_pixel;

assign pixel_valid_mux = cfg_kernel_1x1 ? pixel_in_valid : kw_dout_valid;
assign last_pixel      = cfg_kernel_1x1 ? pixel_in_last  : (pixel_in_last & kw_dout_valid);

// ════════════════════════════════════════════════════════════════
//  Pixel delay for 3x3: 3-stage shift register (matches WT_LATENCY).
//  Valid delay is 4 cycles (1 NBA + 3 shift), pixel delay is 3
//  cycles, so pixel_d2 settles 1 cycle before conv_valid_in.
//  conv_pe synchronously samples the "old" pixel_d2 at the posedge
//  where conv_valid_in fires, giving the correct aligned window.
// ════════════════════════════════════════════════════════════════
logic [63:0] pixel_3x3_d0 [0:2][0:2];
logic [63:0] pixel_3x3_d1 [0:2][0:2];
logic [63:0] pixel_3x3_d2 [0:2][0:2];

always_ff @(posedge clk) begin
    pixel_3x3_d0 <= kw_window;
    pixel_3x3_d1 <= pixel_3x3_d0;
    pixel_3x3_d2 <= pixel_3x3_d1;
end

// ════════════════════════════════════════════════════════════════
//  Pixel delay for 1x1: 4-stage shift register.
//  The controller adds 1 extra cycle (valid_raw NBA) before the
//  WT_LATENCY shift, so total valid delay = 1 + WT_LATENCY = 4.
//  Pixel delay must match: 4 stages.
// ════════════════════════════════════════════════════════════════
logic [63:0] pixel_1x1_d0, pixel_1x1_d1, pixel_1x1_d2, pixel_1x1_d3;

always_ff @(posedge clk) begin
    pixel_1x1_d0 <= pixel_in;
    pixel_1x1_d1 <= pixel_1x1_d0;
    pixel_1x1_d2 <= pixel_1x1_d1;
    pixel_1x1_d3 <= pixel_1x1_d2;
end

// ════════════════════════════════════════════════════════════════
//  Pixel mux for 1x1 mode: feed pixel to center [1][1], zeros elsewhere
//  For 3x3 mode: use the full kernel window from pixel_3x3_d2
// ════════════════════════════════════════════════════════════════
logic [63:0] pixel_mux [0:2][0:2];

always_comb begin
    if (cfg_kernel_1x1) begin
        // 1x1 mode: only center pixel, all others zero
        for (int r = 0; r < 3; r++) begin
            for (int c = 0; c < 3; c++) begin
                pixel_mux[r][c] = (r == 1 && c == 1) ? pixel_1x1_d3 : 64'b0;
            end
        end
    end else begin
        // 3x3 mode: use full kernel window
        pixel_mux = pixel_3x3_d2;
    end
end

// ════════════════════════════════════════════════════════════════
//  Bias Store
// ════════════════════════════════════════════════════════════════
bias_store #(
    .MAX_DEPTH (BIAS_DEPTH)
) u_bias_store (
    .clk         (clk),
    .rst         (rst),
    .wr_en       (bias_wr_en),
    .wr_data     (bias_wr_data),
    .wr_addr_rst (bias_wr_addr_rst),
    .rd_en       (bias_rd_en),
    .rd_group    (bias_rd_group),
    .bias_out    (bias_out),
    .rd_valid    (bias_valid)
);

// ════════════════════════════════════════════════════════════════
//  Weight Manager
// ════════════════════════════════════════════════════════════════
weight_manager #(
    .DEPTH (WT_DEPTH)
) u_weight_manager (
    .clk         (clk),
    .rst         (rst),
    .wr_en       (wt_wr_en),
    .wr_data     (wt_wr_data),
    .wr_addr_rst (wt_wr_addr_rst),
    .rd_en       (wt_rd_en),
    .rd_addr     (wt_rd_addr),
    .data_out    (wt_data_out),
    .data_ready  (wt_data_ready)
);

// ════════════════════════════════════════════════════════════════
//  Conv Controller
//  Orchestrates: bias read → wait → conv (weight + pixel) → drain
//  Delays conv_valid_in / conv_last_channel by WT_LATENCY internally
// ════════════════════════════════════════════════════════════════
conv_controller #(
    .WT_ADDR_WIDTH   (WT_ADDR_WIDTH),
    .BIAS_ADDR_WIDTH (BIAS_GROUP_BITS),
    .WT_LATENCY      (WT_LATENCY),
    .CONV_PE_PIPE    (CONV_PE_PIPE),
    .QUANT_LATENCY   (4),
    .MAXPOOL_LATENCY (4)
) u_conv_controller (
    .clk              (clk),
    .rst              (rst),
    .cfg_ci_groups    (cfg_ci_groups),
    .cfg_output_group (cfg_output_group),
    .cfg_wt_base_addr (cfg_wt_base_addr),
    .go               (go),
    .busy             (busy),
    .done             (done),
    .bias_rd_en       (bias_rd_en),
    .bias_rd_group    (bias_rd_group),
    .bias_valid       (bias_valid),
    .wt_rd_en         (wt_rd_en),
    .wt_rd_addr       (wt_rd_addr),
    .wt_data_ready    (wt_data_ready),
    .pixel_valid      (pixel_valid_mux),
    .last_pixel       (last_pixel),
    .conv_valid_in    (conv_valid_in),
    .conv_last_channel(conv_last_channel)
);

// ════════════════════════════════════════════════════════════════
//  Kernel Window
//  Converts streaming pixel_in into 3×3 sliding window.
//  Uses 2 lineBuffers + 6 delayLines internally.
//  dout_valid goes high after priming delay.
// ════════════════════════════════════════════════════════════════
kernelWindow u_kernel_window (
    .clk        (clk),
    .rst        (rst),
    .data_valid (pixel_in_valid),
    .in_channels(cfg_in_channels),
    .img_width  (cfg_img_width),
    .pixel_in   (pixel_in),
    .window     (kw_window),
    .dout_valid (kw_dout_valid)
);

// ════════════════════════════════════════════════════════════════
//  Conv 3x3: 8 parallel PEs computing 8 output channels
//  For 1x1 mode: pixel_mux feeds center position only, weights have
//  non-zero values only at spatial position 4 (center)
// ════════════════════════════════════════════════════════════════
conv_3x3 u_conv_3x3 (
    .clk          (clk),
    .rst          (rst),
    .valid_in     (conv_valid_in),
    .last_channel (conv_last_channel),
    .pixels       (pixel_mux),
    .weights      (wt_data_out),
    .biases       (bias_out),
    .outs         (conv_3x3_outs),
    .data_valid   (conv_3x3_data_valid)
);

// ════════════════════════════════════════════════════════════════
//  Quantizers ×8: conv_outs[i] (32-bit) → quant_out[i] (8-bit)
//  Latency: 4 cycles from conv_data_valid → quant_valid
// ════════════════════════════════════════════════════════════════
logic [7:0]  quant_out [0:7];
logic        quant_valid;
logic [63:0] quant_packed;

generate
    for (genvar i = 0; i < 8; i++) begin : gen_quant
        quantizer u_quant (
            .clk       (clk),
            .rst       (rst),
            .data_in   (conv_outs[i]),
            .valid_in  (conv_data_valid),
            .M         (cfg_quant_m),
            .n         (cfg_quant_n),
            .use_relu  (cfg_use_relu),
            .data_out  (quant_out[i]),
            .valid_out ()
        );
    end
endgenerate

assign quant_valid = gen_quant[0].u_quant.valid_out;

always_comb begin
    for (int i = 0; i < 8; i++)
        quant_packed[i*8 +: 8] = quant_out[i];
end

// ════════════════════════════════════════════════════════════════
//  MaxPool: operates on quantized 8-bit packed output
//  img_width for 3x3 = cfg_img_width - 2 (conv output spatial width)
//  img_width for 1x1 = cfg_img_width (no spatial reduction)
//  channels  = 8 (always 8 output channels per conv_top call)
// ════════════════════════════════════════════════════════════════
logic [63:0] maxpool_data_out;
logic        maxpool_valid_out;

// Register config-derived signals to break timing paths
// These are stable before processing starts
(* max_fanout = 32 *) logic [15:0] maxpool_img_width_r;
(* max_fanout = 32 *) logic        maxpool_stride_2_r;

always_ff @(posedge clk) begin
    if (rst) begin
        maxpool_img_width_r <= '0;
        maxpool_stride_2_r  <= '0;
    end else begin
        maxpool_img_width_r <= cfg_kernel_1x1 ? cfg_img_width : (cfg_img_width - 16'd2);
        maxpool_stride_2_r  <= cfg_stride_2;
    end
end

maxPool u_maxpool (
    .clk       (clk),
    .rst       (rst),
    .img_width (maxpool_img_width_r),
    .channels  (16'd8),
    .stride_2  (maxpool_stride_2_r),
    .data_in   (quant_packed),
    .valid_in  (quant_valid),
    .data_out  (maxpool_data_out),
    .valid_out (maxpool_valid_out)
);

// ════════════════════════════════════════════════════════════════
//  Output mux: maxpool or direct quantizer bypass
//  Use registered config to break timing path
// ════════════════════════════════════════════════════════════════
(* max_fanout = 32 *) logic cfg_use_maxpool_r;

always_ff @(posedge clk) begin
    if (rst)
        cfg_use_maxpool_r <= '0;
    else
        cfg_use_maxpool_r <= cfg_use_maxpool;
end

assign data_out       = cfg_use_maxpool_r ? maxpool_data_out  : quant_packed;
assign data_out_valid = cfg_use_maxpool_r ? maxpool_valid_out : quant_valid;

endmodule
