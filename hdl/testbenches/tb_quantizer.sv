`timescale 1ns / 1ps
`include "tb_macros.svh"

// ============================================================================
// Testbench for quantizer module
// ============================================================================
// Tests the 4-stage quantization pipeline:
//   Stage 1: leaky_result = leaky_relu(data_in) - arithmetic shift >>3 if negative
//   Stage 2: mult_result  = leaky_result * M
//   Stage 3: shifted_result = mult_result >>> n
//   Stage 4: data_out = clamp(shifted_result) to INT8 [-128, 127]
// ============================================================================

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
    initial clk = 0;
    always #5 clk = ~clk;

    // Timeout
    `TB_TIMEOUT(100us)

    // Error counter
    int errors = 0;
    int test_count = 0;

    // ========================================================================
    // Compute expected output matching quantizer pipeline
    // ========================================================================
    function automatic logic signed [7:0] compute_expected(
        input logic signed [31:0] din,
        input logic [31:0] m_val,
        input logic [4:0]  n_val,
        input logic        relu
    );
        logic signed [31:0] leaky_result;
        logic signed [63:0] mult_result;
        logic signed [31:0] shifted_result;
        logic signed [7:0]  clamped;

        // Stage 1: Leaky ReLU (>>3 if negative and relu enabled)
        if (relu && din < 0)
            leaky_result = din >>> 3;  // Arithmetic right shift
        else
            leaky_result = din;

        // Stage 2: Multiply by M (M treated as unsigned, then sign-extended)
        mult_result = leaky_result * $signed({1'b0, m_val});

        // Stage 3: Arithmetic right shift by n
        shifted_result = mult_result >>> n_val;

        // Stage 4: Clamp to INT8 [-128, 127]
        if (shifted_result > 127)
            clamped = 8'sd127;
        else if (shifted_result < -128)
            clamped = -8'sd128;
        else
            clamped = shifted_result[7:0];

        return clamped;
    endfunction

    // ========================================================================
    // Test helper task - applies input and checks output after pipeline delay
    // ========================================================================
    task automatic run_test(
        input string test_name,
        input logic signed [31:0] din,
        input logic [31:0] m_val,
        input logic [4:0]  n_val,
        input logic        relu
    );
        logic signed [7:0] expected;

        expected = compute_expected(din, m_val, n_val, relu);

        // Configure
        M = m_val;
        n = n_val;
        use_relu = relu;

        // Apply input
        @(posedge clk);
        data_in = din;
        valid_in = 1;
        @(posedge clk);
        valid_in = 0;

        // Wait for pipeline (4 stages)
        repeat(4) @(posedge clk);

        // Check output
        test_count++;
        if ($signed(data_out) !== expected) begin
            $display("[%0t] ERROR: %s - in=%0d, M=%0d, n=%0d, relu=%0d -> got %0d, expected %0d",
                $time, test_name, din, m_val, n_val, relu, $signed(data_out), expected);
            errors++;
        end else begin
            $display("[%0t] OK: %s - in=%0d -> out=%0d", $time, test_name, din, $signed(data_out));
        end
    endtask

    // ========================================================================
    // Main test sequence
    // ========================================================================
    initial begin
        $dumpfile("tb_quantizer.vcd");
        $dumpvars(0, tb_quantizer);

        `TB_HEADER("quantizer")

        // Initialize
        rst = 1;
        valid_in = 0;
        data_in = 0;
        M = 32'h0001_0000;  // M = 65536 (Multiplier for 1.0 if n=16)
        n = 5'd16;
        use_relu = 0;

        repeat(5) @(posedge clk);
        rst = 0;
        repeat(2) @(posedge clk);

        // ====================================================================
        // Test 1: Basic passthrough (M=65536, n=16 -> scale = 1.0)
        // ====================================================================
        `TEST_CASE(1, "Basic passthrough (scale=1.0)")

        run_test("positive small",  32'sd50,  32'h0001_0000, 5'd16, 0);
        run_test("positive medium", 32'sd100, 32'h0001_0000, 5'd16, 0);
        run_test("zero",            32'sd0,   32'h0001_0000, 5'd16, 0);
        run_test("negative small",  -32'sd50, 32'h0001_0000, 5'd16, 0);
        run_test("negative medium", -32'sd100,32'h0001_0000, 5'd16, 0);

        // ====================================================================
        // Test 2: Clamping behavior
        // ====================================================================
        `TEST_CASE(2, "Clamping to INT8 range")

        run_test("clamp positive", 32'sd200,  32'h0001_0000, 5'd16, 0);  // -> 127
        run_test("clamp negative", -32'sd300, 32'h0001_0000, 5'd16, 0);  // -> -128
        run_test("at positive boundary", 32'sd127, 32'h0001_0000, 5'd16, 0);
        run_test("at negative boundary", -32'sd128, 32'h0001_0000, 5'd16, 0);

        // ====================================================================
        // Test 3: Leaky ReLU activation
        // ====================================================================
        `TEST_CASE(3, "Leaky ReLU (>>3 for negative)")

        run_test("leaky positive (no change)", 32'sd80, 32'h0001_0000, 5'd16, 1);  // -> 80
        run_test("leaky negative (>>3)", -32'sd80, 32'h0001_0000, 5'd16, 1);       // -> -80/8 = -10
        run_test("leaky zero", 32'sd0, 32'h0001_0000, 5'd16, 1);
        run_test("leaky negative large", -32'sd240, 32'h0001_0000, 5'd16, 1);      // -> -240/8 = -30

        // ====================================================================
        // Test 4: Different scale factors (M/n combinations)
        // ====================================================================
        `TEST_CASE(4, "Different scale factors")

        // scale = 0.5 (M=32768, n=16)
        run_test("scale 0.5", 32'sd100, 32'h0000_8000, 5'd16, 0);  // -> 50

        // scale = 2.0 (M=131072, n=16)
        run_test("scale 2.0", 32'sd50, 32'h0002_0000, 5'd16, 0);   // -> 100

        // scale = 0.25 (M=16384, n=16)
        run_test("scale 0.25", 32'sd100, 32'h0000_4000, 5'd16, 0); // -> 25

        // Different n values
        run_test("n=8, M=256",  32'sd100, 32'd256,  5'd8,  0);     // -> 100
        run_test("n=20, M=1M",  32'sd100, 32'd1048576, 5'd20, 0);  // -> 100

        // ====================================================================
        // Test 5: Real quantization parameters (from YOLO)
        // ====================================================================
        `TEST_CASE(5, "YOLO-like quantization parameters")

        // Typical YOLO params: M=0x3CA, n=16 (scale ~ 0.015)
        run_test("yolo params pos", 32'sd1000, 32'h000003CA, 5'd16, 1);
        run_test("yolo params neg", -32'sd1000, 32'h000003CA, 5'd16, 1);

        // Large accumulator value
        run_test("large accum", 32'sd50000, 32'h000003CA, 5'd16, 1);

        // ====================================================================
        // Test 6: Edge cases
        // ====================================================================
        `TEST_CASE(6, "Edge cases")

        // Very small M (should underflow to 0 or small value)
        run_test("tiny M", 32'sd100, 32'd1, 5'd16, 0);

        // Large M with large n
        run_test("large M large n", 32'sd100, 32'hFFFF_FFFF, 5'd31, 0);

        // Negative input with leaky that stays in range
        run_test("neg leaky in range", -32'sd8, 32'h0001_0000, 5'd16, 1);  // -> -1

        // ====================================================================
        // Summary
        // ====================================================================
        repeat(10) @(posedge clk);

        `TB_FOOTER(errors)
        $display("  Ran %0d tests", test_count);

        $finish;
    end

endmodule
