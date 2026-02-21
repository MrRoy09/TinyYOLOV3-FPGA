// INT32 → INT8 quantizer with leaky ReLU
// Pipeline: leaky_relu → multiply(M) → shift(n) → clamp
// Matches hardware_sim.py: leaky BEFORE quantization
module quantizer (
    input  logic        clk,
    input  logic        rst,
    input  logic signed [31:0] data_in,
    input  logic        valid_in,
    input  logic [31:0] M,
    input  logic [4:0]  n,
    input  logic        use_relu,
    output logic [7:0]  data_out,
    output logic        valid_out
);

logic signed [31:0] leaky_result;
logic signed [63:0] mult_result;
logic signed [31:0] shifted_result;
logic [3:0] valid_pipe;
logic [3:0] use_relu_pipe;

always_ff @(posedge clk) begin
    if(rst) begin
        leaky_result <= '0;
        mult_result <= '0;
        shifted_result <= '0;
        data_out <= '0;
        valid_pipe <= '0;
        use_relu_pipe <= '0;
    end else begin
        valid_pipe <= {valid_pipe[2:0], valid_in};
        use_relu_pipe <= {use_relu_pipe[2:0], use_relu};

        // Stage 1: Leaky ReLU (negative >> 3)
        if (use_relu_pipe[0])
            leaky_result <= ($signed(data_in) >= 0) ? data_in : (data_in >>> 3);
        else
            leaky_result <= data_in;

        // Stage 2: Multiply by M
        mult_result <= leaky_result * $signed({1'b0, M});

        // Stage 3: Arithmetic right shift
        shifted_result <= mult_result >>> n;

        // Stage 4: Clamp to INT8
        if ($signed(shifted_result) > 32'sd127)
            data_out <= 8'sd127;
        else if ($signed(shifted_result) < -32'sd128)
            data_out <= -8'sd128;
        else
            data_out <= shifted_result[7:0];
    end
end

assign valid_out = valid_pipe[3];

endmodule
