`timescale 1ns / 1ps

// End-to-end test: YOLOv3-tiny layer 0 (3→16, 3x3, BN, leaky ReLU, maxpool stride-2)
// on an 8×8 synthetic image (padded to 10×10).
// Compares RTL output against Python-generated reference (bit-exact).

module tb_conv_top_e2e;

    localparam WT_DEPTH        = 4096;
    localparam WT_ADDR_WIDTH   = $clog2(WT_DEPTH);
    localparam BIAS_DEPTH      = 256;
    localparam BIAS_GROUP_BITS = $clog2(BIAS_DEPTH) - 1;
    localparam WT_LATENCY      = 3;
    localparam CONV_PE_PIPE    = 3;

    localparam PADDED_W        = 10;
    localparam PADDED_H        = 10;
    localparam CI_GROUPS       = 1;
    localparam CO_GROUPS       = 2;
    localparam N_PIXELS        = PADDED_H * PADDED_W;  // 100
    localparam N_WT_WORDS      = CI_GROUPS * 8 * 8;    // 64
    localparam N_EXPECTED      = 16;                    // 4×4 maxpool output

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

    // Debug signals - use `ifndef POST_SYNTH for RTL sim, leave unconnected for post-synth
`ifndef POST_SYNTH
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
    // Output streaming debug
    logic [63:0]                   dbg_data_out;
    logic                          dbg_data_out_valid;
    logic [31:0]                   dbg_output_count;
    logic [63:0]                   dbg_quant_packed;
    logic                          dbg_quant_valid;
    logic [63:0]                   dbg_maxpool_out;
    logic                          dbg_maxpool_valid;
`endif

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
`ifndef POST_SYNTH
        ,
        .dbg_bias_out(dbg_bias_out),
        .dbg_bias_valid(dbg_bias_valid),
        .dbg_wt_data_out(dbg_wt_data_out),
        .dbg_wt_data_ready(dbg_wt_data_ready),
        .dbg_conv_valid_in(dbg_conv_valid_in),
        .dbg_conv_last_channel(dbg_conv_last_channel),
        .dbg_pixel_d2(dbg_pixel_d2),
        .dbg_conv_outs(dbg_conv_outs),
        .dbg_conv_data_valid(dbg_conv_data_valid),
        .dbg_kw_row0(dbg_kw_row0),
        .dbg_kw_row1(dbg_kw_row1),
        .dbg_kw_row2(dbg_kw_row2),
        .dbg_kw_delay_count(dbg_kw_delay_count),
        .dbg_kw_total_delay(dbg_kw_total_delay),
        .dbg_kw_priming_done(dbg_kw_priming_done),
        .dbg_kw_col_cnt(dbg_kw_col_cnt),
        .dbg_kw_col_valid(dbg_kw_col_valid),
        .dbg_kw_delay_depth(dbg_kw_delay_depth),
        .dbg_kw_vectors_per_row(dbg_kw_vectors_per_row),
        .dbg_data_out(dbg_data_out),
        .dbg_data_out_valid(dbg_data_out_valid),
        .dbg_output_count(dbg_output_count),
        .dbg_quant_packed(dbg_quant_packed),
        .dbg_quant_valid(dbg_quant_valid),
        .dbg_maxpool_out(dbg_maxpool_out),
        .dbg_maxpool_valid(dbg_maxpool_valid)
`endif
    );

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
    logic [63:0]  pixel_mem     [0:1][0:N_PIXELS-1];
    logic [71:0]  weight_mem    [0:1][0:N_WT_WORDS-1];
    logic [31:0]  bias_mem      [0:1][0:7];
    logic [63:0]  expected_mem  [0:1][0:N_EXPECTED-1];
    logic [127:0] bias_all_mem  [0:3];  // 4 × 128-bit words for 16 biases

    // Quant params (from quant_params.txt — hardcoded from Python output)
    logic [31:0] quant_m_val [0:1];
    logic [4:0]  quant_n_val [0:1];

    initial begin
        // OG0: M=11001 (0x00002AF9), n=16
        // OG1: M=8354  (0x000020A2), n=16
        quant_m_val[0] = 32'h00002AF9;
        quant_n_val[0] = 5'd16;
        quant_m_val[1] = 32'h000020A2;
        quant_n_val[1] = 5'd16;
    end

    initial begin
        // Paths relative to Vivado xsim working directory
        $readmemh("../../../../../scripts/stimulus/pixels_og0.hex",   pixel_mem[0]);
        $readmemh("../../../../../scripts/stimulus/pixels_og1.hex",   pixel_mem[1]);
        $readmemh("../../../../../scripts/stimulus/weights_og0.hex",  weight_mem[0]);
        $readmemh("../../../../../scripts/stimulus/weights_og1.hex",  weight_mem[1]);
        $readmemh("../../../../../scripts/stimulus/biases_og0.hex",   bias_mem[0]);
        $readmemh("../../../../../scripts/stimulus/biases_og1.hex",   bias_mem[1]);
        $readmemh("../../../../../scripts/stimulus/expected_og0.hex", expected_mem[0]);
        $readmemh("../../../../../scripts/stimulus/expected_og1.hex", expected_mem[1]);
        $readmemh("../../../../../scripts/stimulus/biases_all.hex",   bias_all_mem);
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

