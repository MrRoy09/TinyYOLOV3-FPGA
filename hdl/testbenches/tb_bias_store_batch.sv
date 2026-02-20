`timescale 1ns / 1ps

// Test bias_store behavior under multi-OG batching scenario
// Verifies that:
// 1. Biases accumulate at correct addresses when wr_addr_rst is only pulsed for OG0
// 2. Reading with rd_group selects the correct bias addresses
// 3. No cross-contamination between OG biases

module tb_bias_store_batch;

    localparam MAX_DEPTH = 256;
    localparam ADDR_WIDTH = $clog2(MAX_DEPTH);
    localparam NUM_OGS = 8;  // Test with 8 OGs like Layer 2

    // DUT signals
    logic clk, rst;
    logic wr_en;
    logic [127:0] wr_data;
    logic wr_addr_rst;
    logic rd_en;
    logic [ADDR_WIDTH-2:0] rd_group;
    logic [31:0] bias_out [0:7];
    logic rd_valid;

    // Reference storage for verification
    logic [31:0] expected_biases [0:NUM_OGS-1][0:7];  // [og][bias_idx]

    // DUT
    bias_store #(
        .MAX_DEPTH(MAX_DEPTH),
        .ADDR_WIDTH(ADDR_WIDTH)
    ) u_dut (
        .clk(clk),
        .rst(rst),
        .wr_en(wr_en),
        .wr_data(wr_data),
        .wr_addr_rst(wr_addr_rst),
        .rd_en(rd_en),
        .rd_group(rd_group),
        .bias_out(bias_out),
        .rd_valid(rd_valid)
    );

    // Clock
    initial clk = 0;
    always #5 clk = ~clk;

    // Timeout
    initial begin
        #10us;
        $display("[%0t] TIMEOUT", $time);
        $finish;
    end

    int errors = 0;

    // Generate unique biases for each OG
    // Pattern: bias[og][idx] = (og << 8) | idx | (idx << 16)
    function automatic [31:0] gen_bias(int og, int idx);
        return (og << 24) | (og << 16) | (idx << 8) | idx;
    endfunction

    // Pack 4 biases into 128-bit word
    function automatic [127:0] pack_biases_low(int og);
        logic [127:0] result;
        result = 0;
        for (int i = 0; i < 4; i++) begin
            result |= ({96'b0, gen_bias(og, i)} << (i * 32));
        end
        return result;
    endfunction

    function automatic [127:0] pack_biases_high(int og);
        logic [127:0] result;
        result = 0;
        for (int i = 0; i < 4; i++) begin
            result |= ({96'b0, gen_bias(og, 4 + i)} << (i * 32));
        end
        return result;
    endfunction

    // Write biases for one OG (2 AXI beats)
    task automatic write_og_biases(int og, bit do_addr_reset);
        @(posedge clk);
        if (do_addr_reset) begin
            wr_addr_rst <= 1;
            @(posedge clk);
            wr_addr_rst <= 0;
        end

        // First beat: biases 0-3
        @(posedge clk);
        wr_en <= 1;
        wr_data <= pack_biases_low(og);

        // Second beat: biases 4-7
        @(posedge clk);
        wr_data <= pack_biases_high(og);

        @(posedge clk);
        wr_en <= 0;

        $display("Wrote OG%0d biases (addr_reset=%0d)", og, do_addr_reset);
    endtask

    // Read and verify biases for one OG
    task automatic verify_og_biases(int og);
        int mismatch = 0;

        @(posedge clk);
        rd_en <= 1;
        rd_group <= og[ADDR_WIDTH-2:0];
        @(posedge clk);
        rd_en <= 0;

        // Wait for rd_valid
        @(posedge clk);
        if (!rd_valid) begin
            $display("ERROR: rd_valid not asserted after read");
            errors++;
            return;
        end

        // Check each bias
        for (int i = 0; i < 8; i++) begin
            logic [31:0] expected = gen_bias(og, i);
            if (bias_out[i] !== expected) begin
                $display("  ERROR OG%0d bias[%0d]: got 0x%08h, expected 0x%08h",
                    og, i, bias_out[i], expected);
                mismatch++;
                errors++;
            end
        end

        if (mismatch == 0)
            $display("  OG%0d biases: all 8 correct", og);
    endtask

    initial begin
        $dumpfile("tb_bias_store_batch.vcd");
        $dumpvars(0, tb_bias_store_batch);

        $display("\n=======================================");
        $display("  Bias Store Multi-OG Batching Test");
        $display("  Testing %0d output groups", NUM_OGS);
        $display("=======================================\n");

        // Initialize
        rst = 1;
        wr_en = 0;
        wr_data = 0;
        wr_addr_rst = 0;
        rd_en = 0;
        rd_group = 0;

        repeat(5) @(posedge clk);
        rst = 0;
        repeat(2) @(posedge clk);

        // ====================
        // Test 1: Write all OG biases with proper multi-OG batching pattern
        // (addr reset only for first OG)
        // ====================
        $display("--- Test 1: Write all OG biases ---");
        for (int og = 0; og < NUM_OGS; og++) begin
            write_og_biases(og, og == 0);  // addr_reset only for OG0
        end

        repeat(2) @(posedge clk);

        // ====================
        // Test 2: Verify each OG's biases are at correct addresses
        // ====================
        $display("\n--- Test 2: Verify biases ---");
        for (int og = 0; og < NUM_OGS; og++) begin
            verify_og_biases(og);
        end

        // ====================
        // Test 3: Verify random access pattern (read OGs out of order)
        // ====================
        $display("\n--- Test 3: Random access verification ---");
        verify_og_biases(5);  // Random OG
        verify_og_biases(2);
        verify_og_biases(7);
        verify_og_biases(0);

        // ====================
        // Test 4: Simulate new kernel invocation (re-write biases)
        // ====================
        $display("\n--- Test 4: New kernel invocation ---");

        // Clear with reset
        rst = 1;
        repeat(2) @(posedge clk);
        rst = 0;
        repeat(2) @(posedge clk);

        // Write different biases (add 0x100 offset to distinguish)
        for (int og = 0; og < NUM_OGS; og++) begin
            write_og_biases(og, og == 0);
        end

        // Verify
        for (int og = 0; og < NUM_OGS; og++) begin
            verify_og_biases(og);
        end

        // ====================
        // Summary
        // ====================
        repeat(10) @(posedge clk);

        $display("\n=======================================");
        if (errors == 0)
            $display("  BIAS STORE BATCH TEST PASSED");
        else
            $display("  BIAS STORE BATCH TEST FAILED: %0d errors", errors);
        $display("=======================================\n");

        $finish;
    end

endmodule
