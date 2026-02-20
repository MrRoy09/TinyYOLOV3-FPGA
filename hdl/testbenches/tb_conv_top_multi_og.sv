`timescale 1ns / 1ps

// Multi-OG Sequential Test for conv_top
// This simulates exactly what axi_conv_wrapper does:
// 1. For each OG: reset -> load weights -> load biases -> stream pixels -> wait done
// 2. Biases accumulate at sequential addresses (no reset between OGs)
// 3. Uses real Layer 2 configuration (32->64 channels, 4 OGs for 52x52->26x26)

module tb_conv_top_multi_og;

    localparam WT_DEPTH        = 4096;
    localparam WT_ADDR_WIDTH   = $clog2(WT_DEPTH);
    localparam BIAS_DEPTH      = 256;
    localparam BIAS_GROUP_BITS = $clog2(BIAS_DEPTH) - 1;
    localparam WT_LATENCY      = 3;
    localparam CONV_PE_PIPE    = 4;

    // Layer 2 config (simplified: 8x8 spatial instead of 52x52 for faster sim)
    localparam IMG_H      = 8;
    localparam IMG_W      = 8;
    localparam PADDED_H   = IMG_H + 2;  // 10
    localparam PADDED_W   = IMG_W + 2;  // 10
    localparam CIN        = 32;
    localparam COUT       = 64;
    localparam CI_GROUPS  = CIN / 8;    // 4
    localparam CO_GROUPS  = COUT / 8;   // 8
    localparam OUT_H      = IMG_H / 2;  // 4 (after stride-2 maxpool)
    localparam OUT_W      = IMG_W / 2;  // 4

    localparam N_PIXELS   = PADDED_H * PADDED_W * CI_GROUPS;  // 400
    localparam N_WT_WORDS = CI_GROUPS * 8 * 8;                // 256
    localparam N_EXPECTED = OUT_H * OUT_W;                    // 16
    localparam N_BIAS_WORDS = 2;                              // 2 x 128-bit per OG

    // Layer 2 quantization params
    localparam QUANT_M = 32'h000003CA;  // 970
    localparam QUANT_N = 5'd16;

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
        #100ms;
        $display("[%0t] TIMEOUT", $time);
        $finish;
    end

    int errors = 0;
    int total_outputs [0:CO_GROUPS-1];

    // Generate deterministic test data
    function automatic logic [7:0] gen_pixel(int y, int x, int ch);
        // Simple pattern: (y + x + ch) mod 256, signed range
        int val = ((y * 7 + x * 3 + ch * 5 + 42) % 200) - 100;
        return val[7:0];
    endfunction

    function automatic logic [7:0] gen_weight(int og, int filter, int ch, int ky, int kx);
        int val = ((og * 11 + filter * 7 + ch * 3 + ky * 5 + kx * 2 + 17) % 60) - 30;
        return val[7:0];
    endfunction

    function automatic logic [31:0] gen_bias(int og, int filter);
        // Small bias values
        return ((og * 8 + filter) * 50);
    endfunction

    // Reset DUT for RESET_CYCLES (matching axi_conv_wrapper)
    localparam RESET_CYCLES = 8;

    task automatic datapath_reset();
        rst <= 1;
        repeat(RESET_CYCLES) @(posedge clk);
        rst <= 0;
        @(posedge clk);
    endtask

    // Load weights for one OG (always resets address)
    task automatic load_weights(input int og);
        logic [71:0] wt_word;

        @(posedge clk);
        wt_wr_addr_rst <= 1;
        @(posedge clk);
        wt_wr_addr_rst <= 0;

        for (int addr = 0; addr < CI_GROUPS; addr++) begin
            for (int bank = 0; bank < 8; bank++) begin
                for (int uram = 0; uram < 8; uram++) begin
                    int filter = bank;
                    int ch = addr * 8 + uram;

                    wt_word = 0;
                    for (int s = 0; s < 9; s++) begin
                        int ky = s / 3;
                        int kx = s % 3;
                        wt_word |= ({64'b0, gen_weight(og, filter, ch, ky, kx)} << (s * 8));
                    end

                    @(posedge clk);
                    wt_wr_en   <= 1;
                    wt_wr_data <= wt_word;
                end
            end
        end

        @(posedge clk);
        wt_wr_en <= 0;
    endtask

    // Load biases for one OG
    // Key: addr_reset ONLY for og==0, mimicking axi_conv_wrapper behavior
    task automatic load_biases(input int og);
        logic [127:0] bias_word0, bias_word1;

        // Pack biases
        bias_word0 = {gen_bias(og, 3), gen_bias(og, 2), gen_bias(og, 1), gen_bias(og, 0)};
        bias_word1 = {gen_bias(og, 7), gen_bias(og, 6), gen_bias(og, 5), gen_bias(og, 4)};

        @(posedge clk);
        if (og == 0) begin
            // ONLY reset address for first OG
            bias_wr_addr_rst <= 1;
            @(posedge clk);
            bias_wr_addr_rst <= 0;
        end

        @(posedge clk);
        bias_wr_en   <= 1;
        bias_wr_data <= bias_word0;
        @(posedge clk);
        bias_wr_data <= bias_word1;
        @(posedge clk);
        bias_wr_en <= 0;
    endtask

    // Stream pixels
    task automatic stream_pixels();
        for (int p = 0; p < N_PIXELS; p++) begin
            int y = p / (PADDED_W * CI_GROUPS);
            int x = (p / CI_GROUPS) % PADDED_W;
            int cg = p % CI_GROUPS;
            logic [63:0] pixel_word;

            for (int c = 0; c < 8; c++) begin
                pixel_word[c*8 +: 8] = gen_pixel(y, x, cg * 8 + c);
            end

            @(posedge clk);
            pixel_in_valid <= 1;
            pixel_in       <= pixel_word;
            pixel_in_last  <= (p == N_PIXELS - 1);
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
    endtask

    // Process one OG following axi_conv_wrapper sequence
    task automatic process_og(input int og, output int output_count);
        output_count = 0;

        $display("\n--- Processing OG%0d ---", og);

        // Configure (same for all OGs except cfg_output_group)
        cfg_ci_groups    <= CI_GROUPS;
        cfg_output_group <= og[BIAS_GROUP_BITS-1:0];  // KEY: this selects bias read address
        cfg_wt_base_addr <= '0;
        cfg_img_width    <= 16'(PADDED_W);
        cfg_in_channels  <= 16'(CIN);
        cfg_quant_m      <= QUANT_M;
        cfg_quant_n      <= QUANT_N;
        cfg_use_relu     <= 1;
        cfg_use_maxpool  <= 1;
        cfg_stride_2     <= 1;

        // 1. Reset datapath (like ST_RESET)
        datapath_reset();

        // 2. Load weights (like ST_LOAD_WEIGHTS)
        load_weights(og);

        // 3. Load biases (like ST_LOAD_BIAS)
        load_biases(og);

        // 4. Start processing (like ST_START)
        pulse_go();

        // 5. Stream pixels and collect outputs (like ST_PROCESS)
        fork
            stream_pixels();
            begin
                while (!done) begin
                    @(negedge clk);
                    if (data_out_valid) begin
                        output_count++;
                        if (output_count <= 4) begin
                            $display("  OG%0d output[%0d]: %h", og, output_count-1, data_out);
                        end
                    end
                end
            end
        join

        $display("  OG%0d: %0d outputs received", og, output_count);
        total_outputs[og] = output_count;
    endtask

    // Main test
    initial begin
        $dumpfile("tb_conv_top_multi_og.vcd");
        $dumpvars(0, tb_conv_top_multi_og);

        $display("\n================================================");
        $display("  Multi-OG Sequential Test (Layer 2 config)");
        $display("  %0dx%0d image, %0d->%0d channels, %0d OGs", IMG_H, IMG_W, CIN, COUT, CO_GROUPS);
        $display("  Testing bias address accumulation");
        $display("================================================\n");

        // Initialize
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

        for (int i = 0; i < CO_GROUPS; i++)
            total_outputs[i] = 0;

        repeat(10) @(posedge clk);
        rst = 0;
        repeat(5) @(posedge clk);

        // ================================================================
        // TEST 1: Process all OGs sequentially with per-OG bias loading
        // This exactly matches axi_conv_wrapper behavior:
        // For each OG: reset -> load_weights -> load_biases -> process
        // Key: bias addr_rst only for OG 0, biases accumulate at 0,1 | 2,3 | ...
        // ================================================================
        $display("\n=== TEST 1: Per-OG bias loading (axi_conv_wrapper mode) ===");

        for (int og = 0; og < CO_GROUPS; og++) begin
            int out_cnt;

            $display("\n--- Processing OG%0d ---", og);

            // Configure
            cfg_ci_groups    <= CI_GROUPS;
            cfg_output_group <= og[BIAS_GROUP_BITS-1:0];
            cfg_wt_base_addr <= '0;
            cfg_img_width    <= 16'(PADDED_W);
            cfg_in_channels  <= 16'(CIN);
            cfg_quant_m      <= QUANT_M;
            cfg_quant_n      <= QUANT_N;
            cfg_use_relu     <= 1;
            cfg_use_maxpool  <= 1;
            cfg_stride_2     <= 1;

            // 1. Reset datapath
            datapath_reset();

            // 2. Load weights (always reset addr)
            load_weights(og);

            // 3. Load biases (addr_rst ONLY for og==0)
            load_biases(og);

            // 4. Start and process
            pulse_go();

            out_cnt = 0;
            fork
                stream_pixels();
                begin
                    while (!done) begin
                        @(negedge clk);
                        if (data_out_valid) begin
                            out_cnt++;
                            if (out_cnt <= 4) begin
                                $display("  OG%0d output[%0d]: %h", og, out_cnt-1, data_out);
                            end
                        end
                    end
                end
            join

            $display("  OG%0d: %0d outputs received", og, out_cnt);
            total_outputs[og] = out_cnt;
        end

        // Summary
        $display("\n================================================");
        $display("  Results:");
        for (int og = 0; og < CO_GROUPS; og++) begin
            string status = (total_outputs[og] == N_EXPECTED) ? "OK" : "FAIL";
            $display("    OG%0d: %0d/%0d outputs [%s]", og, total_outputs[og], N_EXPECTED, status);
            if (total_outputs[og] != N_EXPECTED)
                errors++;
        end

        if (errors == 0)
            $display("\n  ALL OGs PASSED");
        else
            $display("\n  FAILED: %0d OGs with wrong output count", errors);
        $display("================================================\n");

        $finish;
    end

endmodule
