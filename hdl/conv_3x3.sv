module conv_3x3 #()
(
    input  logic        clk,
    input  logic        rst,
    input  logic        valid_in,
    input  logic [7:0]  pixels [0:8],
    input  logic [71:0] weights,      // Flat 72-bit vector for easier BRAM connection
    input  logic [31:0] bias,
    output logic [31:0] out,
    output logic        data_valid
);

    // Intermediate Products and Sums
    logic [31:0] prod [0:8];
    logic [31:0] l1_sum [0:4];
    logic [31:0] l2_sum [0:2];
    logic [31:0] l3_sum [0:1];
    
    // Valid Signal Pipeline 
    // Latencies: 2 (BRAM) + 3 (DSP) + 4 (Tree) = 9 cycles total
    logic [8:0] valid_pipe;

    always_ff @(posedge clk) begin
        if (rst) valid_pipe <= '0;
        else     valid_pipe <= {valid_pipe[7:0], valid_in};
    end

    // The output valid signal must align with the final 'out' result (Cycle 9)
    assign data_valid = valid_pipe[8];

    // 1. DSP Multipliers (Latency: 3 cycles)
    genvar i;
    generate
        for (i = 0; i < 9; i=i+1) begin : gen_dsps
            dsp_wrap_int8 i_dsp(
                .clk(clk),
                .rst_n(!rst),
                .en(1'b1),
                .pixel_in(pixels[i]),
                .weight_in(weights[i*8 +: 8]), 
                .acc_in(32'b0),
                .data_out(prod[i])
            );
        end
    endgenerate

    // Pipeline the bias signal
    logic [31:0] bias_reg [0:6]; 

    always_ff @(posedge clk) begin
        if (rst) begin
            for (int j=0; j<7; j++) bias_reg[j] <= '0;
        end else begin
            bias_reg[0] <= bias;
            for (int j=1; j<7; j++) bias_reg[j] <= bias_reg[j-1];
        end
    end

    // 2. Adder Tree (L1 - Cycle 6)
    always_ff @(posedge clk) begin
        l1_sum[0] <= prod[0] + prod[1];
        l1_sum[1] <= prod[2] + prod[3];
        l1_sum[2] <= prod[4] + prod[5];
        l1_sum[3] <= prod[6] + prod[7];
        l1_sum[4] <= prod[8]; 
    end

    // 3. Adder Tree (L2 - Cycle 7)
    always_ff @(posedge clk) begin
        l2_sum[0] <= l1_sum[0] + l1_sum[1];
        l2_sum[1] <= l1_sum[2] + l1_sum[3];
        l2_sum[2] <= l1_sum[4]; 
    end

    // 4. Adder Tree (L3 - Cycle 8)
    always_ff @(posedge clk) begin
        l3_sum[0] <= l2_sum[0] + l2_sum[1];
        l3_sum[1] <= l2_sum[2]; 
    end

    // 5. Final Stage (Cycle 9) - Add everything + Bias
    always_ff @(posedge clk) begin
        out <= l3_sum[0] + l3_sum[1] + bias_reg[6];
    end

endmodule