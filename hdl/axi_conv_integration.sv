// ============================================================================
// AXI-Stream Integration Layer for conv_top
// ============================================================================
// Bridges AXI-Stream interfaces to conv_top's native interface.
// Handles weight/bias loading, pixel streaming, and output generation.
//
// Operation Sequence (CPU Driver):
//   1. Configure registers via AXI-Lite (cfg_*)
//   2. Start weight DMA → streams into weight_manager
//   3. Start bias DMA → streams into bias_store
//   4. Wait for both DMAs to complete (poll or check tlast)
//   5. Assert ap_start
//   6. Start pixel DMA → streams into conv_top
//   7. Start output DMA → receives results
//   8. Wait for ap_done
//
// ============================================================================

module axi_conv_integration #(
    parameter WT_DEPTH        = 4096,
    parameter WT_ADDR_WIDTH   = $clog2(WT_DEPTH),
    parameter BIAS_DEPTH      = 256,
    parameter BIAS_GROUP_BITS = $clog2(BIAS_DEPTH) - 1
)(
    // ════════════════════════════════════════════════════════════════
    // System
    // ════════════════════════════════════════════════════════════════
    input  logic        ap_clk,
    input  logic        ap_rst_n,

    // ════════════════════════════════════════════════════════════════
    // AXI4-Stream: Weights (128-bit, lower 72 bits used)
    // ════════════════════════════════════════════════════════════════
    input  logic                s_axis_weights_tvalid,
    output logic                s_axis_weights_tready,
    input  logic [127:0]        s_axis_weights_tdata,
    input  logic [15:0]         s_axis_weights_tkeep,
    input  logic                s_axis_weights_tlast,

    // ════════════════════════════════════════════════════════════════
    // AXI4-Stream: Bias (128-bit)
    // ════════════════════════════════════════════════════════════════
    input  logic                s_axis_bias_tvalid,
    output logic                s_axis_bias_tready,
    input  logic [127:0]        s_axis_bias_tdata,
    input  logic [15:0]         s_axis_bias_tkeep,
    input  logic                s_axis_bias_tlast,

    // ════════════════════════════════════════════════════════════════
    // AXI4-Stream: Pixels (64-bit)
    // ════════════════════════════════════════════════════════════════
    input  logic                s_axis_pixels_tvalid,
    output logic                s_axis_pixels_tready,
    input  logic [63:0]         s_axis_pixels_tdata,
    input  logic [7:0]          s_axis_pixels_tkeep,
    input  logic                s_axis_pixels_tlast,

    // ════════════════════════════════════════════════════════════════
    // AXI4-Stream: Output (64-bit)
    // ════════════════════════════════════════════════════════════════
    output logic                m_axis_output_tvalid,
    input  logic                m_axis_output_tready,
    output logic [63:0]         m_axis_output_tdata,
    output logic [7:0]          m_axis_output_tkeep,
    output logic                m_axis_output_tlast,

    // ════════════════════════════════════════════════════════════════
    // ap_ctrl_hs Protocol
    // ════════════════════════════════════════════════════════════════
    input  logic                ap_start,
    output logic                ap_idle,
    output logic                ap_done,
    output logic                ap_ready,

    // ════════════════════════════════════════════════════════════════
    // Configuration (32-bit from AXI-Lite, narrowed internally)
    // ════════════════════════════════════════════════════════════════
    input  logic [31:0]         cfg_ci_groups,
    input  logic [31:0]         cfg_output_group,
    input  logic [31:0]         cfg_wt_base_addr,
    input  logic [31:0]         cfg_in_channels,
    input  logic [31:0]         cfg_img_width,
    input  logic [31:0]         cfg_use_maxpool,
    input  logic [31:0]         cfg_stride_2,
    input  logic [31:0]         cfg_quant_m,
    input  logic [31:0]         cfg_quant_n,
    input  logic [31:0]         cfg_use_relu,
    input  logic [31:0]         cfg_kernel_1x1
);

// ════════════════════════════════════════════════════════════════════
// Internal signals
// ════════════════════════════════════════════════════════════════════
logic rst;
assign rst = ~ap_rst_n;

