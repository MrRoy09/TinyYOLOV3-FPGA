`timescale 1ns / 1ps

module tb_conv_controller;

    localparam WT_ADDR_WIDTH   = 12;
    localparam BIAS_ADDR_WIDTH = 7;
    localparam WT_LATENCY      = 3;

    localparam CI_GROUPS  = 16;
    localparam CO_GROUPS  = 32;
    localparam IMG_W      = 8;
    localparam IMG_H      = 8;
    localparam TOTAL_PIXELS = IMG_W * IMG_H;

    logic clk, rst;

    logic [9:0]                  cfg_ci_groups;
    logic [BIAS_ADDR_WIDTH-1:0]  cfg_output_group;
    logic [WT_ADDR_WIDTH-1:0]    cfg_wt_base_addr;
    logic                        go;
    logic                        busy, done;

    logic                        bias_rd_en;
    logic [BIAS_ADDR_WIDTH-1:0]  bias_rd_group;
    logic                        bias_valid;

    logic                        wt_rd_en;
    logic [WT_ADDR_WIDTH-1:0]    wt_rd_addr;
    logic                        wt_data_ready;

    logic                        pixel_valid;
    logic                        last_pixel;

    logic                        conv_valid_in;
    logic                        conv_last_channel;

    conv_controller #(
        .WT_ADDR_WIDTH   (WT_ADDR_WIDTH),
        .BIAS_ADDR_WIDTH (BIAS_ADDR_WIDTH),
        .WT_LATENCY      (WT_LATENCY)
    ) dut (.*);

    initial clk = 0;
    always #5 clk = ~clk;

    initial begin
        #10ms;
        $display("[%0t] ERROR: timeout", $time);
        $finish;
    end

    int errors = 0;

    // simulate bias_store: 1-cycle read latency
    always_ff @(posedge clk) begin
        if (rst)
            bias_valid <= 0;
        else
            bias_valid <= bias_rd_en;
    end

    // simulate weight_manager: WT_LATENCY-cycle read latency
    logic [WT_LATENCY-1:0] wt_ready_pipe;
    assign wt_data_ready = wt_ready_pipe[WT_LATENCY-1];

    always_ff @(posedge clk) begin
        if (rst)
            wt_ready_pipe <= '0;
        else
            wt_ready_pipe <= {wt_ready_pipe[WT_LATENCY-2:0], wt_rd_en};
    end

    // counters
    int wt_rd_count;
    int valid_in_count;
    int last_channel_count;

    // delay tracking: verify conv_valid_in trails wt_rd_en by exactly WT_LATENCY cycles
    int wt_rd_en_cycle_q [$];
    int conv_valid_cycle;
    int cycle_counter;

    always @(posedge clk) begin
        #1;
        cycle_counter++;

        if (wt_rd_en)
            wt_rd_en_cycle_q.push_back(cycle_counter);

        if (conv_valid_in) begin
            if (wt_rd_en_cycle_q.size() > 0) begin
                int expected_cycle = wt_rd_en_cycle_q.pop_front();
                if (cycle_counter !== expected_cycle + WT_LATENCY) begin
                    $display("[%0t] ERROR: conv_valid_in at cycle %0d, expected %0d (wt_rd_en was at %0d, latency=%0d)",
                             $time, cycle_counter, expected_cycle + WT_LATENCY, expected_cycle, WT_LATENCY);
                    errors++;
                end
            end else begin
                $display("[%0t] ERROR: conv_valid_in without prior wt_rd_en", $time);
                errors++;
            end
        end
    end

    // monitor: check weight addresses and count signals
    int expected_ci_cnt;

    always @(posedge clk) begin
        #1;
        if (wt_rd_en) begin
            wt_rd_count++;

            if (wt_rd_addr !== cfg_wt_base_addr + expected_ci_cnt) begin
                $display("[%0t] ERROR: wt_rd_addr=%0d expected=%0d (ci_cnt=%0d)",
                         $time, wt_rd_addr, cfg_wt_base_addr + expected_ci_cnt, expected_ci_cnt);
                errors++;
            end

            if (expected_ci_cnt == CI_GROUPS - 1)
                expected_ci_cnt = 0;
            else
                expected_ci_cnt++;
        end

        if (conv_valid_in)
            valid_in_count++;

        if (conv_last_channel)
            last_channel_count++;
    end

    task automatic run_one_group(input int og);
        wt_rd_count        = 0;
        valid_in_count     = 0;
        last_channel_count = 0;

        @(posedge clk);
        cfg_output_group <= og;
        cfg_wt_base_addr <= og * CI_GROUPS;
        cfg_ci_groups    <= CI_GROUPS;

        // pulse go
        @(posedge clk);
        go <= 1;
        @(posedge clk);
        go <= 0;

        // wait for busy
        @(posedge clk); #1;
        if (!busy) begin
            $display("[%0t] ERROR: busy not asserted after go (og=%0d)", $time, og);
            errors++;
        end

        // check bias_rd_en fires with correct group
        wait(bias_rd_en);
        #1;
        if (bias_rd_group !== og) begin
            $display("[%0t] ERROR: bias_rd_group=%0d expected=%0d", $time, bias_rd_group, og);
            errors++;
        end

        // wait for CONV state
        repeat(3) @(posedge clk);

        // stream pixels
        for (int px = 0; px < TOTAL_PIXELS; px++) begin
            for (int ci = 0; ci < CI_GROUPS; ci++) begin
                @(posedge clk);
                pixel_valid <= 1;
                last_pixel  <= (px == TOTAL_PIXELS - 1) && (ci == CI_GROUPS - 1);
            end
        end
        @(posedge clk);
        pixel_valid <= 0;
        last_pixel  <= 0;

        // wait for done (drain is now 7 cycles)
        wait(done);
        @(posedge clk); #1;

        if (busy) begin
            $display("[%0t] ERROR: busy still asserted after done (og=%0d)", $time, og);
            errors++;
        end
    endtask

    initial begin
        $dumpfile("tb_conv_controller.vcd");
        $dumpvars(0, tb_conv_controller);

        rst              = 1;
        go               = 0;
        pixel_valid      = 0;
        last_pixel       = 0;
        cfg_ci_groups    = CI_GROUPS;
        cfg_output_group = 0;
        cfg_wt_base_addr = 0;
        cycle_counter    = 0;

        repeat(5) @(posedge clk);
        rst = 0;
        repeat(2) @(posedge clk);

        for (int og = 0; og < CO_GROUPS; og++) begin
            expected_ci_cnt = 0;
            wt_rd_en_cycle_q.delete();

            run_one_group(og);

            if (wt_rd_count !== TOTAL_PIXELS * CI_GROUPS) begin
                $display("ERROR og=%0d: wt_rd_count=%0d expected=%0d",
                         og, wt_rd_count, TOTAL_PIXELS * CI_GROUPS);
                errors++;
            end
            if (valid_in_count !== TOTAL_PIXELS * CI_GROUPS) begin
                $display("ERROR og=%0d: valid_in_count=%0d expected=%0d",
                         og, valid_in_count, TOTAL_PIXELS * CI_GROUPS);
                errors++;
            end
            if (last_channel_count !== TOTAL_PIXELS) begin
                $display("ERROR og=%0d: last_channel_count=%0d expected=%0d",
                         og, last_channel_count, TOTAL_PIXELS);
                errors++;
            end

            $display("og=%0d: wt_rds=%0d valid_ins=%0d last_channels=%0d — OK",
                     og, wt_rd_count, valid_in_count, last_channel_count);
        end

        #100;
        if (errors == 0)
            $display("ALL %0d OUTPUT GROUPS PASSED", CO_GROUPS);
        else
            $display("FAILED with %0d errors", errors);
        $finish;
    end

endmodule
