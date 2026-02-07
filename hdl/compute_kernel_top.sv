
module TinyYoloComputeUnit #(
    parameter C_AXIS_TDATA_WIDTH = 512,
    parameter NUM_FILTERS = 64
)(
    input  logic        clk,
    input  logic        rst,
    
    // Scalar Parameters from AXI-Lite
    input  logic [31:0] img_width,
    input  logic [31:0] in_channels,
    input  logic [31:0] out_channels,
    input  logic [31:0] quant_M,
    input  logic [31:0] quant_n,
    input  logic        is_maxpool,
    input  logic        is_1x1,
    input  logic [31:0] stride,
    
    // AXI-Stream Input
    input  logic                        s_axis_tvalid,
    output logic                        s_axis_tready,
    input  logic [C_AXIS_TDATA_WIDTH-1:0] s_axis_tdata,
    input  logic                        s_axis_tlast,
    
    // AXI-Stream Output
    output logic                        m_axis_tvalid,
    input  logic                        m_axis_tready,
    output logic [C_AXIS_TDATA_WIDTH-1:0] m_axis_tdata,
    output logic                        m_axis_tlast
);

    // --------------------------------------------------------
    // 1. Control State Machine
    // --------------------------------------------------------
    typedef enum logic [1:0] {IDLE, LOAD_PARAMS, COMPUTE, DONE} state_t;
    state_t state;
    
    logic load_en, load_done;
    
    always_ff @(posedge clk) begin
        if (rst) begin
            state <= IDLE;
            load_en <= 1'b0;
        end else begin
            case (state)
                IDLE: begin
                    if (s_axis_tvalid) begin
                        state   <= LOAD_PARAMS;
                        load_en <= 1'b1;
                    end
                end
                LOAD_PARAMS: begin
                    if (load_done) begin
                        state   <= COMPUTE;
                        load_en <= 1'b0;
                    end
                end
                COMPUTE: begin
                    if (s_axis_tlast && s_axis_tvalid && s_axis_tready) begin
                        state <= DONE;
                    end
                end
                DONE: begin
                    state <= IDLE;
                end
                default: state <= IDLE;
            endcase
        end
    end

    // --------------------------------------------------------
    // 2. Weight & Bias Memory System
    // --------------------------------------------------------
    logic [8:0]  weight_addr, weight_addr_load, weight_addr_run; // 9 bits = 512 depth
    logic [4607:0] weight_data_in, weight_data_out;
    logic weight_we;
    
    logic [8:0] bias_addr, bias_addr_load, bias_addr_run;
    logic [2047:0] bias_data_in, bias_data_out;
    logic bias_we;
    
    logic loader_ready;

    parameter_loader #(
        .NUM_FILTERS(NUM_FILTERS),
        .K_SIZE(9),
        .W_ADDR_W(9), // Updated depth
        .B_ADDR_W(9),
        .AXIS_WIDTH(C_AXIS_TDATA_WIDTH)
    ) i_loader (
        .clk(clk),
        .rst(rst),
        .s_axis_tdata(s_axis_tdata),
        .s_axis_tvalid(s_axis_tvalid && (state == LOAD_PARAMS)),
        .s_axis_tready(loader_ready),
        .load_en(load_en),
        .expected_weight_rows(in_channels[8:0]), 
        .load_done(load_done),
        .weight_addr(weight_addr_load),
        .weight_data(weight_data_in),
        .weight_we(weight_we),
        .bias_addr(bias_addr_load),
        .bias_data(bias_data_in),
        .bias_we(bias_we)
    );

    
    assign weight_addr = (state == LOAD_PARAMS) ? weight_addr_load : weight_addr_run;
    assign bias_addr   = (state == LOAD_PARAMS) ? bias_addr_load   : bias_addr_run;

    bram_weights_1 i_weight_bram (
        .clka(clk),
        .ena(1'b1),
        .wea(weight_we),
        .addra(weight_addr),
        .dina(weight_data_in),
        .douta(weight_data_out)
    );
    
    bram_bias_1 i_bias_bram (
        .clka(clk),
        .ena(1'b1),
        .wea(bias_we),
        .addra(bias_addr),
        .dina(bias_data_in),
        .douta(bias_data_out)
    );

    // --------------------------------------------------------
    // 3. Pixel Input Stream Adapter
    // --------------------------------------------------------
    logic [7:0] pixel_stream;
    logic       pixel_valid;
    logic       serializer_ready;
    
    pixel_serializer #(
        .AXIS_WIDTH(C_AXIS_TDATA_WIDTH),
        .PIXEL_WIDTH(8)
    ) i_serializer (
        .clk(clk),
        .rst(rst),
        .s_axis_tdata(s_axis_tdata),
        .s_axis_tvalid(s_axis_tvalid && (state == COMPUTE)),
        .s_axis_tready(serializer_ready),
        .pixel_out(pixel_stream),
        .pixel_valid(pixel_valid),
        .pixel_ready(1'b1) 
    );

    assign s_axis_tready = (state == LOAD_PARAMS) ? loader_ready : 
                           (state == COMPUTE)     ? serializer_ready : 1'b0;

    // --------------------------------------------------------
    // 4. Controller & Counters
    // --------------------------------------------------------
    logic [11:0] in_col_cnt, in_row_cnt;
    logic [11:0] in_ch_cnt;
    logic        is_first_ch_in, is_last_ch_in;

    always_ff @(posedge clk) begin
        if (rst || state != COMPUTE) begin
            in_col_cnt     <= '0;
            in_row_cnt     <= '0;
            in_ch_cnt      <= '0;
            is_first_ch_in <= 1'b0;
            is_last_ch_in  <= 1'b0;
        end else if (pixel_valid) begin 
            is_first_ch_in <= (in_ch_cnt == 0);
            is_last_ch_in  <= (in_ch_cnt == in_channels - 1);

            if (in_col_cnt == img_width - 1) begin
                in_col_cnt <= '0;
                if (in_row_cnt == img_width - 1) begin 
                    in_row_cnt <= '0;
                    if (in_ch_cnt == in_channels - 1) in_ch_cnt <= '0;
                    else in_ch_cnt <= in_ch_cnt + 1'b1;
                end else begin
                    in_row_cnt <= in_row_cnt + 1'b1;
                end
            end else begin
                in_col_cnt <= in_col_cnt + 1'b1;
            end
        end
    end

    assign weight_addr_run = in_ch_cnt[10:0];
    assign bias_addr_run   = 0; 

    // Pipeline coordinate status
    struct packed {
        logic [11:0] col;
        logic        first_ch;
        logic        last_ch;
        logic        valid;
    } pipe [0:15];

    always_ff @(posedge clk) begin
        if (rst) begin
            for (int j=0; j<16; j++) pipe[j] <= '0;
        end else begin
            pipe[0].col      <= in_col_cnt;
            pipe[0].first_ch <= is_first_ch_in;
            pipe[0].last_ch  <= is_last_ch_in;
            pipe[0].valid    <= pixel_valid;
            for (int j=1; j<16; j++) pipe[j] <= pipe[j-1];
        end
    end

    // --------------------------------------------------------
    // 5. Kernel Window Generator
    // --------------------------------------------------------
    logic [7:0] window [0:2][0:2];
    logic       window_valid_out;
    
    kernelWindow #(
        .MAX_LB_WIDTH(8192)
    ) i_window (
        .clk(clk),
        .rst(rst),
        .img_width(img_width),
        .in_channels(in_channels),
        .pixel_in(pixel_stream),
        .data_valid(pixel_valid),
        .window(window),
        .valid_out(window_valid_out)
    );

    // --------------------------------------------------------
    // 6. Parallel Compute Array (64 Filters)
    // --------------------------------------------------------
    logic [7:0] window_flat [0:8];
    assign window_flat[0] = window[0][0]; assign window_flat[1] = window[0][1]; assign window_flat[2] = window[0][2];
    assign window_flat[3] = window[1][0]; assign window_flat[4] = window[1][1]; assign window_flat[5] = window[1][2];
    assign window_flat[6] = window[2][0]; assign window_flat[7] = window[2][1]; assign window_flat[8] = window[2][2];

    logic [7:0] final_quant_out [0:NUM_FILTERS-1];
    logic       final_valid;

    genvar f;
    generate
        for (f = 0; f < NUM_FILTERS; f++) begin : gen_engines
            logic [31:0] engine_out;
            logic        engine_valid;
            logic [31:0] acc_out;
            logic        acc_valid;
            
            // Slice weights and bias using constant indices
            localparam int W_OFFSET = f * 72;
            localparam int B_OFFSET = f * 32;

            conv_3x3 i_conv (
                .clk(clk),
                .rst(rst),
                .valid_in(window_valid_out),
                .pixels(window_flat),
                .weights(weight_data_out[W_OFFSET +: 72]),
                .bias(bias_data_out[B_OFFSET +: 32]),
                .out(engine_out),
                .data_valid(engine_valid)
            );
            
            partial_sum_accumulator #(
                .MAX_WIDTH(512)
            ) i_acc (
                .clk(clk),
                .rst(rst),
                .conv_data_in(engine_out),
                .conv_valid_in(engine_valid),
                .is_first_channel(pipe[10].first_ch), 
                .is_last_channel(pipe[10].last_ch),
                .pixel_idx(pipe[10].col[8:0]), 
                .accum_data_out(acc_out),
                .accum_valid_out(acc_valid)
            );
            
            quantizer i_quant (
                .clk(clk),
                .rst(rst),
                .data_in(acc_out),
                .valid_in(acc_valid),
                .M(quant_M),
                .n(quant_n[4:0]),
                .data_out(final_quant_out[f]),
                .valid_out(final_valid) 
            );
        end
    endgenerate

    // --------------------------------------------------------
    // 7. Output Packer
    // --------------------------------------------------------
    output_packer #(
        .NUM_FILTERS(NUM_FILTERS),
        .AXIS_WIDTH(C_AXIS_TDATA_WIDTH)
    ) i_packer (
        .clk(clk),
        .rst(rst),
        .pixel_results(final_quant_out),
        .valid_in(final_valid),
        .m_axis_tdata(m_axis_tdata),
        .m_axis_tvalid(m_axis_tvalid),
        .m_axis_tready(m_axis_tready),
        .m_axis_tlast(pipe[15].last_ch && (pipe[15].col == img_width - 1))
    );

endmodule
