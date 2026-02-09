module conv_3x3 #()
(
    input  logic        clk,
    input  logic        rst,
    input  logic        valid_in,
    input  logic        last_channel,
    input  logic [63:0] pixels [0:2][0:2],
    input  logic [575:0] weights,   
    input  logic [31:0] bias,
    output logic [31:0] out,
    output logic        data_valid
);

logic signed [17:0] products [0:8][0:7];
logic signed [20:0] spatial_sum [0:8];
logic signed [24:0] cycle_sum;

logic [2:0] valid_pipe;
logic [2:0] lastc_pipe;
logic [31:0] bias_pipe [0:2];

logic signed [31:0] acc;

always_ff @(posedge clk) begin
    valid_pipe <= {valid_pipe[1:0] , valid_in};
    lastc_pipe <= {lastc_pipe[1:0] , last_channel};
end

always_ff @(posedge clk) begin
    bias_pipe[0] <= bias;
    bias_pipe[1] <= bias_pipe[0];
    bias_pipe[2] <= bias_pipe[1];
end

always_ff @(posedge clk) begin
    if(rst) begin
        acc <= 0;
        out <= 0;
        data_valid <= 0;
    end else begin
        data_valid <= 0;
        if(valid_pipe[2]) begin
            if(lastc_pipe[2]) begin
                out <= acc + cycle_sum + $signed(bias_pipe[2]);
                data_valid <= 1'b1;
                acc <= 0;
            end else begin
                acc <= acc + cycle_sum;
            end
        end
    end
end

genvar i, j;
generate
for (i = 0; i < 9; i++) begin : spatial_loop

    for(j = 0; j < 8; j++) begin : channel_loop
        logic signed [8:0] pixel_byte;
        logic signed [8:0] weight_byte;
        assign pixel_byte = $signed({1'b0, pixels[i/3][i%3][j*8 +: 8]});
        assign weight_byte = $signed(weights[(i*64 + j*8) +: 8]); // this determines the weight storage format !!

        always_ff @(posedge clk) begin
            if(rst) products[i][j] <= 16'd0;
            else products[i][j] <= pixel_byte * weight_byte;
        end
    end
end
endgenerate

always_ff @(posedge clk) begin
    if(rst) begin
        for (int k = 0; k<9; k++) spatial_sum[k] <= '0;
    end else begin
        for (int k=0; k<9; k++) begin
            spatial_sum[k] <= products[k][0] + products[k][1] + products[k][2] + products[k][3] + products[k][4] +
                              products[k][5] + products[k][6] + products[k][7];
        end
    end
end

always_ff @(posedge clk) begin
    if (rst) cycle_sum <= 0;
    else begin
        cycle_sum <= spatial_sum[0] + spatial_sum[1] + spatial_sum[2] +
                     spatial_sum[3] + spatial_sum[4] + spatial_sum[5] +
                     spatial_sum[6] + spatial_sum[7] + spatial_sum[8];
    end
end

endmodule