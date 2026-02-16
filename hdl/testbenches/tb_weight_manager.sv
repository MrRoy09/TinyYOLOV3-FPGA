`timescale 1ns / 1ps

module tb_weight_manager;

    parameter DEPTH = 4096;
    parameter ADDR_WIDTH = $clog2(DEPTH);

    logic clk, rst;

    logic        wr_en;
    logic [71:0] wr_data;

    logic                    rd_en;
    logic [ADDR_WIDTH-1:0]   rd_addr;
    logic [575:0]            data_out [0:7];
    logic                    data_ready;

    localparam CIN  = 64;
    localparam COUT = 128;
    localparam CI_GROUPS = CIN / 8;
    localparam CO_GROUPS = COUT / 8;
    localparam TOTAL = CO_GROUPS * CI_GROUPS;
    localparam PIPE  = 3;  // weight_bank read latency

    weight_manager #(
        .DEPTH(DEPTH)
    ) dut (
        .clk      (clk),
        .rst      (rst),
        .wr_en    (wr_en),
        .wr_data  (wr_data),
        .rd_en    (rd_en),
        .rd_addr  (rd_addr),
        .data_out (data_out),
        .data_ready (data_ready)
    );

    initial clk = 0;
    always #5 clk = ~clk;

    initial begin
        #500us;
        $display("[%0t] ERROR: Simulation timeout!", $time);
        $finish;
    end

    // Shadow memory: [filter][channel] = 72-bit raw weight word
    logic [71:0] shadow_mem [COUT][CIN];

    // Read schedule: store (og, ig) for each read so we can verify after pipeline
    int rd_og_q [$];
    int rd_ig_q [$];

    int errors = 0;

    initial begin
        $dumpfile("tb_weight_manager.vcd");
        $dumpvars(0, tb_weight_manager);

        rst     = 1;
        wr_en   = 0;
        wr_data = 0;
        rd_en   = 0;
        rd_addr = 0;

        #100 rst = 0;
        #20;

        // ──────────────────────────────────────────────
        // WRITE: stream in CPU order
        //   for addr = 0 .. co_groups*ci_groups-1:
        //     for bank = 0..7:
        //       for uram = 0..7:
        //         stream 72-bit word
        // ──────────────────────────────────────────────
        $display("[%0t] Writing weights (CIN=%0d, COUT=%0d)", $time, CIN, COUT);

        for (int addr = 0; addr < TOTAL; addr++) begin
            int og = addr / CI_GROUPS;
            int ig = addr % CI_GROUPS;
            for (int bank = 0; bank < 8; bank++) begin
                for (int uram = 0; uram < 8; uram++) begin
                    int f = og * 8 + bank;
                    int c = ig * 8 + uram;
                    logic [71:0] word;
                    word = {8'(f), 8'(c), 56'hAABBCCDDEE0000 + 56'(f * 256 + c)};
                    shadow_mem[f][c] = word;

                    @(posedge clk);
                    wr_en   <= 1;
                    wr_data <= word;
                end
            end
        end
        @(posedge clk);
        wr_en <= 0;

        $display("[%0t] Write complete. Total beats: %0d", $time, TOTAL * 64);
        #100;

        // ──────────────────────────────────────────────
        // READ + VERIFY: pipelined — issue reads for TOTAL + PIPE cycles
        //   cycles 0..TOTAL-1: issue rd_en with address
        //   cycles PIPE..TOTAL+PIPE-1: verify output
        // ──────────────────────────────────────────────
        $display("[%0t] Starting pipelined read and verify", $time);

        for (int cyc = 0; cyc < TOTAL + PIPE; cyc++) begin
            @(posedge clk);
            #1; // let NBAs settle before sampling outputs

            // issue read
            if (cyc < TOTAL) begin
                int og = cyc / CI_GROUPS;
                int ig = cyc % CI_GROUPS;
                rd_en   <= 1;
                rd_addr <= og * CI_GROUPS + ig;
                rd_og_q.push_back(og);
                rd_ig_q.push_back(ig);
            end else begin
                rd_en <= 0;
            end

            // verify output (3 cycles behind)
            if (cyc >= PIPE) begin
                int v_og = rd_og_q.pop_front();
                int v_ig = rd_ig_q.pop_front();

                if (!data_ready) begin
                    $display("[%0t] ERROR: data_ready not asserted at og=%0d ig=%0d", $time, v_og, v_ig);
                    errors++;
                end

                for (int bank = 0; bank < 8; bank++) begin
                    logic [575:0] actual;
                    logic [575:0] expected;
                    int f = v_og * 8 + bank;

                    actual = data_out[bank];
                    expected = '0;

                    for (int pos = 0; pos < 9; pos++) begin
                        for (int ch = 0; ch < 8; ch++) begin
                            int c = v_ig * 8 + ch;
                            expected[(pos*64 + ch*8) +: 8] = shadow_mem[f][c][(pos*8) +: 8];
                        end
                    end

                    if (actual !== expected) begin
                        $display("[%0t] MISMATCH: og=%0d ig=%0d bank=%0d (filter=%0d)",
                                 $time, v_og, v_ig, bank, f);
                        errors++;
                    end
                end
            end
        end

        #100;
        if (errors == 0)
            $display("[%0t] ALL TESTS PASSED", $time);
        else
            $display("[%0t] FAILED with %0d errors", $time, errors);
        $finish;
    end

endmodule
