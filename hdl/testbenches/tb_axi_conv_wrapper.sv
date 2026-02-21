`timescale 1ns / 1ps
`include "tb_macros.svh"

// ============================================================================
// Testbench for TinyYOLOV3_HW_Complete_example (axi_conv_wrapper)
// ============================================================================
// Tests the AXI master wrapper for conv_top integration with:
//   - FSM state transitions (IDLE→RESET→LOAD_WEIGHTS→LOAD_BIAS→START→PROCESS→DONE)
//   - AXI read/write operations for weights, biases, pixels, outputs
//   - Multi-OG batching with correct address offset computation
//   - Single OG and multi-OG processing flows
//
// Uses simple AXI memory models and BFM responders to verify:
//   - Correct AXI address generation
//   - Proper data flow through the datapath
//   - FSM coverage and state transitions
// ============================================================================

module tb_axi_conv_wrapper;

    // ========================================================================
    // Parameters
    // ========================================================================
    localparam C_WEIGHT_BIAS_AXI_ADDR_WIDTH = 64;
    localparam C_WEIGHT_BIAS_AXI_DATA_WIDTH = 128;
    localparam C_PIXEL_AXI_ADDR_WIDTH       = 64;
    localparam C_PIXEL_AXI_DATA_WIDTH       = 64;
    localparam C_OUTPUT_AXI_ADDR_WIDTH      = 64;
    localparam C_OUTPUT_AXI_DATA_WIDTH      = 64;

    // Test configuration - small layer for fast simulation
    localparam IMG_WIDTH      = 4;
    localparam IMG_HEIGHT     = 4;
    localparam PADDED_W       = 6;
    localparam PADDED_H       = 6;
    localparam CI_GROUPS      = 1;  // 8 input channels
    localparam CO_GROUPS      = 2;  // 16 output channels (2 OGs)

    // Memory sizes (per OG)
    localparam WEIGHT_BYTES_PER_OG = CI_GROUPS * 8 * 9 * 8;  // ci_groups * 8_filters * 9_spatial * 8_bytes = 576
    localparam BIAS_BYTES_PER_OG   = 8 * 4;                   // 8 biases * 4 bytes = 32
    localparam PIXEL_BYTES         = PADDED_H * PADDED_W * CI_GROUPS * 8;  // 6*6*1*8 = 288
    localparam OUTPUT_BYTES_PER_OG = IMG_HEIGHT * IMG_WIDTH * 8;  // 4*4*8 = 128 (no maxpool)

    // Base addresses
    localparam WEIGHT_BASE_ADDR = 64'h0000_1000;
    localparam BIAS_BASE_ADDR   = 64'h0000_2000;
    localparam PIXEL_BASE_ADDR  = 64'h0000_3000;
    localparam OUTPUT_BASE_ADDR = 64'h0000_4000;

    // ========================================================================
    // DUT Signals
    // ========================================================================
    logic ap_clk;
    logic ap_rst_n;

    // Weight/Bias AXI
    wire                                      weight_bias_axi_awvalid;
    logic                                     weight_bias_axi_awready;
    wire [C_WEIGHT_BIAS_AXI_ADDR_WIDTH-1:0]   weight_bias_axi_awaddr;
    wire [7:0]                                weight_bias_axi_awlen;
    wire                                      weight_bias_axi_wvalid;
    logic                                     weight_bias_axi_wready;
    wire [C_WEIGHT_BIAS_AXI_DATA_WIDTH-1:0]   weight_bias_axi_wdata;
    wire [C_WEIGHT_BIAS_AXI_DATA_WIDTH/8-1:0] weight_bias_axi_wstrb;
    wire                                      weight_bias_axi_wlast;
    logic                                     weight_bias_axi_bvalid;
    wire                                      weight_bias_axi_bready;
    wire                                      weight_bias_axi_arvalid;
    logic                                     weight_bias_axi_arready;
    wire [C_WEIGHT_BIAS_AXI_ADDR_WIDTH-1:0]   weight_bias_axi_araddr;
    wire [7:0]                                weight_bias_axi_arlen;
    logic                                     weight_bias_axi_rvalid;
    wire                                      weight_bias_axi_rready;
    logic [C_WEIGHT_BIAS_AXI_DATA_WIDTH-1:0]  weight_bias_axi_rdata;
    logic                                     weight_bias_axi_rlast;

    // Pixel AXI
    wire                                      pixel_axi_awvalid;
    logic                                     pixel_axi_awready;
    wire [C_PIXEL_AXI_ADDR_WIDTH-1:0]         pixel_axi_awaddr;
    wire [7:0]                                pixel_axi_awlen;
    wire                                      pixel_axi_wvalid;
    logic                                     pixel_axi_wready;
    wire [C_PIXEL_AXI_DATA_WIDTH-1:0]         pixel_axi_wdata;
    wire [C_PIXEL_AXI_DATA_WIDTH/8-1:0]       pixel_axi_wstrb;
    wire                                      pixel_axi_wlast;
    logic                                     pixel_axi_bvalid;
    wire                                      pixel_axi_bready;
    wire                                      pixel_axi_arvalid;
    logic                                     pixel_axi_arready;
    wire [C_PIXEL_AXI_ADDR_WIDTH-1:0]         pixel_axi_araddr;
    wire [7:0]                                pixel_axi_arlen;
    logic                                     pixel_axi_rvalid;
    wire                                      pixel_axi_rready;
    logic [C_PIXEL_AXI_DATA_WIDTH-1:0]        pixel_axi_rdata;
    logic                                     pixel_axi_rlast;

    // Output AXI
    wire                                      output_axi_awvalid;
    logic                                     output_axi_awready;
    wire [C_OUTPUT_AXI_ADDR_WIDTH-1:0]        output_axi_awaddr;
    wire [7:0]                                output_axi_awlen;
    wire                                      output_axi_wvalid;
    logic                                     output_axi_wready;
    wire [C_OUTPUT_AXI_DATA_WIDTH-1:0]        output_axi_wdata;
    wire [C_OUTPUT_AXI_DATA_WIDTH/8-1:0]      output_axi_wstrb;
    wire                                      output_axi_wlast;
    logic                                     output_axi_bvalid;
    wire                                      output_axi_bready;
    wire                                      output_axi_arvalid;
    logic                                     output_axi_arready;
    wire [C_OUTPUT_AXI_ADDR_WIDTH-1:0]        output_axi_araddr;
    wire [7:0]                                output_axi_arlen;
    logic                                     output_axi_rvalid;
    wire                                      output_axi_rready;
    logic [C_OUTPUT_AXI_DATA_WIDTH-1:0]       output_axi_rdata;
    logic                                     output_axi_rlast;

    // Control signals
    logic        ap_start;
    wire         ap_idle;
    wire         ap_done;
    wire         ap_ready;

    // Address and size signals
    logic [63:0] weights_addr;
    logic [63:0] bias_addr;
    logic [63:0] pixels_addr;
    logic [63:0] output_addr;
    logic [31:0] num_weights;
    logic [31:0] num_bias;
    logic [31:0] num_pixels;
    logic [31:0] num_outputs;

    // Configuration registers
    logic [31:0] cfg_ci_groups;
    logic [31:0] cfg_co_groups;
    logic [31:0] cfg_wt_base_addr;
    logic [31:0] cfg_in_channels;
    logic [31:0] cfg_img_width;
    logic [31:0] cfg_use_maxpool;
    logic [31:0] cfg_use_stride2;
    logic [31:0] cfg_quant_m;
    logic [31:0] cfg_quant_n;
    logic [31:0] cfg_use_relu;
    logic [31:0] cfg_kernel_1x1;

    // AXI pointer addresses
    logic [63:0] weights_addr_axi;
    logic [63:0] bias_addr_axi;
    logic [63:0] pixels_addr_axi;
    logic [63:0] output_addr_axi;

    // ========================================================================
    // DUT Instantiation
    // ========================================================================
    TinyYOLOV3_HW_Complete_example #(
        .C_WEIGHT_BIAS_AXI_ADDR_WIDTH(C_WEIGHT_BIAS_AXI_ADDR_WIDTH),
        .C_WEIGHT_BIAS_AXI_DATA_WIDTH(C_WEIGHT_BIAS_AXI_DATA_WIDTH),
        .C_PIXEL_AXI_ADDR_WIDTH(C_PIXEL_AXI_ADDR_WIDTH),
        .C_PIXEL_AXI_DATA_WIDTH(C_PIXEL_AXI_DATA_WIDTH),
        .C_OUTPUT_AXI_ADDR_WIDTH(C_OUTPUT_AXI_ADDR_WIDTH),
        .C_OUTPUT_AXI_DATA_WIDTH(C_OUTPUT_AXI_DATA_WIDTH)
    ) u_dut (
        .ap_clk(ap_clk),
        .ap_rst_n(ap_rst_n),

        // Weight/Bias AXI
        .weight_bias_axi_awvalid(weight_bias_axi_awvalid),
        .weight_bias_axi_awready(weight_bias_axi_awready),
        .weight_bias_axi_awaddr(weight_bias_axi_awaddr),
        .weight_bias_axi_awlen(weight_bias_axi_awlen),
        .weight_bias_axi_wvalid(weight_bias_axi_wvalid),
        .weight_bias_axi_wready(weight_bias_axi_wready),
        .weight_bias_axi_wdata(weight_bias_axi_wdata),
        .weight_bias_axi_wstrb(weight_bias_axi_wstrb),
        .weight_bias_axi_wlast(weight_bias_axi_wlast),
        .weight_bias_axi_bvalid(weight_bias_axi_bvalid),
        .weight_bias_axi_bready(weight_bias_axi_bready),
        .weight_bias_axi_arvalid(weight_bias_axi_arvalid),
        .weight_bias_axi_arready(weight_bias_axi_arready),
        .weight_bias_axi_araddr(weight_bias_axi_araddr),
        .weight_bias_axi_arlen(weight_bias_axi_arlen),
        .weight_bias_axi_rvalid(weight_bias_axi_rvalid),
        .weight_bias_axi_rready(weight_bias_axi_rready),
        .weight_bias_axi_rdata(weight_bias_axi_rdata),
        .weight_bias_axi_rlast(weight_bias_axi_rlast),

        // Pixel AXI
        .pixel_axi_awvalid(pixel_axi_awvalid),
        .pixel_axi_awready(pixel_axi_awready),
        .pixel_axi_awaddr(pixel_axi_awaddr),
        .pixel_axi_awlen(pixel_axi_awlen),
        .pixel_axi_wvalid(pixel_axi_wvalid),
        .pixel_axi_wready(pixel_axi_wready),
        .pixel_axi_wdata(pixel_axi_wdata),
        .pixel_axi_wstrb(pixel_axi_wstrb),
        .pixel_axi_wlast(pixel_axi_wlast),
        .pixel_axi_bvalid(pixel_axi_bvalid),
        .pixel_axi_bready(pixel_axi_bready),
        .pixel_axi_arvalid(pixel_axi_arvalid),
        .pixel_axi_arready(pixel_axi_arready),
        .pixel_axi_araddr(pixel_axi_araddr),
        .pixel_axi_arlen(pixel_axi_arlen),
        .pixel_axi_rvalid(pixel_axi_rvalid),
        .pixel_axi_rready(pixel_axi_rready),
        .pixel_axi_rdata(pixel_axi_rdata),
        .pixel_axi_rlast(pixel_axi_rlast),

        // Output AXI
        .output_axi_awvalid(output_axi_awvalid),
        .output_axi_awready(output_axi_awready),
        .output_axi_awaddr(output_axi_awaddr),
        .output_axi_awlen(output_axi_awlen),
        .output_axi_wvalid(output_axi_wvalid),
        .output_axi_wready(output_axi_wready),
        .output_axi_wdata(output_axi_wdata),
        .output_axi_wstrb(output_axi_wstrb),
        .output_axi_wlast(output_axi_wlast),
        .output_axi_bvalid(output_axi_bvalid),
        .output_axi_bready(output_axi_bready),
        .output_axi_arvalid(output_axi_arvalid),
        .output_axi_arready(output_axi_arready),
        .output_axi_araddr(output_axi_araddr),
        .output_axi_arlen(output_axi_arlen),
        .output_axi_rvalid(output_axi_rvalid),
        .output_axi_rready(output_axi_rready),
        .output_axi_rdata(output_axi_rdata),
        .output_axi_rlast(output_axi_rlast),

        // Control
        .ap_start(ap_start),
        .ap_idle(ap_idle),
        .ap_done(ap_done),
        .ap_ready(ap_ready),

        // Addresses and sizes
        .weights_addr(weights_addr),
        .bias_addr(bias_addr),
        .pixels_addr(pixels_addr),
        .output_addr(output_addr),
        .num_weights(num_weights),
        .num_bias(num_bias),
        .num_pixels(num_pixels),
        .num_outputs(num_outputs),

        // Configuration
        .cfg_ci_groups(cfg_ci_groups),
        .cfg_co_groups(cfg_co_groups),
        .cfg_wt_base_addr(cfg_wt_base_addr),
        .cfg_in_channels(cfg_in_channels),
        .cfg_img_width(cfg_img_width),
        .cfg_use_maxpool(cfg_use_maxpool),
        .cfg_use_stride2(cfg_use_stride2),
        .cfg_quant_m(cfg_quant_m),
        .cfg_quant_n(cfg_quant_n),
        .cfg_use_relu(cfg_use_relu),
        .cfg_kernel_1x1(cfg_kernel_1x1),

        // AXI pointer addresses
        .weights_addr_axi(weights_addr_axi),
        .bias_addr_axi(bias_addr_axi),
        .pixels_addr_axi(pixels_addr_axi),
        .output_addr_axi(output_addr_axi)
    );

    // ========================================================================
    // Clock Generation
    // ========================================================================
    initial ap_clk = 0;
    always #5 ap_clk = ~ap_clk;  // 100MHz

    // ========================================================================
    // Timeout
    // ========================================================================
    `TB_TIMEOUT(5ms)

    // Error counter
    int errors = 0;

    // ========================================================================
    // AXI Memory Models
    // ========================================================================
    // Simple byte-addressable memories
    logic [7:0] weight_bias_mem [0:65535];
    logic [7:0] pixel_mem       [0:65535];
    logic [7:0] output_mem      [0:65535];

    // Address capture for verification
    logic [63:0] captured_wb_araddr [$];
    logic [63:0] captured_px_araddr [$];
    logic [63:0] captured_out_awaddr [$];

    // ========================================================================
    // AXI Read BFM for Weight/Bias (128-bit)
    // ========================================================================
    logic [7:0] wb_burst_cnt;
    logic [63:0] wb_burst_addr;

    always_ff @(posedge ap_clk) begin
        if (!ap_rst_n) begin
            weight_bias_axi_arready <= 1'b0;
            weight_bias_axi_rvalid  <= 1'b0;
            weight_bias_axi_rdata   <= '0;
            weight_bias_axi_rlast   <= 1'b0;
            wb_burst_cnt <= '0;
            wb_burst_addr <= '0;
        end else begin
            // Accept address
            weight_bias_axi_arready <= 1'b1;

            if (weight_bias_axi_arvalid && weight_bias_axi_arready) begin
                // Capture address for verification
                captured_wb_araddr.push_back(weight_bias_axi_araddr);
                wb_burst_addr <= weight_bias_axi_araddr;
                wb_burst_cnt <= weight_bias_axi_arlen + 1;
            end

            // Return read data
            if (wb_burst_cnt > 0 && weight_bias_axi_rready) begin
                weight_bias_axi_rvalid <= 1'b1;
                // Read 16 bytes from memory
                for (int i = 0; i < 16; i++)
                    weight_bias_axi_rdata[i*8 +: 8] <= weight_bias_mem[(wb_burst_addr + i) & 16'hFFFF];
                wb_burst_addr <= wb_burst_addr + 16;
                wb_burst_cnt <= wb_burst_cnt - 1;
                weight_bias_axi_rlast <= (wb_burst_cnt == 1);
            end else begin
                weight_bias_axi_rvalid <= 1'b0;
                weight_bias_axi_rlast <= 1'b0;
            end
        end
    end

    // ========================================================================
    // AXI Read BFM for Pixels (64-bit)
    // ========================================================================
    logic [7:0] px_burst_cnt;
    logic [63:0] px_burst_addr;

    always_ff @(posedge ap_clk) begin
        if (!ap_rst_n) begin
            pixel_axi_arready <= 1'b0;
            pixel_axi_rvalid  <= 1'b0;
            pixel_axi_rdata   <= '0;
            pixel_axi_rlast   <= 1'b0;
            px_burst_cnt <= '0;
            px_burst_addr <= '0;
        end else begin
            pixel_axi_arready <= 1'b1;

            if (pixel_axi_arvalid && pixel_axi_arready) begin
                captured_px_araddr.push_back(pixel_axi_araddr);
                px_burst_addr <= pixel_axi_araddr;
                px_burst_cnt <= pixel_axi_arlen + 1;
            end

            if (px_burst_cnt > 0 && pixel_axi_rready) begin
                pixel_axi_rvalid <= 1'b1;
                for (int i = 0; i < 8; i++)
                    pixel_axi_rdata[i*8 +: 8] <= pixel_mem[(px_burst_addr + i) & 16'hFFFF];
                px_burst_addr <= px_burst_addr + 8;
                px_burst_cnt <= px_burst_cnt - 1;
                pixel_axi_rlast <= (px_burst_cnt == 1);
            end else begin
                pixel_axi_rvalid <= 1'b0;
                pixel_axi_rlast <= 1'b0;
            end
        end
    end

    // ========================================================================
    // AXI Write BFM for Outputs (64-bit)
    // ========================================================================
    logic [7:0] out_burst_cnt;
    logic [63:0] out_burst_addr;
    int output_write_count;

    always_ff @(posedge ap_clk) begin
        if (!ap_rst_n) begin
            output_axi_awready <= 1'b0;
            output_axi_wready  <= 1'b0;
            output_axi_bvalid  <= 1'b0;
            out_burst_cnt <= '0;
            out_burst_addr <= '0;
            output_write_count <= 0;
        end else begin
            output_axi_awready <= 1'b1;
            output_axi_wready  <= 1'b1;

            // Accept write address
            if (output_axi_awvalid && output_axi_awready) begin
                captured_out_awaddr.push_back(output_axi_awaddr);
                out_burst_addr <= output_axi_awaddr;
                out_burst_cnt <= output_axi_awlen + 1;
            end

            // Accept write data
            if (output_axi_wvalid && output_axi_wready) begin
                for (int i = 0; i < 8; i++) begin
                    if (output_axi_wstrb[i])
                        output_mem[(out_burst_addr + i) & 16'hFFFF] <= output_axi_wdata[i*8 +: 8];
                end
                out_burst_addr <= out_burst_addr + 8;
                output_write_count <= output_write_count + 1;

                if (output_axi_wlast) begin
                    output_axi_bvalid <= 1'b1;
                end
            end

            // Clear bvalid after one cycle
            if (output_axi_bvalid && output_axi_bready)
                output_axi_bvalid <= 1'b0;
        end
    end

    // Tie off unused read channel on output port
    initial begin
        output_axi_arready = 1'b1;
        output_axi_rvalid = 1'b0;
        output_axi_rdata = '0;
        output_axi_rlast = 1'b0;
    end

    // Tie off unused write channels on read ports
    initial begin
        weight_bias_axi_awready = 1'b1;
        weight_bias_axi_wready = 1'b1;
        weight_bias_axi_bvalid = 1'b0;
        pixel_axi_awready = 1'b1;
        pixel_axi_wready = 1'b1;
        pixel_axi_bvalid = 1'b0;
    end

    // ========================================================================
    // Helper Tasks
    // ========================================================================
    task automatic reset_dut();
        ap_rst_n = 0;
        ap_start = 0;
        repeat(10) @(posedge ap_clk);
        ap_rst_n = 1;
        repeat(5) @(posedge ap_clk);
    endtask

    task automatic configure_layer(
        input int ci_grps,
        input int co_grps,
        input int width,
        input bit use_mp,
        input bit use_s2
    );
        cfg_ci_groups    = ci_grps;
        cfg_co_groups    = co_grps;
        cfg_wt_base_addr = 0;
        cfg_in_channels  = ci_grps * 8;
        cfg_img_width    = width;
        cfg_use_maxpool  = use_mp;
        cfg_use_stride2  = use_s2;
        cfg_quant_m      = 32'h0001_0000;  // Scale = 1.0
        cfg_quant_n      = 5'd16;
        cfg_use_relu     = 1;
        cfg_kernel_1x1   = 0;

        // Set sizes (per OG)
        num_weights = WEIGHT_BYTES_PER_OG;
        num_bias    = BIAS_BYTES_PER_OG;
        num_pixels  = PIXEL_BYTES;
        num_outputs = OUTPUT_BYTES_PER_OG;

        // Set base addresses
        weights_addr     = WEIGHT_BASE_ADDR;
        bias_addr        = BIAS_BASE_ADDR;
        pixels_addr      = PIXEL_BASE_ADDR;
        output_addr      = OUTPUT_BASE_ADDR;
        weights_addr_axi = WEIGHT_BASE_ADDR;
        bias_addr_axi    = BIAS_BASE_ADDR;
        pixels_addr_axi  = PIXEL_BASE_ADDR;
        output_addr_axi  = OUTPUT_BASE_ADDR;
    endtask

    task automatic init_memories();
        // Initialize weight memory with pattern
        for (int i = 0; i < 65536; i++)
            weight_bias_mem[i] = i[7:0];

        // Initialize pixel memory with pattern
        for (int i = 0; i < 65536; i++)
            pixel_mem[i] = (i * 3) & 8'hFF;

        // Clear output memory
        for (int i = 0; i < 65536; i++)
            output_mem[i] = 8'h00;
    endtask

    task automatic clear_captured_addresses();
        captured_wb_araddr.delete();
        captured_px_araddr.delete();
        captured_out_awaddr.delete();
        output_write_count = 0;
    endtask

    task automatic pulse_ap_start();
        // Drive ap_start at negedge to ensure it's stable before next posedge
        @(negedge ap_clk);
        ap_start = 1;
        @(posedge ap_clk);  // DUT samples ap_start=1 here
        @(negedge ap_clk);
        ap_start = 0;
    endtask

    task automatic wait_for_done(output bit timed_out);
        int timeout_cnt = 0;
        timed_out = 0;
        while (!ap_done && timeout_cnt < 50000) begin
            @(posedge ap_clk);
            timeout_cnt++;
        end
        if (!ap_done) timed_out = 1;
    endtask

    // ========================================================================
    // Test 1: Single OG flow
    // ========================================================================
    task automatic test_single_og();
        bit timed_out;

        `TEST_CASE(1, "Single OG processing flow")

        reset_dut();
        init_memories();
        clear_captured_addresses();
        configure_layer(CI_GROUPS, 1, PADDED_W, 0, 0);  // 1 OG, no maxpool

        $display("  Starting single OG test...");
        pulse_ap_start();

        wait_for_done(timed_out);
        @(posedge ap_clk);  // Wait one cycle for ap_idle to update

        `CHECK_FALSE(timed_out, "ap_done asserted before timeout", errors)
        `CHECK_TRUE(ap_idle, "ap_idle asserted after done", errors)

        // Verify addresses were issued
        `CHECK_TRUE(captured_wb_araddr.size() > 0, "weight/bias read addresses issued", errors)
        `CHECK_TRUE(captured_px_araddr.size() > 0, "pixel read addresses issued", errors)
        `CHECK_TRUE(captured_out_awaddr.size() > 0, "output write addresses issued", errors)

        // Verify first weight address matches expected
        if (captured_wb_araddr.size() > 0) begin
            `CHECK_EQ_HEX(captured_wb_araddr[0], WEIGHT_BASE_ADDR, "first weight addr", errors)
        end

        $display("  Single OG: %0d weight/bias reads, %0d pixel reads, %0d output writes",
            captured_wb_araddr.size(), captured_px_araddr.size(), output_write_count);

    endtask

    // ========================================================================
    // Test 2: Multi-OG batch
    // ========================================================================
    task automatic test_multi_og_batch();
        bit timed_out;

        `TEST_CASE(2, "Multi-OG batch processing (2 OGs)")

        reset_dut();
        init_memories();
        clear_captured_addresses();
        configure_layer(CI_GROUPS, 2, PADDED_W, 0, 0);  // 2 OGs

        $display("  Starting 2-OG batch test...");
        pulse_ap_start();

        wait_for_done(timed_out);
        @(posedge ap_clk);  // Wait one cycle for ap_idle to update

        `CHECK_FALSE(timed_out, "ap_done asserted before timeout", errors)
        `CHECK_TRUE(ap_idle, "ap_idle asserted after done", errors)

        // Should have addresses for 2 OGs
        // Weight addresses: OG0 at WEIGHT_BASE_ADDR, OG1 at WEIGHT_BASE_ADDR + WEIGHT_BYTES_PER_OG
        if (captured_wb_araddr.size() >= 2) begin
            $display("  Captured weight addresses: [0]=%h, [1]=%h",
                captured_wb_araddr[0], captured_wb_araddr[1]);
            // First two should be weight reads for OG0 and OG1 (interleaved with bias)
        end

        $display("  Multi-OG: %0d total AXI transactions", captured_wb_araddr.size());

    endtask

    // ========================================================================
    // Test 3: Address offset verification
    // ========================================================================
    task automatic test_address_offsets();
        bit timed_out;
        logic [63:0] expected_wt_addr_og1;
        logic [63:0] expected_bias_addr_og1;
        logic [63:0] expected_out_addr_og1;
        int found_wt_og1, found_bias_og1, found_out_og1;

        `TEST_CASE(3, "Per-OG address offset computation")

        reset_dut();
        init_memories();
        clear_captured_addresses();
        configure_layer(CI_GROUPS, 2, PADDED_W, 0, 0);  // 2 OGs

        // Compute expected OG1 addresses
        expected_wt_addr_og1   = WEIGHT_BASE_ADDR + WEIGHT_BYTES_PER_OG;
        expected_bias_addr_og1 = BIAS_BASE_ADDR + BIAS_BYTES_PER_OG;
        expected_out_addr_og1  = OUTPUT_BASE_ADDR + OUTPUT_BYTES_PER_OG;

        $display("  Expected OG1 weight addr: %h", expected_wt_addr_og1);
        $display("  Expected OG1 bias addr: %h", expected_bias_addr_og1);
        $display("  Expected OG1 output addr: %h", expected_out_addr_og1);

        pulse_ap_start();
        wait_for_done(timed_out);

        // Search for expected addresses in captured list
        found_wt_og1 = 0;
        found_out_og1 = 0;

        foreach (captured_wb_araddr[i]) begin
            if (captured_wb_araddr[i] == expected_wt_addr_og1)
                found_wt_og1 = 1;
        end

        foreach (captured_out_awaddr[i]) begin
            if (captured_out_awaddr[i] == expected_out_addr_og1)
                found_out_og1 = 1;
        end

        `CHECK_TRUE(found_wt_og1, "OG1 weight address issued", errors)
        `CHECK_TRUE(found_out_og1, "OG1 output address issued", errors)

    endtask

    // ========================================================================
    // Test 4: FSM state coverage
    // ========================================================================
    task automatic test_fsm_coverage();
        bit seen_idle, seen_busy, seen_done;

        `TEST_CASE(4, "FSM state coverage")

        reset_dut();
        init_memories();
        configure_layer(CI_GROUPS, 1, PADDED_W, 0, 0);

        // Check initial state
        `CHECK_TRUE(ap_idle, "starts in IDLE", errors)

        seen_idle = ap_idle;
        seen_busy = 0;
        seen_done = 0;

        pulse_ap_start();

        // Monitor states
        for (int i = 0; i < 50000 && !ap_done; i++) begin
            @(posedge ap_clk);
            if (!ap_idle && !ap_done) seen_busy = 1;
        end
        seen_done = ap_done;

        `CHECK_TRUE(seen_idle, "IDLE state observed", errors)
        `CHECK_TRUE(seen_busy, "BUSY state observed", errors)
        `CHECK_TRUE(seen_done, "DONE state observed", errors)

        // Check return to idle
        repeat(5) @(posedge ap_clk);
        `CHECK_TRUE(ap_idle, "returns to IDLE after DONE", errors)

    endtask

    // ========================================================================
    // Test 5: Back-to-back kernel invocations
    // ========================================================================
    task automatic test_back_to_back();
        bit timed_out;
        int invocation;

        `TEST_CASE(5, "Back-to-back kernel invocations")

        reset_dut();
        init_memories();
        configure_layer(CI_GROUPS, 1, PADDED_W, 0, 0);

        for (invocation = 0; invocation < 3; invocation++) begin
            $display("  Invocation %0d...", invocation);
            clear_captured_addresses();

            pulse_ap_start();
            wait_for_done(timed_out);

            `CHECK_FALSE(timed_out, $sformatf("invocation %0d completes", invocation), errors)

            repeat(10) @(posedge ap_clk);  // Small gap
        end

    endtask

    // ========================================================================
    // Main test sequence
    // ========================================================================
    initial begin
        $dumpfile("tb_axi_conv_wrapper.vcd");
        $dumpvars(0, tb_axi_conv_wrapper);

        `TB_HEADER("TinyYOLOV3_HW_Complete_example (axi_conv_wrapper)")

        test_single_og();
        test_multi_og_batch();
        test_address_offsets();
        test_fsm_coverage();
        test_back_to_back();

        repeat(100) @(posedge ap_clk);

        `TB_FOOTER(errors)

        $finish;
    end

endmodule
