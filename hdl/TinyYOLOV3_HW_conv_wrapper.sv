// ============================================================================
// TinyYOLOV3_HW_conv_wrapper
// ============================================================================
// Drop-in replacement for TinyYOLOV3_HW_example.
// Wraps axi_conv_integration with the exact interface expected by
// TinyYOLOV3_HW.v (the RTL Kernel Wizard-generated top level).
//
// This module can be instantiated in place of TinyYOLOV3_HW_example in
// TinyYOLOV3_HW.v without any other changes.
// ============================================================================

`default_nettype none
`timescale 1ns / 1ps

module TinyYOLOV3_HW_conv_wrapper #(
    parameter integer C_S_AXIS_WEIGHTS_TDATA_WIDTH = 128,
    parameter integer C_S_AXIS_BIAS_TDATA_WIDTH    = 128,
    parameter integer C_S_AXIS_PIXELS_TDATA_WIDTH  = 64,
    parameter integer C_M_AXIS_OUTPUT_TDATA_WIDTH  = 64,
    parameter integer WT_DEPTH                     = 4096,
    parameter integer BIAS_DEPTH                   = 256
)(
    // ════════════════════════════════════════════════════════════════
    // System Signals
    // ════════════════════════════════════════════════════════════════
    input  wire                                      ap_clk,
    input  wire                                      ap_rst_n,

    // ════════════════════════════════════════════════════════════════
    // AXI4-Stream: Weights
    // ════════════════════════════════════════════════════════════════
    input  wire                                      s_axis_weights_tvalid,
    output wire                                      s_axis_weights_tready,
    input  wire [C_S_AXIS_WEIGHTS_TDATA_WIDTH-1:0]   s_axis_weights_tdata,
    input  wire [C_S_AXIS_WEIGHTS_TDATA_WIDTH/8-1:0] s_axis_weights_tkeep,
    input  wire                                      s_axis_weights_tlast,

    // ════════════════════════════════════════════════════════════════
    // AXI4-Stream: Bias
    // ════════════════════════════════════════════════════════════════
    input  wire                                      s_axis_bias_tvalid,
    output wire                                      s_axis_bias_tready,
    input  wire [C_S_AXIS_BIAS_TDATA_WIDTH-1:0]      s_axis_bias_tdata,
    input  wire [C_S_AXIS_BIAS_TDATA_WIDTH/8-1:0]    s_axis_bias_tkeep,
    input  wire                                      s_axis_bias_tlast,

    // ════════════════════════════════════════════════════════════════
    // AXI4-Stream: Pixels
    // ════════════════════════════════════════════════════════════════
    input  wire                                      s_axis_pixels_tvalid,
    output wire                                      s_axis_pixels_tready,
    input  wire [C_S_AXIS_PIXELS_TDATA_WIDTH-1:0]    s_axis_pixels_tdata,
    input  wire [C_S_AXIS_PIXELS_TDATA_WIDTH/8-1:0]  s_axis_pixels_tkeep,
    input  wire                                      s_axis_pixels_tlast,

    // ════════════════════════════════════════════════════════════════
    // AXI4-Stream: Output
    // ════════════════════════════════════════════════════════════════
    output wire                                      m_axis_output_tvalid,
    input  wire                                      m_axis_output_tready,
    output wire [C_M_AXIS_OUTPUT_TDATA_WIDTH-1:0]    m_axis_output_tdata,
    output wire [C_M_AXIS_OUTPUT_TDATA_WIDTH/8-1:0]  m_axis_output_tkeep,
    output wire                                      m_axis_output_tlast,

    // ════════════════════════════════════════════════════════════════
    // Control Signals (ap_ctrl_hs)
    // ════════════════════════════════════════════════════════════════
    input  wire                                      ap_start,
    output wire                                      ap_idle,
    output wire                                      ap_done,
    output wire                                      ap_ready,

    // ════════════════════════════════════════════════════════════════
    // Configuration Scalars (from AXI-Lite)
    // ════════════════════════════════════════════════════════════════
    input  wire [31:0]                               cfg_ci_groups,
    input  wire [31:0]                               cfg_output_group,
    input  wire [31:0]                               cfg_wt_base_addr,
    input  wire [31:0]                               cfg_in_channels,
    input  wire [31:0]                               cfg_img_width,
    input  wire [31:0]                               cfg_use_maxpool,
    input  wire [31:0]                               cfg_stride_2,
    input  wire [31:0]                               cfg_quant_m,
    input  wire [31:0]                               cfg_quant_n,
    input  wire [31:0]                               cfg_use_relu,
    input  wire [31:0]                               cfg_kernel_1x1
);

