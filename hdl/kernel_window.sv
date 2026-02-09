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
    output logic dout_valid
);

logic [63:0] row0, row1, row2;
logic [7:0] delay_depth;
logic [31:0] vectors_per_row;

// Priming Logic
logic [31:0] delay_count;
logic        priming_done;
logic [31:0] total_delay;

assign delay_depth = in_channels >> 3;
assign vectors_per_row = img_width * delay_depth;
assign row2 = pixel_in;

assign total_delay = (vectors_per_row << 1) + (delay_depth << 1);

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

assign dout_valid = priming_done && data_valid;

lineBuffer LineBuffer1 (
    .clk(clk),
    .rst(rst),
    .curr_width(vectors_per_row),
    .pixel(pixel_in),
    .data_valid(data_valid),
    .o_data(row1)
);

lineBuffer LineBuffer0 (
    .clk(clk),
    .rst(rst),
    .curr_width(vectors_per_row),
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



endmodule