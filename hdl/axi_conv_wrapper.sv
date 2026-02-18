// ============================================================================
// TinyYOLOV3_HW_Complete_example.sv (axi_conv_wrapper)
//
// AXI Master wrapper for conv_top integration with Vitis RTL Kernel.
// Drop-in replacement for wizard-generated TinyYOLOV3_HW_Complete_example.sv
//
// Control FSM:
//   IDLE → LOAD_WEIGHTS → LOAD_BIAS → START → PROCESS → DONE
//
// AXI Ports:
//   - weight_bias_axi (128-bit): Sequential reads for weights then biases
//   - pixel_axi (64-bit): Pixel input stream during PROCESS
//   - output_axi (64-bit): Output writes during PROCESS
// ============================================================================

`default_nettype none

module TinyYOLOV3_HW_Complete_example #(
    parameter integer C_WEIGHT_BIAS_AXI_ADDR_WIDTH = 64,
    parameter integer C_WEIGHT_BIAS_AXI_DATA_WIDTH = 128,
    parameter integer C_PIXEL_AXI_ADDR_WIDTH       = 64,
    parameter integer C_PIXEL_AXI_DATA_WIDTH       = 64,
    parameter integer C_OUTPUT_AXI_ADDR_WIDTH      = 64,
    parameter integer C_OUTPUT_AXI_DATA_WIDTH      = 64
)(
    // System Signals
    input  wire                                      ap_clk,
    input  wire                                      ap_rst_n,

    // AXI4 master interface weight_bias_axi
    output wire                                      weight_bias_axi_awvalid,
    input  wire                                      weight_bias_axi_awready,
    output wire [C_WEIGHT_BIAS_AXI_ADDR_WIDTH-1:0]   weight_bias_axi_awaddr,
    output wire [7:0]                                weight_bias_axi_awlen,
    output wire                                      weight_bias_axi_wvalid,
    input  wire                                      weight_bias_axi_wready,
    output wire [C_WEIGHT_BIAS_AXI_DATA_WIDTH-1:0]   weight_bias_axi_wdata,
    output wire [C_WEIGHT_BIAS_AXI_DATA_WIDTH/8-1:0] weight_bias_axi_wstrb,
    output wire                                      weight_bias_axi_wlast,
    input  wire                                      weight_bias_axi_bvalid,
    output wire                                      weight_bias_axi_bready,
    output wire                                      weight_bias_axi_arvalid,
    input  wire                                      weight_bias_axi_arready,
    output wire [C_WEIGHT_BIAS_AXI_ADDR_WIDTH-1:0]   weight_bias_axi_araddr,
    output wire [7:0]                                weight_bias_axi_arlen,
    input  wire                                      weight_bias_axi_rvalid,
    output wire                                      weight_bias_axi_rready,
    input  wire [C_WEIGHT_BIAS_AXI_DATA_WIDTH-1:0]   weight_bias_axi_rdata,
    input  wire                                      weight_bias_axi_rlast,

    // AXI4 master interface pixel_axi
    output wire                                      pixel_axi_awvalid,
    input  wire                                      pixel_axi_awready,
    output wire [C_PIXEL_AXI_ADDR_WIDTH-1:0]         pixel_axi_awaddr,
    output wire [7:0]                                pixel_axi_awlen,
    output wire                                      pixel_axi_wvalid,
    input  wire                                      pixel_axi_wready,
    output wire [C_PIXEL_AXI_DATA_WIDTH-1:0]         pixel_axi_wdata,
    output wire [C_PIXEL_AXI_DATA_WIDTH/8-1:0]       pixel_axi_wstrb,
    output wire                                      pixel_axi_wlast,
    input  wire                                      pixel_axi_bvalid,
    output wire                                      pixel_axi_bready,
    output wire                                      pixel_axi_arvalid,
    input  wire                                      pixel_axi_arready,
    output wire [C_PIXEL_AXI_ADDR_WIDTH-1:0]         pixel_axi_araddr,
    output wire [7:0]                                pixel_axi_arlen,
    input  wire                                      pixel_axi_rvalid,
    output wire                                      pixel_axi_rready,
    input  wire [C_PIXEL_AXI_DATA_WIDTH-1:0]         pixel_axi_rdata,
    input  wire                                      pixel_axi_rlast,

    // AXI4 master interface output_axi
    output wire                                      output_axi_awvalid,
    input  wire                                      output_axi_awready,
    output wire [C_OUTPUT_AXI_ADDR_WIDTH-1:0]        output_axi_awaddr,
    output wire [7:0]                                output_axi_awlen,
    output wire                                      output_axi_wvalid,
    input  wire                                      output_axi_wready,
    output wire [C_OUTPUT_AXI_DATA_WIDTH-1:0]        output_axi_wdata,
    output wire [C_OUTPUT_AXI_DATA_WIDTH/8-1:0]      output_axi_wstrb,
    output wire                                      output_axi_wlast,
    input  wire                                      output_axi_bvalid,
    output wire                                      output_axi_bready,
    output wire                                      output_axi_arvalid,
    input  wire                                      output_axi_arready,
    output wire [C_OUTPUT_AXI_ADDR_WIDTH-1:0]        output_axi_araddr,
    output wire [7:0]                                output_axi_arlen,
    input  wire                                      output_axi_rvalid,
    output wire                                      output_axi_rready,
    input  wire [C_OUTPUT_AXI_DATA_WIDTH-1:0]        output_axi_rdata,
    input  wire                                      output_axi_rlast,

    // Control Signals
    input  wire                                      ap_start,
    output wire                                      ap_idle,
    output wire                                      ap_done,
    output wire                                      ap_ready,

    // Address and size signals
    input  wire [63:0]                               weights_addr,
    input  wire [63:0]                               bias_addr,
    input  wire [63:0]                               pixels_addr,
    input  wire [63:0]                               output_addr,
    input  wire [31:0]                               num_weights,
    input  wire [31:0]                               num_bias,
    input  wire [31:0]                               num_pixels,
    input  wire [31:0]                               num_outputs,

    // Configuration registers
    input  wire [31:0]                               cfg_ci_groups,
    input  wire [31:0]                               cfg_co_groups,
    input  wire [31:0]                               cfg_wt_base_addr,
    input  wire [31:0]                               cfg_in_channels,
    input  wire [31:0]                               cfg_img_width,
    input  wire [31:0]                               cfg_use_maxpool,
    input  wire [31:0]                               cfg_use_stride2,
    input  wire [31:0]                               cfg_quant_m,
    input  wire [31:0]                               cfg_quant_n,
    input  wire [31:0]                               cfg_use_relu,
    input  wire [31:0]                               cfg_kernel_1x1,

    // AXI pointer addresses (same values, used by AXI masters)
    input  wire [63:0]                               weights_addr_axi,
    input  wire [63:0]                               bias_addr_axi,
    input  wire [63:0]                               pixels_addr_axi,
    input  wire [63:0]                               output_addr_axi
);

timeunit 1ps;
timeprecision 1ps;

// ============================================================================
// Local Parameters
// ============================================================================
localparam integer LP_XFER_SIZE_WIDTH = 32;

// ============================================================================
// FSM States
// ============================================================================
typedef enum logic [2:0] {
    ST_IDLE         = 3'd0,
    ST_LOAD_WEIGHTS = 3'd1,
    ST_LOAD_BIAS    = 3'd2,
    ST_START        = 3'd3,
    ST_PROCESS      = 3'd4,
    ST_DONE         = 3'd5
} state_t;

state_t state, state_next;

// ============================================================================
// Internal Signals
// ============================================================================
(* KEEP = "yes" *)
logic areset;
logic ap_start_r;
logic ap_start_pulse;
logic ap_idle_r;
logic ap_done_r;

// Weight/Bias read master signals
logic                                    wb_rd_start;
logic                                    wb_rd_done;
logic [C_WEIGHT_BIAS_AXI_ADDR_WIDTH-1:0] wb_rd_addr;
logic [LP_XFER_SIZE_WIDTH-1:0]           wb_rd_size;

// Weight/Bias read master AXI-Stream output
logic [C_WEIGHT_BIAS_AXI_DATA_WIDTH-1:0] wb_axis_tdata;
logic                                    wb_axis_tvalid;
logic                                    wb_axis_tready;
logic                                    wb_axis_tlast;

// Weight unpack bridge outputs
logic [71:0] wt_wr_data;
logic        wt_wr_en;
logic        wt_unpack_done;

// Pixel read master signals
logic                                    px_rd_start;
logic                                    px_rd_done;
logic [C_PIXEL_AXI_ADDR_WIDTH-1:0]       px_rd_addr;
logic [LP_XFER_SIZE_WIDTH-1:0]           px_rd_size;

// Pixel read master AXI-Stream output
logic [C_PIXEL_AXI_DATA_WIDTH-1:0]       px_axis_tdata;
logic                                    px_axis_tvalid;
logic                                    px_axis_tready;
logic                                    px_axis_tlast;

// Output write master signals
logic                                    out_wr_start;
logic                                    out_wr_done;
logic [C_OUTPUT_AXI_ADDR_WIDTH-1:0]      out_wr_addr;
logic [LP_XFER_SIZE_WIDTH-1:0]           out_wr_size;

// Output write master AXI-Stream input
logic [C_OUTPUT_AXI_DATA_WIDTH-1:0]      out_axis_tdata;
logic                                    out_axis_tvalid;
logic                                    out_axis_tready;

// conv_top signals
logic        conv_go;
logic        conv_busy;
logic        conv_done_pulse;
logic        conv_done_latch;
logic [63:0] conv_data_out;
logic        conv_data_out_valid;

// Bias routing
logic        bias_wr_en;
logic [127:0] bias_wr_data;
logic        bias_wr_addr_rst;
logic        wt_wr_addr_rst;

// State tracking for weight vs bias loading
logic loading_weights;
logic loading_bias;

// ============================================================================
// Reset and ap_start edge detection
// ============================================================================
always_ff @(posedge ap_clk) begin
    areset     <= ~ap_rst_n;
    ap_start_r <= ap_start;
end

assign ap_start_pulse = ap_start & ~ap_start_r;

// ============================================================================
// FSM State Register
// ============================================================================
always_ff @(posedge ap_clk) begin
    if (areset)
        state <= ST_IDLE;
    else
        state <= state_next;
end

// ============================================================================
// FSM Next State Logic
// ============================================================================
always_comb begin
    state_next = state;

    case (state)
        ST_IDLE: begin
            if (ap_start_pulse)
                state_next = ST_LOAD_WEIGHTS;
        end

        ST_LOAD_WEIGHTS: begin
            if (wb_rd_done && wt_unpack_done)
                state_next = ST_LOAD_BIAS;
        end

        ST_LOAD_BIAS: begin
            if (wb_rd_done)
                state_next = ST_START;
        end

        ST_START: begin
            // Single cycle to pulse conv_go and start pixel DMA
            state_next = ST_PROCESS;
        end

        ST_PROCESS: begin
            if (conv_done_latch && out_wr_done)
                state_next = ST_DONE;
        end

        ST_DONE: begin
            state_next = ST_IDLE;
        end

        default: state_next = ST_IDLE;
    endcase
end

// ============================================================================
// FSM Output Logic
// ============================================================================

// ap_idle: high when in IDLE state
always_ff @(posedge ap_clk) begin
    if (areset)
        ap_idle_r <= 1'b1;
    else if (ap_done_r)
        ap_idle_r <= 1'b1;
    else if (ap_start_pulse)
        ap_idle_r <= 1'b0;
end

assign ap_idle = ap_idle_r;

// ap_done: pulse for one cycle when complete
always_ff @(posedge ap_clk) begin
    if (areset)
        ap_done_r <= 1'b0;
    else
        ap_done_r <= (state == ST_DONE);
end

assign ap_done  = ap_done_r;
assign ap_ready = ap_done;

// Weight/Bias read master control
always_ff @(posedge ap_clk) begin
    if (areset) begin
        wb_rd_start     <= 1'b0;
        wb_rd_addr      <= '0;
        wb_rd_size      <= '0;
        loading_weights <= 1'b0;
        loading_bias    <= 1'b0;
    end else begin
        wb_rd_start <= 1'b0;  // Default: pulse

        case (state)
            ST_IDLE: begin
                if (ap_start_pulse) begin
                    // Start weight load
                    wb_rd_start     <= 1'b1;
                    wb_rd_addr      <= weights_addr_axi;
                    wb_rd_size      <= num_weights;  // Size in bytes
                    loading_weights <= 1'b1;
                    loading_bias    <= 1'b0;
                end
            end

            ST_LOAD_WEIGHTS: begin
                if (wb_rd_done && wt_unpack_done) begin
                    // Start bias load
                    wb_rd_start     <= 1'b1;
                    wb_rd_addr      <= bias_addr_axi;
                    wb_rd_size      <= num_bias;  // Size in bytes
                    loading_weights <= 1'b0;
                    loading_bias    <= 1'b1;
                end
            end

            ST_LOAD_BIAS: begin
                if (wb_rd_done) begin
                    loading_bias <= 1'b0;
                end
            end

            default: begin
                loading_weights <= 1'b0;
                loading_bias    <= 1'b0;
            end
        endcase
    end
end

// Pixel read master control
always_ff @(posedge ap_clk) begin
    if (areset) begin
        px_rd_start <= 1'b0;
        px_rd_addr  <= '0;
        px_rd_size  <= '0;
    end else begin
        px_rd_start <= 1'b0;

        if (state == ST_START) begin
            px_rd_start <= 1'b1;
            px_rd_addr  <= pixels_addr_axi;
            px_rd_size  <= num_pixels;
        end
    end
end

// Output write master control
always_ff @(posedge ap_clk) begin
    if (areset) begin
        out_wr_start <= 1'b0;
        out_wr_addr  <= '0;
        out_wr_size  <= '0;
    end else begin
        out_wr_start <= 1'b0;

        if (state == ST_START) begin
            out_wr_start <= 1'b1;
            out_wr_addr  <= output_addr_axi;
            out_wr_size  <= num_outputs;
        end
    end
end

// conv_top control
assign conv_go = (state == ST_START);

// Latch conv_done pulse (cleared when starting new processing)
always_ff @(posedge ap_clk) begin
    if (areset)
        conv_done_latch <= 1'b0;
    else if (state == ST_START)
        conv_done_latch <= 1'b0;
    else if (conv_done_pulse)
        conv_done_latch <= 1'b1;
end

// Address reset pulses
assign wt_wr_addr_rst   = (state == ST_IDLE) && ap_start_pulse;
assign bias_wr_addr_rst = (state == ST_LOAD_WEIGHTS) && wb_rd_done && wt_unpack_done;

// Route weight/bias data based on loading state
assign bias_wr_en   = loading_bias && wb_axis_tvalid && wb_axis_tready;
assign bias_wr_data = wb_axis_tdata;

// Weight unpack bridge ready signal
assign wb_axis_tready = loading_weights ? 1'b1 :
                        loading_bias    ? 1'b1 : 1'b0;

// ============================================================================
// Weight/Bias AXI Read Master (128-bit)
// ============================================================================
TinyYOLOV3_HW_Complete_example_axi_read_master #(
    .C_M_AXI_ADDR_WIDTH  (C_WEIGHT_BIAS_AXI_ADDR_WIDTH),
    .C_M_AXI_DATA_WIDTH  (C_WEIGHT_BIAS_AXI_DATA_WIDTH),
    .C_XFER_SIZE_WIDTH   (LP_XFER_SIZE_WIDTH),
    .C_MAX_OUTSTANDING   (16),
    .C_INCLUDE_DATA_FIFO (1)
) u_wb_read_master (
    .aclk                    (ap_clk),
    .areset                  (areset),
    .ctrl_start              (wb_rd_start),
    .ctrl_done               (wb_rd_done),
    .ctrl_addr_offset        (wb_rd_addr),
    .ctrl_xfer_size_in_bytes (wb_rd_size),
    .m_axi_arvalid           (weight_bias_axi_arvalid),
    .m_axi_arready           (weight_bias_axi_arready),
    .m_axi_araddr            (weight_bias_axi_araddr),
    .m_axi_arlen             (weight_bias_axi_arlen),
    .m_axi_rvalid            (weight_bias_axi_rvalid),
    .m_axi_rready            (weight_bias_axi_rready),
    .m_axi_rdata             (weight_bias_axi_rdata),
    .m_axi_rlast             (weight_bias_axi_rlast),
    .m_axis_aclk             (ap_clk),
    .m_axis_areset           (areset),
    .m_axis_tvalid           (wb_axis_tvalid),
    .m_axis_tready           (wb_axis_tready),
    .m_axis_tdata            (wb_axis_tdata),
    .m_axis_tlast            (wb_axis_tlast)
);

// Tie off write channels (read-only port)
assign weight_bias_axi_awvalid = 1'b0;
assign weight_bias_axi_awaddr  = '0;
assign weight_bias_axi_awlen   = '0;
assign weight_bias_axi_wvalid  = 1'b0;
assign weight_bias_axi_wdata   = '0;
assign weight_bias_axi_wstrb   = '0;
assign weight_bias_axi_wlast   = 1'b0;
assign weight_bias_axi_bready  = 1'b1;

// ============================================================================
// Weight extraction (128-bit → 72-bit) - inline, no separate module needed
// ============================================================================
// Extract lower 72 bits from 128-bit AXI data
assign wt_wr_data = wb_axis_tdata[71:0];
assign wt_wr_en   = wb_axis_tvalid && loading_weights;

// Track when weight loading is done (latch on tlast)
always_ff @(posedge ap_clk) begin
    if (areset)
        wt_unpack_done <= 1'b0;
    else if ((state == ST_IDLE) && ap_start_pulse)
        wt_unpack_done <= 1'b0;  // Clear on new transfer
    else if (wb_axis_tvalid && wb_axis_tlast && loading_weights)
        wt_unpack_done <= 1'b1;
end

// ============================================================================
// Pixel AXI Read Master (64-bit)
// ============================================================================
TinyYOLOV3_HW_Complete_example_axi_read_master #(
    .C_M_AXI_ADDR_WIDTH  (C_PIXEL_AXI_ADDR_WIDTH),
    .C_M_AXI_DATA_WIDTH  (C_PIXEL_AXI_DATA_WIDTH),
    .C_XFER_SIZE_WIDTH   (LP_XFER_SIZE_WIDTH),
    .C_MAX_OUTSTANDING   (16),
    .C_INCLUDE_DATA_FIFO (1)
) u_pixel_read_master (
    .aclk                    (ap_clk),
    .areset                  (areset),
    .ctrl_start              (px_rd_start),
    .ctrl_done               (px_rd_done),
    .ctrl_addr_offset        (px_rd_addr),
    .ctrl_xfer_size_in_bytes (px_rd_size),
    .m_axi_arvalid           (pixel_axi_arvalid),
    .m_axi_arready           (pixel_axi_arready),
    .m_axi_araddr            (pixel_axi_araddr),
    .m_axi_arlen             (pixel_axi_arlen),
    .m_axi_rvalid            (pixel_axi_rvalid),
    .m_axi_rready            (pixel_axi_rready),
    .m_axi_rdata             (pixel_axi_rdata),
    .m_axi_rlast             (pixel_axi_rlast),
    .m_axis_aclk             (ap_clk),
    .m_axis_areset           (areset),
    .m_axis_tvalid           (px_axis_tvalid),
    .m_axis_tready           (px_axis_tready),
    .m_axis_tdata            (px_axis_tdata),
    .m_axis_tlast            (px_axis_tlast)
);

// Tie off write channels (read-only port)
assign pixel_axi_awvalid = 1'b0;
assign pixel_axi_awaddr  = '0;
assign pixel_axi_awlen   = '0;
assign pixel_axi_wvalid  = 1'b0;
assign pixel_axi_wdata   = '0;
assign pixel_axi_wstrb   = '0;
assign pixel_axi_wlast   = 1'b0;
assign pixel_axi_bready  = 1'b1;

// ============================================================================
// Output AXI Write Master (64-bit)
// ============================================================================
TinyYOLOV3_HW_Complete_example_axi_write_master #(
    .C_M_AXI_ADDR_WIDTH  (C_OUTPUT_AXI_ADDR_WIDTH),
    .C_M_AXI_DATA_WIDTH  (C_OUTPUT_AXI_DATA_WIDTH),
    .C_XFER_SIZE_WIDTH   (LP_XFER_SIZE_WIDTH),
    .C_MAX_OUTSTANDING   (32),
    .C_INCLUDE_DATA_FIFO (1)
) u_output_write_master (
    .aclk                    (ap_clk),
    .areset                  (areset),
    .ctrl_start              (out_wr_start),
    .ctrl_done               (out_wr_done),
    .ctrl_addr_offset        (out_wr_addr),
    .ctrl_xfer_size_in_bytes (out_wr_size),
    .m_axi_awvalid           (output_axi_awvalid),
    .m_axi_awready           (output_axi_awready),
    .m_axi_awaddr            (output_axi_awaddr),
    .m_axi_awlen             (output_axi_awlen),
    .m_axi_wvalid            (output_axi_wvalid),
    .m_axi_wready            (output_axi_wready),
    .m_axi_wdata             (output_axi_wdata),
    .m_axi_wstrb             (output_axi_wstrb),
    .m_axi_wlast             (output_axi_wlast),
    .m_axi_bvalid            (output_axi_bvalid),
    .m_axi_bready            (output_axi_bready),
    .s_axis_aclk             (ap_clk),
    .s_axis_areset           (areset),
    .s_axis_tvalid           (out_axis_tvalid),
    .s_axis_tready           (out_axis_tready),
    .s_axis_tdata            (out_axis_tdata)
);

// Tie off read channels (write-only port)
assign output_axi_arvalid = 1'b0;
assign output_axi_araddr  = '0;
assign output_axi_arlen   = '0;
assign output_axi_rready  = 1'b1;

// ============================================================================
// conv_top Instance
// ============================================================================
conv_top u_conv_top (
    .clk              (ap_clk),
    .rst              (areset),

    // Configuration (directly from AXI-Lite registers)
    .cfg_ci_groups    (cfg_ci_groups[9:0]),
    .cfg_output_group (cfg_co_groups[6:0]),      // Note: using cfg_co_groups for output group
    .cfg_wt_base_addr (cfg_wt_base_addr[11:0]),
    .cfg_in_channels  (cfg_in_channels[15:0]),
    .cfg_img_width    (cfg_img_width[15:0]),
    .cfg_use_maxpool  (cfg_use_maxpool[0]),
    .cfg_stride_2     (cfg_use_stride2[0]),
    .cfg_quant_m      (cfg_quant_m),
    .cfg_quant_n      (cfg_quant_n[4:0]),
    .cfg_use_relu     (cfg_use_relu[0]),
    .cfg_kernel_1x1   (cfg_kernel_1x1[0]),

    // Control
    .go               (conv_go),
    .busy             (conv_busy),
    .done             (conv_done_pulse),

    // Bias DMA
    .bias_wr_en       (bias_wr_en),
    .bias_wr_data     (bias_wr_data),
    .bias_wr_addr_rst (bias_wr_addr_rst),

    // Weight DMA
    .wt_wr_en         (wt_wr_en),
    .wt_wr_data       (wt_wr_data),
    .wt_wr_addr_rst   (wt_wr_addr_rst),

    // Pixel input (from pixel AXI read master)
    .pixel_in         (px_axis_tdata),
    .pixel_in_valid   (px_axis_tvalid),
    .pixel_in_last    (px_axis_tlast),

    // Output (to output AXI write master)
    .data_out         (conv_data_out),
    .data_out_valid   (conv_data_out_valid)
);

// Connect conv_top output to write master
assign out_axis_tdata  = conv_data_out;
assign out_axis_tvalid = conv_data_out_valid;

// Pixel stream ready (conv_top doesn't have backpressure, always accept)
assign px_axis_tready = 1'b1;

endmodule : TinyYOLOV3_HW_Complete_example

`default_nettype wire