// ════════════════════════════════════════════════════════════════
// Debug monitors - only for RTL simulation (not post-synthesis)
// ════════════════════════════════════════════════════════════════
`ifndef POST_SYNTH
    // ── Capture pixel_d2 at posedge when conv_valid_in fires ──
    logic [63:0] first_pixel_d2 [0:2][0:2];
    logic [63:0] row1_pixel_d2 [0:2][0:2];  // For position [1,0]
    int capture_conv_cnt = 0;
    always @(posedge clk) begin
        if (rst) begin
            capture_conv_cnt <= 0;
        end else if (dbg_conv_valid_in) begin
            if (capture_conv_cnt == 0) begin
                for (int r = 0; r < 3; r++)
                    for (int c = 0; c < 3; c++)
                        first_pixel_d2[r][c] <= dbg_pixel_d2[r][c];
            end
            if (capture_conv_cnt == 8) begin  // Position [1,0]
                for (int r = 0; r < 3; r++)
                    for (int c = 0; c < 3; c++)
                        row1_pixel_d2[r][c] <= dbg_pixel_d2[r][c];
                $display("  >>> CAPTURED PIXEL_D2 for conv[1,0] at posedge:");
                for (int r = 0; r < 3; r++)
                    $display("      row%0d: %h %h %h", r,
                        dbg_pixel_d2[r][0], dbg_pixel_d2[r][1], dbg_pixel_d2[r][2]);
            end
            capture_conv_cnt <= capture_conv_cnt + 1;
        end
    end

    // ── Debug monitor: dump conv outputs and pixel_d2 ──
    int dbg_conv_cnt = 0;
    int dbg_conv_out_cnt = 0;  // counter for conv outputs (row-major position)
    always @(negedge clk) begin
        if (dbg_conv_data_valid) begin
            int out_row, out_col;
            out_row = dbg_conv_out_cnt / 8;
            out_col = dbg_conv_out_cnt % 8;

            // Print first few and row 1 outputs
            if (dbg_conv_out_cnt < 4 || (out_row == 1 && out_col < 4)) begin
                $display("  DBG CONV[r=%0d,c=%0d]: %0d %0d %0d %0d %0d %0d %0d %0d",
                    out_row, out_col,
                    $signed(dbg_conv_outs[0]), $signed(dbg_conv_outs[1]),
                    $signed(dbg_conv_outs[2]), $signed(dbg_conv_outs[3]),
                    $signed(dbg_conv_outs[4]), $signed(dbg_conv_outs[5]),
                    $signed(dbg_conv_outs[6]), $signed(dbg_conv_outs[7]));
            end
            dbg_conv_out_cnt++;
        end

        // Dump pixel_d2 at specific conv_valid_in cycles
        if (dbg_conv_valid_in) begin
            // Print window for first output and first output of row 1
            if (dbg_conv_cnt == 0 || dbg_conv_cnt == 8) begin
                $display("  DBG PIXEL_D2 at conv_valid_in[%0d]:", dbg_conv_cnt);
                for (int r = 0; r < 3; r++)
                    $display("    row%0d: %h %h %h", r,
                        dbg_pixel_d2[r][0], dbg_pixel_d2[r][1], dbg_pixel_d2[r][2]);
                if (dbg_conv_cnt == 0) begin
                    // Dump first weight vector (filter 0) - 576 bits = 9 spatial × 8 channels
                    $display("  DBG WT_DATA_OUT[0] at first conv_valid_in:");
                    for (int pos = 0; pos < 9; pos++) begin
                        $display("    pos%0d: ch0=%h ch1=%h ch2=%h ch3=%h ch4=%h ch5=%h ch6=%h ch7=%h",
                            pos,
                            dbg_wt_data_out[0][(pos*64 + 0*8) +: 8],
                            dbg_wt_data_out[0][(pos*64 + 1*8) +: 8],
                            dbg_wt_data_out[0][(pos*64 + 2*8) +: 8],
                            dbg_wt_data_out[0][(pos*64 + 3*8) +: 8],
                            dbg_wt_data_out[0][(pos*64 + 4*8) +: 8],
                            dbg_wt_data_out[0][(pos*64 + 5*8) +: 8],
                            dbg_wt_data_out[0][(pos*64 + 6*8) +: 8],
                            dbg_wt_data_out[0][(pos*64 + 7*8) +: 8]);
                    end
                    $display("  DBG BIAS_OUT at first conv_valid_in: %0d %0d %0d %0d %0d %0d %0d %0d",
                        $signed(dbg_bias_out[0]), $signed(dbg_bias_out[1]),
                        $signed(dbg_bias_out[2]), $signed(dbg_bias_out[3]),
                        $signed(dbg_bias_out[4]), $signed(dbg_bias_out[5]),
                        $signed(dbg_bias_out[6]), $signed(dbg_bias_out[7]));
                end
            end
            dbg_conv_cnt++;
        end
    end

    // ── Quantizer debug: print each quantizer's input on first conv_data_valid ──
    int dbg_quant_in_cnt = 0;
    always @(negedge clk) begin
        if (dbg_conv_data_valid && dbg_quant_in_cnt < 4) begin
            $display("  DBG QUANT_IN[%0d]: ch0=%0d ch1=%0d ch2=%0d ch3=%0d ch4=%0d ch5=%0d ch6=%0d ch7=%0d",
                dbg_quant_in_cnt,
                $signed(u_dut.gen_quant[0].u_quant.data_in),
                $signed(u_dut.gen_quant[1].u_quant.data_in),
                $signed(u_dut.gen_quant[2].u_quant.data_in),
                $signed(u_dut.gen_quant[3].u_quant.data_in),
                $signed(u_dut.gen_quant[4].u_quant.data_in),
                $signed(u_dut.gen_quant[5].u_quant.data_in),
                $signed(u_dut.gen_quant[6].u_quant.data_in),
                $signed(u_dut.gen_quant[7].u_quant.data_in));
            dbg_quant_in_cnt++;
        end
    end

    // ── Quantizer debug: print mult_result and valid_pipe on first quant_valid ──
    int dbg_quant_out_cnt = 0;
    always @(negedge clk) begin
        if (u_dut.quant_valid && dbg_quant_out_cnt < 4) begin
            $display("  DBG QUANT_OUT[%0d]: ch0=%0d ch1=%0d ch2=%0d ch3=%0d ch4=%0d ch5=%0d ch6=%0d ch7=%0d",
                dbg_quant_out_cnt,
                $signed(u_dut.gen_quant[0].u_quant.data_out),
                $signed(u_dut.gen_quant[1].u_quant.data_out),
                $signed(u_dut.gen_quant[2].u_quant.data_out),
                $signed(u_dut.gen_quant[3].u_quant.data_out),
                $signed(u_dut.gen_quant[4].u_quant.data_out),
                $signed(u_dut.gen_quant[5].u_quant.data_out),
                $signed(u_dut.gen_quant[6].u_quant.data_out),
                $signed(u_dut.gen_quant[7].u_quant.data_out));
            dbg_quant_out_cnt++;
        end
    end

    // ── Maxpool debug: dump quant input and maxpool internal state ──
    int dbg_mp_qcnt = 0;
    int dbg_mp_outcnt = 0;
    always @(negedge clk) begin
        // Dump first 20 quant_valid pulses (maxpool input)
        if (u_dut.quant_valid && dbg_mp_qcnt < 20) begin
            $display("  DBG MP_IN[%0d] col=%0d row=%0d: %h  h_max_latched=%h",
                dbg_mp_qcnt,
                u_dut.u_maxpool.col_cnt,
                u_dut.u_maxpool.row_cnt,
                u_dut.quant_packed,
                u_dut.u_maxpool.h_max_latched);
            dbg_mp_qcnt++;
        end
        // Dump maxpool outputs with internal state
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
`endif // POST_SYNTH

    initial begin
        $dumpfile("tb_conv_top_e2e.vcd");
        $dumpvars(0, tb_conv_top_e2e);

        $display("\n═══════════════════════════════════════");
        $display("  E2E Test: YOLOv3-tiny Layer 0");
        $display("  8x8 image, 3→16 channels, maxpool");
        $display("═══════════════════════════════════════");

        reset_all();

        // Set image dimensions for flush
        cfg_img_width   = 16'(PADDED_W);
        cfg_in_channels = 16'd8;
        flush_pipeline();

        // Load all biases (once, for both output groups)
        load_all_biases();

        // Process output group 0
`ifndef POST_SYNTH
        dbg_conv_cnt = 0;
        dbg_conv_out_cnt = 0;
        capture_conv_cnt = 0;
        dbg_mp_qcnt = 0;
        dbg_mp_outcnt = 0;
        dbg_quant_in_cnt = 0;
        dbg_quant_out_cnt = 0;
`endif
        run_output_group(0);

        // Flush between output groups (reset kernel window / delay line state)
        cfg_img_width   = 16'(PADDED_W);
        cfg_in_channels = 16'd8;
        flush_pipeline();

        // Process output group 1
`ifndef POST_SYNTH
        dbg_conv_cnt = 0;
        dbg_conv_out_cnt = 0;
        capture_conv_cnt = 0;
        dbg_mp_qcnt = 0;
        dbg_mp_outcnt = 0;
        dbg_quant_in_cnt = 0;
        dbg_quant_out_cnt = 0;
`endif
        run_output_group(1);

        #200;
        $display("\n═══════════════════════════════════════");
        if (errors == 0) $display("  E2E TEST PASSED");
        else $display("  E2E TEST FAILED with %0d errors", errors);
        $display("═══════════════════════════════════════\n");
        $finish;
    end

endmodule
