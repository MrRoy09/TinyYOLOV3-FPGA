`timescale 1ns/1ps

module tb_conv_layer;

// ── Test geometry ──
localparam IMG_W      = 6;
localparam IMG_H      = 6;
localparam PAD_W      = IMG_W + 2;          // 8
localparam PAD_H      = IMG_H + 2;          // 8
localparam C_IN       = 8;
localparam C_OUT      = 16;
localparam CI_GROUPS  = C_IN  / 8;          // 1
localparam CO_GROUPS  = C_OUT / 8;          // 2
localparam PIXEL_VAL  = 8'd1;

// Priming (from kernelWindow logic)
localparam VPR         = PAD_W * CI_GROUPS;                  // 8
localparam DELAY_D     = CI_GROUPS;                          // 1
localparam TOTAL_DLY   = 2 * VPR + 2 * DELAY_D;             // 18
localparam FIRST_VALID = TOTAL_DLY + 1;                      // 19
localparam NUM_SPATIAL  = PAD_W * PAD_H - FIRST_VALID;       // 45
localparam NUM_OUTPUTS  = NUM_SPATIAL * CO_GROUPS;            // 90

// Bias values per output group
localparam BIAS_G0 = 0;
localparam BIAS_G1 = 80;

// ── Clock / reset ──
logic clk = 0;
always #5 clk = ~clk;
logic rst;

// ── DUT ports ──
logic [15:0] cfg_img_width, cfg_img_height, cfg_in_channels;
logic [9:0]  cfg_ci_groups, cfg_co_groups;
logic        cfg_use_relu, cfg_use_maxpool;
logic [31:0] cfg_quant_M;
logic [4:0]  cfg_quant_n;

logic        weight_wr_mode, weight_wr_valid;
logic [71:0] weight_wr_data;
logic        weight_wr_done;

logic        bias_wr_mode, bias_wr_valid;
logic [31:0] bias_wr_data;
logic        bias_wr_done;

logic [63:0] pixel_in;
logic        pixel_valid;
logic        pixel_ready;

logic [63:0] data_out;
logic        data_valid_out;
logic        layer_done;

// ── DUT ──
conv_layer #(
    .WEIGHT_DEPTH  (4096),
    .MAX_CI_GROUPS (128)
) DUT (
    .clk             (clk),
    .rst             (rst),
    .cfg_img_width   (cfg_img_width),
    .cfg_img_height  (cfg_img_height),
    .cfg_in_channels (cfg_in_channels),
    .cfg_ci_groups   (cfg_ci_groups),
    .cfg_co_groups   (cfg_co_groups),
    .cfg_use_relu    (cfg_use_relu),
    .cfg_use_maxpool (cfg_use_maxpool),
    .cfg_quant_M     (cfg_quant_M),
    .cfg_quant_n     (cfg_quant_n),
    .weight_wr_mode  (weight_wr_mode),
    .weight_wr_valid (weight_wr_valid),
    .weight_wr_data  (weight_wr_data),
    .weight_wr_done  (weight_wr_done),
    .bias_wr_mode    (bias_wr_mode),
    .bias_wr_valid   (bias_wr_valid),
    .bias_wr_data    (bias_wr_data),
    .bias_wr_done    (bias_wr_done),
    .pixel_in        (pixel_in),
    .pixel_valid     (pixel_valid),
    .pixel_ready     (pixel_ready),
    .data_out        (data_out),
    .data_valid_out  (data_valid_out),
    .layer_done      (layer_done)
);

// ── Static config ──
initial begin
    cfg_img_width   = PAD_W;
    cfg_img_height  = PAD_H;
    cfg_in_channels = C_IN;
    cfg_ci_groups   = CI_GROUPS;
    cfg_co_groups   = CO_GROUPS;
    cfg_use_relu    = 1;
    cfg_use_maxpool = 0;
    cfg_quant_M     = 32'd1;
    cfg_quant_n     = 5'd3;         // divide by 8
end

// ── Pixel data (pre-built padded image) ──
localparam TOTAL_VECTORS = PAD_H * PAD_W * CI_GROUPS;
logic [63:0] pixel_data [0:TOTAL_VECTORS-1];

initial begin
    for (int r = 0; r < PAD_H; r++)
        for (int c = 0; c < PAD_W; c++)
            for (int g = 0; g < CI_GROUPS; g++) begin
                int idx = (r * PAD_W + c) * CI_GROUPS + g;
                if (r >= 1 && r <= IMG_H && c >= 1 && c <= IMG_W)
                    pixel_data[idx] = {8{PIXEL_VAL}};
                else
                    pixel_data[idx] = 64'd0;
            end
end

// ── Reference helpers ──

// Count non-zero neighbours in 3×3 window centred at (cr,cc) in padded frame
function automatic int ref_pixel_sum(int cr, int cc);
    int count = 0;
    for (int dr = -1; dr <= 1; dr++)
        for (int dc = -1; dc <= 1; dc++) begin
            int r = cr + dr;
            int c = cc + dc;
            if (r >= 1 && r <= IMG_H && c >= 1 && c <= IMG_W)
                count++;
        end
    return count;
endfunction

// Quantize: multiply by M, arithmetic-shift-right by n, leaky-ReLU, clamp
function automatic logic [7:0] ref_quant(int conv_sum);
    int shifted = conv_sum >>> 3;
    int relu;
    if (shifted >= 0) relu = shifted;
    else              relu = shifted >>> 3;
    if      (relu >  127) return 8'd127;
    else if (relu < -128) return -8'sd128;
    else                  return relu[7:0];
endfunction

// ── Output monitor ──
int out_count  = 0;
int pass_count = 0;
int fail_count = 0;

always @(posedge clk) begin
    if (!rst && data_valid_out) begin
        automatic int spatial_idx = out_count / CO_GROUPS;
        automatic int group_idx   = out_count % CO_GROUPS;
        automatic int input_idx   = spatial_idx + FIRST_VALID;
        automatic int padded_r    = input_idx / PAD_W;
        automatic int padded_c    = input_idx % PAD_W;
        automatic int center_r    = padded_r - 1;
        automatic int center_c    = padded_c - 1;
        automatic int psum        = ref_pixel_sum(center_r, center_c);
        automatic int bias_val    = (group_idx == 0) ? BIAS_G0 : BIAS_G1;
        automatic int conv_sum    = psum * C_IN * PIXEL_VAL + bias_val;
        automatic logic [7:0]  exp_byte = ref_quant(conv_sum);
        automatic logic [63:0] exp_word = {8{exp_byte}};

        if (data_out === exp_word)
            pass_count++;
        else begin
            fail_count++;
            $display("  FAIL [%0d] ctr=(%0d,%0d) grp=%0d psum=%0d exp=%02h got=%016h",
                     out_count, center_r, center_c, group_idx, psum, exp_byte, data_out);
        end
        out_count++;
    end
end

// ── Main sequence ──
initial begin
    $dumpfile("tb_conv_layer.vcd");
    $dumpvars(0, tb_conv_layer);

    rst = 1;
    weight_wr_mode = 0; weight_wr_valid = 0; weight_wr_data = '0;
    bias_wr_mode   = 0; bias_wr_valid   = 0; bias_wr_data   = '0;
    pixel_in       = '0; pixel_valid     = 0;

    repeat (10) @(posedge clk);
    rst = 0;
    repeat (2)  @(posedge clk);

    // ────────── 1. Load weights ──────────
    // Order: for each filter (0..C_OUT-1), for each channel (0..C_IN-1)
    // 72-bit word = 9 spatial × 8-bit weights, all set to +1
    weight_wr_mode = 1;
    for (int f = 0; f < C_OUT; f++) begin
        for (int ch = 0; ch < C_IN; ch++) begin
            @(posedge clk);
            weight_wr_valid <= 1;
            weight_wr_data  <= 72'h01_01_01_01_01_01_01_01_01;
        end
    end
    @(posedge clk);
    weight_wr_valid <= 0;
    wait (weight_wr_done);
    @(posedge clk);
    weight_wr_mode = 0;
    @(posedge clk);

    // ────────── 2. Load biases ──────────
    // Filters 0-7 → 0,  filters 8-15 → 80
    bias_wr_mode = 1;
    for (int f = 0; f < C_OUT; f++) begin
        @(posedge clk);
        bias_wr_valid <= 1;
        bias_wr_data  <= (f < 8) ? 32'd0 : 32'd80;
    end
    @(posedge clk);
    bias_wr_valid <= 0;
    wait (bias_wr_done);
    @(posedge clk);
    bias_wr_mode = 0;
    @(posedge clk);

    // ────────── 3. Stream padded pixels ──────────
    begin
        int pix_idx = 0;
        while (pix_idx < TOTAL_VECTORS) begin
            @(negedge clk);
            pixel_in    = pixel_data[pix_idx];
            pixel_valid = 1;
            @(posedge clk);
            if (pixel_ready)
                pix_idx++;
        end
        @(negedge clk);
        pixel_valid = 0;
    end

    // ────────── 4. Drain pipeline ──────────
    repeat (500) @(posedge clk);

    // ────────── 5. Report ──────────
    $display("──────────────────────────────────────");
    $display(" conv_layer testbench  (%0dx%0d, Cin=%0d, Cout=%0d)", IMG_W, IMG_H, C_IN, C_OUT);
    $display("   Outputs received : %0d / %0d expected", out_count, NUM_OUTPUTS);
    $display("   PASS             : %0d", pass_count);
    $display("   FAIL             : %0d", fail_count);
    if (out_count == NUM_OUTPUTS && fail_count == 0)
        $display(" *** TEST PASSED ***");
    else
        $display(" *** TEST FAILED ***");
    $display("──────────────────────────────────────");
    $finish;
end

// Safety timeout
initial begin
    #200_000;
    $display("TIMEOUT");
    $finish;
end

endmodule
