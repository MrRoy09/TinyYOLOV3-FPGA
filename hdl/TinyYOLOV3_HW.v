// ============================================================================
// TinyYOLOV3_HW - RTL Kernel Top Level
// ============================================================================
// Modified version of the RTL Kernel Wizard-generated wrapper.
// Replaces the example module with TinyYOLOV3_HW_conv_wrapper.
//
// Original file: TinyYOLOV3_HW_ex/imports/TinyYOLOV3_HW.v
// ============================================================================

`default_nettype none
`timescale 1 ns / 1 ps

module TinyYOLOV3_HW #(
    parameter integer C_S_AXI_CONTROL_ADDR_WIDTH   = 12,
    parameter integer C_S_AXI_CONTROL_DATA_WIDTH   = 32,
    parameter integer C_S_AXIS_WEIGHTS_TDATA_WIDTH = 128,
    parameter integer C_S_AXIS_BIAS_TDATA_WIDTH    = 128,
    parameter integer C_S_AXIS_PIXELS_TDATA_WIDTH  = 64,
    parameter integer C_M_AXIS_OUTPUT_TDATA_WIDTH  = 64
)(
    // ════════════════════════════════════════════════════════════════
    // System Signals
    // ════════════════════════════════════════════════════════════════
    input  wire                                      ap_clk,
    input  wire                                      ap_rst_n,

    // ════════════════════════════════════════════════════════════════
    // AXI4-Stream (slave) interface s_axis_weights
    // ════════════════════════════════════════════════════════════════
    input  wire                                      s_axis_weights_tvalid,
    output wire                                      s_axis_weights_tready,
    input  wire [C_S_AXIS_WEIGHTS_TDATA_WIDTH-1:0]   s_axis_weights_tdata,
    input  wire [C_S_AXIS_WEIGHTS_TDATA_WIDTH/8-1:0] s_axis_weights_tkeep,
    input  wire                                      s_axis_weights_tlast,

    // ════════════════════════════════════════════════════════════════
    // AXI4-Stream (slave) interface s_axis_bias
    // ════════════════════════════════════════════════════════════════
    input  wire                                      s_axis_bias_tvalid,
    output wire                                      s_axis_bias_tready,
    input  wire [C_S_AXIS_BIAS_TDATA_WIDTH-1:0]      s_axis_bias_tdata,
    input  wire [C_S_AXIS_BIAS_TDATA_WIDTH/8-1:0]    s_axis_bias_tkeep,
    input  wire                                      s_axis_bias_tlast,

    // ════════════════════════════════════════════════════════════════
    // AXI4-Stream (slave) interface s_axis_pixels
    // ════════════════════════════════════════════════════════════════
    input  wire                                      s_axis_pixels_tvalid,
    output wire                                      s_axis_pixels_tready,
    input  wire [C_S_AXIS_PIXELS_TDATA_WIDTH-1:0]    s_axis_pixels_tdata,
    input  wire [C_S_AXIS_PIXELS_TDATA_WIDTH/8-1:0]  s_axis_pixels_tkeep,
    input  wire                                      s_axis_pixels_tlast,

    // ════════════════════════════════════════════════════════════════
    // AXI4-Stream (master) interface m_axis_output
    // ════════════════════════════════════════════════════════════════
    output wire                                      m_axis_output_tvalid,
    input  wire                                      m_axis_output_tready,
    output wire [C_M_AXIS_OUTPUT_TDATA_WIDTH-1:0]    m_axis_output_tdata,
    output wire [C_M_AXIS_OUTPUT_TDATA_WIDTH/8-1:0]  m_axis_output_tkeep,
    output wire                                      m_axis_output_tlast,

    // ════════════════════════════════════════════════════════════════
    // AXI4-Lite slave interface (control registers)
    // ════════════════════════════════════════════════════════════════
    input  wire                                      s_axi_control_awvalid,
    output wire                                      s_axi_control_awready,
    input  wire [C_S_AXI_CONTROL_ADDR_WIDTH-1:0]     s_axi_control_awaddr,
    input  wire                                      s_axi_control_wvalid,
    output wire                                      s_axi_control_wready,
    input  wire [C_S_AXI_CONTROL_DATA_WIDTH-1:0]     s_axi_control_wdata,
    input  wire [C_S_AXI_CONTROL_DATA_WIDTH/8-1:0]   s_axi_control_wstrb,
    input  wire                                      s_axi_control_arvalid,
    output wire                                      s_axi_control_arready,
    input  wire [C_S_AXI_CONTROL_ADDR_WIDTH-1:0]     s_axi_control_araddr,
    output wire                                      s_axi_control_rvalid,
    input  wire                                      s_axi_control_rready,
    output wire [C_S_AXI_CONTROL_DATA_WIDTH-1:0]     s_axi_control_rdata,
    output wire [2-1:0]                              s_axi_control_rresp,
    output wire                                      s_axi_control_bvalid,
    input  wire                                      s_axi_control_bready,
    output wire [2-1:0]                              s_axi_control_bresp,
    output wire                                      interrupt
);

