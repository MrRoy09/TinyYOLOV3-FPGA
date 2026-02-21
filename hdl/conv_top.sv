// Top-level convolution module: window → conv_3x3 → quantizer → maxpool
module conv_top #(
    parameter WT_DEPTH        = 4096,
    parameter WT_ADDR_WIDTH   = $clog2(WT_DEPTH),
    parameter BIAS_DEPTH      = 256,
    parameter BIAS_GROUP_BITS = $clog2(BIAS_DEPTH) - 1,
    parameter WT_LATENCY      = 3,
    parameter CONV_PE_PIPE    = 4
)(
    input  logic        clk,
    input  logic        rst,
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
    input  logic                          cfg_kernel_1x1,
    input  logic                          go,
    output logic                          busy,
    output logic                          done,
    input  logic                          bias_wr_en,
    input  logic [127:0]                  bias_wr_data,
    input  logic                          bias_wr_addr_rst,
    input  logic                          wt_wr_en,
    input  logic [71:0]                   wt_wr_data,
    input  logic                          wt_wr_addr_rst,
    input  logic [63:0]                   pixel_in,
    input  logic                          pixel_in_valid,
    input  logic                          pixel_in_last,
    output logic [63:0]                   data_out,
    output logic                          data_out_valid
);

logic                        bias_rd_en;
logic [BIAS_GROUP_BITS-1:0]  bias_rd_group;
logic                        bias_valid;
logic [31:0]                 bias_out [0:7];

logic                        wt_rd_en;
logic [WT_ADDR_WIDTH-1:0]    wt_rd_addr;
logic                        wt_data_ready;
logic [575:0]                wt_data_out [0:7];

logic                        conv_valid_in;
logic                        conv_last_channel;

logic [31:0]                 conv_3x3_outs [0:7];
logic                        conv_3x3_data_valid;

logic [31:0]                 conv_outs [0:7];
logic                        conv_data_valid;

assign conv_outs       = conv_3x3_outs;
assign conv_data_valid = conv_3x3_data_valid;

logic [63:0]                 kw_window [0:2][0:2];
logic                        kw_dout_valid;

logic                        pixel_valid_mux;
logic                        last_pixel;

assign pixel_valid_mux = cfg_kernel_1x1 ? pixel_in_valid : kw_dout_valid;
assign last_pixel      = cfg_kernel_1x1 ? pixel_in_last  : (pixel_in_last & kw_dout_valid);

// Pixel pipeline: 3-stage delay to match weight latency
logic [63:0] pixel_3x3_d0 [0:2][0:2];
logic [63:0] pixel_3x3_d1 [0:2][0:2];
logic [63:0] pixel_3x3_d2 [0:2][0:2];

always_ff @(posedge clk) begin
    pixel_3x3_d0 <= kw_window;
    pixel_3x3_d1 <= pixel_3x3_d0;
    pixel_3x3_d2 <= pixel_3x3_d1;
end

logic [63:0] pixel_1x1_d0, pixel_1x1_d1, pixel_1x1_d2, pixel_1x1_d3;

always_ff @(posedge clk) begin
    pixel_1x1_d0 <= pixel_in;
    pixel_1x1_d1 <= pixel_1x1_d0;
    pixel_1x1_d2 <= pixel_1x1_d1;
    pixel_1x1_d3 <= pixel_1x1_d2;
end

logic [63:0] pixel_mux [0:2][0:2];

always_comb begin
    if (cfg_kernel_1x1) begin
        for (int r = 0; r < 3; r++)
            for (int c = 0; c < 3; c++)
                pixel_mux[r][c] = (r == 1 && c == 1) ? pixel_1x1_d3 : 64'b0;
    end else begin
        pixel_mux = pixel_3x3_d2;
    end
end

bias_store #(.MAX_DEPTH(BIAS_DEPTH)) u_bias_store (
    .clk(clk), .rst(rst),
    .wr_en(bias_wr_en), .wr_data(bias_wr_data), .wr_addr_rst(bias_wr_addr_rst),
    .rd_en(bias_rd_en), .rd_group(bias_rd_group),
    .bias_out(bias_out), .rd_valid(bias_valid)
);

