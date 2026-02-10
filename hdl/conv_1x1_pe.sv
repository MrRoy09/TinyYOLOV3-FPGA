module conv_1x1_pe #()
(
    input  logic        clk,
    input  logic        rst,
    input  logic        valid_in,
    input  logic        last_channel,
    input  logic [63:0] pixel,      // 8 channels
    input  logic [63:0] weights,    // 8 weights for 1 output channel
    input  logic [31:0] bias,
    output logic [31:0] out,
    output logic        data_valid
);

logic signed [15:0] products [0:7];
logic signed [19:0] channel_sum;

logic [2:0] valid_pipe;
logic [2:0] lastc_pipe;
logic [31:0] bias_pipe [0:2];

logic signed [31:0] acc;

// Pipeline control signals to match multiplier and adder tree latency
always_ff @(posedge clk) begin
    valid_pipe <= {valid_pipe[1:0] , valid_in};
    lastc_pipe <= {lastc_pipe[1:0] , last_channel};
end

always_ff @(posedge clk) begin
    bias_pipe[0] <= bias;
    bias_pipe[1] <= bias_pipe[0];
    bias_pipe[2] <= bias_pipe[1];
end

// Accumulation and Output
always_ff @(posedge clk) begin
    if(rst) begin
        acc <= 0;
        out <= 0;
        data_valid <= 0;
    end else begin
        data_valid <= 0;
        if(valid_pipe[2]) begin
            if(lastc_pipe[2]) begin
                out <= acc + channel_sum + $signed(bias_pipe[2]);
                data_valid <= 1'b1;
                acc <= 0;
            end else begin
                acc <= acc + channel_sum;
            end
        end
    end
end

// Multiplication Stage (Stage 0)
genvar j;
generate
    for(j = 0; j < 8; j++) begin : channel_loop
        logic signed [8:0] pixel_byte;
        logic signed [8:0] weight_byte;
        assign pixel_byte  = $signed({1'b0, pixel[j*8 +: 8]});
        assign weight_byte = $signed(weights[j*8 +: 8]);

        always_ff @(posedge clk) begin
            if(rst) products[j] <= 16'd0;
            else products[j] <= pixel_byte * weight_byte;
        end
    end
endgenerate

// Adder Tree Stage (Stage 1)
always_ff @(posedge clk) begin
    if(rst) begin
        channel_sum <= '0;
    end else begin
        channel_sum <= products[0] + products[1] + products[2] + products[3] + 
                       products[4] + products[5] + products[6] + products[7];
    end
end

endmodule
