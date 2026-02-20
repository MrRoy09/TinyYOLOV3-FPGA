module maxPool #()
(
    input logic clk,
    input logic rst,
    input logic [15:0] img_width,
    input logic [15:0] channels,
    input logic stride_2,

    input logic [63:0] data_in,
    input logic valid_in,

    output logic [63:0] data_out,
    output logic valid_out
);

// ════════════════════════════════════════════════════════════════════════════
// Local config registers - break timing path from AXI config to LineBuffer
// These configs are stable before processing starts, so registering is safe.
// ════════════════════════════════════════════════════════════════════════════
(* max_fanout = 32 *) logic [15:0] img_width_r;
(* max_fanout = 32 *) logic [15:0] channels_r;
(* max_fanout = 32 *) logic        stride_2_r;
(* max_fanout = 32 *) logic [7:0]  ch_limit_r;
(* max_fanout = 32 *) logic [31:0] vectors_per_row_r;

always_ff @(posedge clk) begin
    if (rst) begin
        img_width_r       <= '0;
        channels_r        <= '0;
        stride_2_r        <= '0;
        ch_limit_r        <= '0;
        vectors_per_row_r <= '0;
    end else begin
        img_width_r <= img_width;
        channels_r  <= channels;
        stride_2_r  <= stride_2;
        ch_limit_r  <= channels_r >> 3;
        vectors_per_row_r <= (stride_2_r ? img_width_r >> 1 : img_width_r) * ch_limit_r;
    end
end

// ════════════════════════════════════════════════════════════════════════════
// Stride-1 Padding Injection: Replace padding positions with -128
// For stride-1 maxpool, host pads conv input to produce (H+1)x(W+1) output.
// The extra row/column is padding. We inject -128 so it never wins the max.
// ════════════════════════════════════════════════════════════════════════════
localparam [63:0] PAD_VALUE = 64'h8080808080808080;  // -128 for all 8 channels

logic [12:0] ch_cnt;
logic [15:0] col_cnt;
logic [15:0] row_cnt;

// Detect padding positions for stride-1 (assume square: img_height = img_width)
wire is_padding_col = (col_cnt == img_width_r - 1);
wire is_padding_row = (row_cnt == img_width_r - 1);
wire is_padding = !stride_2_r && (is_padding_col || is_padding_row);

// Effective data_in: replace with PAD_VALUE at padding positions
wire [63:0] data_in_eff = is_padding ? PAD_VALUE : data_in;

logic [63:0] prev_col;
logic [63:0] h_max;

logic [63:0] prev_row;
logic lb_en;

logic [63:0] v_max;
logic [63:0] h_max_latched;

// Pipeline stage 1: delayed input tracking
logic v_in_q;
logic [15:0] col_q, row_q;

// Pipeline stage 2: captured at lb_en time for v_max + valid_out
logic [63:0] h_max_for_vmax;
logic lb_en_q;
logic [15:0] row_at_lben;
logic [15:0] col_at_lben;  // Track column position for stride-1 col 0 skip

// ── Input position counters (use registered configs) ──
always_ff @(posedge clk) begin
    if(rst) begin
        ch_cnt <= 0;
        row_cnt <= 0;
        col_cnt <= 0;
    end else if (valid_in) begin
        if (ch_cnt == ch_limit_r - 1) begin
            ch_cnt <= 0;
            if (col_cnt == img_width_r - 1) begin
                col_cnt <= 0;
                row_cnt <= row_cnt + 1;
            end else begin
                col_cnt <= col_cnt + 1;
            end
        end else begin
            ch_cnt <= ch_cnt + 1;
        end
    end
end