// conv_top signals
logic        conv_go;
logic        conv_busy;
logic        conv_done;

// ════════════════════════════════════════════════════════════════════
// Registered config signals
// Breaks timing path from AXI-Lite registers to deep logic.
// Config is latched when idle/ready, before computation starts.
// max_fanout forces Vivado to replicate high-fanout registers.
// ════════════════════════════════════════════════════════════════════
(* max_fanout = 32 *) logic [31:0] cfg_ci_groups_r;
(* max_fanout = 32 *) logic [31:0] cfg_output_group_r;
(* max_fanout = 32 *) logic [31:0] cfg_wt_base_addr_r;
(* max_fanout = 32 *) logic [31:0] cfg_in_channels_r;
(* max_fanout = 32 *) logic [31:0] cfg_img_width_r;
(* max_fanout = 32 *) logic [31:0] cfg_use_maxpool_r;
(* max_fanout = 32 *) logic [31:0] cfg_stride_2_r;
(* max_fanout = 32 *) logic [31:0] cfg_quant_m_r;
(* max_fanout = 32 *) logic [31:0] cfg_quant_n_r;
(* max_fanout = 32 *) logic [31:0] cfg_use_relu_r;
(* max_fanout = 32 *) logic [31:0] cfg_kernel_1x1_r;

logic        bias_wr_en;
logic [127:0] bias_wr_data;
logic        bias_wr_addr_rst;

logic        wt_wr_en;
logic [71:0] wt_wr_data;
logic        wt_wr_addr_rst;

logic [63:0] pixel_in;
logic        pixel_in_valid;
logic        pixel_in_last;

logic [63:0] data_out;
logic        data_out_valid;

// ════════════════════════════════════════════════════════════════════
// Main State Machine
// ════════════════════════════════════════════════════════════════════
typedef enum logic [2:0] {
    ST_IDLE,        // Waiting, accepting weight/bias streams
    ST_READY,       // Weights and biases loaded, waiting for ap_start
    ST_GO,          // Pulse go signal
    ST_RUNNING,     // Convolution in progress
    ST_DONE         // Convolution complete
} state_t;

state_t state;

// Track weight and bias loading completion
logic wt_load_done;
logic bias_load_done;

// ap_start edge detection
logic ap_start_d;
logic ap_start_pulse;

always_ff @(posedge ap_clk) begin
    if (rst)
        ap_start_d <= 1'b0;
    else
        ap_start_d <= ap_start;
end

assign ap_start_pulse = ap_start && !ap_start_d;

// ════════════════════════════════════════════════════════════════════
// Weight Loading FSM
// ════════════════════════════════════════════════════════════════════
typedef enum logic [1:0] {
    WT_IDLE,
    WT_FIRST,   // First word: reset address
    WT_LOAD,    // Loading remaining words
    WT_DONE
} wt_state_t;

wt_state_t wt_state;

always_ff @(posedge ap_clk) begin
    if (rst) begin
        wt_state      <= WT_IDLE;
        wt_load_done  <= 1'b0;
    end else begin
        case (wt_state)
            WT_IDLE: begin
                if (s_axis_weights_tvalid && s_axis_weights_tready)
                    wt_state <= WT_FIRST;
            end

            WT_FIRST: begin
                // Address was reset, now loading
                if (s_axis_weights_tlast && s_axis_weights_tvalid && s_axis_weights_tready) begin
                    wt_state     <= WT_DONE;
                    wt_load_done <= 1'b1;
                end else begin
                    wt_state <= WT_LOAD;
                end
            end

            WT_LOAD: begin
                if (s_axis_weights_tlast && s_axis_weights_tvalid && s_axis_weights_tready) begin
                    wt_state     <= WT_DONE;
                    wt_load_done <= 1'b1;
                end
            end

            WT_DONE: begin
                // Stay done until main FSM resets us
                if (state == ST_DONE && !ap_start) begin
                    wt_state     <= WT_IDLE;
                    wt_load_done <= 1'b0;
                end
            end
        endcase
    end
end

// Weight write signals
assign s_axis_weights_tready = (wt_state == WT_IDLE) ||
                                (wt_state == WT_FIRST) ||
                                (wt_state == WT_LOAD);
