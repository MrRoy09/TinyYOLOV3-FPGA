`timescale 1ns / 1ps
`include "tb_macros.svh"

// ============================================================================
// Testbench for bias_store module
// ============================================================================
// Verifies BRAM-based bias storage with:
//   - Sequential write of 128-bit words (4 biases per word)
//   - Random-access read by output group
//   - Out-of-order access patterns
// ============================================================================

module tb_bias_store;

    localparam MAX_DEPTH  = 256;
    localparam ADDR_WIDTH = $clog2(MAX_DEPTH);
    localparam NUM_GROUPS = 4;  // test with 4 output groups = 32 biases

    logic        clk, rst;
    logic        wr_en;
    logic [127:0] wr_data;
    logic        rd_en;
    logic [ADDR_WIDTH-2:0] rd_group;
    logic [31:0] bias_out [0:7];
    logic        rd_valid;

    // Error counter
    int errors = 0;

    bias_store #(
        .MAX_DEPTH(MAX_DEPTH)
    ) dut (.*);

    // Clock
    initial clk = 0;
    always #5 clk = ~clk;

    // Timeout
    `TB_TIMEOUT(100us)

    // Expected bias values: bias[n] = n + 1
    task automatic write_all_biases();
        for (int g = 0; g < NUM_GROUPS; g++) begin
            // row 0: biases [g*8 +: 4]
            for (int r = 0; r < 2; r++) begin
                logic [127:0] word;
                for (int i = 0; i < 4; i++) begin
                    word[i*32 +: 32] = g * 8 + r * 4 + i + 1;
                end
                @(posedge clk);
                wr_en   <= 1;
                wr_data <= word;
            end
        end
        @(posedge clk);
        wr_en <= 0;
    endtask

    task automatic read_and_check(input int group);
        int expected;

        @(posedge clk);
        rd_en    <= 1;
        rd_group <= group;
        @(posedge clk);
        rd_en <= 0;
        @(posedge clk); // wait for rd_valid

        // Check rd_valid
        if (!rd_valid) begin
            $display("[%0t] ERROR: rd_valid not asserted for group %0d", $time, group);
            errors++;
            return;
        end

        // Check each bias value
        for (int i = 0; i < 8; i++) begin
            expected = group * 8 + i + 1;
            if (bias_out[i] != expected) begin
                $display("[%0t] ERROR: group %0d bias[%0d]: got %0d, expected %0d",
                    $time, group, i, bias_out[i], expected);
                errors++;
            end
        end

        if (errors == 0 || (errors > 0 && bias_out[0] == group * 8 + 1)) begin
            $display("  OK: group %0d biases = [%0d %0d %0d %0d %0d %0d %0d %0d]",
                group,
                bias_out[0], bias_out[1], bias_out[2], bias_out[3],
                bias_out[4], bias_out[5], bias_out[6], bias_out[7]);
        end
    endtask

    initial begin
        $dumpfile("tb_bias_store.vcd");
        $dumpvars(0, tb_bias_store);

        `TB_HEADER("bias_store")

        rst      = 1;
        wr_en    = 0;
        rd_en    = 0;
        rd_group = 0;
        wr_data  = 0;

        repeat(3) @(posedge clk);
        rst = 0;
        @(posedge clk);

        // ====================================================================
        // Test 1: Write all biases
        // ====================================================================
        `TEST_CASE(1, "Write biases")
        $display("  Writing %0d groups (%0d biases)...", NUM_GROUPS, NUM_GROUPS * 8);
        write_all_biases();
        repeat(2) @(posedge clk);

        // ====================================================================
        // Test 2: Sequential read back
        // ====================================================================
        `TEST_CASE(2, "Sequential read")
        for (int g = 0; g < NUM_GROUPS; g++) begin
            read_and_check(g);
        end

        // ====================================================================
        // Test 3: Out-of-order reads
        // ====================================================================
        `TEST_CASE(3, "Out-of-order reads")
        read_and_check(3);
        read_and_check(0);
        read_and_check(2);
        read_and_check(1);

        // ====================================================================
        // Test 4: Back-to-back reads
        // ====================================================================
        `TEST_CASE(4, "Back-to-back reads")
        for (int g = 0; g < NUM_GROUPS; g++) begin
            @(posedge clk);
            rd_en    <= 1;
            rd_group <= g;
        end
        @(posedge clk);
        rd_en <= 0;

        // Wait for all reads to complete
        repeat(NUM_GROUPS + 2) @(posedge clk);

        // ====================================================================
        // Summary
        // ====================================================================
        repeat(5) @(posedge clk);

        `TB_FOOTER(errors)

        $finish;
    end

endmodule