// ── Stage 1: h_max_latched and delayed tracking ──
always_ff @(posedge clk) begin
    if (rst) begin
        h_max_latched <= '0;
        v_in_q <= 0;
    end else begin
        v_in_q    <= valid_in;
        col_q     <= col_cnt;
        row_q     <= row_cnt;

        // Latch h_max at odd columns (stride-2) or every column (stride-1).
        // Use registered stride_2_r for timing closure.
        if (valid_in && (stride_2_r ? col_cnt[0] : 1'b1))
            h_max_latched <= h_max;
    end
end

// ── Horizontal max (combinatorial) ──
// Uses data_in_eff to inject -128 at padding positions for stride-1
assign h_max = vec_max(prev_col, data_in_eff);

// ── lb_en: triggers LB write and h_max_for_vmax capture ──
// Use registered stride_2_r for timing closure.
assign lb_en = v_in_q && (stride_2_r ? col_q[0] : 1'b1);

// ── Stage 2: capture h_max_latched at lb_en, delay lb_en by 1 ──
// When lb_en fires, h_max_latched is still valid (set at odd col,
// lb_en fires 1 cycle later at even col, so h_max_latched hasn't changed).
// Also capture row_q and col_q for the valid_out check.
always_ff @(posedge clk) begin
    if (rst) begin
        h_max_for_vmax <= '0;
        lb_en_q <= 0;
        row_at_lben <= 0;
        col_at_lben <= 0;
    end else begin
        lb_en_q <= lb_en;
        if (lb_en) begin
            h_max_for_vmax <= h_max_latched;
            row_at_lben <= row_q;
            col_at_lben <= col_q;  // Capture column position at lb_en time
        end
    end
end

// ── Vertical max: uses captured h_max and LB prev_row ──
// Both h_max_for_vmax and prev_row are stable 1 cycle after lb_en.
assign v_max = vec_max(h_max_for_vmax, prev_row);

// ── Output register ──
// valid_out fires 1 cycle after lb_en (= lb_en_q), gated by row/col conditions.
// Use registered stride_2_r for timing closure.
// For stride-2: output at odd rows only (row_at_lben[0])
// For stride-1 with padded input: skip row 0 AND col 0
//   (backward-looking output at [R][C] maps to forward-looking at [R-1][C-1])
always_ff @(posedge clk) begin
    if(rst) begin
        data_out <= 0;
        valid_out <= 0;
    end else begin
        data_out <= v_max;
        if(stride_2_r)
            valid_out <= lb_en_q && row_at_lben[0];
        else
            valid_out <= lb_en_q && (row_at_lben > 0) && (col_at_lben > 0);
    end
end

function automatic logic [63:0] vec_max(input logic [63:0] a , input logic [63:0] b);
    logic [63:0] res;
    for (int i = 0 ; i<8; i++) begin
        if($signed(a[i*8 +: 8]) > $signed(b[i*8 +: 8])) res[i*8 +: 8] = a[i*8 +: 8];
        else res[i*8 +: 8] = b[i*8 +: 8];
    end
    return res;
endfunction

// ── Inline circular buffer for column delay ──
// For ch_limit=1: direct register (1-cycle delay).
// For ch_limit>=2: circular buffer with ch_limit-1 entries + output reg = ch_limit total.
logic [63:0] col_buf [0:127];
logic [7:0]  col_buf_ptr;

initial begin
    for (int i = 0; i < 128; i++) col_buf[i] = '0;
end

always_ff @(posedge clk) begin
    if (rst) begin
        prev_col    <= '0;
        col_buf_ptr <= '0;
    end else if (valid_in) begin
        if (ch_limit_r <= 8'd1) begin
            // Direct 1-cycle delay (bypass circular buffer)
            // Uses data_in_eff for stride-1 padding injection
            prev_col <= data_in_eff;
        end else begin
            // Circular buffer: ch_limit-1 entries + 1 output reg = ch_limit total
            // Uses data_in_eff for stride-1 padding injection
            prev_col             <= col_buf[col_buf_ptr];
            col_buf[col_buf_ptr] <= data_in_eff;
            if (col_buf_ptr >= ch_limit_r - 2)
                col_buf_ptr <= '0;
            else
                col_buf_ptr <= col_buf_ptr + 1'b1;
        end
    end
end

// ── Row line buffer ──
// Use registered vectors_per_row_r for timing closure.
lineBuffer LineBuffer1 (
    .clk(clk),
    .rst(rst),
    .curr_width(vectors_per_row_r),
    .pixel(h_max_latched),
    .data_valid(lb_en),
    .o_data(prev_row)
);

endmodule