weight_manager #(.DEPTH(WT_DEPTH)) u_weight_manager (
    .clk(clk), .rst(rst),
    .wr_en(wt_wr_en), .wr_data(wt_wr_data), .wr_addr_rst(wt_wr_addr_rst),
    .rd_en(wt_rd_en), .rd_addr(wt_rd_addr),
    .data_out(wt_data_out), .data_ready(wt_data_ready)
);

conv_controller #(
    .WT_ADDR_WIDTH(WT_ADDR_WIDTH), .BIAS_ADDR_WIDTH(BIAS_GROUP_BITS),
    .WT_LATENCY(WT_LATENCY), .CONV_PE_PIPE(CONV_PE_PIPE),
    .QUANT_LATENCY(4), .MAXPOOL_LATENCY(4)
) u_conv_controller (
    .clk(clk), .rst(rst),
    .cfg_ci_groups(cfg_ci_groups), .cfg_output_group(cfg_output_group),
    .cfg_wt_base_addr(cfg_wt_base_addr),
    .go(go), .busy(busy), .done(done),
    .bias_rd_en(bias_rd_en), .bias_rd_group(bias_rd_group), .bias_valid(bias_valid),
    .wt_rd_en(wt_rd_en), .wt_rd_addr(wt_rd_addr), .wt_data_ready(wt_data_ready),
    .pixel_valid(pixel_valid_mux), .last_pixel(last_pixel),
    .conv_valid_in(conv_valid_in), .conv_last_channel(conv_last_channel)
);

kernelWindow u_kernel_window (
    .clk(clk), .rst(rst),
    .data_valid(pixel_in_valid), .in_channels(cfg_in_channels), .img_width(cfg_img_width),
    .pixel_in(pixel_in), .window(kw_window), .dout_valid(kw_dout_valid)
);

conv_3x3 u_conv_3x3 (
    .clk(clk), .rst(rst),
    .valid_in(conv_valid_in), .last_channel(conv_last_channel),
    .pixels(pixel_mux), .weights(wt_data_out), .biases(bias_out),
    .outs(conv_3x3_outs), .data_valid(conv_3x3_data_valid)
);

logic [7:0]  quant_out [0:7];
logic        quant_valid;
logic [63:0] quant_packed;

generate
    for (genvar i = 0; i < 8; i++) begin : gen_quant
        quantizer u_quant (
            .clk(clk), .rst(rst),
            .data_in(conv_outs[i]), .valid_in(conv_data_valid),
            .M(cfg_quant_m), .n(cfg_quant_n), .use_relu(cfg_use_relu),
            .data_out(quant_out[i]), .valid_out()
        );
    end
endgenerate

assign quant_valid = gen_quant[0].u_quant.valid_out;

always_comb begin
    for (int i = 0; i < 8; i++)
        quant_packed[i*8 +: 8] = quant_out[i];
end

logic [63:0] maxpool_data_out;
logic        maxpool_valid_out;

(* max_fanout = 32 *) logic [15:0] maxpool_img_width_r;
(* max_fanout = 32 *) logic        maxpool_stride_2_r;
(* max_fanout = 32 *) logic [15:0] conv_out_width_r;

always_ff @(posedge clk) begin
    if (rst) begin
        maxpool_img_width_r <= '0;
        maxpool_stride_2_r  <= '0;
        conv_out_width_r    <= '0;
    end else begin
        conv_out_width_r    <= cfg_kernel_1x1 ? cfg_img_width : (cfg_img_width - 16'd2);
        maxpool_img_width_r <= conv_out_width_r;
        maxpool_stride_2_r  <= cfg_stride_2;
    end
end

// Stride-1 maxpool: host pads conv input to produce (H+1)x(W+1) output
// Maxpool skips row0/col0, outputting HxW
logic [63:0] mp_data_in;
logic        mp_valid_in;

assign mp_data_in  = quant_packed;
assign mp_valid_in = quant_valid;

maxPool u_maxpool (
    .clk(clk), .rst(rst),
    .img_width(maxpool_img_width_r), .channels(16'd8), .stride_2(maxpool_stride_2_r),
    .data_in(mp_data_in), .valid_in(mp_valid_in),
    .data_out(maxpool_data_out), .valid_out(maxpool_valid_out)
);

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
