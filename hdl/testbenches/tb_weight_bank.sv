`timescale 1ns / 1ps

module tb_weight_bank;

    parameter DEPTH = 16;
    parameter ADDR_WIDTH = $clog2(DEPTH);

    logic clk;
    logic rst;

    logic wen [0:7];
    logic [71:0] wdata;
    logic [ADDR_WIDTH-1:0] waddr;

    logic ren [0:7];
    logic [ADDR_WIDTH-1:0] raddr;
    logic [575:0] rdata;

    // Instantiate DUT
    weight_bank #(
        .DEPTH(DEPTH)
    ) uut (
        .clk(clk),
        .rst(rst),
        .wen(wen),
        .wdata(wdata),
        .waddr(waddr),
        .ren(ren),
        .raddr(raddr),
        .rdata(rdata)
    );

    // Clock generation
    always #5 clk = ~clk;

    // Helper to extract a 72-bit bank slice from rdata
    function logic [71:0] get_bank(input int idx);
        return rdata[idx*72 +: 72];
    endfunction

    // Helper tasks
    task set_all_wen(input logic val);
        for (int i = 0; i < 8; i++) wen[i] = val;
    endtask

    task set_all_ren(input logic val);
        for (int i = 0; i < 8; i++) ren[i] = val;
    endtask

    integer pass_count;
    integer fail_count;

    task check_bank(input int bank, input logic [71:0] expected);
        logic [71:0] actual;
        actual = get_bank(bank);
        if (actual === expected) begin
            $display("  PASS | bank[%0d] = 0x%018h", bank, actual);
            pass_count++;
        end else begin
            $display("  FAIL | bank[%0d] = 0x%018h, expected 0x%018h", bank, actual, expected);
            fail_count++;
        end
    endtask

    initial begin
        // Initialize
        clk = 0;
        rst = 1;
        wdata = '0;
        waddr = '0;
        raddr = '0;
        set_all_wen(0);
        set_all_ren(0);
        pass_count = 0;
        fail_count = 0;

        #20 rst = 0;
        #10;

        $display("\n--- START WEIGHT_BANK TEST ---\n");

        // =============================================
        // Test 1: Write to all 8 banks at addr 0
        // =============================================
        $display("Test 1: Write all banks at addr 0, read back");
        @(posedge clk);
        waddr = 0;
        wdata = 72'hAA_BBCCDDEE_FF001122;
        set_all_wen(1);
        @(posedge clk);
        set_all_wen(0);

        // Read back from addr 0
        @(posedge clk);
        raddr = 0;
        set_all_ren(1);
        @(posedge clk);
        set_all_ren(0);

        // Wait for 3-stage read pipeline
        repeat(3) @(posedge clk);

        for (int i = 0; i < 8; i++)
            check_bank(i, 72'hAA_BBCCDDEE_FF001122);

        // =============================================
        // Test 2: Write different data per bank
        // =============================================
        $display("\nTest 2: Write different data per bank at addr 1");
        for (int i = 0; i < 8; i++) begin
            @(posedge clk);
            waddr = 1;
            wdata = 72'h10 * (i + 1); // bank0=0x10, bank1=0x20, ...
            set_all_wen(0);
            wen[i] = 1;
            @(posedge clk);
            wen[i] = 0;
        end

        // Read back addr 1
        @(posedge clk);
        raddr = 1;
        set_all_ren(1);
        @(posedge clk);
        set_all_ren(0);

        repeat(3) @(posedge clk);

        for (int i = 0; i < 8; i++)
            check_bank(i, 72'h10 * (i + 1));

        // =============================================
        // Test 3: Selective bank read enable
        // =============================================
        $display("\nTest 3: Read with only bank 0 enabled (addr 0 still has Test 1 data)");

        // First reset pipeline by asserting rst briefly
        @(posedge clk);
        rst = 1;
        repeat(2) @(posedge clk);
        rst = 0;
        @(posedge clk);

        // Read with only bank 0 enabled
        raddr = 0;
        set_all_ren(0);
        ren[0] = 1;
        @(posedge clk);
        ren[0] = 0;

        repeat(3) @(posedge clk);

        check_bank(0, 72'hAA_BBCCDDEE_FF001122);

        // =============================================
        // Test 4: Write and read at different addresses
        // =============================================
        $display("\nTest 4: Write to multiple addresses, read back");

        // Write addr 5
        @(posedge clk);
        waddr = 5;
        wdata = 72'hDEAD_BEEF_CAFE_0000_00;
        set_all_wen(1);
        @(posedge clk);
        set_all_wen(0);

        // Write addr 10
        @(posedge clk);
        waddr = 10;
        wdata = 72'h1234_5678_9ABC_DEF0_00;
        set_all_wen(1);
        @(posedge clk);
        set_all_wen(0);

        // Read addr 5
        @(posedge clk);
        raddr = 5;
        set_all_ren(1);
        @(posedge clk);
        set_all_ren(0);
        repeat(3) @(posedge clk);

        $display("  addr 5:");
        for (int i = 0; i < 8; i++)
            check_bank(i, 72'hDEAD_BEEF_CAFE_0000_00);

        // Read addr 10
        @(posedge clk);
        raddr = 10;
        set_all_ren(1);
        @(posedge clk);
        set_all_ren(0);
        repeat(3) @(posedge clk);

        $display("  addr 10:");
        for (int i = 0; i < 8; i++)
            check_bank(i, 72'h1234_5678_9ABC_DEF0_00);

        // =============================================
        // Summary
        // =============================================
        #50;
        $display("\n--- WEIGHT_BANK TEST FINISHED ---");
        $display("  Results: %0d passed, %0d failed\n", pass_count, fail_count);
        $finish;
    end

endmodule