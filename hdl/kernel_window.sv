module kernelWindow #(
    parameter MAX_DEPTH = 8192
)
(
    input logic clk,
    input logic rst,
    input logic data_valid,
    input logic [15:0] in_channels,
    input logic [15:0] img_width,
    input logic [63:0] pixel_in,
    output logic [63:0] window[0:2][0:2],
    output logic dout_valid,
    // Debug outputs
    output logic [63:0] dbg_row0,
    output logic [63:0] dbg_row1,
    output logic [63:0] dbg_row2,
    output logic [31:0] dbg_delay_count,
    output logic [31:0] dbg_total_delay,
    output logic        dbg_priming_done,
    output logic [31:0] dbg_col_cnt,
    output logic        dbg_col_valid,
    output logic [7:0]  dbg_delay_depth,
    output logic [31:0] dbg_vectors_per_row
);

logic [63:0] row0, row1, row2;
logic [7:0] delay_depth;
logic [31:0] vectors_per_row;

// Priming Logic
logic [31:0] delay_count;
logic        priming_done;
logic [31:0] total_delay;

// Column counter: suppresses output during the first 2*delay_depth
// beats of each row, where delay lines wrap across the row boundary.
// With zero-padded input the values happen to be correct, but the
// spatial positions are padding columns that must not generate
// conv_valid_in pulses.
logic [31:0] col_cnt;
logic        col_valid;

assign delay_depth = in_channels >> 3;
assign vectors_per_row = img_width * delay_depth;

// Register row2 to match lineBuffer timing (both are registered outputs)
always_ff @(posedge clk) begin
    if (data_valid)
        row2 <= pixel_in;
end

// Pipeline depth = 2*vectors_per_row + 2*delay_depth.
// Subtract 1 because priming_done is registered (takes effect
// one cycle after the trigger), so the trigger must fire one
// cycle early to align with the first valid window output.
assign total_delay = (vectors_per_row << 1) + (delay_depth << 1) - 1;

always_ff @(posedge clk) begin
    if (rst) begin
        delay_count  <= '0;
        priming_done <= '0;
    end else if (data_valid) begin
        if (!priming_done) begin
            if (delay_count >= total_delay) begin
                priming_done <= 1'b1;
            end else begin
                delay_count <= delay_count + 1'b1;
            end
        end
    end
end

always_ff @(posedge clk) begin
    if (rst) begin
        col_cnt <= '0;
    end else if (data_valid) begin
        if (col_cnt == vectors_per_row - 1)
            col_cnt <= '0;
        else
            col_cnt <= col_cnt + 1;
    end
end

assign col_valid  = (col_cnt >= (delay_depth << 1));
assign dout_valid = priming_done && data_valid && col_valid;

lineBuffer LineBuffer1 (
    .clk(clk),
    .rst(rst),
    .curr_width(vectors_per_row),
    .pixel(pixel_in),
    .data_valid(data_valid),
    .o_data(row1)
);

// LineBuffer0 takes row1 (which already has 1 extra cycle of delay from
// LineBuffer1's registered output). To get exactly 2*vectors_per_row total
// delay for row0 (relative to the 1-cycle delayed row2), we need
// LineBuffer0 to provide (vectors_per_row - 1) buffer cycles + 1 register
// cycle = vectors_per_row cycles. This compensates for the cascaded
// registered output latency.
lineBuffer LineBuffer0 (
    .clk(clk),
    .rst(rst),
    .curr_width(vectors_per_row - 1),
    .pixel(row1),
    .data_valid(data_valid),
    .o_data(row0)
);

delayLine DelayLine2_1 (
    .clk(clk), .rst(rst), .en(data_valid), .delay_depth(delay_depth),
    .din(row2), .dout(window[2][1])
);
delayLine DelayLine2_0 (
    .clk(clk), .rst(rst), .en(data_valid), .delay_depth(delay_depth),
    .din(window[2][1]), .dout(window[2][0])
);
assign window[2][2] = row2;


delayLine DelayLine1_1 (
    .clk(clk), .rst(rst), .en(data_valid), .delay_depth(delay_depth),
    .din(row1), .dout(window[1][1])
);
delayLine DelayLine1_0 (
    .clk(clk), .rst(rst), .en(data_valid), .delay_depth(delay_depth),
    .din(window[1][1]), .dout(window[1][0])
);
assign window[1][2] = row1;


delayLine DelayLine0_1 (
    .clk(clk), .rst(rst), .en(data_valid), .delay_depth(delay_depth),
    .din(row0), .dout(window[0][1])
);
delayLine DelayLine0_0 (
    .clk(clk), .rst(rst), .en(data_valid), .delay_depth(delay_depth),
    .din(window[0][1]), .dout(window[0][0])
);
assign window[0][2] = row0;

// Debug outputs
assign dbg_row0 = row0;
assign dbg_row1 = row1;
assign dbg_row2 = row2;
assign dbg_delay_count = delay_count;
assign dbg_total_delay = total_delay;
assign dbg_priming_done = priming_done;
assign dbg_col_cnt = col_cnt;
assign dbg_col_valid = col_valid;
assign dbg_delay_depth = delay_depth;
assign dbg_vectors_per_row = vectors_per_row;

endmodule