assign wt_wr_en       = s_axis_weights_tvalid && s_axis_weights_tready;
assign wt_wr_data     = s_axis_weights_tdata[71:0];  // Lower 72 bits
assign wt_wr_addr_rst = (wt_state == WT_IDLE) && s_axis_weights_tvalid;

// ════════════════════════════════════════════════════════════════════
// Bias Loading FSM
// ════════════════════════════════════════════════════════════════════
typedef enum logic [1:0] {
    BIAS_IDLE,
    BIAS_FIRST,
    BIAS_LOAD,
    BIAS_DONE
} bias_state_t;

bias_state_t bias_state;

always_ff @(posedge ap_clk) begin
    if (rst) begin
        bias_state     <= BIAS_IDLE;
        bias_load_done <= 1'b0;
    end else begin
        case (bias_state)
            BIAS_IDLE: begin
                if (s_axis_bias_tvalid && s_axis_bias_tready)
                    bias_state <= BIAS_FIRST;
            end

            BIAS_FIRST: begin
                if (s_axis_bias_tlast && s_axis_bias_tvalid && s_axis_bias_tready) begin
                    bias_state     <= BIAS_DONE;
                    bias_load_done <= 1'b1;
                end else begin
                    bias_state <= BIAS_LOAD;
                end
            end

            BIAS_LOAD: begin
                if (s_axis_bias_tlast && s_axis_bias_tvalid && s_axis_bias_tready) begin
                    bias_state     <= BIAS_DONE;
                    bias_load_done <= 1'b1;
                end
            end

            BIAS_DONE: begin
                if (state == ST_DONE && !ap_start) begin
                    bias_state     <= BIAS_IDLE;
                    bias_load_done <= 1'b0;
                end
            end
        endcase
    end
end

// Bias write signals
assign s_axis_bias_tready = (bias_state == BIAS_IDLE) ||
                            (bias_state == BIAS_FIRST) ||
                            (bias_state == BIAS_LOAD);
assign bias_wr_en       = s_axis_bias_tvalid && s_axis_bias_tready;
assign bias_wr_data     = s_axis_bias_tdata;
assign bias_wr_addr_rst = (bias_state == BIAS_IDLE) && s_axis_bias_tvalid;

// ════════════════════════════════════════════════════════════════════
// Config Register Pipeline
// Latch config values when idle/ready to break timing paths.
// ════════════════════════════════════════════════════════════════════
always_ff @(posedge ap_clk) begin
    if (rst) begin
        cfg_ci_groups_r    <= '0;
        cfg_output_group_r <= '0;
        cfg_wt_base_addr_r <= '0;
        cfg_in_channels_r  <= '0;
        cfg_img_width_r    <= '0;
        cfg_use_maxpool_r  <= '0;
        cfg_stride_2_r     <= '0;
        cfg_quant_m_r      <= '0;
        cfg_quant_n_r      <= '0;
        cfg_use_relu_r     <= '0;
        cfg_kernel_1x1_r   <= '0;
    end else if (state == ST_IDLE || state == ST_READY) begin
        // Latch config only when not running
        cfg_ci_groups_r    <= cfg_ci_groups;
        cfg_output_group_r <= cfg_output_group;
        cfg_wt_base_addr_r <= cfg_wt_base_addr;
        cfg_in_channels_r  <= cfg_in_channels;
        cfg_img_width_r    <= cfg_img_width;
        cfg_use_maxpool_r  <= cfg_use_maxpool;
        cfg_stride_2_r     <= cfg_stride_2;
        cfg_quant_m_r      <= cfg_quant_m;
        cfg_quant_n_r      <= cfg_quant_n;
        cfg_use_relu_r     <= cfg_use_relu;
        cfg_kernel_1x1_r   <= cfg_kernel_1x1;
    end
end

