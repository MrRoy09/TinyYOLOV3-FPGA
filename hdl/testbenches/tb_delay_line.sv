`timescale 1ns / 1ps

// Testbench for delayLine: verifies output delay matches delay_depth cycles

module tb_delay_line;

    logic        clk;
    logic        rst;
    logic        en;
    logic [7:0]  delay_depth;
    logic [63:0] din;
    logic [63:0] dout;

    delayLine #(
        .WIDTH    (64),
        .MAX_DEPTH(32)
    ) u_dut (
        .clk        (clk),
        .rst        (rst),
        .en         (en),
        .delay_depth(delay_depth),
        .din        (din),
        .dout       (dout)
    );

    // Clock generation
    initial clk = 0;
    always #5 clk = ~clk;

    // Timeout
    initial begin
        #100us;
        $display("[%0t] TIMEOUT", $time);
        $finish;
    end

    int errors = 0;

    // Test a specific delay_depth value
    // For delay_depth=N, hardware delay is N cycles.
    // Testbench captures dout before the clock edge, so it sees the value
    // that was computed in the previous cycle. This adds 1 to the observed delay.
    task automatic test_depth(input int depth);
        logic [63:0] history [$];
        logic [63:0] expected;
        logic [63:0] captured_dout;
        int          i;
        int          testbench_delay;

        $display("\n--- Testing delay_depth = %0d ---", depth);

        // Hardware delay = depth cycles
        // Testbench sees depth+1 iterations because we capture before clock edge
        // (But our capture is aligned, so just use depth)
        testbench_delay = depth;

        // Reset
        rst = 1;
        en = 0;
        din = 0;
        delay_depth = depth;
        repeat(3) @(posedge clk);
        rst = 0;
        repeat(2) @(posedge clk);

        // Stream values with enable
        history = {};

        for (i = 0; i < 30; i++) begin
            // Capture dout BEFORE changing din (this is the output from previous cycle)
            captured_dout = dout;

            // Check if we have enough history to verify (accounting for priming)
            if (history.size() >= testbench_delay) begin
                expected = history.pop_front();
                if (captured_dout !== expected) begin
                    $display("  ERROR at cycle %0d: got %h, expected %h", i, captured_dout, expected);
                    errors++;
                end else begin
                    $display("  OK cycle %0d: %h", i, captured_dout);
                end
            end

            // Now set new din and push to history
            din = 64'hBEEF_0000_0000_0000 | i;
            en = 1;
            history.push_back(din);

            @(posedge clk);
        end

        // Drain remaining - continue streaming zeros to push out buffered values
        while (history.size() > 0) begin
            captured_dout = dout;
            expected = history.pop_front();
            if (captured_dout !== expected) begin
                $display("  ERROR drain: got %h, expected %h", captured_dout, expected);
                errors++;
            end else begin
                $display("  OK drain: %h", captured_dout);
            end

            din = 64'h0;
            en = 1;
            @(posedge clk);
        end

        en = 0;

    endtask

    // Test enable gating
    // For delay_depth=3, we use 2 buffer entries (delay_depth-1 entries)
    // When en=0, buffer doesn't advance, so enable acts as a clock gate
    task automatic test_enable_gating();
        $display("\n--- Testing enable gating ---");

        // Reset
        rst = 1;
        en = 0;
        din = 0;
        delay_depth = 3;  // Use depth=3 to get 2 buffer entries
        repeat(3) @(posedge clk);
        rst = 0;
        repeat(2) @(posedge clk);

        // Enabled cycle 0: write A to mem[0], ptr 0->1, dout=garbage
        din = 64'hAAAA_AAAA_AAAA_AAAA;
        en = 1;
        @(posedge clk);

        // Enabled cycle 1: write B to mem[1], ptr 1->0, dout=garbage
        din = 64'hBBBB_BBBB_BBBB_BBBB;
        en = 1;
        @(posedge clk);

        // Enabled cycle 2: write C to mem[0], ptr 0->1, dout=A
        din = 64'hCCCC_CCCC_CCCC_CCCC;
        en = 1;
        @(posedge clk);

        // After enabled cycle 2, dout = A
        if (dout !== 64'hAAAA_AAAA_AAAA_AAAA) begin
            $display("  ERROR: expected AAAA..., got %h", dout);
            errors++;
        end else begin
            $display("  OK: delay=3 works, got %h", dout);
        end

        // Enabled cycle 3: write D to mem[1], ptr 1->0, dout=B
        din = 64'hDDDD_DDDD_DDDD_DDDD;
        en = 1;
        @(posedge clk);

        // After enabled cycle 3, dout = B
        if (dout !== 64'hBBBB_BBBB_BBBB_BBBB) begin
            $display("  ERROR: expected BBBB..., got %h", dout);
            errors++;
        end else begin
            $display("  OK: second value correct, got %h", dout);
        end

        // Now test with enable gaps
        // Disable for 2 cycles - buffer should freeze
        en = 0;
        @(posedge clk);
        @(posedge clk);

        // dout should still be B (no change during disable)
        if (dout !== 64'hBBBB_BBBB_BBBB_BBBB) begin
            $display("  ERROR: enable gate failed, expected BBBB..., got %h", dout);
            errors++;
        end else begin
            $display("  OK: enable gating works, dout unchanged during disable");
        end

        en = 0;

    endtask

    initial begin
        $dumpfile("tb_delay_line.vcd");
        $dumpvars(0, tb_delay_line);

        $display("\n=========================================");
        $display("  delayLine Testbench");
        $display("=========================================");

        // Test various depths
        test_depth(1);   // Bypass mode (direct register)
        test_depth(2);   // Minimal buffer
        test_depth(4);   // Multi-channel case
        test_depth(8);   // Larger depth

        // Test enable gating
        test_enable_gating();

        #100;
        $display("\n=========================================");
        if (errors == 0)
            $display("  PASSED: All tests passed");
        else
            $display("  FAILED: %0d errors", errors);
        $display("=========================================\n");
        $finish;
    end

endmodule
