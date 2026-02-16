`timescale 1ns / 1ps

module tb_wt_conv_integration;

    localparam DEPTH = 4096;
    localparam ADDR_WIDTH = $clog2(DEPTH);
    localparam WT_LATENCY = 3;

    logic clk, rst;

    // weight_manager ports
    logic        wt_wr_en;
    logic [71:0] wt_wr_data;
    logic        wt_rd_en;
    logic [ADDR_WIDTH-1:0] wt_rd_addr;
    logic [575:0] weights [0:7];
    logic         wt_data_ready;

    // conv_3x3 ports
    logic [63:0] pixels [0:2][0:2];
    logic [31:0] biases [0:7];
    logic        valid_in;
    logic        last_channel;
    logic [31:0] outs [0:7];
    logic        data_valid;

    // pixel delay pipeline (3 stages, matching WT_LATENCY)
    logic [63:0] pixel_d0 [0:2][0:2];
    logic [63:0] pixel_d1 [0:2][0:2];
    logic [63:0] pixel_d2 [0:2][0:2];

    always_ff @(posedge clk) begin
        if (rst) begin
            for (int r = 0; r < 3; r++)
                for (int c = 0; c < 3; c++) begin
                    pixel_d0[r][c] <= '0;
                    pixel_d1[r][c] <= '0;
                    pixel_d2[r][c] <= '0;
                end
        end else begin
            pixel_d0 <= pixels;
            pixel_d1 <= pixel_d0;
            pixel_d2 <= pixel_d1;
        end
    end

    // valid/last_channel delay pipeline
    logic [WT_LATENCY-1:0] valid_dly;
    logic [WT_LATENCY-1:0] lastch_dly;

    always_ff @(posedge clk) begin
        if (rst) begin
            valid_dly  <= '0;
            lastch_dly <= '0;
        end else begin
            valid_dly  <= {valid_dly[WT_LATENCY-2:0], valid_in};
            lastch_dly <= {lastch_dly[WT_LATENCY-2:0], last_channel};
        end
    end

    weight_manager #(.DEPTH(DEPTH)) u_wt (
        .clk       (clk),
        .rst       (rst),
        .wr_en     (wt_wr_en),
        .wr_data   (wt_wr_data),
        .rd_en     (wt_rd_en),
        .rd_addr   (wt_rd_addr),
        .data_out  (weights),
        .data_ready(wt_data_ready)
    );

    conv_3x3 u_conv (
        .clk          (clk),
        .rst          (rst),
        .valid_in     (valid_dly[WT_LATENCY-1]),
        .last_channel (lastch_dly[WT_LATENCY-1]),
        .pixels       (pixel_d2),
        .weights      (weights),
        .biases       (biases),
        .outs         (outs),
        .data_valid   (data_valid)
    );

    initial clk = 0;
    always #5 clk = ~clk;

    initial begin
        #5ms;
        $display("[%0t] ERROR: timeout", $time);
        $finish;
    end

    int errors = 0;

    // ── Test 1: all weights=1, all pixels=1, bias=0, ci_groups=1 ──
    // Expected per PE: 9 spatial × 8 channels × (1 × 1) = 72
    task automatic test_all_ones();
        localparam CI_GROUPS = 1;
        localparam CO_GROUPS = 1;
        localparam NUM_PIXELS = 4;
        int out_count;

        $display("=== Test 1: all ones, ci_groups=%0d ===", CI_GROUPS);

        // load weights: all bytes = 1
        // stream order: for addr, for bank, for uram
        for (int addr = 0; addr < CO_GROUPS * CI_GROUPS; addr++) begin
            for (int bank = 0; bank < 8; bank++) begin
                for (int uram = 0; uram < 8; uram++) begin
                    @(posedge clk);
                    wt_wr_en   <= 1;
                    wt_wr_data <= {9{8'd1}};  // 9 spatial weights, each = 1
                end
            end
        end
        @(posedge clk);
        wt_wr_en <= 0;

        // set biases = 0
        for (int i = 0; i < 8; i++) biases[i] = 0;

        repeat(5) @(posedge clk);

        // stream pixels: all bytes = 1
        out_count = 0;
        for (int px = 0; px < NUM_PIXELS; px++) begin
            for (int ci = 0; ci < CI_GROUPS; ci++) begin
                @(posedge clk);
                for (int r = 0; r < 3; r++)
                    for (int c = 0; c < 3; c++)
                        pixels[r][c] <= {8{8'd1}};

                valid_in     <= 1;
                last_channel <= (ci == CI_GROUPS - 1);
                wt_rd_en     <= 1;
                wt_rd_addr   <= ci;  // output_group=0, so base=0
            end
        end
        @(posedge clk);
        valid_in <= 0;
        last_channel <= 0;
        wt_rd_en <= 0;

        // wait for outputs
        repeat(10) @(posedge clk);

        // collect results using a monitor (checked below)
    endtask

    // ── Test 2: all weights=1, all pixels=1, bias=0, ci_groups=2 ──
    // Expected per PE: 2 groups × 9 spatial × 8 channels × 1 = 144
    task automatic test_multi_ci();
        localparam CI_GROUPS = 2;
        localparam CO_GROUPS = 1;
        localparam NUM_PIXELS = 4;

        $display("=== Test 2: all ones, ci_groups=%0d ===", CI_GROUPS);

        // reset weight write counter
        rst <= 1;
        repeat(3) @(posedge clk);
        rst <= 0;
        repeat(3) @(posedge clk);

        // load weights
        for (int addr = 0; addr < CO_GROUPS * CI_GROUPS; addr++) begin
            for (int bank = 0; bank < 8; bank++) begin
                for (int uram = 0; uram < 8; uram++) begin
                    @(posedge clk);
                    wt_wr_en   <= 1;
                    wt_wr_data <= {9{8'd1}};
                end
            end
        end
        @(posedge clk);
        wt_wr_en <= 0;

        for (int i = 0; i < 8; i++) biases[i] = 0;

        repeat(5) @(posedge clk);

        // stream pixels: each pixel needs CI_GROUPS cycles
        for (int px = 0; px < NUM_PIXELS; px++) begin
            for (int ci = 0; ci < CI_GROUPS; ci++) begin
                @(posedge clk);
                for (int r = 0; r < 3; r++)
                    for (int c = 0; c < 3; c++)
                        pixels[r][c] <= {8{8'd1}};

                valid_in     <= 1;
                last_channel <= (ci == CI_GROUPS - 1);
                wt_rd_en     <= 1;
                wt_rd_addr   <= ci;
            end
        end
        @(posedge clk);
        valid_in <= 0;
        last_channel <= 0;
        wt_rd_en <= 0;

        repeat(10) @(posedge clk);
    endtask

    // ── Test 3: weights=1, pixels=1, bias=10, ci_groups=1 ──
    // Expected per PE: 72 + 10 = 82
    task automatic test_with_bias();
        localparam CI_GROUPS = 1;
        localparam CO_GROUPS = 1;
        localparam NUM_PIXELS = 4;

        $display("=== Test 3: with bias=10, ci_groups=%0d ===", CI_GROUPS);

        rst <= 1;
        repeat(3) @(posedge clk);
        rst <= 0;
        repeat(3) @(posedge clk);

        for (int addr = 0; addr < CO_GROUPS * CI_GROUPS; addr++) begin
            for (int bank = 0; bank < 8; bank++) begin
                for (int uram = 0; uram < 8; uram++) begin
                    @(posedge clk);
                    wt_wr_en   <= 1;
                    wt_wr_data <= {9{8'd1}};
                end
            end
        end
        @(posedge clk);
        wt_wr_en <= 0;

        for (int i = 0; i < 8; i++) biases[i] = 32'd10;

        repeat(5) @(posedge clk);

        for (int px = 0; px < NUM_PIXELS; px++) begin
            for (int ci = 0; ci < CI_GROUPS; ci++) begin
                @(posedge clk);
                for (int r = 0; r < 3; r++)
                    for (int c = 0; c < 3; c++)
                        pixels[r][c] <= {8{8'd1}};

                valid_in     <= 1;
                last_channel <= (ci == CI_GROUPS - 1);
                wt_rd_en     <= 1;
                wt_rd_addr   <= ci;
            end
        end
        @(posedge clk);
        valid_in <= 0;
        last_channel <= 0;
        wt_rd_en <= 0;

        repeat(10) @(posedge clk);
    endtask

    // output monitor
    int result_count;
    int current_expected;

    always @(posedge clk) begin
        #1;
        if (data_valid) begin
            result_count++;
            for (int i = 0; i < 8; i++) begin
                if ($signed(outs[i]) !== current_expected) begin
                    $display("[%0t] ERROR: PE%0d output=%0d expected=%0d (result #%0d)",
                             $time, i, $signed(outs[i]), current_expected, result_count);
                    errors++;
                end
            end
        end
    end

    initial begin
        $dumpfile("tb_wt_conv_integration.vcd");
        $dumpvars(0, tb_wt_conv_integration);

        rst          = 1;
        wt_wr_en     = 0;
        wt_wr_data   = 0;
        wt_rd_en     = 0;
        wt_rd_addr   = 0;
        valid_in     = 0;
        last_channel = 0;
        for (int i = 0; i < 8; i++) biases[i] = 0;
        for (int r = 0; r < 3; r++)
            for (int c = 0; c < 3; c++)
                pixels[r][c] = 0;

        repeat(5) @(posedge clk);
        rst = 0;
        repeat(3) @(posedge clk);

        // Test 1: expected = 72
        result_count = 0;
        current_expected = 72;
        test_all_ones();
        $display("Test 1: %0d outputs collected, expected 4", result_count);
        if (result_count !== 4) errors++;

        // Test 2: expected = 144
        result_count = 0;
        current_expected = 144;
        test_multi_ci();
        $display("Test 2: %0d outputs collected, expected 4", result_count);
        if (result_count !== 4) errors++;

        // Test 3: expected = 82
        result_count = 0;
        current_expected = 82;
        test_with_bias();
        $display("Test 3: %0d outputs collected, expected 4", result_count);
        if (result_count !== 4) errors++;

        #100;
        if (errors == 0)
            $display("ALL INTEGRATION TESTS PASSED");
        else
            $display("FAILED with %0d errors", errors);
        $finish;
    end

endmodule
