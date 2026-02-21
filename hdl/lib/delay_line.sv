// Configurable delay line with timing-safe implementation
// Memory ops are unconditional to avoid cfg -> memory CE timing paths
module delayLine #(
    parameter WIDTH = 64,
    parameter MAX_DEPTH = 128
)(
    input logic clk,
    input logic rst,
    input logic en,
    input logic [7:0] delay_depth,
    input logic [WIDTH-1:0] din,
    output logic [WIDTH-1:0] dout
);

(* ram_style = "distributed" *)
logic [WIDTH-1:0] mem [MAX_DEPTH-1:0];
logic [7:0] ptr;
logic [WIDTH-1:0] mem_rd;
logic [WIDTH-1:0] reg_d1;

wire [7:0] wrap_threshold = delay_depth - 8'd3;

initial begin
    for (int i = 0; i < MAX_DEPTH; i++) mem[i] = '0;
end

always_ff @(posedge clk) begin
    if(rst) begin
        dout <= '0;
        mem_rd <= '0;
        reg_d1 <= '0;
        ptr <= '0;
    end else if(en) begin
        // Unconditional ops (timing-safe: no delay_depth -> CE path)
        reg_d1 <= din;
        mem_rd <= mem[ptr];
        mem[ptr] <= din;
        ptr <= (ptr >= wrap_threshold) ? '0 : ptr + 8'd1;

        // Output mux (delay_depth -> mux -> dout is OK)
        if(delay_depth <= 8'd1)
            dout <= din;
        else if(delay_depth == 8'd2)
            dout <= reg_d1;
        else
            dout <= mem_rd;
    end
end

endmodule
