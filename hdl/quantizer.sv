module quantizer (
    input  logic        clk,
    input  logic        rst,
    input  logic [31:0] data_in,
    input  logic        valid_in,
    input  logic [31:0] M, // Multiplier
    input  logic [4:0]  n, // Shift
    output logic [7:0]  data_out,
    output logic        valid_out
);
    
    logic [63:0] mult_result;
    logic        valid_s1, valid_s2, valid_s3;
    logic [31:0] shifted_val;
    logic [31:0] relu_val;
    logic [4:0]  n_s1; 

    always_ff @(posedge clk) begin
        if (rst) begin
            mult_result <= '0;
            shifted_val <= '0;
            relu_val    <= '0;
            data_out    <= '0;
            valid_s1    <= '0;
            valid_s2    <= '0;
            valid_s3    <= '0;
            valid_out   <= '0;
            n_s1        <= '0;
        end else begin
            mult_result <= $signed(data_in) * $signed(M);
            n_s1        <= n;
            valid_s1    <= valid_in;

            if (valid_s1) begin
                shifted_val <= $signed(mult_result) >>> n_s1;
                valid_s2    <= 1'b1;
            end else begin
                valid_s2    <= 1'b0;
            end

            if (valid_s2) begin
                if ($signed(shifted_val) > 0)
                    relu_val <= shifted_val;
                else
                    relu_val <= $signed(shifted_val) >>> 3; // Approximation of 0.125
                valid_s3 <= 1'b1;
            end else begin
                valid_s3 <= 1'b0;
            end

            if (valid_s3) begin
                if ($signed(relu_val) > 127)
                    data_out <= 8'd127;
                else if ($signed(relu_val) < -128)
                    data_out <= -8'd128;
                else
                    data_out <= relu_val[7:0];
                valid_out <= 1'b1;
            end else begin
                valid_out <= 1'b0;
            end
        end
    end

endmodule