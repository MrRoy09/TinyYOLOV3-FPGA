// 2x2 Maxpool with stride-1 and stride-2 support
// Stride-1: host pads conv input; maxpool skips row0/col0
// Stride-2: standard 2x2 pooling with /2 output size
module maxPool #()(
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

// Registered configs for timing closure
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

// Stride-1 padding: inject -128 at padding positions
localparam [63:0] PAD_VALUE = 64'h8080808080808080;

logic [12:0] ch_cnt;
logic [15:0] col_cnt;
logic [15:0] row_cnt;

wire is_padding_col = (col_cnt == img_width_r - 1);
wire is_padding_row = (row_cnt == img_width_r - 1);
wire is_padding = !stride_2_r && (is_padding_col || is_padding_row);
wire [63:0] data_in_eff = is_padding ? PAD_VALUE : data_in;

logic [63:0] prev_col, h_max, prev_row;
logic lb_en;
logic [63:0] v_max, h_max_latched;

logic v_in_q;
logic [15:0] col_q, row_q;

logic [63:0] h_max_for_vmax;
logic lb_en_q;
logic [15:0] row_at_lben, col_at_lben;

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

always_ff @(posedge clk) begin
    if (rst) begin
        h_max_latched <= '0;
        v_in_q <= 0;
    end else begin
        v_in_q <= valid_in;
        col_q  <= col_cnt;
        row_q  <= row_cnt;
        if (valid_in && (stride_2_r ? col_cnt[0] : 1'b1))
            h_max_latched <= h_max;
    end
end

assign h_max = vec_max(prev_col, data_in_eff);
assign lb_en = v_in_q && (stride_2_r ? col_q[0] : 1'b1);

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
            col_at_lben <= col_q;
        end
    end
end

assign v_max = vec_max(h_max_for_vmax, prev_row);

// Output: stride-2 at odd rows, stride-1 skips row0/col0
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

function automatic logic [63:0] vec_max(input logic [63:0] a, input logic [63:0] b);
    logic [63:0] res;
    for (int i = 0; i < 8; i++)
        res[i*8 +: 8] = ($signed(a[i*8 +: 8]) > $signed(b[i*8 +: 8])) ? a[i*8 +: 8] : b[i*8 +: 8];
    return res;
endfunction

// Column delay buffer
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
            prev_col <= data_in_eff;
        end else begin
            prev_col             <= col_buf[col_buf_ptr];
            col_buf[col_buf_ptr] <= data_in_eff;
            col_buf_ptr <= (col_buf_ptr >= ch_limit_r - 2) ? '0 : col_buf_ptr + 1'b1;
        end
    end
end

lineBuffer LineBuffer1 (
    .clk(clk), .rst(rst),
    .curr_width(vectors_per_row_r),
    .pixel(h_max_latched), .data_valid(lb_en),
    .o_data(prev_row)
);

endmodule
