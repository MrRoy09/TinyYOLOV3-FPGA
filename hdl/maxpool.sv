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

logic [12:0] ch_cnt;
logic [15:0] col_cnt;
logic [15:0] row_cnt;
logic [7:0] ch_limit;

logic [63:0] prev_col;
logic [63:0] h_max;

logic [63:0] prev_row;
logic lb_en; 

logic [63:0] v_max;
logic [63:0] data_in_q;
logic [63:0] h_max_q;

logic v_in_q, v_in_qq, v_in_qqq;
logic [15:0] col_q, col_qq, col_qqq;
logic [15:0] row_q, row_qq, row_qqq;

logic [31:0] vectors_per_row;

assign ch_limit = channels >> 3;
assign vectors_per_row = (stride_2 ? img_width >> 1 : img_width) * ch_limit;

always_ff @(posedge clk) begin
    if(rst) begin
        ch_cnt <= 0;
        row_cnt <= 0;
        col_cnt <= 0;
    end else if (valid_in) begin
        if (ch_cnt == ch_limit - 1) begin
            ch_cnt <= 0;
            if (col_cnt == img_width -1 ) begin
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
        data_in_q <= '0;
        h_max_q    <= '0;
        {v_in_q, v_in_qq, v_in_qqq} <= '0;
    end else begin
        data_in_q <= data_in;
        v_in_q    <= valid_in;
        col_q     <= col_cnt;
        row_q     <= row_cnt;

        h_max_q   <= h_max;
        v_in_qq   <= v_in_q;
        col_qq    <= col_q;
        row_qq    <= row_q;

        v_in_qqq  <= v_in_qq;
        col_qqq   <= col_qq;
        row_qqq   <= row_qq;
    end
end

assign h_max = vec_max(prev_col, data_in_q);
assign v_max = vec_max(h_max_q, prev_row);

assign lb_en = v_in_q && (stride_2 ? col_q[0] : 1'b1);

always_ff @(posedge clk) begin
    if(rst) begin
        data_out <= 0;
        valid_out <= 0;
    end else begin
        data_out <= v_max;
        if(stride_2) begin
            valid_out <= v_in_qq && col_qq[0] && row_qq[0];
        end else begin
            valid_out <= v_in_qq && (row_qq > 0) && (col_qq > 0);
        end
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

delayLine DelayLine0 (
    .clk(clk), .rst(rst), .en(valid_in), .delay_depth(ch_limit),
    .din(data_in), .dout(prev_col)
);

lineBuffer LineBuffer1 (
    .clk(clk),
    .rst(rst),
    .curr_width(vectors_per_row),
    .pixel(h_max),
    .data_valid(lb_en),
    .o_data(prev_row)
);

endmodule