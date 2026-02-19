module quantizer (
    input  logic        clk,
    input  logic        rst,
    input  logic signed [31:0] data_in,
    input  logic        valid_in,
    input  logic [31:0] M, // Multiplier
    input  logic [4:0]  n, // Shift
    input  logic        use_relu,
    output logic [7:0]  data_out,
    output logic        valid_out
);

// ============================================================================
// Pipeline Structure (4 stages, matching hardware_sim.py order):
//
//   Stage 1: leaky_result   = leaky_relu(data_in)     (>>3 if negative)
//   Stage 2: mult_result    = leaky_result * M
//   Stage 3: shifted_result = mult_result >>> n
//   Stage 4: data_out       = clamp(shifted_result)   (to INT8)
//
// This matches hardware_sim.py which applies leaky BEFORE quantization:
//   if activation == 'leaky': output = np.where(output > 0, output, output >> 3)
//   output = (output.astype(np.int64) * M) >> n
// ============================================================================

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
        // Pipeline control signals
        valid_pipe <= {valid_pipe[2:0], valid_in};
        use_relu_pipe <= {use_relu_pipe[2:0], use_relu};

        // Stage 1: Leaky ReLU FIRST (on accumulator, before quantization)
        // Matches hardware_sim.py: output = np.where(output > 0, output, output >> 3)
        if (use_relu_pipe[0]) begin
            if ($signed(data_in) >= 0)
                leaky_result <= data_in;
            else
                leaky_result <= data_in >>> 3;  // Arithmetic right shift
        end else begin
            leaky_result <= data_in;
        end

        // Stage 2: Multiply by M (M is unsigned, zero-extend to signed)
        mult_result <= leaky_result * $signed({1'b0, M});

        // Stage 3: Arithmetic right shift by n
        shifted_result <= mult_result >>> n;

        // Stage 4: Clamp to INT8 range [-128, 127]
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
