`timescale 1ns / 1ps

module tb_quantizer;

    logic        clk;
    logic        rst;
    logic signed [31:0] data_in;
    logic        valid_in;
    logic [31:0] M;
    logic [4:0]  n;
    logic        use_relu;
    logic [7:0]  data_out;
    logic        valid_out;

    // Instantiate the Quantizer
    quantizer uut (
        .clk(clk),
        .rst(rst),
        .data_in(data_in),
        .valid_in(valid_in),
        .M(M),
        .n(n),
        .use_relu(use_relu),
        .data_out(data_out),
        .valid_out(valid_out)
    );

    // Clock generation
    always #5 clk = ~clk;

    initial begin
        // Initialize
        clk = 0;
        rst = 1;
        valid_in = 0;
        data_in = 0;
        M = 32'h0001_0000; // M = 65536 (Multiplier for 1.0 if n=16)
        n = 5'd16;
        use_relu = 0;

        #20 rst = 0;
        #20;

        $display("\n--- START QUANTIZER TEST ---");

        // --- Test 1: Positive Value, No ReLU ---
        // Expected: 50 * (65536 / 2^16) = 50
        @(posedge clk);
        data_in = 32'sd50;
        valid_in = 1;
        use_relu = 0;
        @(posedge clk);
        valid_in = 0;
        
        repeat(4) @(posedge clk); // Wait for pipeline (4 cycles)
        $display("Test 1 | in: 50 | out: %d | expected: 50", $signed(data_out));

        // --- Test 2: Negative Value, No ReLU ---
        // Expected: -50
        @(posedge clk);
        data_in = -32'sd50;
        valid_in = 1;
        use_relu = 0;
        @(posedge clk);
        valid_in = 0;
        
        repeat(4) @(posedge clk);
        $display("Test 2 | in: -50 | out: %d | expected: -50", $signed(data_out));

        // --- Test 3: Negative Value, WITH Leaky ReLU ---
        // Expected: -80 * 1.0 * 0.125 = -10
        @(posedge clk);
        data_in = -32'sd80;
        valid_in = 1;
        use_relu = 1;
        @(posedge clk);
        valid_in = 0;
        
        repeat(4) @(posedge clk);
        $display("Test 3 | in: -80 (ReLU) | out: %d | expected: -10", $signed(data_out));

        // --- Test 4: Clamping (Positive) ---
        // Expected: 200 -> 127
        @(posedge clk);
        data_in = 32'sd200;
        valid_in = 1;
        use_relu = 0;
        @(posedge clk);
        valid_in = 0;
        
        repeat(4) @(posedge clk);
        $display("Test 4 | in: 200 | out: %d | expected: 127", $signed(data_out));

        // --- Test 5: Clamping (Negative) ---
        // Expected: -300 -> -128
        @(posedge clk);
        data_in = -32'sd300;
        valid_in = 1;
        use_relu = 0;
        @(posedge clk);
        valid_in = 0;
        
        repeat(4) @(posedge clk);
        $display("Test 5 | in: -300 | out: %d | expected: -128", $signed(data_out));

        #50;
        $display("--- QUANTIZER TEST FINISHED ---");
        $finish;
    end

endmodule
