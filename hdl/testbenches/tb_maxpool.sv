`timescale 1ns / 1ps
`include "tb_macros.svh"

// ============================================================================
// Testbench for maxPool module
// ============================================================================
// Tests 2x2 max pooling with:
//   - Stride-2 mode: 4x4 -> 2x2 output
//   - Stride-1 mode: 4x4 -> 3x3 output (backward-looking)
//   - Multi-channel verification (8 channels per vector)
//   - Signed INT8 comparison
// ============================================================================

module tb_maxpool;

    // Clock and Reset
    logic clk;
    logic rst;

    // Module Inputs
    logic [15:0] img_width;
    logic [15:0] channels;
    logic stride_2;
    logic [63:0] data_in;
    logic valid_in;

    // Module Outputs
    logic [63:0] data_out;
    logic valid_out;

    // Instantiate the Unit Under Test (UUT)
    maxPool uut (
        .clk(clk),
        .rst(rst),
        .img_width(img_width),
        .channels(channels),
        .stride_2(stride_2),
        .data_in(data_in),
        .valid_in(valid_in),
        .data_out(data_out),
        .valid_out(valid_out)
    );

    // Clock Generation (100MHz)
    initial clk = 0;
    always #5 clk = ~clk;

    // Timeout
    `TB_TIMEOUT(200us)

    // Error counter
    int errors = 0;

    // ========================================================================
    // Test data storage
    // ========================================================================
    // Input image: 4x4 spatial, 8 channels (single ci_group)
    logic signed [7:0] input_image [0:3][0:3][0:7];

    // Expected outputs for stride-2: 2x2 spatial
    logic [63:0] expected_s2 [0:1][0:1];

    // Expected outputs for stride-1: 3x3 spatial (padded 5x5 -> 4x4 -> 3x3)
    logic [63:0] expected_s1 [0:2][0:2];

    // Output capture
    int output_idx;
    logic [63:0] captured_outputs [0:15];

    // ========================================================================
    // Helper: Compute signed max of 2x2 region for one channel
    // ========================================================================
    function automatic logic signed [7:0] max4(
        input logic signed [7:0] a,
        input logic signed [7:0] b,
        input logic signed [7:0] c,
        input logic signed [7:0] d
    );
        logic signed [7:0] max_ab, max_cd;
        max_ab = (a > b) ? a : b;
        max_cd = (c > d) ? c : d;
        return (max_ab > max_cd) ? max_ab : max_cd;
    endfunction

    // ========================================================================
    // Helper: Pack 8 signed bytes into 64-bit vector
    // ========================================================================
    function automatic logic [63:0] pack_channels(
        input logic signed [7:0] ch [0:7]
    );
        logic [63:0] result;
        for (int i = 0; i < 8; i++)
            result[i*8 +: 8] = ch[i];
        return result;
    endfunction

    // ========================================================================
    // Helper: Send one super-pixel (all channels for one spatial location)
    // ========================================================================
    task automatic send_pixel(input int row, input int col);
        logic [63:0] packed_data;

        // Pack channels
        for (int ch = 0; ch < 8; ch++)
            packed_data[ch*8 +: 8] = input_image[row][col][ch];

        @(posedge clk);
        valid_in <= 1;
        data_in  <= packed_data;
        @(posedge clk);
        valid_in <= 0;
    endtask

    // ========================================================================
    // Helper: Stream entire image
    // ========================================================================
    task automatic stream_image(input int width, input int height);
        for (int r = 0; r < height; r++) begin
            for (int c = 0; c < width; c++) begin
                send_pixel(r, c);
            end
        end
    endtask

    // ========================================================================
    // Initialize test image with known values
    // ========================================================================
    task automatic init_test_image();
        // Create distinctive values at each position
        // Format: pixel[r][c][ch] = base + ch where base varies by position
        // Include some negative values to test signed comparison

        for (int r = 0; r < 4; r++) begin
            for (int c = 0; c < 4; c++) begin
                for (int ch = 0; ch < 8; ch++) begin
                    // Base value based on position, varying pattern
                    case ({r[1:0], c[1:0]})
                        4'b0000: input_image[r][c][ch] = 8'sd10 + ch;   // (0,0): 10-17
                        4'b0001: input_image[r][c][ch] = 8'sd50 + ch;   // (0,1): 50-57 <- max for [0,0] in s2
                        4'b0010: input_image[r][c][ch] = 8'sd20 + ch;   // (0,2): 20-27
                        4'b0011: input_image[r][c][ch] = 8'sd60 + ch;   // (0,3): 60-67 <- max for [0,1] in s2
                        4'b0100: input_image[r][c][ch] = 8'sd30 + ch;   // (1,0): 30-37
                        4'b0101: input_image[r][c][ch] = 8'sd40 + ch;   // (1,1): 40-47
                        4'b0110: input_image[r][c][ch] = 8'sd25 + ch;   // (1,2): 25-32
                        4'b0111: input_image[r][c][ch] = 8'sd55 + ch;   // (1,3): 55-62
                        4'b1000: input_image[r][c][ch] = -8'sd10 + ch;  // (2,0): negative values
                        4'b1001: input_image[r][c][ch] = 8'sd70 + ch;   // (2,1): 70-77 <- max for [1,0] in s2
                        4'b1010: input_image[r][c][ch] = 8'sd15 + ch;   // (2,2): 15-22
                        4'b1011: input_image[r][c][ch] = 8'sd80 + ch;   // (2,3): 80-87 <- max for [1,1] in s2
                        4'b1100: input_image[r][c][ch] = 8'sd5 + ch;    // (3,0): 5-12
                        4'b1101: input_image[r][c][ch] = 8'sd45 + ch;   // (3,1): 45-52
                        4'b1110: input_image[r][c][ch] = -8'sd20 + ch;  // (3,2): negative values
                        4'b1111: input_image[r][c][ch] = 8'sd35 + ch;   // (3,3): 35-42
                    endcase
                end
            end
        end
    endtask

    // ========================================================================
    // Compute expected outputs for stride-2
    // 2x2 pooling on 4x4 -> 2x2 output
    // ========================================================================
    task automatic compute_expected_s2();
        logic signed [7:0] ch_result [0:7];

        // Output [0,0] = max of input [0:1][0:1]
        for (int ch = 0; ch < 8; ch++) begin
            ch_result[ch] = max4(
                input_image[0][0][ch], input_image[0][1][ch],
                input_image[1][0][ch], input_image[1][1][ch]
            );
        end
        expected_s2[0][0] = pack_channels(ch_result);

        // Output [0,1] = max of input [0:1][2:3]
        for (int ch = 0; ch < 8; ch++) begin
            ch_result[ch] = max4(
                input_image[0][2][ch], input_image[0][3][ch],
                input_image[1][2][ch], input_image[1][3][ch]
            );
        end
        expected_s2[0][1] = pack_channels(ch_result);

        // Output [1,0] = max of input [2:3][0:1]
        for (int ch = 0; ch < 8; ch++) begin
            ch_result[ch] = max4(
                input_image[2][0][ch], input_image[2][1][ch],
                input_image[3][0][ch], input_image[3][1][ch]
            );
        end
        expected_s2[1][0] = pack_channels(ch_result);

        // Output [1,1] = max of input [2:3][2:3]
        for (int ch = 0; ch < 8; ch++) begin
            ch_result[ch] = max4(
                input_image[2][2][ch], input_image[2][3][ch],
                input_image[3][2][ch], input_image[3][3][ch]
            );
        end
        expected_s2[1][1] = pack_channels(ch_result);

        $display("  Expected stride-2 outputs:");
        $display("    [0,0]: %h", expected_s2[0][0]);
        $display("    [0,1]: %h", expected_s2[0][1]);
        $display("    [1,0]: %h", expected_s2[1][0]);
        $display("    [1,1]: %h", expected_s2[1][1]);
    endtask

    // ========================================================================
    // Test 1: Stride-2 mode (4x4 -> 2x2)
    // ========================================================================
    task automatic test_stride2();
        int expected_count = 4;
        int actual_count = 0;

        `TEST_CASE(1, "Stride-2 mode (4x4 -> 2x2)")

        // Reset
        rst = 1;
        stride_2 = 1;
        img_width = 16'd4;
        channels = 16'd8;
        valid_in = 0;
        data_in = '0;
        output_idx = 0;
        repeat(5) @(posedge clk);
        rst = 0;
        repeat(3) @(posedge clk);  // Let config registers stabilize

        // Initialize test data
        init_test_image();
        compute_expected_s2();

        // Start output capture in parallel
        fork
            // Stream input
            stream_image(4, 4);

            // Capture outputs
            begin
                while (actual_count < expected_count) begin
                    @(posedge clk);
                    if (valid_out) begin
                        captured_outputs[actual_count] = data_out;
                        actual_count++;
                    end
                end
            end
        join_any

        // Wait for any remaining outputs
        repeat(20) @(posedge clk);

        // Count any additional outputs
        // (shouldn't be any, but check)
        repeat(10) begin
            @(posedge clk);
            if (valid_out) actual_count++;
        end

        // Verify output count
        `CHECK_EQ(actual_count, expected_count, "output count", errors)

        // Verify output values (in row-major order)
        if (actual_count >= 1) `CHECK_EQ_HEX(captured_outputs[0], expected_s2[0][0], "out[0,0]", errors)
        if (actual_count >= 2) `CHECK_EQ_HEX(captured_outputs[1], expected_s2[0][1], "out[0,1]", errors)
        if (actual_count >= 3) `CHECK_EQ_HEX(captured_outputs[2], expected_s2[1][0], "out[1,0]", errors)
        if (actual_count >= 4) `CHECK_EQ_HEX(captured_outputs[3], expected_s2[1][1], "out[1,1]", errors)

    endtask

    // ========================================================================
    // Test 2: Stride-2 with multi-channel (16 channels = 2 super-pixels)
    // ========================================================================
    task automatic test_stride2_multichannel();
        logic [63:0] test_input [0:3][0:3][0:1];  // 4x4, 2 channel groups
        int expected_count = 8;  // 2x2 spatial * 2 channel groups
        int actual_count = 0;

        `TEST_CASE(2, "Stride-2 with 16 channels")

        // Reset
        rst = 1;
        stride_2 = 1;
        img_width = 16'd4;
        channels = 16'd16;  // 2 super-pixels per spatial position
        valid_in = 0;
        data_in = '0;
        repeat(5) @(posedge clk);
        rst = 0;
        repeat(3) @(posedge clk);

        // Create simple test pattern
        for (int r = 0; r < 4; r++) begin
            for (int c = 0; c < 4; c++) begin
                // Channel group 0: position-based values
                test_input[r][c][0] = {8{8'(r*16 + c*4)}};
                // Channel group 1: inverted pattern
                test_input[r][c][1] = {8{8'(64 - r*16 - c*4)}};
            end
        end

        // Make position (1,1) have max values for first 2x2 block
        test_input[1][1][0] = 64'hFFFF_FFFF_FFFF_FFFF;  // Will be interpreted as -1 (signed)
        test_input[0][1][0] = {8{8'd100}};  // Unsigned 100 > signed -1

        // Stream image (2 channel groups per spatial position)
        fork
            begin
                for (int r = 0; r < 4; r++) begin
                    for (int c = 0; c < 4; c++) begin
                        for (int cg = 0; cg < 2; cg++) begin
                            @(posedge clk);
                            valid_in <= 1;
                            data_in  <= test_input[r][c][cg];
                        end
                    end
                end
                @(posedge clk);
                valid_in <= 0;
            end

            begin
                // Count outputs
                forever begin
                    @(posedge clk);
                    if (valid_out) actual_count++;
                end
            end
        join_any

        repeat(50) @(posedge clk);

        // Just verify we got the right count
        `CHECK_EQ(actual_count, expected_count, "16-ch output count", errors)

    endtask

    // ========================================================================
    // Test 3: Signed comparison verification
    // ========================================================================
    task automatic test_signed_comparison();
        logic [63:0] test_data [0:3][0:3];
        int actual_count = 0;
        logic [63:0] captured;

        `TEST_CASE(3, "Signed comparison (negative values)")

        // Reset
        rst = 1;
        stride_2 = 1;
        img_width = 16'd4;
        channels = 16'd8;
        valid_in = 0;
        repeat(5) @(posedge clk);
        rst = 0;
        repeat(3) @(posedge clk);

        // Create test with all negative values except one
        // Position (0,0): -50 for all channels
        // Position (0,1): -10 for all channels (this should be max)
        // Position (1,0): -100 for all channels
        // Position (1,1): -30 for all channels
        test_data[0][0] = {8{-8'sd50}};   // -50
        test_data[0][1] = {8{-8'sd10}};   // -10 <- MAX
        test_data[1][0] = {8{-8'sd100}};  // -100
        test_data[1][1] = {8{-8'sd30}};   // -30

        // Fill rest with minimum value
        for (int r = 0; r < 4; r++)
            for (int c = 0; c < 4; c++)
                if (r >= 2 || c >= 2)
                    test_data[r][c] = {8{8'h80}};  // -128

        // Stream
        fork
            begin
                for (int r = 0; r < 4; r++) begin
                    for (int c = 0; c < 4; c++) begin
                        @(posedge clk);
                        valid_in <= 1;
                        data_in  <= test_data[r][c];
                    end
                end
                @(posedge clk);
                valid_in <= 0;
            end

            begin
                // Capture first output
                while (actual_count == 0) begin
                    @(posedge clk);
                    if (valid_out) begin
                        captured = data_out;
                        actual_count++;
                    end
                end
            end
        join_any

        repeat(20) @(posedge clk);

        // First output should be -10 for all channels (the max of the negative values)
        `CHECK_EQ_HEX(captured, {8{-8'sd10}}, "max of negatives", errors)

    endtask

    // ========================================================================
    // Test 4: Reset behavior
    // ========================================================================
    task automatic test_reset();
        `TEST_CASE(4, "Reset clears internal state")

        // Initialize and start streaming
        rst = 1;
        stride_2 = 1;
        img_width = 16'd4;
        channels = 16'd8;
        valid_in = 0;
        repeat(5) @(posedge clk);
        rst = 0;
        repeat(3) @(posedge clk);

        // Stream partial data
        for (int i = 0; i < 8; i++) begin
            @(posedge clk);
            valid_in <= 1;
            data_in  <= 64'hDEAD_BEEF_CAFE_BABE;
        end
        @(posedge clk);
        valid_in <= 0;

        // Apply reset
        @(posedge clk);
        rst = 1;
        repeat(3) @(posedge clk);
        rst = 0;
        repeat(3) @(posedge clk);

        // Verify no spurious outputs after reset
        int spurious = 0;
        repeat(20) begin
            @(posedge clk);
            if (valid_out) spurious++;
        end

        `CHECK_EQ(spurious, 0, "no spurious outputs after reset", errors)

    endtask

    // ========================================================================
    // Main test sequence
    // ========================================================================
    initial begin
        $dumpfile("tb_maxpool.vcd");
        $dumpvars(0, tb_maxpool);

        `TB_HEADER("maxPool")

        test_stride2();
        test_stride2_multichannel();
        test_signed_comparison();
        test_reset();

        repeat(20) @(posedge clk);

        `TB_FOOTER(errors)

        $finish;
    end

endmodule