// ════════════════════════════════════════════════════════════════════
// Local Parameters
// ════════════════════════════════════════════════════════════════════
localparam integer WT_DEPTH   = 4096;
localparam integer BIAS_DEPTH = 256;

// ════════════════════════════════════════════════════════════════════
// Wires and Variables
// ════════════════════════════════════════════════════════════════════
(* DONT_TOUCH = "yes" *)
reg                                 areset = 1'b0;

wire                                ap_start;
wire                                ap_idle;
wire                                ap_done;
wire                                ap_ready;
wire [32-1:0]                       cfg_ci_groups;
wire [32-1:0]                       cfg_output_group;
wire [32-1:0]                       cfg_wt_base_addr;
wire [32-1:0]                       cfg_in_channels;
wire [32-1:0]                       cfg_img_width;
wire [32-1:0]                       cfg_use_maxpool;
wire [32-1:0]                       cfg_stride_2;
wire [32-1:0]                       cfg_quant_m;
wire [32-1:0]                       cfg_quant_n;
wire [32-1:0]                       cfg_use_relu;
wire [32-1:0]                       cfg_kernel_1x1;

// Register and invert reset signal
always @(posedge ap_clk) begin
    areset <= ~ap_rst_n;
end

// ════════════════════════════════════════════════════════════════════
// AXI4-Lite Control Interface
// ════════════════════════════════════════════════════════════════════
TinyYOLOV3_HW_control_s_axi #(
    .C_S_AXI_ADDR_WIDTH (C_S_AXI_CONTROL_ADDR_WIDTH),
    .C_S_AXI_DATA_WIDTH (C_S_AXI_CONTROL_DATA_WIDTH)
) inst_control_s_axi (
    .ACLK             (ap_clk),
    .ARESET           (areset),
    .ACLK_EN          (1'b1),
    .AWVALID          (s_axi_control_awvalid),
    .AWREADY          (s_axi_control_awready),
    .AWADDR           (s_axi_control_awaddr),
    .WVALID           (s_axi_control_wvalid),
    .WREADY           (s_axi_control_wready),
    .WDATA            (s_axi_control_wdata),
    .WSTRB            (s_axi_control_wstrb),
    .ARVALID          (s_axi_control_arvalid),
    .ARREADY          (s_axi_control_arready),
    .ARADDR           (s_axi_control_araddr),
    .RVALID           (s_axi_control_rvalid),
    .RREADY           (s_axi_control_rready),
    .RDATA            (s_axi_control_rdata),
    .RRESP            (s_axi_control_rresp),
    .BVALID           (s_axi_control_bvalid),
    .BREADY           (s_axi_control_bready),
    .BRESP            (s_axi_control_bresp),
    .interrupt        (interrupt),
    .ap_start         (ap_start),
    .ap_done          (ap_done),
    .ap_ready         (ap_ready),
    .ap_idle          (ap_idle),
    .cfg_ci_groups    (cfg_ci_groups),
    .cfg_output_group (cfg_output_group),
    .cfg_wt_base_addr (cfg_wt_base_addr),
    .cfg_in_channels  (cfg_in_channels),
    .cfg_img_width    (cfg_img_width),
    .cfg_use_maxpool  (cfg_use_maxpool),
    .cfg_stride_2     (cfg_stride_2),
    .cfg_quant_m      (cfg_quant_m),
    .cfg_quant_n      (cfg_quant_n),
    .cfg_use_relu     (cfg_use_relu),
    .cfg_kernel_1x1   (cfg_kernel_1x1)
);

// ════════════════════════════════════════════════════════════════════
// Conv Wrapper (replaces TinyYOLOV3_HW_example)
// ════════════════════════════════════════════════════════════════════
TinyYOLOV3_HW_conv_wrapper #(
    .C_S_AXIS_WEIGHTS_TDATA_WIDTH (C_S_AXIS_WEIGHTS_TDATA_WIDTH),
    .C_S_AXIS_BIAS_TDATA_WIDTH    (C_S_AXIS_BIAS_TDATA_WIDTH),
    .C_S_AXIS_PIXELS_TDATA_WIDTH  (C_S_AXIS_PIXELS_TDATA_WIDTH),
    .C_M_AXIS_OUTPUT_TDATA_WIDTH  (C_M_AXIS_OUTPUT_TDATA_WIDTH),
    .WT_DEPTH                     (WT_DEPTH),
    .BIAS_DEPTH                   (BIAS_DEPTH)
) inst_conv_wrapper (
    .ap_clk                (ap_clk),
    .ap_rst_n              (ap_rst_n),

    // AXI-Stream: Weights
    .s_axis_weights_tvalid (s_axis_weights_tvalid),
    .s_axis_weights_tready (s_axis_weights_tready),
    .s_axis_weights_tdata  (s_axis_weights_tdata),
    .s_axis_weights_tkeep  (s_axis_weights_tkeep),
    .s_axis_weights_tlast  (s_axis_weights_tlast),

    // AXI-Stream: Bias
    .s_axis_bias_tvalid    (s_axis_bias_tvalid),
    .s_axis_bias_tready    (s_axis_bias_tready),
    .s_axis_bias_tdata     (s_axis_bias_tdata),
    .s_axis_bias_tkeep     (s_axis_bias_tkeep),
    .s_axis_bias_tlast     (s_axis_bias_tlast),

    // AXI-Stream: Pixels
    .s_axis_pixels_tvalid  (s_axis_pixels_tvalid),
    .s_axis_pixels_tready  (s_axis_pixels_tready),
    .s_axis_pixels_tdata   (s_axis_pixels_tdata),
    .s_axis_pixels_tkeep   (s_axis_pixels_tkeep),
    .s_axis_pixels_tlast   (s_axis_pixels_tlast),

    // AXI-Stream: Output
    .m_axis_output_tvalid  (m_axis_output_tvalid),
    .m_axis_output_tready  (m_axis_output_tready),
    .m_axis_output_tdata   (m_axis_output_tdata),
    .m_axis_output_tkeep   (m_axis_output_tkeep),
    .m_axis_output_tlast   (m_axis_output_tlast),

    // Control
    .ap_start              (ap_start),
    .ap_done               (ap_done),
    .ap_idle               (ap_idle),
    .ap_ready              (ap_ready),

    // Configuration
    .cfg_ci_groups         (cfg_ci_groups),
    .cfg_output_group      (cfg_output_group),
    .cfg_wt_base_addr      (cfg_wt_base_addr),
    .cfg_in_channels       (cfg_in_channels),
    .cfg_img_width         (cfg_img_width),
    .cfg_use_maxpool       (cfg_use_maxpool),
    .cfg_stride_2          (cfg_stride_2),
    .cfg_quant_m           (cfg_quant_m),
    .cfg_quant_n           (cfg_quant_n),
    .cfg_use_relu          (cfg_use_relu),
    .cfg_kernel_1x1        (cfg_kernel_1x1)
);

endmodule

`default_nettype wire
