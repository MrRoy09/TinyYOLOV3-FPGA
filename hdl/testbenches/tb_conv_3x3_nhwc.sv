`timescale 1ns / 1ps
`include "tb_macros.svh"

// ============================================================================
// Testbench for conv_3x3 module (8 parallel conv_pe instances)
// ============================================================================
// Tests parallel 3x3 convolution for 8 output filters sharing the same
// pixel window but with different weights and biases.
//
// Key aspects:
//   - All 8 filters computed in parallel
//   - data_valid comes from filter 0 only
//   - Supports multi ci_group accumulation
// ============================================================================

module tb_conv_3x3_nhwc;

    logic clk;
    logic rst;
    logic valid_in;
    logic last_channel;
    logic [63:0] pixels [0:2][0:2];
    logic [575:0] weights [0:7];
    logic [31:0] biases [0:7];
    logic [31:0] outs [0:7];
    logic data_valid;

    // Instantiate the Top-Level Unit Under Test (UUT)
    conv_3x3 uut (
        .clk(clk),
        .rst(rst),
        .valid_in(valid_in),
        .last_channel(last_channel),
        .pixels(pixels),
        .weights(weights),
        .biases(biases),
        .outs(outs),
        .data_valid(data_valid)
    );

    // Clock generation (100MHz)
    initial clk = 0;
    always #5 clk = ~clk;

    // Timeout
    `TB_TIMEOUT(100us)

    // Error counter
    int errors = 0;

    // ========================================================================
    // Helper function: compute expected output for one filter
    // ========================================================================
    function automatic int compute_expected(
        input logic [63:0] px [0:2][0:2],
        input logic [575:0] wt,
        input logic [31:0] b
    );
        int acc = 0;
        int pixel_val, weight_val, product;

        for (int i = 0; i < 9; i++) begin
            for (int j = 0; j < 8; j++) begin
                // Pixel: unsigned 8-bit
                pixel_val = px[i/3][i%3][j*8 +: 8];
                // Weight: signed 8-bit
                weight_val = $signed(wt[(i*64 + j*8) +: 8]);
                product = pixel_val * weight_val;
                acc = acc + product;
            end
        end

        return acc + $signed(b);
    endfunction

    // ========================================================================
    // Helper: pack weights for a filter (all same value)
    // ========================================================================
    function automatic logic [575:0] pack_weights_const(input logic signed [7:0] val);
        logic [575:0] result = '0;
        for (int i = 0; i < 72; i++)
            result[i*8 +: 8] = val;
        return result;
    endfunction

    // ========================================================================
    // Helper: set all pixels to same value per channel
    // ========================================================================
    task automatic set_pixels_const(input logic [7:0] val);
        for (int r = 0; r < 3; r++)
            for (int c = 0; c < 3; c++)
                for (int ch = 0; ch < 8; ch++)
                    pixels[r][c][ch*8 +: 8] = val;
    endtask

    // ========================================================================
    // Helper: set pixels with position-based values
    // ========================================================================
    task automatic set_pixels_pattern(input logic [7:0] base);
        for (int r = 0; r < 3; r++)
            for (int c = 0; c < 3; c++)
                for (int ch = 0; ch < 8; ch++)
                    pixels[r][c][ch*8 +: 8] = base + r*24 + c*8 + ch;
    endtask

    // ========================================================================
    // Test 1: Single ci_group, 8 filters in parallel
    // ========================================================================
    task automatic test_single_ci_group();
        int expected [0:7];
        int wait_cycles;

        `TEST_CASE(1, "Single ci_group, 8 parallel filters")

        // Reset
        rst = 1;
        valid_in = 0;
        last_channel = 0;
        for (int f = 0; f < 8; f++) begin
            biases[f] = 32'd0;
            weights[f] = '0;
        end
        for (int r = 0; r < 3; r++)
            for (int c = 0; c < 3; c++)
                pixels[r][c] = '0;

        repeat(5) @(posedge clk);
        rst = 0;
        repeat(2) @(posedge clk);

        // Setup: Filter f gets weight value (f+1), all pixels = 1
        set_pixels_const(8'd1);
        for (int f = 0; f < 8; f++) begin
            weights[f] = pack_weights_const(8'(f + 1));
            biases[f] = 32'd0;
        end

        // Compute expected: dot_product = 9 positions * 8 channels * 1 * (f+1) = 72 * (f+1)
        for (int f = 0; f < 8; f++)
            expected[f] = 72 * (f + 1);

        // Apply input
        @(posedge clk);
        valid_in = 1;
        last_channel = 1;
        @(posedge clk);
        valid_in = 0;
        last_channel = 0;

        // Wait for data_valid
        wait_cycles = 0;
        while (!data_valid && wait_cycles < 20) begin
            @(posedge clk);
            wait_cycles++;
        end

        `CHECK_TRUE(data_valid, "data_valid asserted", errors)

        // Check all 8 filter outputs
        for (int f = 0; f < 8; f++) begin
            `CHECK_EQ($signed(outs[f]), expected[f], $sformatf("filter[%0d]", f), errors)
        end

        @(posedge clk);
    endtask

    // ========================================================================
    // Test 2: Multi ci_group (2 groups) with accumulation
    // ========================================================================
    task automatic test_multi_ci_group();
        int expected [0:7];
        int contrib_g0 [0:7];
        int contrib_g1 [0:7];
        int wait_cycles;
        logic [63:0] px_g0 [0:2][0:2];
        logic [63:0] px_g1 [0:2][0:2];

        `TEST_CASE(2, "Multi ci_group (2 groups) accumulation")

        // Reset
        rst = 1;
        valid_in = 0;
        last_channel = 0;
        for (int f = 0; f < 8; f++) begin
            biases[f] = 32'd100 * (f + 1);  // Biases: 100, 200, 300, ...
            weights[f] = pack_weights_const(8'sd2);  // All weights = 2
        end
        repeat(5) @(posedge clk);
        rst = 0;
        repeat(2) @(posedge clk);

        // Group 0: pixels = 1
        set_pixels_pattern(8'd10);
        for (int r = 0; r < 3; r++)
            for (int c = 0; c < 3; c++)
                px_g0[r][c] = pixels[r][c];

        // Compute expected contribution from group 0
        for (int f = 0; f < 8; f++)
            contrib_g0[f] = compute_expected(px_g0, weights[f], 0);

        // Apply group 0 (valid, no last_channel)
        @(posedge clk);
        valid_in = 1;
        last_channel = 0;
        @(posedge clk);
        valid_in = 0;

        // Small gap
        repeat(2) @(posedge clk);

        // Group 1: different pixels
        set_pixels_pattern(8'd20);
        for (int r = 0; r < 3; r++)
            for (int c = 0; c < 3; c++)
                px_g1[r][c] = pixels[r][c];

        // Compute expected contribution from group 1
        for (int f = 0; f < 8; f++)
            contrib_g1[f] = compute_expected(px_g1, weights[f], 0);

        // Total expected = g0 + g1 + bias
        for (int f = 0; f < 8; f++)
            expected[f] = contrib_g0[f] + contrib_g1[f] + $signed(biases[f]);

        // Apply group 1 (valid + last_channel)
        @(posedge clk);
        valid_in = 1;
        last_channel = 1;
        @(posedge clk);
        valid_in = 0;
        last_channel = 0;

        // Wait for data_valid
        wait_cycles = 0;
        while (!data_valid && wait_cycles < 20) begin
            @(posedge clk);
            wait_cycles++;
        end

        `CHECK_TRUE(data_valid, "data_valid asserted", errors)

        // Check outputs
        for (int f = 0; f < 8; f++) begin
            `CHECK_EQ($signed(outs[f]), expected[f], $sformatf("filter[%0d] (2 groups)", f), errors)
        end

        @(posedge clk);
    endtask

    // ========================================================================
    // Test 3: Negative weights
    // ========================================================================
    task automatic test_negative_weights();
        int expected [0:7];
        int wait_cycles;

        `TEST_CASE(3, "Negative weights")

        // Reset
        rst = 1;
        valid_in = 0;
        last_channel = 0;
        repeat(5) @(posedge clk);
        rst = 0;
        repeat(2) @(posedge clk);

        // Setup: alternating positive/negative weights
        set_pixels_const(8'd10);
        for (int f = 0; f < 8; f++) begin
            if (f % 2 == 0)
                weights[f] = pack_weights_const(8'sd5);   // Positive
            else
                weights[f] = pack_weights_const(-8'sd3);  // Negative
            biases[f] = 32'd0;
        end

        // Compute expected
        // Each filter: 72 products of (10 * weight)
        for (int f = 0; f < 8; f++) begin
            if (f % 2 == 0)
                expected[f] = 72 * 10 * 5;   // 3600
            else
                expected[f] = 72 * 10 * (-3);  // -2160
        end

        // Apply
        @(posedge clk);
        valid_in = 1;
        last_channel = 1;
        @(posedge clk);
        valid_in = 0;
        last_channel = 0;

        // Wait
        wait_cycles = 0;
        while (!data_valid && wait_cycles < 20) begin
            @(posedge clk);
            wait_cycles++;
        end

        // Check
        for (int f = 0; f < 8; f++) begin
            `CHECK_EQ($signed(outs[f]), expected[f], $sformatf("filter[%0d] neg wt", f), errors)
        end

        @(posedge clk);
    endtask

    // ========================================================================
    // Test 4: Back-to-back outputs (multiple spatial positions)
    // ========================================================================
    task automatic test_back_to_back();
        int output_count = 0;

        `TEST_CASE(4, "Back-to-back outputs")

        // Reset
        rst = 1;
        valid_in = 0;
        last_channel = 0;
        repeat(5) @(posedge clk);
        rst = 0;
        repeat(2) @(posedge clk);

        // Simple setup
        set_pixels_const(8'd1);
        for (int f = 0; f < 8; f++) begin
            weights[f] = pack_weights_const(8'sd1);
            biases[f] = 32'd0;
        end

        // Stream 3 consecutive spatial positions
        for (int pos = 0; pos < 3; pos++) begin
            @(posedge clk);
            valid_in = 1;
            last_channel = 1;
        end
        @(posedge clk);
        valid_in = 0;
        last_channel = 0;

        // Count outputs
        repeat(20) begin
            @(posedge clk);
            if (data_valid) output_count++;
        end

        // Should get 3 outputs (one per spatial position)
        `CHECK_EQ(output_count, 3, "back-to-back output count", errors)

        @(posedge clk);
    endtask

    // ========================================================================
    // Main test sequence
    // ========================================================================
    initial begin
        $dumpfile("tb_conv_3x3_nhwc.vcd");
        $dumpvars(0, tb_conv_3x3_nhwc);

        `TB_HEADER("conv_3x3")

        test_single_ci_group();
        test_multi_ci_group();
        test_negative_weights();
        test_back_to_back();

        repeat(10) @(posedge clk);

        `TB_FOOTER(errors)

        $finish;
    end

endmodule