// ════════════════════════════════════════════════════════════════════
// Internal signals (wire → logic conversion for SystemVerilog modules)
// ════════════════════════════════════════════════════════════════════
logic s_axis_weights_tready_int;
logic s_axis_bias_tready_int;
logic s_axis_pixels_tready_int;
logic m_axis_output_tvalid_int;
logic [C_M_AXIS_OUTPUT_TDATA_WIDTH-1:0] m_axis_output_tdata_int;
logic [C_M_AXIS_OUTPUT_TDATA_WIDTH/8-1:0] m_axis_output_tkeep_int;
logic m_axis_output_tlast_int;
logic ap_idle_int;
logic ap_done_int;
logic ap_ready_int;

// ════════════════════════════════════════════════════════════════════
// Output assignments
// ════════════════════════════════════════════════════════════════════
assign s_axis_weights_tready = s_axis_weights_tready_int;
assign s_axis_bias_tready    = s_axis_bias_tready_int;
assign s_axis_pixels_tready  = s_axis_pixels_tready_int;
assign m_axis_output_tvalid  = m_axis_output_tvalid_int;
assign m_axis_output_tdata   = m_axis_output_tdata_int;
assign m_axis_output_tkeep   = m_axis_output_tkeep_int;
assign m_axis_output_tlast   = m_axis_output_tlast_int;
assign ap_idle               = ap_idle_int;
assign ap_done               = ap_done_int;
assign ap_ready              = ap_ready_int;

// ════════════════════════════════════════════════════════════════════
// AXI Conv Integration Instance
// ════════════════════════════════════════════════════════════════════
axi_conv_integration #(
    .WT_DEPTH   (WT_DEPTH),
    .BIAS_DEPTH (BIAS_DEPTH)
) u_axi_conv_integration (
    // System
    .ap_clk               (ap_clk),
    .ap_rst_n             (ap_rst_n),

    // AXI-Stream: Weights
    .s_axis_weights_tvalid(s_axis_weights_tvalid),
    .s_axis_weights_tready(s_axis_weights_tready_int),
    .s_axis_weights_tdata (s_axis_weights_tdata),
    .s_axis_weights_tkeep (s_axis_weights_tkeep),
    .s_axis_weights_tlast (s_axis_weights_tlast),

    // AXI-Stream: Bias
    .s_axis_bias_tvalid   (s_axis_bias_tvalid),
    .s_axis_bias_tready   (s_axis_bias_tready_int),
    .s_axis_bias_tdata    (s_axis_bias_tdata),
    .s_axis_bias_tkeep    (s_axis_bias_tkeep),
    .s_axis_bias_tlast    (s_axis_bias_tlast),

    // AXI-Stream: Pixels
    .s_axis_pixels_tvalid (s_axis_pixels_tvalid),
    .s_axis_pixels_tready (s_axis_pixels_tready_int),
    .s_axis_pixels_tdata  (s_axis_pixels_tdata),
    .s_axis_pixels_tkeep  (s_axis_pixels_tkeep),
    .s_axis_pixels_tlast  (s_axis_pixels_tlast),

    // AXI-Stream: Output
    .m_axis_output_tvalid (m_axis_output_tvalid_int),
    .m_axis_output_tready (m_axis_output_tready),
    .m_axis_output_tdata  (m_axis_output_tdata_int),
    .m_axis_output_tkeep  (m_axis_output_tkeep_int),
    .m_axis_output_tlast  (m_axis_output_tlast_int),

    // Control
    .ap_start             (ap_start),
    .ap_idle              (ap_idle_int),
    .ap_done              (ap_done_int),
    .ap_ready             (ap_ready_int),

    // Configuration
    .cfg_ci_groups        (cfg_ci_groups),
    .cfg_output_group     (cfg_output_group),
    .cfg_wt_base_addr     (cfg_wt_base_addr),
    .cfg_in_channels      (cfg_in_channels),
    .cfg_img_width        (cfg_img_width),
    .cfg_use_maxpool      (cfg_use_maxpool),
    .cfg_stride_2         (cfg_stride_2),
    .cfg_quant_m          (cfg_quant_m),
    .cfg_quant_n          (cfg_quant_n),
    .cfg_use_relu         (cfg_use_relu),
    .cfg_kernel_1x1       (cfg_kernel_1x1)
);

endmodule

`default_nettype wire
