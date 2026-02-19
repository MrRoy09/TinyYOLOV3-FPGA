module conv_pe #()
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

// ════════════════════════════════════════════════════════════════════════════
// Pipeline Structure (4 stages for 200 MHz timing closure):
//
//   Stage 1: products      = pixel × weight         (72 multiplies)
//   Stage 2: partial_sum   = sum of 4 products      (18 partial sums)
//   Stage 3: spatial_sum   = sum of 2 partials      (9 spatial sums)
//            cycle_sum     = sum of 9 spatials      (1 total)
//   Stage 4: acc update    = acc + cycle_sum        (accumulate)
//
// DSP inference: Do NOT reset data-path registers (products, sums).
// DSP48E2 doesn't support sync reset on multiply stage.
// Only reset control logic (valid_pipe, acc, data_valid).
// ════════════════════════════════════════════════════════════════════════════

// Stage 1 outputs: 9 spatial × 8 channel products
// int8 × int8 = int16 (signed 8-bit × signed 8-bit)
(* use_dsp = "yes" *) logic signed [15:0] products [0:8][0:7];

// Stage 2 outputs: 9 spatial × 4 partial sums (pairs of channels)
// 16-bit + 16-bit = 17-bit
logic signed [16:0] partial_sum [0:8][0:3];

// Stage 3 outputs: 9 spatial sums + 1 cycle sum
// 4 partials (8 products) = 19-bit, 9 spatials (72 products) = 23-bit
logic signed [18:0] spatial_sum [0:8];
logic signed [22:0] cycle_sum;

// Control pipeline (4 stages to match data path)
logic [3:0] valid_pipe;
logic [3:0] lastc_pipe;
logic [31:0] bias_pipe [0:3];

logic signed [31:0] acc;

always_ff @(posedge clk) begin
    if (rst) begin
        valid_pipe <= '0;
        lastc_pipe <= '0;
    end else begin
        valid_pipe <= {valid_pipe[2:0], valid_in};
        lastc_pipe <= {lastc_pipe[2:0], last_channel};
    end
end

always_ff @(posedge clk) begin
    if (rst) begin
        bias_pipe[0] <= '0;
        bias_pipe[1] <= '0;
        bias_pipe[2] <= '0;
        bias_pipe[3] <= '0;
    end else begin
        bias_pipe[0] <= bias;
        bias_pipe[1] <= bias_pipe[0];
        bias_pipe[2] <= bias_pipe[1];
        bias_pipe[3] <= bias_pipe[2];
    end
end

always_ff @(posedge clk) begin
    if (rst) begin
        acc        <= 0;
        out        <= 0;
        data_valid <= 0;
    end else begin
        data_valid <= 0;
        if (valid_pipe[3]) begin
            if (lastc_pipe[3]) begin
                out        <= acc + cycle_sum + $signed(bias_pipe[3]);
                data_valid <= 1'b1;
                acc        <= 0;
            end else begin
                acc <= acc + cycle_sum;
            end
        end
    end
end

genvar i, j;
generate
    for (i = 0; i < 9; i++) begin : spatial_loop
        for (j = 0; j < 8; j++) begin : channel_loop
            logic signed [7:0] pixel_byte;
            logic signed [7:0] weight_byte;

            // Pixels are now SIGNED int8 (matching hardware_sim.py)
            // Input range: [-128, 127] where 127 = max brightness
            assign pixel_byte  = $signed(pixels[i/3][i%3][j*8 +: 8]);
            assign weight_byte = $signed(weights[(i*64 + j*8) +: 8]);

            // No reset on multiply - allows DSP48E2 inference
            always_ff @(posedge clk) begin
                products[i][j] <= pixel_byte * weight_byte;
            end
        end
    end
endgenerate

always_ff @(posedge clk) begin
    for (int k = 0; k < 9; k++) begin
        partial_sum[k][0] <= products[k][0] + products[k][1];
        partial_sum[k][1] <= products[k][2] + products[k][3];
        partial_sum[k][2] <= products[k][4] + products[k][5];
        partial_sum[k][3] <= products[k][6] + products[k][7];
    end
end

always_ff @(posedge clk) begin
    for (int k = 0; k < 9; k++) begin
        spatial_sum[k] <= (partial_sum[k][0] + partial_sum[k][1]) +
                          (partial_sum[k][2] + partial_sum[k][3]);
    end

    cycle_sum <= ((spatial_sum[0] + spatial_sum[1]) + (spatial_sum[2] + spatial_sum[3])) +
                 ((spatial_sum[4] + spatial_sum[5]) + (spatial_sum[6] + spatial_sum[7])) +
                 spatial_sum[8];
end

endmodule