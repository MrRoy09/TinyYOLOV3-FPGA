`timescale 1ns / 1ps

// End-to-end test: YOLOv3-tiny layer 1 (16→32, 3x3, BN, leaky ReLU, maxpool stride-2)
// on a 4×4 synthetic image (padded to 6×6).
// Tests multi ci_groups (ci_groups=2).
// Compares RTL output against Python-generated reference (bit-exact).

module tb_conv_top_e2e_l1;

    localparam WT_DEPTH        = 4096;
    localparam WT_ADDR_WIDTH   = $clog2(WT_DEPTH);
    localparam BIAS_DEPTH      = 256;
    localparam BIAS_GROUP_BITS = $clog2(BIAS_DEPTH) - 1;
    localparam WT_LATENCY      = 3;
    localparam CONV_PE_PIPE    = 3;

    localparam PADDED_W        = 6;
    localparam PADDED_H        = 6;
    localparam CI_GROUPS       = 2;
    localparam CO_GROUPS       = 4;
    localparam N_PIXELS        = PADDED_H * PADDED_W * CI_GROUPS;  // 72
    localparam N_WT_WORDS      = CI_GROUPS * 8 * 8;                // 128
    localparam N_EXPECTED      = 4;                                // 2×2 maxpool output
    localparam N_BIAS_WORDS    = 8;                                // 32 biases / 4 per word

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

    // Debug (unused but must be connected)
    logic [31:0]                   dbg_bias_out [0:7];
    logic                          dbg_bias_valid;
    logic [575:0]                  dbg_wt_data_out [0:7];
    logic                          dbg_wt_data_ready;
    logic                          dbg_conv_valid_in;
    logic                          dbg_conv_last_channel;
    logic [63:0]                   dbg_pixel_d2 [0:2][0:2];
    logic [31:0]                   dbg_conv_outs [0:7];
    logic                          dbg_conv_data_valid;
    // Kernel window debug
    logic [63:0]                   dbg_kw_row0;
    logic [63:0]                   dbg_kw_row1;
    logic [63:0]                   dbg_kw_row2;
    logic [31:0]                   dbg_kw_delay_count;
    logic [31:0]                   dbg_kw_total_delay;
    logic                          dbg_kw_priming_done;
    logic [31:0]                   dbg_kw_col_cnt;
    logic                          dbg_kw_col_valid;
    logic [7:0]                    dbg_kw_delay_depth;
    logic [31:0]                   dbg_kw_vectors_per_row;

    // ── DUT ──
    conv_top #(
        .WT_DEPTH   (WT_DEPTH),
        .BIAS_DEPTH (BIAS_DEPTH),
        .WT_LATENCY (WT_LATENCY),
        .CONV_PE_PIPE(CONV_PE_PIPE)
    ) u_dut (.*);

    // ── Clock ──
    initial clk = 0;
    always #5 clk = ~clk;

    // ── Timeout ──
    initial begin
        #10ms;
        $display("[%0t] TIMEOUT", $time);
        $finish;
    end

    int errors = 0;

    // ── Stimulus memories ──
    logic [63:0]  pixel_mem     [0:CO_GROUPS-1][0:N_PIXELS-1];
    logic [71:0]  weight_mem    [0:CO_GROUPS-1][0:N_WT_WORDS-1];
    logic [63:0]  expected_mem  [0:CO_GROUPS-1][0:N_EXPECTED-1];
    logic [127:0] bias_all_mem  [0:N_BIAS_WORDS-1];

    // Quant params (from Python output)
    logic [31:0] quant_m_val [0:CO_GROUPS-1];
    logic [4:0]  quant_n_val [0:CO_GROUPS-1];

    initial begin
        quant_m_val[0] = 32'h000001b1;  // OG0: M=433
        quant_n_val[0] = 5'd16;
        quant_m_val[1] = 32'h0000017f;  // OG1: M=383
        quant_n_val[1] = 5'd16;
        quant_m_val[2] = 32'h00000162;  // OG2: M=354
        quant_n_val[2] = 5'd16;
        quant_m_val[3] = 32'h000001bb;  // OG3: M=443
        quant_n_val[3] = 5'd16;
    end

    initial begin
        $readmemh("../../../../../scripts/stimulus_l1/pixels_og0.hex",   pixel_mem[0]);
        $readmemh("../../../../../scripts/stimulus_l1/pixels_og1.hex",   pixel_mem[1]);
        $readmemh("../../../../../scripts/stimulus_l1/pixels_og2.hex",   pixel_mem[2]);
        $readmemh("../../../../../scripts/stimulus_l1/pixels_og3.hex",   pixel_mem[3]);
        $readmemh("../../../../../scripts/stimulus_l1/weights_og0.hex",  weight_mem[0]);
        $readmemh("../../../../../scripts/stimulus_l1/weights_og1.hex",  weight_mem[1]);
        $readmemh("../../../../../scripts/stimulus_l1/weights_og2.hex",  weight_mem[2]);
        $readmemh("../../../../../scripts/stimulus_l1/weights_og3.hex",  weight_mem[3]);
        $readmemh("../../../../../scripts/stimulus_l1/expected_og0.hex", expected_mem[0]);
        $readmemh("../../../../../scripts/stimulus_l1/expected_og1.hex", expected_mem[1]);
        $readmemh("../../../../../scripts/stimulus_l1/expected_og2.hex", expected_mem[2]);
        $readmemh("../../../../../scripts/stimulus_l1/expected_og3.hex", expected_mem[3]);
        $readmemh("../../../../../scripts/stimulus_l1/biases_all.hex",   bias_all_mem);
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
        cfg_in_channels  = 16'd16;
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

    // ── Debug monitor ──
    int dbg_conv_cnt = 0;
    int dbg_pixel_cnt = 0;
    int dbg_kw_valid_cnt = 0;

    // Monitor kernel window priming
    always @(negedge clk) begin
        if (pixel_in_valid && dbg_pixel_cnt < 40) begin
            if (dbg_pixel_cnt == 0) begin
                $display("  KW CONFIG: delay_depth=%0d vectors_per_row=%0d total_delay=%0d",
                    dbg_kw_delay_depth, dbg_kw_vectors_per_row, dbg_kw_total_delay);
            end
            if (dbg_pixel_cnt < 5 || (dbg_pixel_cnt >= 20 && dbg_pixel_cnt < 35)) begin
                $display("  PIX[%0d]: in=%h row0=%h row1=%h row2=%h dcnt=%0d prime=%b col=%0d colv=%b",
                    dbg_pixel_cnt, pixel_in, dbg_kw_row0, dbg_kw_row1, dbg_kw_row2,
                    dbg_kw_delay_count, dbg_kw_priming_done, dbg_kw_col_cnt, dbg_kw_col_valid);
            end
            dbg_pixel_cnt++;
        end
    end

    // Monitor kw_dout_valid
    always @(negedge clk) begin
        if (u_dut.kw_dout_valid && dbg_kw_valid_cnt < 10) begin
            $display("  KW_VALID[%0d]: window[0]=%h,%h,%h  window[1]=%h,%h,%h  window[2]=%h,%h,%h",
                dbg_kw_valid_cnt,
                u_dut.kw_window[0][0], u_dut.kw_window[0][1], u_dut.kw_window[0][2],
                u_dut.kw_window[1][0], u_dut.kw_window[1][1], u_dut.kw_window[1][2],
                u_dut.kw_window[2][0], u_dut.kw_window[2][1], u_dut.kw_window[2][2]);
            dbg_kw_valid_cnt++;
        end
    end

    always @(negedge clk) begin
        if (dbg_conv_data_valid && dbg_conv_cnt < 4) begin
            $display("  DBG CONV[%0d]: %0d %0d %0d %0d %0d %0d %0d %0d",
                dbg_conv_cnt,
                $signed(dbg_conv_outs[0]), $signed(dbg_conv_outs[1]),
                $signed(dbg_conv_outs[2]), $signed(dbg_conv_outs[3]),
                $signed(dbg_conv_outs[4]), $signed(dbg_conv_outs[5]),
                $signed(dbg_conv_outs[6]), $signed(dbg_conv_outs[7]));
            dbg_conv_cnt++;
        end
        if (dbg_conv_valid_in && dbg_conv_cnt == 0) begin
            $display("  DBG PIXEL_D2 at first conv_valid_in:");
            for (int r = 0; r < 3; r++)
                $display("    row%0d: %h %h %h", r,
                    dbg_pixel_d2[r][0], dbg_pixel_d2[r][1], dbg_pixel_d2[r][2]);
        end
    end

    int dbg_mp_qcnt = 0;
    int dbg_mp_outcnt = 0;
    always @(negedge clk) begin
        if (u_dut.quant_valid && dbg_mp_qcnt < 20) begin
            $display("  DBG MP_IN[%0d] col=%0d row=%0d: %h  h_max_latched=%h",
                dbg_mp_qcnt,
                u_dut.u_maxpool.col_cnt,
                u_dut.u_maxpool.row_cnt,
                u_dut.quant_packed,
                u_dut.u_maxpool.h_max_latched);
            dbg_mp_qcnt++;
        end
        if (u_dut.maxpool_valid_out && dbg_mp_outcnt < 20) begin
            $display("  DBG MP_OUT[%0d]: data=%h  h_for_v=%h  prev_row=%h  lb_en_q=%b row_at=%0d",
                dbg_mp_outcnt,
                u_dut.maxpool_data_out,
                u_dut.u_maxpool.h_max_for_vmax,
                u_dut.u_maxpool.prev_row,
                u_dut.u_maxpool.lb_en_q,
                u_dut.u_maxpool.row_at_lben);
            dbg_mp_outcnt++;
        end
    end

    initial begin
        $dumpfile("tb_conv_top_e2e_l1.vcd");
        $dumpvars(0, tb_conv_top_e2e_l1);

        $display("\n═══════════════════════════════════════");
        $display("  E2E Test: YOLOv3-tiny Layer 1");
        $display("  4x4 image, 16→32 channels, ci_groups=2, maxpool");
        $display("═══════════════════════════════════════");

        reset_all();

        // Set image dimensions for flush
        cfg_img_width   = 16'(PADDED_W);
        cfg_in_channels = 16'd16;
        flush_pipeline();

        // Load all biases (once, for all 4 output groups)
        load_all_biases();

        // Process all 4 output groups
        for (int og = 0; og < CO_GROUPS; og++) begin
            dbg_conv_cnt = 0;
            dbg_mp_qcnt = 0;
            dbg_mp_outcnt = 0;
            dbg_pixel_cnt = 0;
            dbg_kw_valid_cnt = 0;
            run_output_group(og);

            // Flush between output groups
            cfg_img_width   = 16'(PADDED_W);
            cfg_in_channels = 16'd16;
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
