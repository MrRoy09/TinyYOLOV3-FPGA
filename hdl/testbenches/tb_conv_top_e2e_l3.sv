`timescale 1ns / 1ps

// End-to-end test: Layer 3 (64→128, 3x3, BN, leaky ReLU, maxpool stride-2)
// on a 4×4 synthetic image (padded to 6×6).
// Tests ci_groups=8 to debug hardware issues at higher channel counts.
// Compares RTL output against Python-generated reference (bit-exact).

module tb_conv_top_e2e_l3;

    localparam WT_DEPTH        = 4096;
    localparam WT_ADDR_WIDTH   = $clog2(WT_DEPTH);
    localparam BIAS_DEPTH      = 256;
    localparam BIAS_GROUP_BITS = $clog2(BIAS_DEPTH) - 1;
    localparam WT_LATENCY      = 3;
    localparam CONV_PE_PIPE    = 3;

    localparam PADDED_W        = 6;
    localparam PADDED_H        = 6;
    localparam CI_GROUPS       = 8;
    localparam CO_GROUPS       = 16;
    localparam N_PIXELS        = PADDED_H * PADDED_W * CI_GROUPS;  // 288
    localparam N_WT_WORDS      = CI_GROUPS * 8 * 8;                // 512
    localparam N_EXPECTED      = 4;                                // 2×2 maxpool output
    localparam N_BIAS_WORDS    = 32;                               // 128 biases / 4 per word

    // ── DUT signals ──
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

    // ── DUT ──
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

    // ── Clock ──
    initial clk = 0;
    always #5 clk = ~clk;

    // ── Timeout ──
    initial begin
        #50ms;
        $display("[%0t] TIMEOUT", $time);
        $finish;
    end

    int errors = 0;

    // ── Stimulus memories ──
    logic [63:0]  pixel_mem     [0:CO_GROUPS-1][0:N_PIXELS-1];
    logic [71:0]  weight_mem    [0:CO_GROUPS-1][0:N_WT_WORDS-1];
    logic [63:0]  expected_mem  [0:CO_GROUPS-1][0:N_EXPECTED-1];
    logic [127:0] bias_all_mem  [0:N_BIAS_WORDS-1];

    // Quant params (same M for all OGs - from hardware_sim.py)
    logic [31:0] quant_m_val;
    logic [4:0]  quant_n_val;

    initial begin
        quant_m_val = 32'h0000022b;  // M=555
        quant_n_val = 5'd16;
    end

    initial begin
        $readmemh("../../../../../scripts/stimulus_l3/pixels_og0.hex",   pixel_mem[0]);
        $readmemh("../../../../../scripts/stimulus_l3/pixels_og1.hex",   pixel_mem[1]);
        $readmemh("../../../../../scripts/stimulus_l3/pixels_og2.hex",   pixel_mem[2]);
        $readmemh("../../../../../scripts/stimulus_l3/pixels_og3.hex",   pixel_mem[3]);
        $readmemh("../../../../../scripts/stimulus_l3/pixels_og4.hex",   pixel_mem[4]);
        $readmemh("../../../../../scripts/stimulus_l3/pixels_og5.hex",   pixel_mem[5]);
        $readmemh("../../../../../scripts/stimulus_l3/pixels_og6.hex",   pixel_mem[6]);
        $readmemh("../../../../../scripts/stimulus_l3/pixels_og7.hex",   pixel_mem[7]);
        $readmemh("../../../../../scripts/stimulus_l3/pixels_og8.hex",   pixel_mem[8]);
        $readmemh("../../../../../scripts/stimulus_l3/pixels_og9.hex",   pixel_mem[9]);
        $readmemh("../../../../../scripts/stimulus_l3/pixels_og10.hex",  pixel_mem[10]);
        $readmemh("../../../../../scripts/stimulus_l3/pixels_og11.hex",  pixel_mem[11]);
        $readmemh("../../../../../scripts/stimulus_l3/pixels_og12.hex",  pixel_mem[12]);
        $readmemh("../../../../../scripts/stimulus_l3/pixels_og13.hex",  pixel_mem[13]);
        $readmemh("../../../../../scripts/stimulus_l3/pixels_og14.hex",  pixel_mem[14]);
        $readmemh("../../../../../scripts/stimulus_l3/pixels_og15.hex",  pixel_mem[15]);

        $readmemh("../../../../../scripts/stimulus_l3/weights_og0.hex",  weight_mem[0]);
        $readmemh("../../../../../scripts/stimulus_l3/weights_og1.hex",  weight_mem[1]);
        $readmemh("../../../../../scripts/stimulus_l3/weights_og2.hex",  weight_mem[2]);
        $readmemh("../../../../../scripts/stimulus_l3/weights_og3.hex",  weight_mem[3]);
        $readmemh("../../../../../scripts/stimulus_l3/weights_og4.hex",  weight_mem[4]);
        $readmemh("../../../../../scripts/stimulus_l3/weights_og5.hex",  weight_mem[5]);
        $readmemh("../../../../../scripts/stimulus_l3/weights_og6.hex",  weight_mem[6]);
        $readmemh("../../../../../scripts/stimulus_l3/weights_og7.hex",  weight_mem[7]);
        $readmemh("../../../../../scripts/stimulus_l3/weights_og8.hex",  weight_mem[8]);
        $readmemh("../../../../../scripts/stimulus_l3/weights_og9.hex",  weight_mem[9]);
        $readmemh("../../../../../scripts/stimulus_l3/weights_og10.hex", weight_mem[10]);
        $readmemh("../../../../../scripts/stimulus_l3/weights_og11.hex", weight_mem[11]);
        $readmemh("../../../../../scripts/stimulus_l3/weights_og12.hex", weight_mem[12]);
        $readmemh("../../../../../scripts/stimulus_l3/weights_og13.hex", weight_mem[13]);
        $readmemh("../../../../../scripts/stimulus_l3/weights_og14.hex", weight_mem[14]);
        $readmemh("../../../../../scripts/stimulus_l3/weights_og15.hex", weight_mem[15]);

        $readmemh("../../../../../scripts/stimulus_l3/expected_og0.hex", expected_mem[0]);
        $readmemh("../../../../../scripts/stimulus_l3/expected_og1.hex", expected_mem[1]);
        $readmemh("../../../../../scripts/stimulus_l3/expected_og2.hex", expected_mem[2]);
        $readmemh("../../../../../scripts/stimulus_l3/expected_og3.hex", expected_mem[3]);
        $readmemh("../../../../../scripts/stimulus_l3/expected_og4.hex", expected_mem[4]);
        $readmemh("../../../../../scripts/stimulus_l3/expected_og5.hex", expected_mem[5]);
        $readmemh("../../../../../scripts/stimulus_l3/expected_og6.hex", expected_mem[6]);
        $readmemh("../../../../../scripts/stimulus_l3/expected_og7.hex", expected_mem[7]);
        $readmemh("../../../../../scripts/stimulus_l3/expected_og8.hex", expected_mem[8]);
        $readmemh("../../../../../scripts/stimulus_l3/expected_og9.hex", expected_mem[9]);
        $readmemh("../../../../../scripts/stimulus_l3/expected_og10.hex", expected_mem[10]);
        $readmemh("../../../../../scripts/stimulus_l3/expected_og11.hex", expected_mem[11]);
        $readmemh("../../../../../scripts/stimulus_l3/expected_og12.hex", expected_mem[12]);
        $readmemh("../../../../../scripts/stimulus_l3/expected_og13.hex", expected_mem[13]);
        $readmemh("../../../../../scripts/stimulus_l3/expected_og14.hex", expected_mem[14]);
        $readmemh("../../../../../scripts/stimulus_l3/expected_og15.hex", expected_mem[15]);

        $readmemh("../../../../../scripts/stimulus_l3/biases_all.hex",   bias_all_mem);
    end

    // ── Helpers ──

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

    task automatic stream_pixels(input int og);
        for (int i = 0; i < N_PIXELS; i++) begin
            @(posedge clk);
            pixel_in_valid <= 1;
            pixel_in       <= pixel_mem[og][i];
            pixel_in_last  <= (i == N_PIXELS - 1);
        end
        @(posedge clk);
        pixel_in_valid <= 0;
        pixel_in_last  <= 0;
    endtask

    task automatic flush_pipeline();
        int flush_beats = 2 * cfg_img_width * (cfg_in_channels >> 3) + 4;
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

    // ── Main test ──

    task automatic run_output_group(input int og);
        int pulse_count = 0;
        int mismatch_count = 0;

        $display("\n--- Output Group %0d ---", og);

        // Configure
        cfg_ci_groups    = CI_GROUPS;
        cfg_output_group = og[BIAS_GROUP_BITS-1:0];
        cfg_wt_base_addr = '0;
        cfg_img_width    = 16'(PADDED_W);
        cfg_in_channels  = 16'd64;
        cfg_quant_m      = quant_m_val;
        cfg_quant_n      = quant_n_val;
        cfg_use_relu     = 1;
        cfg_use_maxpool  = 1;
        cfg_stride_2     = 1;

        // Load weights for this og
        load_weights(og);

        pulse_go();

        fork
            stream_pixels(og);
            begin
                while (!done) begin
                    @(negedge clk);
                    if (data_out_valid) begin
                        if (pulse_count < N_EXPECTED) begin
                            if (data_out !== expected_mem[og][pulse_count]) begin
                                $display("  ERROR OG%0d pulse %0d: got %h, expected %h",
                                    og, pulse_count, data_out, expected_mem[og][pulse_count]);
                                mismatch_count++;
                                errors++;
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
            errors++;
        end else begin
            $display("  OG%0d: %0d/%0d pulses correct (%0d mismatches)",
                og, pulse_count - mismatch_count, pulse_count, mismatch_count);
        end
    endtask

    initial begin
        $dumpfile("tb_conv_top_e2e_l3.vcd");
        $dumpvars(0, tb_conv_top_e2e_l3);

        $display("\n═══════════════════════════════════════");
        $display("  E2E Test: Layer 3 (ci_groups=8)");
        $display("  4x4 image, 64→128 channels, maxpool");
        $display("═══════════════════════════════════════");

        reset_all();

        // Set image dimensions for flush
        cfg_img_width   = 16'(PADDED_W);
        cfg_in_channels = 16'd64;
        flush_pipeline();

        // Load all biases (once, for all 16 output groups)
        load_all_biases();

        // Process all 16 output groups
        for (int og = 0; og < CO_GROUPS; og++) begin
            run_output_group(og);

            // Flush between output groups
            cfg_img_width   = 16'(PADDED_W);
            cfg_in_channels = 16'd64;
            flush_pipeline();
        end

        #200;
        $display("\n═══════════════════════════════════════");
        if (errors == 0) $display("  E2E TEST PASSED");
        else $display("  E2E TEST FAILED with %0d errors", errors);
        $display("═══════════════════════════════════════\n");
        $finish;
    end

endmodule
