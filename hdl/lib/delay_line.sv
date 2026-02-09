module delay_line #(
    parameter WIDTH = 64,
    parameter MAX_DEPTH = 128
)(
    input logic clk,
    input logic rst,
    input logic en,
    input logic [7:0] delay_depth,// Cin/8
    input logic [WIDTH-1:0] din,
    output logic [WIDTH-1:0] dout
);

(* ram_style = "distributed" *)
logic [WIDTH-1:0] mem [MAX_DEPTH-1:0];
logic [7:0] ptr;

always_ff @(posedge clk) begin
    if(rst) begin
        dout <= '0;
        ptr <= '0;
    end else if(en) begin
        dout <= mem[ptr];
        mem[ptr] <= din;
        
        if(ptr >= delay_depth - 1) ptr <= '0;
        else ptr <= ptr + 1'b1;
    end
end

endmodule