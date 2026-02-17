`timescale 1ns / 1ps

// Test conv_1x1 mode: 4x4 image, 16->8 channels, no maxpool
// Verifies the 1x1 convolution path bypasses kernel_window correctly

module tb_conv_top_1x1;

    localparam WT_DEPTH        = 4096;
    localparam WT_ADDR_WIDTH   = $clog2(WT_DEPTH);
    localparam BIAS_DEPTH      = 256;
    localparam BIAS_GROUP_BITS = $clog2(BIAS_DEPTH) - 1;

    localparam IMG_W           = 4;
    localparam IMG_H           = 4;
    localparam CI_GROUPS       = 2;      // 16 input channels / 8
    localparam N_PIXELS        = IMG_H * IMG_W * CI_GROUPS;  // 32
    localparam N_WT_WORDS      = CI_GROUPS * 8 * 8;          // 128
    localparam N_EXPECTED      = IMG_H * IMG_W;              // 16 (no spatial reduction for 1x1)

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
        .BIAS_DEPTH (BIAS_DEPTH)
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
        #100us;
        $display("[%0t] TIMEOUT", $time);
        $display("DEBUG: pixel_valid_cnt=%0d, conv_valid_cnt=%0d, last_channel_cnt=%0d",
                 pixel_valid_cnt, conv_valid_cnt, last_channel_cnt);
        $display("DEBUG: busy=%b, done=%b", busy, done);
        $finish;
    end

    int errors = 0;

    // ── Stimulus memories ──
    logic [63:0]  pixel_mem    [0:N_PIXELS-1];
    logic [71:0]  weight_mem   [0:N_WT_WORDS-1];
    logic [63:0]  expected_mem [0:N_EXPECTED-1];
    logic [127:0] bias_mem     [0:1];

    initial begin
        $readmemh("/media/ubuntu/T7/projects/arm-bharat/scripts/stimulus_1x1/pixels.hex",   pixel_mem);
        $readmemh("/media/ubuntu/T7/projects/arm-bharat/scripts/stimulus_1x1/weights.hex",  weight_mem);
        $readmemh("/media/ubuntu/T7/projects/arm-bharat/scripts/stimulus_1x1/expected.hex", expected_mem);
        $readmemh("/media/ubuntu/T7/projects/arm-bharat/scripts/stimulus_1x1/biases.hex",   bias_mem);
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

    task automatic load_biases();
        @(posedge clk);
        bias_wr_addr_rst <= 1;
        @(posedge clk);
        bias_wr_addr_rst <= 0;
        @(posedge clk);
        for (int i = 0; i < 2; i++) begin
            bias_wr_en   <= 1;
            bias_wr_data <= bias_mem[i];
            @(posedge clk);
        end
        bias_wr_en <= 0;
    endtask

    task automatic load_weights();
        @(posedge clk);
        wt_wr_addr_rst <= 1;
        @(posedge clk);
        wt_wr_addr_rst <= 0;
        for (int i = 0; i < N_WT_WORDS; i++) begin
            @(posedge clk);
            wt_wr_en   <= 1;
            wt_wr_data <= weight_mem[i];
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

    task automatic pulse_go();
        @(posedge clk);
        go <= 1;
        @(posedge clk);
        go <= 0;
        // Wait for controller to enter CONV state (IDLE->LOAD_BIAS->WAIT_BIAS->CONV)
        // This takes about 3 cycles after go
        while (!u_dut.u_conv_controller.bias_valid) @(posedge clk);
        @(posedge clk); // One more cycle for state to become CONV
    endtask

    // ── Debug monitoring ──
    int pixel_valid_cnt = 0;
    int conv_valid_cnt = 0;
    int last_channel_cnt = 0;

    always @(posedge clk) begin
        if (pixel_in_valid) pixel_valid_cnt++;
        if (u_dut.conv_valid_in) conv_valid_cnt++;
        if (u_dut.conv_valid_in && u_dut.conv_last_channel) last_channel_cnt++;
    end

    // ── Main test ──

    initial begin
        $dumpfile("tb_conv_top_1x1.vcd");
        $dumpvars(0, tb_conv_top_1x1);

        $display("\n═══════════════════════════════════════");
        $display("  Conv 1x1 Test: 4x4 image, 16->8 channels");
        $display("  cfg_kernel_1x1 = 1, no maxpool");
        $display("═══════════════════════════════════════");

        reset_all();

        // Load biases and weights
        load_biases();
        load_weights();

        // Configure for 1x1 conv
        cfg_ci_groups    = CI_GROUPS;
        cfg_output_group = 0;
        cfg_wt_base_addr = '0;
        cfg_img_width    = 16'(IMG_W);
        cfg_in_channels  = 16'd16;
        cfg_quant_m      = 32'h00004000;  // 16384
        cfg_quant_n      = 5'd8;
        cfg_use_relu     = 1;
        cfg_use_maxpool  = 0;  // No maxpool for this test
        cfg_stride_2     = 0;
        cfg_kernel_1x1   = 1;  // Enable 1x1 mode

        pulse_go();

        // Stream pixels and check outputs
        fork
            stream_pixels();
            begin
                int pulse_count = 0;
                int mismatch_count = 0;

                // Wait for outputs with timeout, checking even after done
                while (pulse_count < N_EXPECTED) begin
                    @(negedge clk);
                    if (data_out_valid) begin
                        if (data_out !== expected_mem[pulse_count]) begin
                            $display("  [%0t] ERROR pulse %0d: got %h, expected %h",
                                $time, pulse_count, data_out, expected_mem[pulse_count]);
                            mismatch_count++;
                            errors++;
                        end else begin
                            $display("  [%0t] OK    pulse %0d: %h", $time, pulse_count, data_out);
                        end
                        pulse_count++;
                    end
                    // Timeout if done and no more outputs for 100 cycles
                    if (done) begin
                        static int done_wait = 0;
                        done_wait++;
                        if (done_wait > 100) begin
                            $display("  [%0t] Timeout waiting for outputs after done", $time);
                            break;
                        end
                    end
                end

                if (pulse_count !== N_EXPECTED) begin
                    $display("  ERROR: expected %0d pulses, got %0d", N_EXPECTED, pulse_count);
                    errors++;
                end else begin
                    $display("  %0d/%0d pulses correct (%0d mismatches)",
                        pulse_count - mismatch_count, pulse_count, mismatch_count);
                end
            end
        join

        #200;
        $display("\nDEBUG: pixel_valid_cnt=%0d, conv_valid_cnt=%0d, last_channel_cnt=%0d",
                 pixel_valid_cnt, conv_valid_cnt, last_channel_cnt);
        $display("DEBUG: busy=%b, done=%b", busy, done);
        $display("\n═══════════════════════════════════════");
        if (errors == 0) $display("  CONV 1x1 TEST PASSED");
        else $display("  CONV 1x1 TEST FAILED with %0d errors", errors);
        $display("═══════════════════════════════════════\n");
        $finish;
    end

endmodule
