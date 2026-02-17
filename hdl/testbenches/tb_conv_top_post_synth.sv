`timescale 1ns / 1ps

// Post-synthesis functional simulation testbench
// No debug ports - only I/O verification
// Tests YOLOv3-tiny layer 0 (3->16, 3x3, BN, leaky ReLU, maxpool stride-2)

module tb_conv_top_post_synth;

    localparam WT_DEPTH        = 4096;
    localparam WT_ADDR_WIDTH   = $clog2(WT_DEPTH);
    localparam BIAS_DEPTH      = 256;
    localparam BIAS_GROUP_BITS = $clog2(BIAS_DEPTH) - 1;

    localparam PADDED_W        = 10;
    localparam PADDED_H        = 10;
    localparam CI_GROUPS       = 1;
    localparam CO_GROUPS       = 2;
    localparam N_PIXELS        = PADDED_H * PADDED_W;  // 100
    localparam N_WT_WORDS      = CI_GROUPS * 8 * 8;    // 64
    localparam N_EXPECTED      = 16;                   // 4x4 maxpool output

    // ── DUT signals (I/O only) ──
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

    // ── DUT instantiation (no debug ports) ──
    conv_top u_dut (
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
    logic [63:0]  pixel_mem     [0:1][0:N_PIXELS-1];
    logic [71:0]  weight_mem    [0:1][0:N_WT_WORDS-1];
    logic [63:0]  expected_mem  [0:1][0:N_EXPECTED-1];
    logic [127:0] bias_all_mem  [0:3];

    // Quant params
    logic [31:0] quant_m_val [0:1];
    logic [4:0]  quant_n_val [0:1];

    initial begin
        quant_m_val[0] = 32'h00002AF9;
        quant_n_val[0] = 5'd16;
        quant_m_val[1] = 32'h000020A2;
        quant_n_val[1] = 5'd16;
    end

    initial begin
        $readmemh("/media/ubuntu/T7/projects/arm-bharat/scripts/stimulus/pixels_og0.hex",   pixel_mem[0]);
        $readmemh("/media/ubuntu/T7/projects/arm-bharat/scripts/stimulus/pixels_og1.hex",   pixel_mem[1]);
        $readmemh("/media/ubuntu/T7/projects/arm-bharat/scripts/stimulus/weights_og0.hex",  weight_mem[0]);
        $readmemh("/media/ubuntu/T7/projects/arm-bharat/scripts/stimulus/weights_og1.hex",  weight_mem[1]);
        $readmemh("/media/ubuntu/T7/projects/arm-bharat/scripts/stimulus/expected_og0.hex", expected_mem[0]);
        $readmemh("/media/ubuntu/T7/projects/arm-bharat/scripts/stimulus/expected_og1.hex", expected_mem[1]);
        $readmemh("/media/ubuntu/T7/projects/arm-bharat/scripts/stimulus/biases_all.hex",   bias_all_mem);
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
        cfg_kernel_1x1   = 0;  // 3x3 mode
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
        for (int i = 0; i < 4; i++) begin
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
        cfg_in_channels  = 16'd8;
        cfg_quant_m      = quant_m_val[og];
        cfg_quant_n      = quant_n_val[og];
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
        $display("\n═══════════════════════════════════════");
        $display("  Post-Synth E2E Test: YOLOv3-tiny Layer 0");
        $display("  8x8 image, 3->16 channels, maxpool");
        $display("═══════════════════════════════════════");

        reset_all();

        // Set image dimensions for flush
        cfg_img_width   = 16'(PADDED_W);
        cfg_in_channels = 16'd8;
        flush_pipeline();

        // Load all biases
        load_all_biases();

        // Process output group 0
        run_output_group(0);

        // Flush between output groups
        cfg_img_width   = 16'(PADDED_W);
        cfg_in_channels = 16'd8;
        flush_pipeline();

        // Process output group 1
        run_output_group(1);

        #200;
        $display("\n═══════════════════════════════════════");
        if (errors == 0) $display("  POST-SYNTH E2E TEST PASSED");
        else $display("  POST-SYNTH E2E TEST FAILED with %0d errors", errors);
        $display("═══════════════════════════════════════\n");
        $finish;
    end

endmodule
