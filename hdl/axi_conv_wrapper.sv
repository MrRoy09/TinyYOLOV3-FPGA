// AXI Master wrapper for conv_top - Vitis RTL Kernel integration
// FSM: IDLE → RESET → LOAD_WEIGHTS → LOAD_BIAS → START → PROCESS → DONE
`default_nettype none

module TinyYOLOV3_HW_Complete_example #(
    parameter integer C_WEIGHT_BIAS_AXI_ADDR_WIDTH = 64,
    parameter integer C_WEIGHT_BIAS_AXI_DATA_WIDTH = 128,
    parameter integer C_PIXEL_AXI_ADDR_WIDTH       = 64,
    parameter integer C_PIXEL_AXI_DATA_WIDTH       = 64,
    parameter integer C_OUTPUT_AXI_ADDR_WIDTH      = 64,
    parameter integer C_OUTPUT_AXI_DATA_WIDTH      = 64
)(
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

    // Control
    input  wire                                      ap_start,
    output wire                                      ap_idle,
    output wire                                      ap_done,
    output wire                                      ap_ready,

    // Addresses and sizes
    input  wire [63:0]                               weights_addr,
    input  wire [63:0]                               bias_addr,
    input  wire [63:0]                               pixels_addr,
    input  wire [63:0]                               output_addr,
    input  wire [31:0]                               num_weights,
    input  wire [31:0]                               num_bias,
    input  wire [31:0]                               num_pixels,
    input  wire [31:0]                               num_outputs,

    // Configuration
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

    input  wire [63:0]                               weights_addr_axi,
    input  wire [63:0]                               bias_addr_axi,
    input  wire [63:0]                               pixels_addr_axi,
    input  wire [63:0]                               output_addr_axi
);

timeunit 1ps;
timeprecision 1ps;

localparam integer LP_XFER_SIZE_WIDTH = 32;

typedef enum logic [2:0] {
    ST_IDLE         = 3'd0,
    ST_RESET        = 3'd1,
    ST_LOAD_WEIGHTS = 3'd2,
    ST_LOAD_BIAS    = 3'd3,
    ST_START        = 3'd4,
    ST_PROCESS      = 3'd5,
    ST_DONE         = 3'd6
} state_t;

state_t state, state_next;

// Multi-OG batching: process multiple output groups per kernel invocation
logic [7:0]  og_count;
wire         og_last = (og_count >= cfg_co_groups[7:0] - 8'd1);

// Pre-computed addresses (timing fix: all arithmetic in registered stage)
// FSM does simple copy, avoiding FSM→multiplier→adder→reg path
logic [63:0] weight_full_addr_r;
logic [63:0] bias_full_addr_r;
logic [63:0] output_full_addr_r;

always_ff @(posedge ap_clk) begin
    if (areset) begin
        weight_full_addr_r <= '0;
        bias_full_addr_r   <= '0;
        output_full_addr_r <= '0;
    end else begin
        weight_full_addr_r <= weights_addr_axi + ({32'b0, og_count} * {32'b0, num_weights});
        bias_full_addr_r   <= bias_addr_axi + ({32'b0, og_count} * {32'b0, num_bias});
        output_full_addr_r <= output_addr_axi + ({32'b0, og_count} * {32'b0, num_outputs});
    end
end

(* KEEP = "yes" *)
logic areset;
logic ap_start_r, ap_start_pulse;
logic ap_idle_r, ap_done_r;

logic                                    wb_rd_start, wb_rd_done;
logic [C_WEIGHT_BIAS_AXI_ADDR_WIDTH-1:0] wb_rd_addr;
logic [LP_XFER_SIZE_WIDTH-1:0]           wb_rd_size;

logic [C_WEIGHT_BIAS_AXI_DATA_WIDTH-1:0] wb_axis_tdata;
logic                                    wb_axis_tvalid, wb_axis_tready, wb_axis_tlast;

logic [71:0] wt_wr_data;
logic        wt_wr_en, wt_unpack_done;
logic        wb_rd_done_latch, bias_load_done;

logic [LP_XFER_SIZE_WIDTH-1:0] wt_total_bytes_reg, wt_byte_count;
logic [LP_XFER_SIZE_WIDTH-1:0] bias_total_bytes_reg, bias_byte_count;

logic                              px_rd_start, px_rd_done;
logic [C_PIXEL_AXI_ADDR_WIDTH-1:0] px_rd_addr;
logic [LP_XFER_SIZE_WIDTH-1:0]     px_rd_size;

logic [C_PIXEL_AXI_DATA_WIDTH-1:0] px_axis_tdata;
logic                              px_axis_tvalid, px_axis_tready, px_axis_tlast;

// Pixel byte counter: AXI TLAST fires per-burst, not at end of transfer
logic [LP_XFER_SIZE_WIDTH-1:0] px_total_bytes_reg, px_byte_count;
logic                          px_true_last;

logic                               out_wr_start, out_wr_done;
logic [C_OUTPUT_AXI_ADDR_WIDTH-1:0] out_wr_addr;
logic [LP_XFER_SIZE_WIDTH-1:0]      out_wr_size;

logic [C_OUTPUT_AXI_DATA_WIDTH-1:0] out_axis_tdata;
logic                               out_axis_tvalid, out_axis_tready;

logic        conv_go, conv_busy, conv_done_pulse, conv_done_latch;
logic [63:0] conv_data_out;
logic        conv_data_out_valid;
logic        out_wr_done_latch;

logic        bias_wr_en;
logic [127:0] bias_wr_data;
logic        bias_wr_addr_rst, wt_wr_addr_rst;
logic        loading_weights, loading_bias;

always_ff @(posedge ap_clk) begin
    areset     <= ~ap_rst_n;
    ap_start_r <= ap_start;
end
assign ap_start_pulse = ap_start & ~ap_start_r;

always_ff @(posedge ap_clk) begin
    if (areset)
        og_count <= '0;
    else if (ap_start_pulse)
        og_count <= '0;
    else if (state == ST_DONE && !og_last)
        og_count <= og_count + 8'd1;
end

// Datapath reset: clears maxpool buffers between OG iterations
localparam RESET_CYCLES = 8;
logic [3:0] reset_cnt;
logic       datapath_rst, reset_done;

always_ff @(posedge ap_clk) begin
    if (areset) begin
        reset_cnt    <= '0;
        datapath_rst <= 1'b1;
        reset_done   <= 1'b0;
    end else if (state == ST_RESET) begin
        datapath_rst <= 1'b1;
        if (reset_cnt < RESET_CYCLES - 1) begin
            reset_cnt  <= reset_cnt + 1;
            reset_done <= 1'b0;
        end else begin
            reset_done <= 1'b1;
        end
    end else begin
        reset_cnt    <= '0;
        datapath_rst <= 1'b0;
        reset_done   <= 1'b0;
    end
end

// Latch wb_rd_done: may fire before data arrives due to FIFO delay
always_ff @(posedge ap_clk) begin
    if (areset)
        wb_rd_done_latch <= 1'b0;
    else if (state == ST_RESET)
        wb_rd_done_latch <= 1'b0;
    else if (wb_rd_done)
        wb_rd_done_latch <= 1'b1;
    else if ((state == ST_LOAD_WEIGHTS) && (wb_rd_done_latch && wt_unpack_done))
        wb_rd_done_latch <= 1'b0;
    else if ((state == ST_LOAD_BIAS) && (wb_rd_done_latch && bias_load_done))
        wb_rd_done_latch <= 1'b0;
end

always_ff @(posedge ap_clk) begin
    if (areset)
        state <= ST_IDLE;
    else
        state <= state_next;
end

always_comb begin
    state_next = state;
    case (state)
        ST_IDLE:         if (ap_start_pulse) state_next = ST_RESET;
        ST_RESET:        if (reset_done) state_next = ST_LOAD_WEIGHTS;
        ST_LOAD_WEIGHTS: if ((wb_rd_done || wb_rd_done_latch) && wt_unpack_done) state_next = ST_LOAD_BIAS;
        ST_LOAD_BIAS:    if ((wb_rd_done || wb_rd_done_latch) && bias_load_done) state_next = ST_START;
        ST_START:        state_next = ST_PROCESS;
        ST_PROCESS:      if (conv_done_latch && out_wr_done_latch) state_next = ST_DONE;
        ST_DONE:         state_next = og_last ? ST_IDLE : ST_RESET;
        default:         state_next = ST_IDLE;
    endcase
end

always_ff @(posedge ap_clk) begin
    if (areset)
        ap_idle_r <= 1'b1;
    else if (ap_done_r)
        ap_idle_r <= 1'b1;
    else if (ap_start_pulse)
        ap_idle_r <= 1'b0;
end
assign ap_idle = ap_idle_r;

always_ff @(posedge ap_clk) begin
    if (areset)
        ap_done_r <= 1'b0;
    else
        ap_done_r <= (state == ST_DONE) && og_last;
end
assign ap_done  = ap_done_r;
assign ap_ready = ap_done;

// Weight/Bias read master control
// CRITICAL: addr must be stable BEFORE start pulse (read master samples on same edge)
logic wb_addr_weight_set, wb_addr_bias_set;

always_ff @(posedge ap_clk) begin
    if (areset) begin
        wb_rd_start        <= 1'b0;
        wb_rd_addr         <= '0;
        wb_rd_size         <= '0;
        loading_weights    <= 1'b0;
        loading_bias       <= 1'b0;
        wb_addr_weight_set <= 1'b0;
        wb_addr_bias_set   <= 1'b0;
    end else begin
        wb_rd_start <= 1'b0;

        case (state)
            ST_IDLE: begin
                wb_addr_weight_set <= 1'b0;
                wb_addr_bias_set   <= 1'b0;
            end

            ST_RESET: begin
                // Wait reset_cnt>1 for full_addr_r to be valid after og_count change
                if (!wb_addr_weight_set && reset_cnt > 4'd1) begin
                    wb_rd_addr <= weight_full_addr_r;
                    wb_rd_size <= num_weights;
                    wb_addr_weight_set <= 1'b1;
                end
                if (reset_done && wb_addr_weight_set) begin
                    wb_rd_start     <= 1'b1;
                    loading_weights <= 1'b1;
                    loading_bias    <= 1'b0;
                end
            end

            ST_LOAD_WEIGHTS: begin
                if (!wb_addr_bias_set) begin
                    wb_rd_addr <= bias_full_addr_r;
                    wb_rd_size <= num_bias;
                    wb_addr_bias_set <= 1'b1;
                end
                if ((wb_rd_done || wb_rd_done_latch) && wt_unpack_done && wb_addr_bias_set) begin
                    wb_rd_start     <= 1'b1;
                    loading_weights <= 1'b0;
                    loading_bias    <= 1'b1;
                end
            end

            ST_LOAD_BIAS: begin
                if ((wb_rd_done || wb_rd_done_latch) && bias_load_done)
                    loading_bias <= 1'b0;
            end

            ST_DONE: begin
                wb_addr_weight_set <= 1'b0;
                wb_addr_bias_set   <= 1'b0;
            end

            default: begin
                loading_weights <= 1'b0;
                loading_bias    <= 1'b0;
            end
        endcase
    end
end

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

// Output write master: addr set in ST_LOAD_BIAS (before ST_START pulse)
always_ff @(posedge ap_clk) begin
    if (areset) begin
        out_wr_start <= 1'b0;
        out_wr_addr  <= '0;
        out_wr_size  <= '0;
    end else begin
        out_wr_start <= 1'b0;
        if (state == ST_LOAD_BIAS) begin
            out_wr_addr <= output_full_addr_r;
            out_wr_size <= num_outputs;
        end
        if (state == ST_START)
            out_wr_start <= 1'b1;
    end
end

assign conv_go = (state == ST_START);

always_ff @(posedge ap_clk) begin
    if (areset)
        conv_done_latch <= 1'b0;
    else if (state == ST_START)
        conv_done_latch <= 1'b0;
    else if (conv_done_pulse)
        conv_done_latch <= 1'b1;
end

always_ff @(posedge ap_clk) begin
    if (areset)
        out_wr_done_latch <= 1'b0;
    else if (state == ST_START)
        out_wr_done_latch <= 1'b0;
    else if (out_wr_done)
        out_wr_done_latch <= 1'b1;
end

assign wt_wr_addr_rst   = (state == ST_RESET) && reset_done;
// Bias addr reset only on first OG; subsequent OGs accumulate addresses
assign bias_wr_addr_rst = (state == ST_LOAD_WEIGHTS) && (wb_rd_done || wb_rd_done_latch) && wt_unpack_done && (og_count == 8'd0);

assign bias_wr_en   = loading_bias && wb_axis_tvalid && wb_axis_tready;
assign bias_wr_data = wb_axis_tdata;

assign wb_axis_tready = loading_weights || loading_bias;

// Weight/Bias AXI Read Master
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

assign weight_bias_axi_awvalid = 1'b0;
assign weight_bias_axi_awaddr  = '0;
assign weight_bias_axi_awlen   = '0;
assign weight_bias_axi_wvalid  = 1'b0;
assign weight_bias_axi_wdata   = '0;
assign weight_bias_axi_wstrb   = '0;
assign weight_bias_axi_wlast   = 1'b0;
assign weight_bias_axi_bready  = 1'b1;

// Weight extraction (128-bit → 72-bit)
assign wt_wr_data = wb_axis_tdata[71:0];
assign wt_wr_en   = wb_axis_tvalid && loading_weights;

logic loading_weights_d, loading_bias_d;
wire  loading_weights_rise = loading_weights && !loading_weights_d;
wire  loading_bias_rise    = loading_bias && !loading_bias_d;

always_ff @(posedge ap_clk) begin
    if (areset) begin
        loading_weights_d <= 1'b0;
        loading_bias_d    <= 1'b0;
    end else begin
        loading_weights_d <= loading_weights;
        loading_bias_d    <= loading_bias;
    end
end

always_ff @(posedge ap_clk) begin
    if (areset) begin
        wt_total_bytes_reg   <= '0;
        bias_total_bytes_reg <= '0;
    end else if (loading_weights_rise)
        wt_total_bytes_reg <= num_weights;
    else if (loading_bias_rise)
        bias_total_bytes_reg <= num_bias;
end

always_ff @(posedge ap_clk) begin
    if (areset)
        wt_byte_count <= '0;
    else if (state == ST_RESET)
        wt_byte_count <= '0;
    else if (wt_wr_en)
        wt_byte_count <= wt_byte_count + (C_WEIGHT_BIAS_AXI_DATA_WIDTH / 8);
end

always_ff @(posedge ap_clk) begin
    if (areset)
        bias_byte_count <= '0;
    else if (state == ST_RESET)
        bias_byte_count <= '0;
    else if (bias_wr_en)
        bias_byte_count <= bias_byte_count + (C_WEIGHT_BIAS_AXI_DATA_WIDTH / 8);
end

wire wt_true_last = wt_wr_en &&
                    ((wt_byte_count + (C_WEIGHT_BIAS_AXI_DATA_WIDTH / 8)) >= wt_total_bytes_reg) &&
                    (wt_total_bytes_reg != '0);

wire bias_true_last = bias_wr_en &&
                      ((bias_byte_count + (C_WEIGHT_BIAS_AXI_DATA_WIDTH / 8)) >= bias_total_bytes_reg) &&
                      (bias_total_bytes_reg != '0);

always_ff @(posedge ap_clk) begin
    if (areset)
        wt_unpack_done <= 1'b0;
    else if (state == ST_RESET)
        wt_unpack_done <= 1'b0;
    else if (wt_true_last)
        wt_unpack_done <= 1'b1;
end

always_ff @(posedge ap_clk) begin
    if (areset)
        bias_load_done <= 1'b0;
    else if (state == ST_RESET)
        bias_load_done <= 1'b0;
    else if (bias_true_last)
        bias_load_done <= 1'b1;
end

// Pixel AXI Read Master
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

assign pixel_axi_awvalid = 1'b0;
assign pixel_axi_awaddr  = '0;
assign pixel_axi_awlen   = '0;
assign pixel_axi_wvalid  = 1'b0;
assign pixel_axi_wdata   = '0;
assign pixel_axi_wstrb   = '0;
assign pixel_axi_wlast   = 1'b0;
assign pixel_axi_bready  = 1'b1;

// Pixel byte counter: AXI TLAST fires per-burst, need true last detection
always_ff @(posedge ap_clk) begin
    if (areset)
        px_total_bytes_reg <= '0;
    else if (px_rd_start)
        px_total_bytes_reg <= px_rd_size;
end

always_ff @(posedge ap_clk) begin
    if (areset)
        px_byte_count <= '0;
    else if (state == ST_RESET)
        px_byte_count <= '0;
    else if (px_axis_tvalid && px_axis_tready)
        px_byte_count <= px_byte_count + (C_PIXEL_AXI_DATA_WIDTH / 8);
end

assign px_true_last = px_axis_tvalid && px_axis_tready &&
                      ((px_byte_count + (C_PIXEL_AXI_DATA_WIDTH / 8)) >= px_total_bytes_reg) &&
                      (px_total_bytes_reg != '0);

// Output AXI Write Master
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

assign output_axi_arvalid = 1'b0;
assign output_axi_araddr  = '0;
assign output_axi_arlen   = '0;
assign output_axi_rready  = 1'b1;

// conv_top instance
conv_top u_conv_top (
    .clk              (ap_clk),
    .rst              (datapath_rst),
    .cfg_ci_groups    (cfg_ci_groups[9:0]),
    .cfg_output_group (og_count[6:0]),
    .cfg_wt_base_addr (cfg_wt_base_addr[11:0]),
    .cfg_in_channels  (cfg_in_channels[15:0]),
    .cfg_img_width    (cfg_img_width[15:0]),
    .cfg_use_maxpool  (cfg_use_maxpool[0]),
    .cfg_stride_2     (cfg_use_stride2[0]),
    .cfg_quant_m      (cfg_quant_m),
    .cfg_quant_n      (cfg_quant_n[4:0]),
    .cfg_use_relu     (cfg_use_relu[0]),
    .cfg_kernel_1x1   (cfg_kernel_1x1[0]),
    .go               (conv_go),
    .busy             (conv_busy),
    .done             (conv_done_pulse),
    .bias_wr_en       (bias_wr_en),
    .bias_wr_data     (bias_wr_data),
    .bias_wr_addr_rst (bias_wr_addr_rst),
    .wt_wr_en         (wt_wr_en),
    .wt_wr_data       (wt_wr_data),
    .wt_wr_addr_rst   (wt_wr_addr_rst),
    .pixel_in         (px_axis_tdata),
    .pixel_in_valid   (px_axis_tvalid),
    .pixel_in_last    (px_true_last),
    .data_out         (conv_data_out),
    .data_out_valid   (conv_data_out_valid)
);

assign out_axis_tdata  = conv_data_out_valid ? conv_data_out : '0;
assign out_axis_tvalid = conv_data_out_valid;
assign px_axis_tready  = 1'b1;

endmodule : TinyYOLOV3_HW_Complete_example

`default_nettype wire
