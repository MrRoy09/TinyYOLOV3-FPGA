`timescale 1ns / 1ps

// End-to-end batch test for conv_top with Layer 2-like configuration
// Tests 8 output groups with ci_groups=4 to verify multi-OG batching
//
// Uses stimulus from scripts/stimulus_batch_test/

module tb_conv_top_e2e_batch;

    localparam WT_DEPTH        = 4096;
    localparam WT_ADDR_WIDTH   = $clog2(WT_DEPTH);
    localparam BIAS_DEPTH      = 256;
    localparam BIAS_GROUP_BITS = $clog2(BIAS_DEPTH) - 1;
    localparam WT_LATENCY      = 3;
    localparam CONV_PE_PIPE    = 4;

    // Layer 2-like configuration (4x4 → 2x2)
    localparam PADDED_W   = 6;
    localparam PADDED_H   = 6;
    localparam CI_GROUPS  = 4;
    localparam CO_GROUPS  = 8;
    localparam N_PIXELS   = PADDED_H * PADDED_W * CI_GROUPS;  // 144
    localparam N_WT_WORDS = CI_GROUPS * 8 * 8;                // 256
    localparam N_EXPECTED = 4;                                // 2×2 maxpool output
    localparam N_BIAS_WORDS = CO_GROUPS * 2;                  // 16 (2 per OG)

    // DUT signals
    logic        clk, rst;
    logic [9:0]                    cfg_ci_groups;
    logic [BIAS_GROUP_BITS-1:0]    cfg_output_group;
    logic [WT_ADDR_WIDTH-1:0]      cfg_wt_base_addr;
    logic [15:0]                   cfg_in_channels;
    logic [15:0]                   cfg_img_width;
    logic                          cfg_use_maxpool;
    logic                          cfg_stride_2;
    logic [31:0]                   cfg_quant_m;
    logic [4:0]                    cfg_quant_n;
    logic                          cfg_use_relu;
    logic                          cfg_kernel_1x1;
    logic                          go;
    logic                          busy, done;

    logic                          bias_wr_en;
    logic [127:0]                  bias_wr_data;
    logic                          bias_wr_addr_rst;

    logic                          wt_wr_en;
    logic [71:0]                   wt_wr_data;
    logic                          wt_wr_addr_rst;

    logic [63:0]                   pixel_in;
    logic                          pixel_in_valid;
    logic                          pixel_in_last;

    logic [63:0]                   data_out;
    logic                          data_out_valid;

    // DUT
    conv_top #(
        .WT_DEPTH   (WT_DEPTH),
        .BIAS_DEPTH (BIAS_DEPTH),
        .WT_LATENCY (WT_LATENCY),
        .CONV_PE_PIPE(CONV_PE_PIPE)
    ) u_dut (
        .clk(clk),
        .rst(rst),
        .cfg_ci_groups(cfg_ci_groups),
        .cfg_output_group(cfg_output_group),
        .cfg_wt_base_addr(cfg_wt_base_addr),
        .cfg_in_channels(cfg_in_channels),
        .cfg_img_width(cfg_img_width),
        .cfg_use_maxpool(cfg_use_maxpool),
        .cfg_stride_2(cfg_stride_2),
        .cfg_quant_m(cfg_quant_m),
        .cfg_quant_n(cfg_quant_n),
        .cfg_use_relu(cfg_use_relu),
        .cfg_kernel_1x1(cfg_kernel_1x1),
        .go(go),
        .busy(busy),
        .done(done),
        .bias_wr_en(bias_wr_en),
        .bias_wr_data(bias_wr_data),
        .bias_wr_addr_rst(bias_wr_addr_rst),
        .wt_wr_en(wt_wr_en),
        .wt_wr_data(wt_wr_data),
        .wt_wr_addr_rst(wt_wr_addr_rst),
        .pixel_in(pixel_in),
        .pixel_in_valid(pixel_in_valid),
        .pixel_in_last(pixel_in_last),
        .data_out(data_out),
        .data_out_valid(data_out_valid)
    );

    // Clock
    initial clk = 0;
    always #5 clk = ~clk;

    // Timeout
    initial begin
        #50ms;
        $display("[%0t] TIMEOUT", $time);
        $finish;
    end

    int errors = 0;
    int total_og_errors [0:CO_GROUPS-1];

    // Stimulus memories
    logic [63:0]  pixel_mem     [0:N_PIXELS-1];
    logic [71:0]  weight_mem    [0:CO_GROUPS-1][0:N_WT_WORDS-1];
    logic [63:0]  expected_mem  [0:CO_GROUPS-1][0:N_EXPECTED-1];
    logic [127:0] bias_all_mem  [0:N_BIAS_WORDS-1];
    logic [127:0] bias_og_mem   [0:CO_GROUPS-1][0:1];  // 2 words per OG

    // Load stimulus files
    initial begin
        // Pixels (same for all OGs)
        $readmemh("../../../../../scripts/stimulus_batch_test/pixels_og0.hex", pixel_mem);

        // All biases packed
        $readmemh("../../../../../scripts/stimulus_batch_test/biases_all.hex", bias_all_mem);

        // Per-OG data
        $readmemh("../../../../../scripts/stimulus_batch_test/weights_og0.hex",  weight_mem[0]);
        $readmemh("../../../../../scripts/stimulus_batch_test/weights_og1.hex",  weight_mem[1]);
        $readmemh("../../../../../scripts/stimulus_batch_test/weights_og2.hex",  weight_mem[2]);
        $readmemh("../../../../../scripts/stimulus_batch_test/weights_og3.hex",  weight_mem[3]);
        $readmemh("../../../../../scripts/stimulus_batch_test/weights_og4.hex",  weight_mem[4]);
        $readmemh("../../../../../scripts/stimulus_batch_test/weights_og5.hex",  weight_mem[5]);
        $readmemh("../../../../../scripts/stimulus_batch_test/weights_og6.hex",  weight_mem[6]);
        $readmemh("../../../../../scripts/stimulus_batch_test/weights_og7.hex",  weight_mem[7]);

        $readmemh("../../../../../scripts/stimulus_batch_test/expected_og0.hex", expected_mem[0]);
        $readmemh("../../../../../scripts/stimulus_batch_test/expected_og1.hex", expected_mem[1]);
        $readmemh("../../../../../scripts/stimulus_batch_test/expected_og2.hex", expected_mem[2]);
        $readmemh("../../../../../scripts/stimulus_batch_test/expected_og3.hex", expected_mem[3]);
        $readmemh("../../../../../scripts/stimulus_batch_test/expected_og4.hex", expected_mem[4]);
        $readmemh("../../../../../scripts/stimulus_batch_test/expected_og5.hex", expected_mem[5]);
        $readmemh("../../../../../scripts/stimulus_batch_test/expected_og6.hex", expected_mem[6]);
        $readmemh("../../../../../scripts/stimulus_batch_test/expected_og7.hex", expected_mem[7]);

        $readmemh("../../../../../scripts/stimulus_batch_test/biases_og0.hex", bias_og_mem[0]);
        $readmemh("../../../../../scripts/stimulus_batch_test/biases_og1.hex", bias_og_mem[1]);
        $readmemh("../../../../../scripts/stimulus_batch_test/biases_og2.hex", bias_og_mem[2]);
        $readmemh("../../../../../scripts/stimulus_batch_test/biases_og3.hex", bias_og_mem[3]);
        $readmemh("../../../../../scripts/stimulus_batch_test/biases_og4.hex", bias_og_mem[4]);
        $readmemh("../../../../../scripts/stimulus_batch_test/biases_og5.hex", bias_og_mem[5]);
        $readmemh("../../../../../scripts/stimulus_batch_test/biases_og6.hex", bias_og_mem[6]);
        $readmemh("../../../../../scripts/stimulus_batch_test/biases_og7.hex", bias_og_mem[7]);
    end

    // Helpers
    task automatic reset_all();
        rst              = 1;
        go               = 0;
        cfg_ci_groups    = 0;
        cfg_output_group = 0;
        cfg_wt_base_addr = 0;
        cfg_in_channels  = 0;
        cfg_img_width    = 0;
        cfg_use_maxpool  = 0;
        cfg_stride_2     = 0;
        cfg_quant_m      = 0;
        cfg_quant_n      = 0;
        cfg_use_relu     = 0;
        cfg_kernel_1x1   = 0;
        bias_wr_en       = 0;
        bias_wr_data     = 0;
        bias_wr_addr_rst = 0;
        wt_wr_en         = 0;
        wt_wr_data       = 0;
        wt_wr_addr_rst   = 0;
        pixel_in         = 0;
        pixel_in_valid   = 0;
        pixel_in_last    = 0;
        repeat(5) @(posedge clk);
        rst = 0;
        repeat(2) @(posedge clk);
    endtask

    // Load all biases at once (original per-OG approach)
    task automatic load_all_biases();
        @(posedge clk);
        bias_wr_addr_rst <= 1;
        @(posedge clk);
        bias_wr_addr_rst <= 0;
        @(posedge clk);
        for (int i = 0; i < N_BIAS_WORDS; i++) begin
            bias_wr_en   <= 1;
            bias_wr_data <= bias_all_mem[i];
            @(posedge clk);
        end
        bias_wr_en <= 0;
        $display("  Loaded all %0d bias words", N_BIAS_WORDS);
    endtask

    // Load biases for single OG with optional addr reset (batched mode)
    task automatic load_og_biases(input int og, input bit do_addr_reset);
        @(posedge clk);
        if (do_addr_reset) begin
            bias_wr_addr_rst <= 1;
            @(posedge clk);
            bias_wr_addr_rst <= 0;
        end
        @(posedge clk);
        for (int i = 0; i < 2; i++) begin
            bias_wr_en   <= 1;
            bias_wr_data <= bias_og_mem[og][i];
            @(posedge clk);
        end
        bias_wr_en <= 0;
    endtask

    task automatic load_weights(input int og);
        @(posedge clk);
        wt_wr_addr_rst <= 1;
        @(posedge clk);
        wt_wr_addr_rst <= 0;
        for (int i = 0; i < N_WT_WORDS; i++) begin
            @(posedge clk);
            wt_wr_en   <= 1;
            wt_wr_data <= weight_mem[og][i];
        end
        @(posedge clk);
        wt_wr_en <= 0;
    endtask

    task automatic stream_pixels();
        for (int i = 0; i < N_PIXELS; i++) begin
            @(posedge clk);
            pixel_in_valid <= 1;
            pixel_in       <= pixel_mem[i];
            pixel_in_last  <= (i == N_PIXELS - 1);
        end
        @(posedge clk);
        pixel_in_valid <= 0;
        pixel_in_last  <= 0;
    endtask

    task automatic flush_pipeline();
        int flush_beats = 2 * PADDED_W * CI_GROUPS + 4;
        for (int i = 0; i < flush_beats; i++) begin
            @(posedge clk);
            pixel_in_valid <= 1;
            pixel_in       <= '0;
        end
        @(posedge clk);
        pixel_in_valid <= 0;
        rst = 1;
        repeat(5) @(posedge clk);
        rst = 0;
        repeat(2) @(posedge clk);
    endtask

    task automatic pulse_go();
        @(posedge clk);
        go <= 1;
        @(posedge clk);
        go <= 0;
    endtask

    task automatic run_og(input int og, output int mismatch_count);
        int pulse_count = 0;
        mismatch_count = 0;

        // Configure
        cfg_ci_groups    = CI_GROUPS;
        cfg_output_group = og[BIAS_GROUP_BITS-1:0];
        cfg_wt_base_addr = '0;
        cfg_img_width    = 16'(PADDED_W);
        cfg_in_channels  = 16'd32;
        cfg_quant_m      = 32'h000003CA;
        cfg_quant_n      = 5'd16;
        cfg_use_relu     = 1;
        cfg_use_maxpool  = 1;
        cfg_stride_2     = 1;

        load_weights(og);
        pulse_go();

        fork
            stream_pixels();
            begin
                while (!done) begin
                    @(negedge clk);
                    if (data_out_valid) begin
                        if (pulse_count < N_EXPECTED) begin
                            if (data_out !== expected_mem[og][pulse_count]) begin
                                $display("  ERROR OG%0d pulse %0d: got %h, expected %h",
                                    og, pulse_count, data_out, expected_mem[og][pulse_count]);
                                mismatch_count++;
                            end else begin
                                $display("  OK    OG%0d pulse %0d: %h", og, pulse_count, data_out);
                            end
                        end
                        pulse_count++;
                    end
                end
            end
        join

        if (pulse_count !== N_EXPECTED) begin
            $display("  ERROR OG%0d: expected %0d pulses, got %0d", og, N_EXPECTED, pulse_count);
            mismatch_count++;
        end

        total_og_errors[og] = mismatch_count;
        errors += mismatch_count;
    endtask

    // Main test
    initial begin
        $dumpfile("tb_conv_top_e2e_batch.vcd");
        $dumpvars(0, tb_conv_top_e2e_batch);

        for (int i = 0; i < CO_GROUPS; i++)
            total_og_errors[i] = 0;

        $display("\n================================================");
        $display("  E2E Batch Test (Layer 2-like, ci_groups=4)");
        $display("  4x4 image, 32→64 channels, 8 output groups");
        $display("================================================\n");

        // ================================================================
        // TEST 1: Original per-OG approach (all biases loaded upfront)
        // ================================================================
        $display("=== TEST 1: Per-OG Approach (biases pre-loaded) ===\n");

        reset_all();
        cfg_img_width   = 16'(PADDED_W);
        cfg_in_channels = 16'd32;
        flush_pipeline();

        // Load ALL biases once
        load_all_biases();

        for (int og = 0; og < CO_GROUPS; og++) begin
            int mm;
            $display("\n--- OG%0d ---", og);
            run_og(og, mm);
            flush_pipeline();
        end

        $display("\n--- TEST 1 Results ---");
        for (int og = 0; og < CO_GROUPS; og++)
            $display("  OG%0d: %0d errors", og, total_og_errors[og]);

        // ================================================================
        // TEST 2: Batched approach (biases loaded incrementally per OG)
        // ================================================================
        $display("\n\n=== TEST 2: Batched Approach (biases loaded per-OG) ===\n");

        // Reset error counts
        errors = 0;
        for (int i = 0; i < CO_GROUPS; i++)
            total_og_errors[i] = 0;

        reset_all();
        cfg_img_width   = 16'(PADDED_W);
        cfg_in_channels = 16'd32;
        flush_pipeline();

        // Load biases incrementally - this mimics AXI wrapper behavior
        // Key: addr reset only for OG0
        for (int og = 0; og < CO_GROUPS; og++) begin
            load_og_biases(og, og == 0);
        end
        $display("  Loaded biases with accumulating addresses");

        // Now process each OG
        for (int og = 0; og < CO_GROUPS; og++) begin
            int mm;
            $display("\n--- OG%0d ---", og);
            run_og(og, mm);
            flush_pipeline();
        end

        $display("\n--- TEST 2 Results ---");
        for (int og = 0; og < CO_GROUPS; og++)
            $display("  OG%0d: %0d errors", og, total_og_errors[og]);

        // ================================================================
        // Summary
        // ================================================================
        $display("\n================================================");
        if (errors == 0)
            $display("  ALL TESTS PASSED");
        else
            $display("  TESTS FAILED: %0d total errors", errors);
        $display("================================================\n");

        $finish;
    end

endmodule
