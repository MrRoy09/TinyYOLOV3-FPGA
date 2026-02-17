`timescale 1ns / 1ps

// Testbench for kernelWindow: verifies 3x3 window generation from NHWC stream
// Tests with a simple 4x4 image, 8 channels (ci_groups=1)

module tb_kernel_window;

    logic        clk;
    logic        rst;
    logic        data_valid;
    logic [15:0] in_channels;
    logic [15:0] img_width;
    logic [63:0] pixel_in;
    logic [63:0] window [0:2][0:2];
    logic        dout_valid;

    kernelWindow #(
        .MAX_DEPTH(128)
    ) u_dut (
        .clk       (clk),
        .rst       (rst),
        .data_valid(data_valid),
        .in_channels(in_channels),
        .img_width (img_width),
        .pixel_in  (pixel_in),
        .window    (window),
        .dout_valid(dout_valid)
    );

    // Clock generation
    initial clk = 0;
    always #5 clk = ~clk;

    // Timeout
    initial begin
        #200us;
        $display("[%0t] TIMEOUT", $time);
        $finish;
    end

    int errors = 0;
    int output_count = 0;

    // Test 1: 4x4 image, 8 channels (1 ci_group)
    // Expected: dout_valid fires at positions (r,c) where r>=2 and c>=2
    // That's (2,2), (2,3), (3,2), (3,3) = 4 valid outputs
    task automatic test_4x4_8ch();
        int ci_groups;
        int vpr;  // vectors_per_row
        int total_delay;
        int cycle;
        int pixel_idx;
        int expected_outputs;
        int r, c, cg;
        logic [63:0] test_image [0:15];  // 4x4 = 16 pixels (each 64-bit)

        $display("\n--- Test: 4x4 image, 8 channels ---");

        in_channels = 16'd8;
        img_width = 16'd4;
        ci_groups = in_channels >> 3;  // = 1
        vpr = img_width * ci_groups;   // = 4
        total_delay = (vpr << 1) + (ci_groups << 1) - 1;  // = 8 + 2 - 1 = 9

        $display("  ci_groups=%0d, vectors_per_row=%0d, total_delay=%0d", ci_groups, vpr, total_delay);

        // Create test image: pixel[row][col] = row*16 + col*4 + ci_group
        // For 1 ci_group, each pixel is just: row*16 + col*4
        // We'll pack this into 64-bit values with distinct byte patterns
        for (int row = 0; row < 4; row++) begin
            for (int col = 0; col < 4; col++) begin
                // Each pixel gets a unique 64-bit value
                // Format: {row, col, 0, 0, 0, 0, 0, 0} for easy identification
                test_image[row*4 + col] = {8'(row), 8'(col), 48'h0};
            end
        end

        // Reset
        rst = 1;
        data_valid = 0;
        pixel_in = 0;
        repeat(5) @(posedge clk);
        rst = 0;
        repeat(2) @(posedge clk);

        // Stream all pixels in NHWC order
        // For 1 ci_group, each pixel is 1 cycle
        output_count = 0;
        cycle = 0;

        for (r = 0; r < 4; r++) begin
            for (c = 0; c < 4; c++) begin
                for (cg = 0; cg < ci_groups; cg++) begin
                    pixel_in = test_image[r*4 + c];
                    data_valid = 1;
                    @(posedge clk);
                    cycle++;

                    if (dout_valid) begin
                        output_count++;
                        $display("  Output %0d at cycle %0d (r=%0d, c=%0d)",
                                 output_count, cycle, r, c);
                        $display("    window[0][0]=%h, window[0][2]=%h, window[2][2]=%h",
                                 window[0][0], window[0][2], window[2][2]);
                    end
                end
            end
        end

        data_valid = 0;

        // Expected outputs: for 4x4 image with 3x3 kernel and ci_groups=1
        // Valid positions: (2,2), (2,3), (3,2), (3,3) = 4 outputs
        expected_outputs = 4;
        if (output_count != expected_outputs) begin
            $display("  ERROR: got %0d outputs, expected %0d", output_count, expected_outputs);
            errors++;
        end else begin
            $display("  OK: got %0d outputs as expected", output_count);
        end

        @(posedge clk);
    endtask

    // Test 2: 4x4 image, 16 channels (2 ci_groups)
    task automatic test_4x4_16ch();
        int ci_groups;
        int vpr;
        int total_delay;
        int cycle;
        int expected_outputs;
        int r, c, cg;

        $display("\n--- Test: 4x4 image, 16 channels ---");

        in_channels = 16'd16;
        img_width = 16'd4;
        ci_groups = in_channels >> 3;  // = 2
        vpr = img_width * ci_groups;   // = 8
        total_delay = (vpr << 1) + (ci_groups << 1) - 1;  // = 16 + 4 - 1 = 19

        $display("  ci_groups=%0d, vectors_per_row=%0d, total_delay=%0d", ci_groups, vpr, total_delay);

        // Reset
        rst = 1;
        data_valid = 0;
        pixel_in = 0;
        repeat(5) @(posedge clk);
        rst = 0;
        repeat(2) @(posedge clk);

        // Stream all pixels
        output_count = 0;
        cycle = 0;

        for (r = 0; r < 4; r++) begin
            for (c = 0; c < 4; c++) begin
                for (cg = 0; cg < ci_groups; cg++) begin
                    // Unique pixel value encoding position and ci_group
                    pixel_in = {8'(r), 8'(c), 8'(cg), 40'h0};
                    data_valid = 1;
                    @(posedge clk);
                    cycle++;

                    if (dout_valid) begin
                        output_count++;
                    end
                end
            end
        end

        data_valid = 0;

        // Expected outputs: 4 spatial positions × 2 ci_groups = 8 outputs
        expected_outputs = 8;
        if (output_count != expected_outputs) begin
            $display("  ERROR: got %0d outputs, expected %0d", output_count, expected_outputs);
            errors++;
        end else begin
            $display("  OK: got %0d outputs as expected", output_count);
        end

        @(posedge clk);
    endtask

    // Test 3: Verify window contents are correct
    task automatic test_window_contents();
        int ci_groups;
        int vpr;
        int cycle;
        int r, c, cg;
        logic [63:0] expected_window [0:2][0:2];
        int output_idx;

        $display("\n--- Test: Window contents verification ---");

        in_channels = 16'd8;
        img_width = 16'd4;
        ci_groups = 1;
        vpr = 4;

        // Reset
        rst = 1;
        data_valid = 0;
        pixel_in = 0;
        repeat(5) @(posedge clk);
        rst = 0;
        repeat(2) @(posedge clk);

        // Stream pixels with unique identifiers
        output_idx = 0;
        for (r = 0; r < 4; r++) begin
            for (c = 0; c < 4; c++) begin
                // Pixel value = (row * 4 + col) for easy verification
                pixel_in = {8'(r*4 + c), 56'h0};
                data_valid = 1;
                @(posedge clk);

                if (dout_valid) begin
                    // At position (r, c), the window should contain:
                    // window[2][2] = pixel_in = current pixel (r, c)
                    // window[1][2] = row above (r-1, c)
                    // window[0][2] = two rows above (r-2, c)
                    // window[x][1] = one column left
                    // window[x][0] = two columns left

                    // For first valid output at (2,2):
                    // window[0][0] = (0,0), window[0][1] = (0,1), window[0][2] = (0,2)
                    // window[1][0] = (1,0), window[1][1] = (1,1), window[1][2] = (1,2)
                    // window[2][0] = (2,0), window[2][1] = (2,1), window[2][2] = (2,2)

                    if (output_idx == 0) begin
                        // Check first output at position (2,2)
                        $display("  First valid output at (r=%0d, c=%0d)", r, c);
                        $display("    window[2][2] = %h (expect: 0A = pixel 10 = (2,2))", window[2][2]);
                        $display("    window[1][2] = %h (expect: 06 = pixel 6 = (1,2))", window[1][2]);
                        $display("    window[0][2] = %h (expect: 02 = pixel 2 = (0,2))", window[0][2]);

                        // Verify window[2][2] = current pixel
                        if (window[2][2][63:56] !== 8'(r*4 + c)) begin
                            $display("  ERROR: window[2][2] incorrect");
                            errors++;
                        end else begin
                            $display("  OK: window[2][2] correct");
                        end
                    end

                    output_idx++;
                end
            end
        end

        data_valid = 0;

        @(posedge clk);
    endtask

    initial begin
        $dumpfile("tb_kernel_window.vcd");
        $dumpvars(0, tb_kernel_window);

        $display("\n=========================================");
        $display("  kernelWindow Testbench");
        $display("=========================================");

        test_4x4_8ch();
        test_4x4_16ch();
        test_window_contents();

        #200;
        $display("\n=========================================");
        if (errors == 0)
            $display("  PASSED: All tests passed");
        else
            $display("  FAILED: %0d errors", errors);
        $display("=========================================\n");
        $finish;
    end

endmodule
