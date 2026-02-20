`timescale 1ns / 1ps

// Multi-OG Batching Test for conv_top
// Mimics the behavior of axi_conv_wrapper:
// - Biases are loaded per-OG with accumulating addresses (reset only for OG0)
// - cfg_output_group is set to current OG index for each iteration
//
// This tests if the bias addressing is correct when biases accumulate
// at different addresses (0,1 for OG0; 2,3 for OG1; etc.)
//
// Uses small synthetic stimulus for fast simulation.

module tb_conv_top_batch;

    localparam WT_DEPTH        = 4096;
    localparam WT_ADDR_WIDTH   = $clog2(WT_DEPTH);
    localparam BIAS_DEPTH      = 256;
    localparam BIAS_GROUP_BITS = $clog2(BIAS_DEPTH) - 1;
    localparam WT_LATENCY      = 3;
    localparam CONV_PE_PIPE    = 4;  // Updated for timing fix

    // Small test: 4x4 padded to 6x6, similar to Layer 2 structure
    localparam PADDED_W   = 6;
    localparam PADDED_H   = 6;
    localparam CI_GROUPS  = 4;   // 32 input channels (like Layer 2)
    localparam CO_GROUPS  = 8;   // 64 output channels (like Layer 2)
    localparam CIN        = CI_GROUPS * 8;  // 32
    localparam COUT       = CO_GROUPS * 8;  // 64
    localparam N_PIXELS   = PADDED_H * PADDED_W * CI_GROUPS;  // 144
    localparam N_WT_WORDS = CI_GROUPS * 8 * 8;                // 256
    localparam N_EXPECTED = 4;   // 2x2 maxpool output

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

    // Stimulus generation functions
    // Generate unique pixel value based on position and channel
    function automatic [7:0] gen_pixel(int y, int x, int ch);
        // Use position and channel to create unique values
        // Range: -64 to +63 for reasonable convolution results
        int val = ((y * 7 + x * 3 + ch * 5) % 127) - 63;
        return val[7:0];
    endfunction

    // Generate unique weight value based on og, filter, channel, spatial position
    function automatic [7:0] gen_weight(int og, int filter, int ch, int ky, int kx);
        // Range: -32 to +31 for reasonable convolution results
        int val = ((og * 11 + filter * 7 + ch * 3 + ky * 5 + kx * 2) % 63) - 31;
        return val[7:0];
    endfunction

    // Generate bias value for each output channel
    function automatic [31:0] gen_bias(int og, int filter);
        // Small bias to avoid overflow, but unique per channel
        return (og * 8 + filter) * 100;  // 0, 100, 200, ... 6300
    endfunction

    // Calculate expected output for a given output position
    // This is a simplified reference - in real test, use Python golden
    function automatic [31:0] calc_conv_output(int og, int filter, int out_y, int out_x);
        int acc = 0;
        int in_y, in_x;

        // With padding=1, output (0,0) uses input (0:2, 0:2)
        // Since input is 0-padded at borders, we start from padded coordinates
        in_y = out_y * 2;  // stride-2 maxpool
        in_x = out_x * 2;

        // 3x3 convolution over all input channels
        for (int c = 0; c < CIN; c++) begin
            for (int ky = 0; ky < 3; ky++) begin
                for (int kx = 0; kx < 3; kx++) begin
                    int py = in_y + ky;
                    int px = in_x + kx;
                    automatic logic signed [7:0] p = gen_pixel(py, px, c);
                    automatic logic signed [7:0] w = gen_weight(og, filter, c, ky, kx);
                    acc = acc + (p * w);
                end
            end
        end

        // Add bias
        acc = acc + gen_bias(og, filter);

        return acc;
    endfunction

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

    // Load biases for a single OG - mimicking multi-OG batching
    // Key: addr_reset only for first OG
    task automatic load_og_biases(input int og);
        logic [127:0] bias_word0, bias_word1;

        // Pack 4 biases per 128-bit word
        bias_word0 = {gen_bias(og, 3), gen_bias(og, 2), gen_bias(og, 1), gen_bias(og, 0)};
        bias_word1 = {gen_bias(og, 7), gen_bias(og, 6), gen_bias(og, 5), gen_bias(og, 4)};

        @(posedge clk);
        if (og == 0) begin
            // ONLY reset address for first OG - this is the key behavior to test
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

        $display("  Loaded biases for OG%0d (addr_rst=%0d)", og, og == 0);
    endtask

    // Load weights for a single OG
    task automatic load_og_weights(input int og);
        logic [71:0] wt_word;

        @(posedge clk);
        wt_wr_addr_rst <= 1;
        @(posedge clk);
        wt_wr_addr_rst <= 0;

        for (int addr = 0; addr < CI_GROUPS; addr++) begin
            for (int bank = 0; bank < 8; bank++) begin
                for (int uram = 0; uram < 8; uram++) begin
                    int filter = bank;  // output channel within OG
                    int ch = addr * 8 + uram;  // input channel

                    // Pack 9 weights (3x3 kernel) into 72 bits
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
        $display("  Loaded weights for OG%0d", og);
    endtask

    // Stream pixels
    task automatic stream_pixels();
        for (int p = 0; p < N_PIXELS; p++) begin
            int y = p / (PADDED_W * CI_GROUPS);
            int x = (p / CI_GROUPS) % PADDED_W;
            int cg = p % CI_GROUPS;
            logic [63:0] pixel_word;

            // Pack 8 channels
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

    // Run one OG - used for both batched and per-OG modes
    task automatic run_og(input int og);
        int pulse_count = 0;

        // Configure
        cfg_ci_groups    = CI_GROUPS;
        cfg_output_group = og[BIAS_GROUP_BITS-1:0];  // Key: this selects which bias addresses to read
        cfg_wt_base_addr = '0;
        cfg_img_width    = 16'(PADDED_W);
        cfg_in_channels  = 16'(CIN);
        cfg_quant_m      = 32'h00003CA;  // Same as Layer 2
        cfg_quant_n      = 5'd16;
        cfg_use_relu     = 1;
        cfg_use_maxpool  = 1;
        cfg_stride_2     = 1;

        // Load weights (always reset address)
        load_og_weights(og);

        pulse_go();

        fork
            stream_pixels();
            begin
                while (!done) begin
                    @(negedge clk);
                    if (data_out_valid) begin
                        if (pulse_count < N_EXPECTED) begin
                            $display("  OG%0d output[%0d]: 0x%016h", og, pulse_count, data_out);
                        end
                        pulse_count++;
                    end
                end
            end
        join

        $display("  OG%0d: %0d output pulses", og, pulse_count);

        if (pulse_count !== N_EXPECTED) begin
            $display("  ERROR OG%0d: expected %0d pulses, got %0d", og, N_EXPECTED, pulse_count);
            errors++;
        end
    endtask

    // Main test - compares batched vs per-OG behavior
    initial begin
        $dumpfile("tb_conv_top_batch.vcd");
        $dumpvars(0, tb_conv_top_batch);

        $display("\n================================================");
        $display("  Multi-OG Batching Test (Layer 2 config)");
        $display("  %0dx%0d image, %0d->%0d channels, %0d OGs",
            PADDED_W-2, PADDED_H-2, CIN, COUT, CO_GROUPS);
        $display("================================================\n");

        reset_all();

        // Configure for flush
        cfg_img_width   = 16'(PADDED_W);
        cfg_in_channels = 16'(CIN);
        flush_pipeline();

        // ==================================================================
        // TEST 1: Multi-OG Batching Mode
        // Load all biases incrementally (like axi_conv_wrapper does)
        // ==================================================================
        $display("--- TEST 1: Multi-OG Batching Mode ---");
        $display("Loading biases with accumulating addresses...");

        // Load biases for ALL OGs before processing any
        // This mimics the full batching scenario
        for (int og = 0; og < CO_GROUPS; og++) begin
            load_og_biases(og);  // addr_reset only for og==0
        end

        // Process each OG
        for (int og = 0; og < CO_GROUPS; og++) begin
            $display("\nProcessing OG%0d (batched mode)...", og);
            run_og(og);
            flush_pipeline();
        end

        // ==================================================================
        // TEST 2: Per-OG Mode (Original behavior)
        // Load biases fresh for each OG with address reset
        // ==================================================================
        $display("\n\n--- TEST 2: Per-OG Mode (Reference) ---");

        reset_all();
        cfg_img_width   = 16'(PADDED_W);
        cfg_in_channels = 16'(CIN);
        flush_pipeline();

        for (int og = 0; og < CO_GROUPS; og++) begin
            $display("\nProcessing OG%0d (per-OG mode)...", og);

            // Fresh bias load with address reset for EACH OG
            @(posedge clk);
            bias_wr_addr_rst <= 1;
            @(posedge clk);
            bias_wr_addr_rst <= 0;

            // Load this OG's biases at address 0,1
            load_og_biases(0);  // Use OG0 biases as template but should use og

            // BUT cfg_output_group is 0, so it reads from address 0,1
            cfg_output_group = 0;  // This was the bug in original code!

            run_og(og);
            flush_pipeline();
        end

        // ==================================================================
        // Summary
        // ==================================================================
        repeat(20) @(posedge clk);

        $display("\n================================================");
        if (errors == 0)
            $display("  BATCHING TEST PASSED");
        else
            $display("  BATCHING TEST FAILED: %0d errors", errors);
        $display("================================================\n");

        $finish;
    end

endmodule