// ════════════════════════════════════════════════════════════════════
// Main State Machine
// ════════════════════════════════════════════════════════════════════
always_ff @(posedge ap_clk) begin
    if (rst) begin
        state <= ST_IDLE;
    end else begin
        case (state)
            ST_IDLE: begin
                // Wait for both weight and bias loading to complete
                if (wt_load_done && bias_load_done)
                    state <= ST_READY;
            end

            ST_READY: begin
                // Wait for ap_start
                if (ap_start_pulse)
                    state <= ST_GO;
            end

            ST_GO: begin
                // Single cycle go pulse
                state <= ST_RUNNING;
            end

            ST_RUNNING: begin
                // Wait for convolution to complete
                if (conv_done)
                    state <= ST_DONE;
            end

            ST_DONE: begin
                // Wait for ap_start to deassert, then return to idle
                if (!ap_start)
                    state <= ST_IDLE;
            end
        endcase
    end
end

// ════════════════════════════════════════════════════════════════════
// conv_top Control Signals
// ════════════════════════════════════════════════════════════════════
assign conv_go = (state == ST_GO);

// ════════════════════════════════════════════════════════════════════
// Pixel Stream Handling
// ════════════════════════════════════════════════════════════════════
// Accept pixels only when conv_top is running (busy)
assign s_axis_pixels_tready = conv_busy;
assign pixel_in             = s_axis_pixels_tdata;
assign pixel_in_valid       = s_axis_pixels_tvalid && s_axis_pixels_tready;
assign pixel_in_last        = s_axis_pixels_tlast;

// ════════════════════════════════════════════════════════════════════
// Output Stream Handling
// ════════════════════════════════════════════════════════════════════
// Note: conv_top does not support backpressure. We assume the output
// DMA is always ready. For robust operation, add an output FIFO.
assign m_axis_output_tdata  = data_out;
assign m_axis_output_tvalid = data_out_valid;
assign m_axis_output_tkeep  = 8'hFF;
assign m_axis_output_tlast  = conv_done;

// ════════════════════════════════════════════════════════════════════
// ap_ctrl_hs Protocol Signals
// ════════════════════════════════════════════════════════════════════
assign ap_idle  = (state == ST_IDLE) || (state == ST_READY);
assign ap_done  = (state == ST_DONE);
assign ap_ready = (state == ST_DONE);

// ════════════════════════════════════════════════════════════════════
// conv_top Instance
// Uses registered config signals to break timing paths from AXI-Lite.
// ════════════════════════════════════════════════════════════════════
conv_top #(
    .WT_DEPTH   (WT_DEPTH),
    .BIAS_DEPTH (BIAS_DEPTH)
) u_conv_top (
    .clk              (ap_clk),
    .rst              (rst),

    // Configuration (use registered values, narrow to actual widths)
    .cfg_ci_groups    (cfg_ci_groups_r[9:0]),
    .cfg_output_group (cfg_output_group_r[BIAS_GROUP_BITS-1:0]),
    .cfg_wt_base_addr (cfg_wt_base_addr_r[WT_ADDR_WIDTH-1:0]),
    .cfg_in_channels  (cfg_in_channels_r[15:0]),
    .cfg_img_width    (cfg_img_width_r[15:0]),
    .cfg_use_maxpool  (cfg_use_maxpool_r[0]),
    .cfg_stride_2     (cfg_stride_2_r[0]),
    .cfg_quant_m      (cfg_quant_m_r),
    .cfg_quant_n      (cfg_quant_n_r[4:0]),
    .cfg_use_relu     (cfg_use_relu_r[0]),
    .cfg_kernel_1x1   (cfg_kernel_1x1_r[0]),

    // Control
    .go               (conv_go),
    .busy             (conv_busy),
    .done             (conv_done),

    // Bias write port
    .bias_wr_en       (bias_wr_en),
    .bias_wr_data     (bias_wr_data),
    .bias_wr_addr_rst (bias_wr_addr_rst),

    // Weight write port
    .wt_wr_en         (wt_wr_en),
    .wt_wr_data       (wt_wr_data),
    .wt_wr_addr_rst   (wt_wr_addr_rst),

    // Pixel input
    .pixel_in         (pixel_in),
    .pixel_in_valid   (pixel_in_valid),
    .pixel_in_last    (pixel_in_last),

    // Data output
    .data_out         (data_out),
    .data_out_valid   (data_out_valid)
);

endmodule
