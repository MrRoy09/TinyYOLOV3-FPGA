`timescale 1ns / 1ps

module tb_conv_3x3_nhwc;

    logic clk;
    logic rst;
    logic valid_in;
    logic last_channel;
    logic [63:0] pixels [0:2][0:2];
    logic [575:0] weights;
    logic [31:0] bias;
    logic [31:0] out;
    logic data_valid;

    // Instantiate the Unit Under Test (UUT)
    conv_3x3 uut (
        .clk(clk),
        .rst(rst),
        .valid_in(valid_in),
        .last_channel(last_channel),
        .pixels(pixels),
        .weights(weights),
        .bias(bias),
        .out(out),
        .data_valid(data_valid)
    );

    // Clock generation (100MHz)
    always #5 clk = ~clk;

    initial begin
        // Initialize Signals
        clk = 0;
        rst = 1;
        valid_in = 0;
        last_channel = 0;
        bias = 32'd1;
        
        // Fill weights with 1s (72 weights total)
        for (int i=0; i<72; i++) begin
            weights[i*8 +: 8] = 8'd1;
        end

        // Fill pixels with 1s (9 positions * 8 channels)
        for (int r=0; r<3; r++) begin
            for (int c=0; c<3; c++) begin
                for (int ch=0; ch<8; ch++) begin
                    pixels[r][c][ch*8 +: 8] = 8'd1;
                end
            end
        end

        // Reset
        #20 rst = 0;
        #20;

        // --- TEST 1: Single 8-channel Cycle ---
        // Expected: (9 positions * 8 channels * 1 * 1) + 1 (bias) = 73
        @(posedge clk);
        valid_in = 1;
        last_channel = 1;
        
        @(posedge clk);
        valid_in = 0;
        last_channel = 0;

        // Wait for result
        wait(data_valid);
        #1;
        $display("TEST 1 (8 Channels)  | out: %d | expected: 73", out);
        if (out === 32'd73) $display(">>> SUCCESS");
        else $display(">>> FAILURE");

        #100;

        // --- TEST 2: Two 8-channel Cycles (16 channels total) ---
        // Expected: (Cycle 1: 72) + (Cycle 2: 72) + 1 (bias) = 145
        @(posedge clk);
        valid_in = 1;
        last_channel = 0; // First 8 channels
        
        @(posedge clk);
        valid_in = 1;
        last_channel = 1; // Last 8 channels
        
        @(posedge clk);
        valid_in = 0;
        last_channel = 0;

        // Wait for result
        wait(data_valid);
        #1;
        $display("TEST 2 (16 Channels) | out: %d | expected: 145", out);
        if (out === 32'd145) $display(">>> SUCCESS");
        else $display(">>> FAILURE");

        #100;
        $display("Simulation Finished.");
        $finish;
    end

endmodule
