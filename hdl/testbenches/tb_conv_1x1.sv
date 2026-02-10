`timescale 1ns / 1ps

module tb_conv_1x1;

    logic clk;
    logic rst;
    logic valid_in;
    logic last_channel;
    logic [63:0] pixel;
    logic [63:0] weights [0:7];
    logic [31:0] biases [0:7];

    logic [31:0] outs [0:7];
    logic data_valid;

    // Instantiate UUT
    conv_1x1 uut (
        .clk(clk),
        .rst(rst),
        .valid_in(valid_in),
        .last_channel(last_channel),
        .pixel(pixel),
        .weights(weights),
        .biases(biases),
        .outs(outs),
        .data_valid(data_valid)
    );

    always #5 clk = ~clk;

    initial begin
        // Initialize
        clk = 0;
        rst = 1;
        valid_in = 0;
        last_channel = 0;
        pixel = 0;
        
        for (int i=0; i<8; i++) begin
            biases[i] = i + 1; // Bias 1, 2, 3...
            for (int j=0; j<8; j++) begin
                weights[i][j*8 +: 8] = 8'd1; // All weights 1
            end
        end

        #20 rst = 0;
        #20;

        // --- TEST 1: Single 8-channel Cycle ---
        // Pixel: all channels = 2.
        // Dot product = 8 * 2 * 1 = 16.
        // Out[0] = 16 + 1 = 17
        // Out[1] = 16 + 2 = 18 ...
        for (int j=0; j<8; j++) pixel[j*8 +: 8] = 8'd2;
        
        @(posedge clk);
        valid_in = 1;
        last_channel = 1;
        
        @(posedge clk);
        valid_in = 0;
        last_channel = 0;

        wait(data_valid);
        #1;
        $display("TEST 1 (8 Channels)  | out[0]: %d | expected: 17", outs[0]);
        $display("TEST 1 (8 Channels)  | out[7]: %d | expected: 24", outs[7]);
        if (outs[0] === 17 && outs[7] === 24) $display(">>> SUCCESS");
        else $display(">>> FAILURE");

        #100;

        // --- TEST 2: Two 8-channel Cycles (16 channels) ---
        // Cycle 1: pixel channels = 1. Sum = 8.
        // Cycle 2: pixel channels = 3. Sum = 24.
        // Total dot product = 32.
        // Out[0] = 32 + 1 = 33
        
        @(posedge clk);
        for (int j=0; j<8; j++) pixel[j*8 +: 8] = 8'd1;
        valid_in = 1;
        last_channel = 0;
        
        @(posedge clk);
        for (int j=0; j<8; j++) pixel[j*8 +: 8] = 8'd3;
        valid_in = 1;
        last_channel = 1;
        
        @(posedge clk);
        valid_in = 0;
        last_channel = 0;

        wait(data_valid);
        #1;
        $display("TEST 2 (16 Channels) | out[0]: %d | expected: 33", outs[0]);
        if (outs[0] === 33) $display(">>> SUCCESS");
        else $display(">>> FAILURE");

        #100;
        $finish;
    end

endmodule
