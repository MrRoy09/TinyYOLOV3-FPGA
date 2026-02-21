// Line buffer: circular BRAM with dynamic width
module lineBuffer #(
    parameter MAX_WIDTH = 8192
)(
    input  logic        clk,
    input  logic        rst,
    input  logic [31:0] curr_width,
    input  logic [63:0] pixel,
    input  logic        data_valid,
    output logic [63:0] o_data
);

(* max_fanout = 32 *) logic [31:0] curr_width_r;

always_ff @(posedge clk) begin
    if (rst)
        curr_width_r <= '0;
    else
        curr_width_r <= curr_width;
end

(* ram_style = "block" *)
logic [63:0] line [MAX_WIDTH-1:0];

initial begin
    for (int i = 0; i < MAX_WIDTH; i++) line[i] = '0;
end

logic [$clog2(MAX_WIDTH)-1:0] wrPtr;

always_ff @(posedge clk) begin
    if (rst) begin
        wrPtr  <= '0;
        o_data <= '0;
    end else if (data_valid) begin
        if (curr_width_r <= 1) begin
            o_data <= pixel;
        end else begin
            o_data <= line[wrPtr];
            line[wrPtr] <= pixel;
            wrPtr <= (wrPtr >= curr_width_r - 1) ? '0 : wrPtr + 1'b1;
        end
    end
end

endmodule
