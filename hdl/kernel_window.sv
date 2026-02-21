// 3x3 sliding window generator for NHWC convolution
// Uses line buffers + delay lines to produce 9 pixels per clock
module kernelWindow #(
    parameter MAX_DEPTH = 8192
)(
    input logic clk,
    input logic rst,
    input logic data_valid,
    input logic [15:0] in_channels,
    input logic [15:0] img_width,
    input logic [63:0] pixel_in,
    output logic [63:0] window[0:2][0:2],
    output logic dout_valid
);

logic [63:0] row0, row1, row2;

// Registered config-derived values (timing fix: breaks DSP → comparison path)
(* max_fanout = 32 *) logic [7:0]  delay_depth_r;
(* max_fanout = 32 *) logic [31:0] vectors_per_row_r;
(* max_fanout = 32 *) logic [31:0] total_delay_r;
(* max_fanout = 32 *) logic [31:0] col_threshold_r;
(* max_fanout = 32 *) logic [31:0] lb0_width_r;

always_ff @(posedge clk) begin
    if (rst) begin
        delay_depth_r     <= '0;
        vectors_per_row_r <= '0;
        total_delay_r     <= '0;
        col_threshold_r   <= '0;
        lb0_width_r       <= '0;
    end else begin
        delay_depth_r     <= in_channels >> 3;
        vectors_per_row_r <= img_width * delay_depth_r;
        total_delay_r     <= (vectors_per_row_r << 1) + (delay_depth_r << 1) - 1;
        col_threshold_r   <= delay_depth_r << 1;
        lb0_width_r       <= vectors_per_row_r - 1;
    end
end

logic [31:0] delay_count;
logic        priming_done;

logic [31:0] col_cnt;
logic        col_valid;

always_ff @(posedge clk) begin
    if (data_valid)
        row2 <= pixel_in;
end

always_ff @(posedge clk) begin
    if (rst) begin
        delay_count  <= '0;
        priming_done <= '0;
    end else if (data_valid) begin
        if (!priming_done) begin
            if (delay_count >= total_delay_r)
                priming_done <= 1'b1;
            else
                delay_count <= delay_count + 1'b1;
        end
    end
end

always_ff @(posedge clk) begin
    if (rst)
        col_cnt <= '0;
    else if (data_valid)
        col_cnt <= (col_cnt >= vectors_per_row_r - 1) ? '0 : col_cnt + 1;
end

assign col_valid  = (col_cnt >= col_threshold_r);
assign dout_valid = priming_done && data_valid && col_valid;

lineBuffer LineBuffer1 (
    .clk(clk), .rst(rst),
    .curr_width(vectors_per_row_r),
    .pixel(pixel_in), .data_valid(data_valid),
    .o_data(row1)
);

lineBuffer LineBuffer0 (
    .clk(clk), .rst(rst),
    .curr_width(lb0_width_r),
    .pixel(row1), .data_valid(data_valid),
    .o_data(row0)
);

// Row 2 delay chain
delayLine DelayLine2_1 (.clk(clk), .rst(rst), .en(data_valid), .delay_depth(delay_depth_r), .din(row2), .dout(window[2][1]));
delayLine DelayLine2_0 (.clk(clk), .rst(rst), .en(data_valid), .delay_depth(delay_depth_r), .din(window[2][1]), .dout(window[2][0]));
assign window[2][2] = row2;

// Row 1 delay chain
delayLine DelayLine1_1 (.clk(clk), .rst(rst), .en(data_valid), .delay_depth(delay_depth_r), .din(row1), .dout(window[1][1]));
delayLine DelayLine1_0 (.clk(clk), .rst(rst), .en(data_valid), .delay_depth(delay_depth_r), .din(window[1][1]), .dout(window[1][0]));
assign window[1][2] = row1;

// Row 0 delay chain
delayLine DelayLine0_1 (.clk(clk), .rst(rst), .en(data_valid), .delay_depth(delay_depth_r), .din(row0), .dout(window[0][1]));
delayLine DelayLine0_0 (.clk(clk), .rst(rst), .en(data_valid), .delay_depth(delay_depth_r), .din(window[0][1]), .dout(window[0][0]));
assign window[0][2] = row0;

endmodule
