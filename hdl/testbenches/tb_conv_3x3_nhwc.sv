`timescale 1ns / 1ps

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
    always #5 clk = ~clk;

    initial begin
        // Initialize Signals
        clk = 0;
        rst = 1;
        valid_in = 0;
        last_channel = 0;
        
        // Initialize Biases to 0
        for (int f=0; f<8; f++) biases[f] = 32'd0;

        // Initialize Weights: Filter f gets weight value (f+1)
        // Each filter has 72 weights (9 positions * 8 channels)
        for (int f=0; f<8; f++) begin
            for (int w=0; w<72; w++) begin
                weights[f][w*8 +: 8] = 8'(f + 1);
            end
        end

        // Initialize Pixels: All set to 1
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

        // --- TEST: Single 8-channel Cycle for 8 Filters ---
        // Expected for Filter f: (9 positions * 8 channels * pixel=1 * weight=(f+1)) + bias=0
        // Expected: Filter 0 = 72, Filter 1 = 144, Filter 2 = 216 ... Filter 7 = 576
        
        @(posedge clk);
        valid_in = 1;
        last_channel = 1;
        
        @(posedge clk);
        valid_in = 0;
        last_channel = 0;

        // Wait for result
        wait(data_valid);
        #1;
        $display("\n--- PARALLEL FILTER TEST (8 CHANNELS) ---");
        for (int f=0; f<8; f++) begin
            automatic int expected = 72 * (f + 1);
            $display("Filter %0d | out: %d | expected: %d", f, outs[f], expected);
            if (outs[f] !== expected) begin
                $display(">>> FAILURE at Filter %0d", f);
            end
        end

        #100;
        $display("\nSimulation Finished.");
        $finish;
    end

endmodule
