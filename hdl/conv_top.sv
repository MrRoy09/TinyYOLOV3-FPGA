module conv_top #(
    parameter WT_DEPTH        = 4096,
    parameter WT_ADDR_WIDTH   = $clog2(WT_DEPTH),
    parameter BIAS_DEPTH      = 256,
    parameter BIAS_GROUP_BITS = $clog2(BIAS_DEPTH) - 1,
    parameter WT_LATENCY      = 3,
    parameter CONV_PE_PIPE    = 3
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
    output logic                          data_out_valid,

    // ── Debug outputs ──
    output logic [31:0]                   dbg_bias_out [0:7],
    output logic                          dbg_bias_valid,
    output logic [575:0]                  dbg_wt_data_out [0:7],
    output logic                          dbg_wt_data_ready,
    output logic                          dbg_conv_valid_in,
    output logic                          dbg_conv_last_channel,
    output logic [63:0]                   dbg_pixel_d2 [0:2][0:2]
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
//  Internal wires: kernel window → pixel delay
// ════════════════════════════════════════════════════════════════
logic [63:0]                 kw_window [0:2][0:2];
logic                        kw_dout_valid;

// last_pixel: pixel_in_last delayed through kernel window priming.
// After priming, dout_valid = data_valid, so pixel_in_last on the
// final beat coincides with kw_dout_valid.
logic                        last_pixel;
assign last_pixel = pixel_in_last & kw_dout_valid;

// ════════════════════════════════════════════════════════════════
//  Pixel delay: 3-stage shift register (matches URAM read pipeline)
//  Free-running — advances every clock, same as weight_manager's
//  rdata_pipe. Verified in tb_wt_conv_integration.
// ════════════════════════════════════════════════════════════════
logic [63:0] pixel_d0 [0:2][0:2];
logic [63:0] pixel_d1 [0:2][0:2];
logic [63:0] pixel_d2 [0:2][0:2];

always_ff @(posedge clk) begin
    pixel_d0 <= kw_window;
    pixel_d1 <= pixel_d0;
    pixel_d2 <= pixel_d1;
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
    .CONV_PE_PIPE    (CONV_PE_PIPE)
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
    .pixel_valid      (kw_dout_valid),
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
//  Debug output connections
// ════════════════════════════════════════════════════════════════
assign dbg_bias_valid        = bias_valid;
assign dbg_wt_data_ready     = wt_data_ready;
assign dbg_conv_valid_in     = conv_valid_in;
assign dbg_conv_last_channel = conv_last_channel;

always_comb begin
    for (int i = 0; i < 8; i++) begin
        dbg_bias_out[i]    = bias_out[i];
        dbg_wt_data_out[i] = wt_data_out[i];
    end
    for (int r = 0; r < 3; r++)
        for (int c = 0; c < 3; c++)
            dbg_pixel_d2[r][c] = pixel_d2[r][c];
end

// ════════════════════════════════════════════════════════════════
//  TODO: conv_3x3      (pixel_d2, wt_data_out, bias_out → conv_outs)
//  TODO: quantizers ×8  (conv_outs → quant_packed)
//  TODO: maxpool mux   (quant_packed → data_out)
// ════════════════════════════════════════════════════════════════
assign data_out       = '0;
assign data_out_valid = 1'b0;

endmodule
