module delayLine #(
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

initial begin
    for (int i = 0; i < MAX_DEPTH; i++) begin
        mem[i] = '0;
    end
end

always_ff @(posedge clk) begin
    if(rst) begin
        dout <= '0;
        ptr <= '0;
    end else if(en) begin
        if(delay_depth <= 1) begin
            // Bypass memory: just a register = 1 cycle delay
            dout <= din;
        end else if(delay_depth == 2) begin
            // Special case: delay_depth=2 means we want 2 cycles total delay.
            // Due to registered sampling, a simple register gives exactly 1 cycle,
            // so we need 1 additional cycle from the buffer.
            // Use a single-entry buffer (delay_depth-1 = 1 entry).
            dout <= mem[0];
            mem[0] <= din;
        end else begin
            // Circular buffer with (delay_depth-1) entries, read-before-write.
            // The registered sampling adds 1 cycle, so total = (delay_depth-1) + 1 = delay_depth.
            // Input at cycle N appears at output at cycle N+delay_depth.
            dout <= mem[ptr];
            mem[ptr] <= din;

            if(ptr >= delay_depth - 2) ptr <= '0;
            else ptr <= ptr + 1'b1;
        end
    end
end

endmodule
