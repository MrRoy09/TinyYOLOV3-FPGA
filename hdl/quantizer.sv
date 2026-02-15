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


logic signed [63:0] mult_result;
logic signed [31:0] shifted_result;
logic signed [31:0] relu_result;
logic [3:0] valid_pipe;
logic [1:0] use_relu_pipe;


always_ff @(posedge clk) begin
    if(rst) begin
        mult_result <= '0;
        shifted_result <= '0;
        relu_result <= '0;
        data_out <= '0;
        valid_pipe <= '0;
        use_relu_pipe <= '0;

    end else begin
        valid_pipe <= {valid_pipe[2:0], valid_in};
        use_relu_pipe <= {use_relu_pipe[0], use_relu};
        mult_result <= data_in * $signed({1'b0, M});
        shifted_result <= mult_result >>> n;
        if(use_relu_pipe[1]) begin
            if($signed(shifted_result)>=0) relu_result <= shifted_result;
            else relu_result <= $signed(shifted_result) >>> 3;
        end else begin
            relu_result <= shifted_result;
        end
        if($signed(relu_result)> 32'sd127) data_out <= 8'sd127;
        else if($signed(relu_result) < -32'sd128) data_out <= -8'sd128;
        else data_out <= relu_result[7:0];
    end
end

assign valid_out = valid_pipe[3];

endmodule
    