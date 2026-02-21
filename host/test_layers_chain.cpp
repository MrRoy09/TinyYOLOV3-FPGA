/*
 * test_layers_chain.cpp - Full TinyYOLOv3 Inference (All 13 Layers)
 *
 * Layers 0-5:  Downsampling path with stride-2/1 maxpool
 * Layers 6-9:  Detection head 1 (512→1024→256→512→255)
 * Layers 10-12: Detection head 2 (route+upsample+concat path)
 *
 * Special operations:
 * - Layer 7,9,10,12: 1x1 convolution
 * - Layer 9,12: Linear activation (no ReLU) - detection outputs
 * - Layer 10: Route (uses layer 7 output as input)
 * - Layer 11: Concat (upsample(layer 10) + layer 4 conv output)
 *
 * Build: make test_layers_chain TARGET=hw
 * Run:   ./test_layers_chain <xclbin> [stimulus_dir] [--isolated] [max_layers]
 *
 * Options:
 *   --isolated : Test each layer independently using pre-computed inputs
 *                from the Python golden model (pixels.bin in each layer dir).
 *                Helps isolate whether RTL issues are in a specific layer
 *                vs error propagation from earlier layers.
 *   max_layers : Run only the first N layers (for quick debugging)
 */

#include <iostream>
#include <fstream>
#include <vector>
#include <string>
#include <cstring>
#include <cstdint>
#include <iomanip>
#include <chrono>
#include <cmath>
#include <algorithm>
#include <cctype>

#include "xrt/xrt_device.h"
#include "xrt/xrt_kernel.h"
#include "xrt/xrt_bo.h"
#include "ert.h"

struct LayerConfig {
    int hw_layer;
    int cin, cout;
    int cin_pad;
    int ci_groups, co_groups;
    int img_h, img_w;        // Before padding
    int padded_h, padded_w;  // After padding (for 3x3: +2, for 1x1: same)
    int out_h, out_w;        // After conv + maxpool
    int maxpool_stride;      // 0=none, 1=stride-1, 2=stride-2
    uint32_t quant_m;
    uint32_t quant_n;
    int kernel_1x1;          // 1 for 1x1 conv, 0 for 3x3
    int use_relu;            // 1 for leaky relu, 0 for linear (detection heads)
};

// Layer configurations from hardware_sim.py
const LayerConfig LAYERS[] = {
    // hw_layer, cin, cout, cin_pad, ci_groups, co_groups, img_h, img_w, padded_h, padded_w, out_h, out_w, mp_stride, M, n, kernel_1x1, use_relu
    // Downsampling path (layers 0-5)
    {0,   3,   16,    8,   1,   2, 416, 416, 418, 418, 208, 208, 2, 0x000000C0, 16, 0, 1},
    {1,  16,   32,   16,   2,   4, 208, 208, 210, 210, 104, 104, 2, 0x000002BC, 16, 0, 1},
    {2,  32,   64,   32,   4,   8, 104, 104, 106, 106,  52,  52, 2, 0x000003CA, 16, 0, 1},
    {3,  64,  128,   64,   8,  16,  52,  52,  54,  54,  26,  26, 2, 0x0000022B, 16, 0, 1},
    {4, 128,  256,  128,  16,  32,  26,  26,  28,  28,  13,  13, 2, 0x00000230, 16, 0, 1},
    {5, 256,  512,  256,  32,  64,  13,  13,  15,  15,  13,  13, 1, 0x00000173, 16, 0, 1},  // stride-1 maxpool

    // Detection head 1 (layers 6-9)
    {6,  512, 1024,  512,  64, 128,  13,  13,  15,  15,  13,  13, 0, 0x0000014E, 16, 0, 1},  // 3x3, no maxpool
    {7, 1024,  256, 1024, 128,  32,  13,  13,  13,  13,  13,  13, 0, 0x000003BD, 16, 1, 1},  // 1x1 conv
    {8,  256,  512,  256,  32,  64,  13,  13,  15,  15,  13,  13, 0, 0x000000B7, 16, 0, 1},  // 3x3
    {9,  512,  255,  512,  64,  32,  13,  13,  13,  13,  13,  13, 0, 0x00000107, 16, 1, 0},  // 1x1, LINEAR (detection)

    // Detection head 2 (layers 10-12)
    {10, 256,  128,  256,  32,  16,  13,  13,  13,  13,  13,  13, 0, 0x0000047B, 16, 1, 1},  // 1x1 (input from route/layer 7)
    {11, 384,  256,  384,  48,  32,  26,  26,  28,  28,  26,  26, 0, 0x000000A3, 16, 0, 1},  // 3x3 (concat input)
    {12, 256,  255,  256,  32,  32,  26,  26,  26,  26,  26,  26, 0, 0x000000B6, 16, 1, 0},  // 1x1, LINEAR (detection)
};
const int NUM_LAYERS = sizeof(LAYERS) / sizeof(LAYERS[0]);

std::string g_stimulus_dir = "scripts/stimulus_full";
int g_max_layers = 0;              // Run all layers by default
bool g_stop_on_mismatch = false;   // Stop on first layer with mismatches
bool g_isolated_mode = false;      // Test each layer with known-good inputs from stimulus
bool g_no_batch = false;           // Disable batching: process 1 OG per kernel call

std::vector<uint8_t> read_binary_file(const std::string& path) {
    std::ifstream file(path, std::ios::binary | std::ios::ate);
    if (!file.is_open()) {
        throw std::runtime_error("Cannot open file: " + path);
    }
    size_t size = file.tellg();
    file.seekg(0, std::ios::beg);
    std::vector<uint8_t> data(size);
    file.read(reinterpret_cast<char*>(data.data()), size);
    return data;
}

void pad_spatial(const std::vector<uint8_t>& input, int h, int w, int c,
                 std::vector<uint8_t>& output) {
    // Add 1-pixel zero border
    int padded_h = h + 2;
    int padded_w = w + 2;
    output.resize(padded_h * padded_w * c, 0);

    for (int y = 0; y < h; y++) {
        for (int x = 0; x < w; x++) {
            for (int ch = 0; ch < c; ch++) {
                int src_idx = (y * w + x) * c + ch;
                int dst_idx = ((y + 1) * padded_w + (x + 1)) * c + ch;
                output[dst_idx] = input[src_idx];
            }
        }
    }
}

// Pad spatial dimensions for stride-1 maxpool
// The RTL uses backward-looking maxpool: output[r][c] = max(input[r-1:r+1, c-1:c+1])
// Python golden uses forward-looking: output[r][c] = max(input[r:r+2, c:c+2]) with padding
// To match: RTL skips row 0/col 0, so we pad conv input to produce (H+1)x(W+1) conv output
// Then maxpool outputs HxH which matches Python forward-looking on HxH input
void pad_spatial_stride1(const std::vector<uint8_t>& input, int h, int w, int c,
                         std::vector<uint8_t>& output) {
    // For stride-1 maxpool:
    // - Pad input to (H+3)x(W+3): +1 for extra row/col, +2 for 3x3 conv padding
    // - Conv produces (H+1)x(W+1) output
    // - Maxpool skips row 0/col 0, producing HxH output
    int padded_h = h + 3;
    int padded_w = w + 3;
    output.resize(padded_h * padded_w * c, 0);

    // Copy input to center (offset by 1 for conv padding)
    for (int y = 0; y < h; y++) {
        for (int x = 0; x < w; x++) {
            for (int ch = 0; ch < c; ch++) {
                int src_idx = (y * w + x) * c + ch;
                int dst_idx = ((y + 1) * padded_w + (x + 1)) * c + ch;
                output[dst_idx] = input[src_idx];
            }
        }
    }
}

// CPU stride-2 maxpool for layer 4 (26x26 → 13x13)
void cpu_maxpool_stride2(const uint8_t* input, uint8_t* output, int h, int w, int c) {
    int out_h = h / 2, out_w = w / 2;
    for (int y = 0; y < out_h; y++) {
        for (int x = 0; x < out_w; x++) {
            for (int ch = 0; ch < c; ch++) {
                int8_t v00 = static_cast<int8_t>(input[((y*2  )*w + (x*2  ))*c + ch]);
                int8_t v01 = static_cast<int8_t>(input[((y*2  )*w + (x*2+1))*c + ch]);
                int8_t v10 = static_cast<int8_t>(input[((y*2+1)*w + (x*2  ))*c + ch]);
                int8_t v11 = static_cast<int8_t>(input[((y*2+1)*w + (x*2+1))*c + ch]);
                int8_t max_val = v00;
                if (v01 > max_val) max_val = v01;
                if (v10 > max_val) max_val = v10;
                if (v11 > max_val) max_val = v11;
                output[(y * out_w + x) * c + ch] = static_cast<uint8_t>(max_val);
            }
        }
    }
}

// CPU 2x nearest-neighbor upsample (13x13 → 26x26)
void cpu_upsample_2x(const uint8_t* input, uint8_t* output, int h, int w, int c) {
    for (int y = 0; y < h; y++) {
        for (int x = 0; x < w; x++) {
            for (int ch = 0; ch < c; ch++) {
                uint8_t val = input[(y * w + x) * c + ch];
                // Duplicate to 2x2 block in output
                output[((y*2  ) * (w*2) + (x*2  )) * c + ch] = val;
                output[((y*2  ) * (w*2) + (x*2+1)) * c + ch] = val;
                output[((y*2+1) * (w*2) + (x*2  )) * c + ch] = val;
                output[((y*2+1) * (w*2) + (x*2+1)) * c + ch] = val;
            }
        }
    }
}

// CPU channel concatenation: A (HxWxCA) + B (HxWxCB) → Output (HxWx(CA+CB))
void cpu_concat_channels(const uint8_t* a, int ca,
                         const uint8_t* b, int cb,
                         uint8_t* output, int h, int w) {
    int c_out = ca + cb;
    for (int y = 0; y < h; y++) {
        for (int x = 0; x < w; x++) {
            // Copy channels from A
            for (int ch = 0; ch < ca; ch++) {
                output[(y * w + x) * c_out + ch] = a[(y * w + x) * ca + ch];
            }
            // Copy channels from B
            for (int ch = 0; ch < cb; ch++) {
                output[(y * w + x) * c_out + ca + ch] = b[(y * w + x) * cb + ch];
            }
        }
    }
}

int compare_outputs(const uint8_t* actual, const uint8_t* expected, size_t size,
                    int tolerance, const std::string& label, bool verbose = false) {
    int mismatches = 0;
    int close_matches = 0;
    int max_diff = 0;
    int printed = 0;

    for (size_t i = 0; i < size; i++) {
        int8_t act = static_cast<int8_t>(actual[i]);
        int8_t exp = static_cast<int8_t>(expected[i]);
        int diff = std::abs(static_cast<int>(act) - static_cast<int>(exp));

        max_diff = std::max(max_diff, diff);

        if (diff == 0) {
            // Exact match
        } else if (diff <= tolerance) {
            close_matches++;
        } else {
            mismatches++;
            if (verbose && printed < 5) {
                std::cout << "    MISMATCH [" << i << "]: exp=" << static_cast<int>(exp)
                          << " act=" << static_cast<int>(act) << " diff=" << diff << std::endl;
                printed++;
            }
        }
    }

    size_t exact = size - mismatches - close_matches;
    std::cout << label << ": exact=" << exact << "/" << size
              << " (" << std::fixed << std::setprecision(1) << (100.0 * exact / size) << "%)"
              << ", within_tol=" << close_matches
              << ", mismatch=" << mismatches
              << ", max_diff=" << max_diff << std::endl;

    return mismatches;
}

int run_layer(xrt::device& device, xrt::kernel& kernel, const LayerConfig& cfg,
              const std::vector<uint8_t>& pixels,
              std::vector<uint8_t>& layer_output,
              const std::string& layer_dir) {

    std::cout << "\n========================================" << std::endl;
    std::cout << " Layer " << cfg.hw_layer << ": " << cfg.cin << "→" << cfg.cout
              << ", " << cfg.img_h << "→" << cfg.out_h
              << (cfg.kernel_1x1 ? " [1x1]" : " [3x3]")
              << (cfg.use_relu ? "" : " [LINEAR]") << std::endl;
    std::cout << "========================================" << std::endl;
    std::cout << "  ci_groups=" << cfg.ci_groups << ", co_groups=" << cfg.co_groups << std::endl;
    std::cout << "  M=0x" << std::hex << cfg.quant_m << std::dec << ", n=" << cfg.quant_n << std::endl;

    // =========================================================================
    // Multi-OG Batching: Process multiple OGs in single kernel invocation
    // URAM depth = 4096. Each OG needs ci_groups addresses.
    // max_og_per_chunk = 4096 / ci_groups
    // With --no-batch flag: force 1 OG per kernel call (for debugging)
    // =========================================================================
    int max_og_per_chunk = g_no_batch ? 1 : (4096 / cfg.ci_groups);
    int num_chunks = (cfg.co_groups + max_og_per_chunk - 1) / max_og_per_chunk;

    std::cout << "  BATCHING: max_og_per_chunk=" << max_og_per_chunk
              << ", num_chunks=" << num_chunks << std::endl;

    // Maxpool handling:
    // - stride=0: no maxpool, HW output = cfg.out_h
    // - stride=1: HW maxpool with backward-looking (skip row 0/col 0)
    // - stride=2: HW maxpool, output = input/2
    int hw_out_h = cfg.out_h;
    int hw_out_w = cfg.out_w;

    if (cfg.maxpool_stride == 1) {
        std::cout << "  NOTE: HW stride-1 maxpool (conv produces " << (cfg.out_h + 1) << "x" << (cfg.out_w + 1) << ")" << std::endl;
    } else if (cfg.maxpool_stride == 0) {
        std::cout << "  NOTE: No maxpool (conv only)" << std::endl;
    }

    // Calculate per-OG sizes
    int actual_padded_h = (cfg.maxpool_stride == 1) ? (cfg.out_h + 3) : cfg.padded_h;
    int actual_padded_w = (cfg.maxpool_stride == 1) ? (cfg.out_w + 3) : cfg.padded_w;
    size_t pixel_bytes = actual_padded_h * actual_padded_w * cfg.cin_pad;
    size_t output_bytes_per_og = hw_out_h * hw_out_w * 8;
    size_t weight_bytes_per_og = cfg.ci_groups * 8 * 8 * 16;  // ci_groups * 8 banks * 8 urams * 16 bytes
    size_t bias_bytes_per_og = 16;  // 8 channels * 4 bytes (only first 16B used, but file may be larger)

    // Allocate buffers for max chunk size (all OGs in chunk packed contiguously)
    int chunk_size = std::min(max_og_per_chunk, cfg.co_groups);
    size_t total_weight_bytes = chunk_size * weight_bytes_per_og;
    size_t total_bias_bytes = chunk_size * 32;  // 32 bytes per OG for bias (2 x 128-bit words)
    size_t total_output_bytes = chunk_size * output_bytes_per_og;

    size_t weight_buf_size = ((total_weight_bytes + 4095) / 4096) * 4096;
    size_t bias_buf_size = ((total_bias_bytes + 4095) / 4096) * 4096;
    size_t pixel_buf_size = ((pixel_bytes + 4095) / 4096) * 4096;
    size_t output_buf_size = ((total_output_bytes + 4095) / 4096) * 4096;

    xrt::bo weight_bo(device, weight_buf_size, kernel.group_id(19));
    xrt::bo bias_bo(device, bias_buf_size, kernel.group_id(20));
    xrt::bo pixel_bo(device, pixel_buf_size, kernel.group_id(21));
    xrt::bo output_bo(device, output_buf_size, kernel.group_id(22));

    auto weight_ptr = weight_bo.map<uint8_t*>();
    auto bias_ptr = bias_bo.map<uint8_t*>();
    auto pixel_ptr = pixel_bo.map<uint8_t*>();
    auto output_ptr = output_bo.map<uint8_t*>();

    // Copy pixels (same for all OGs - pixels are re-read from DDR for each OG)
    std::memset(pixel_ptr, 0, pixel_buf_size);
    std::memcpy(pixel_ptr, pixels.data(), std::min(pixels.size(), pixel_buf_size));
    pixel_bo.sync(XCL_BO_SYNC_BO_TO_DEVICE);

    // Prepare output buffer
    layer_output.resize(cfg.out_h * cfg.out_w * cfg.cout);
    int total_mismatches = 0;

    auto layer_start = std::chrono::high_resolution_clock::now();

    // Process chunks (most layers have only 1 chunk)
    for (int chunk = 0; chunk < num_chunks; chunk++) {
        int chunk_start_og = chunk * max_og_per_chunk;
        int ogs_in_chunk = std::min(max_og_per_chunk, cfg.co_groups - chunk_start_og);

        std::cout << "  Chunk " << chunk << ": OGs " << chunk_start_og
                  << "-" << (chunk_start_og + ogs_in_chunk - 1) << std::endl;

        // Pack all OG weights and biases into contiguous buffers
        std::memset(weight_ptr, 0, weight_buf_size);
        std::memset(bias_ptr, 0, bias_buf_size);
        std::memset(output_ptr, 0, output_buf_size);

        for (int og_in_chunk = 0; og_in_chunk < ogs_in_chunk; og_in_chunk++) {
            int global_og = chunk_start_og + og_in_chunk;

            // Load and pack weights
            std::string weights_path = layer_dir + "/weights_og" + std::to_string(global_og) + ".bin";
            auto weights = read_binary_file(weights_path);
            std::memcpy(weight_ptr + og_in_chunk * weight_bytes_per_og,
                       weights.data(),
                       std::min(weights.size(), weight_bytes_per_og));

            // Load and pack biases
            std::string biases_path = layer_dir + "/biases_og" + std::to_string(global_og) + ".bin";
            auto biases = read_binary_file(biases_path);
            // Bias layout: 32 bytes per OG (2 x 128-bit AXI beats)
            std::memcpy(bias_ptr + og_in_chunk * 32,
                       biases.data(),
                       std::min(biases.size(), static_cast<size_t>(32)));
        }

        // Sync packed data to device
        weight_bo.sync(XCL_BO_SYNC_BO_TO_DEVICE);
        bias_bo.sync(XCL_BO_SYNC_BO_TO_DEVICE);
        output_bo.sync(XCL_BO_SYNC_BO_TO_DEVICE);

        // Configure kernel for batched execution
        xrt::run run(kernel);
        run.set_arg(0, weight_bo.address());
        run.set_arg(1, bias_bo.address());
        run.set_arg(2, pixel_bo.address());
        run.set_arg(3, output_bo.address());

        // Per-OG sizes (RTL uses these as strides for address calculation)
        run.set_arg(4, static_cast<uint32_t>(weight_bytes_per_og));  // Bytes per OG for weights
        run.set_arg(5, static_cast<uint32_t>(32));                   // Bytes per OG for biases (32B aligned)
        run.set_arg(6, static_cast<uint32_t>(pixel_bytes));          // Total pixel bytes (same for all OGs)
        run.set_arg(7, static_cast<uint32_t>(output_bytes_per_og));  // Bytes per OG for output

        run.set_arg(8, static_cast<uint32_t>(cfg.ci_groups));
        // cfg_co_groups now means "number of OGs to process" (batched mode)
        run.set_arg(9, static_cast<uint32_t>(ogs_in_chunk));
        run.set_arg(10, static_cast<uint32_t>(0));  // wt_base_addr always 0
        run.set_arg(11, static_cast<uint32_t>(cfg.cin_pad));
        run.set_arg(12, static_cast<uint32_t>(actual_padded_w));

        // Maxpool config
        bool enable_hw_maxpool = (cfg.maxpool_stride != 0);
        run.set_arg(13, static_cast<uint32_t>(enable_hw_maxpool ? 1 : 0));
        run.set_arg(14, static_cast<uint32_t>(cfg.maxpool_stride == 2 ? 1 : 0));
        run.set_arg(15, cfg.quant_m);
        run.set_arg(16, cfg.quant_n);
        run.set_arg(17, static_cast<uint32_t>(cfg.use_relu));
        run.set_arg(18, static_cast<uint32_t>(cfg.kernel_1x1));

        run.set_arg(19, weight_bo);
        run.set_arg(20, bias_bo);
        run.set_arg(21, pixel_bo);
        run.set_arg(22, output_bo);

        // Execute single kernel call for all OGs in chunk
        run.start();
        auto state = run.wait(std::chrono::seconds(300));  // Longer timeout for batched ops

        if (state == ERT_CMD_STATE_TIMEOUT) {
            std::cerr << "TIMEOUT on layer " << cfg.hw_layer << " chunk " << chunk << std::endl;
            return -1;
        }

        // Sync all outputs at once
        output_bo.sync(XCL_BO_SYNC_BO_FROM_DEVICE);

        // Unpack outputs and verify each OG
        for (int og_in_chunk = 0; og_in_chunk < ogs_in_chunk; og_in_chunk++) {
            int global_og = chunk_start_og + og_in_chunk;
            const uint8_t* og_output_ptr = output_ptr + og_in_chunk * output_bytes_per_og;

            // Store in layer output (interleaved by output group)
            int valid_channels = std::min(8, cfg.cout - global_og * 8);
            for (int y = 0; y < cfg.out_h; y++) {
                for (int x = 0; x < cfg.out_w; x++) {
                    for (int ch = 0; ch < valid_channels; ch++) {
                        int src_idx = (y * cfg.out_w + x) * 8 + ch;
                        int dst_idx = (y * cfg.out_w + x) * cfg.cout + global_og * 8 + ch;
                        layer_output[dst_idx] = og_output_ptr[src_idx];
                    }
                }
            }

            // Compare with expected
            std::string expected_path = layer_dir + "/expected_og" + std::to_string(global_og) + ".bin";
            auto expected = read_binary_file(expected_path);

            // Enable verbose debug for layers 2+ to diagnose mismatch issues
            // Print first 2 OGs for each layer >= 2
            bool verbose_debug = (cfg.hw_layer >= 2 && global_og <= 1);
            int mismatches = compare_outputs(og_output_ptr, expected.data(),
                                            output_bytes_per_og, 3,
                                            "  OG" + std::to_string(global_og), verbose_debug);

            // Always print detailed comparison for layers 2-5, first 2 OGs
            if (cfg.hw_layer >= 2 && cfg.hw_layer <= 5 && global_og <= 1) {
                std::cout << "    === DETAILED DEBUG Layer " << cfg.hw_layer << " OG" << global_og << " ===" << std::endl;

                // Print first 32 values (4 pixels x 8 channels)
                std::cout << "    First 32 actual:   ";
                for (int k = 0; k < 32 && k < (int)output_bytes_per_og; k++) {
                    std::cout << std::setw(4) << static_cast<int>(static_cast<int8_t>(og_output_ptr[k])) << " ";
                    if ((k + 1) % 8 == 0) std::cout << "| ";
                }
                std::cout << std::endl;
                std::cout << "    First 32 expected: ";
                for (int k = 0; k < 32 && k < (int)expected.size(); k++) {
                    std::cout << std::setw(4) << static_cast<int>(static_cast<int8_t>(expected[k])) << " ";
                    if ((k + 1) % 8 == 0) std::cout << "| ";
                }
                std::cout << std::endl;

                // Calculate and print per-pixel difference
                std::cout << "    Diff (act-exp):    ";
                for (int k = 0; k < 32 && k < (int)output_bytes_per_og && k < (int)expected.size(); k++) {
                    int diff = static_cast<int>(static_cast<int8_t>(og_output_ptr[k])) -
                               static_cast<int>(static_cast<int8_t>(expected[k]));
                    std::cout << std::setw(4) << diff << " ";
                    if ((k + 1) % 8 == 0) std::cout << "| ";
                }
                std::cout << std::endl;

                // Print some values from middle of output to check pattern
                size_t mid = output_bytes_per_og / 2;
                if (mid + 16 <= output_bytes_per_og && mid + 16 <= expected.size()) {
                    std::cout << "    Mid-16 actual:     ";
                    for (int k = 0; k < 16; k++) {
                        std::cout << std::setw(4) << static_cast<int>(static_cast<int8_t>(og_output_ptr[mid + k])) << " ";
                        if ((k + 1) % 8 == 0) std::cout << "| ";
                    }
                    std::cout << std::endl;
                    std::cout << "    Mid-16 expected:   ";
                    for (int k = 0; k < 16; k++) {
                        std::cout << std::setw(4) << static_cast<int>(static_cast<int8_t>(expected[mid + k])) << " ";
                        if ((k + 1) % 8 == 0) std::cout << "| ";
                    }
                    std::cout << std::endl;
                }
            }
            total_mismatches += mismatches;
        }
    }

    auto layer_end = std::chrono::high_resolution_clock::now();
    auto layer_ms = std::chrono::duration_cast<std::chrono::milliseconds>(layer_end - layer_start).count();

    std::cout << "  Layer " << cfg.hw_layer << " total: " << cfg.co_groups << " OGs in "
              << layer_ms << " ms (" << num_chunks << " kernel calls), mismatches=" << total_mismatches << std::endl;

    return total_mismatches;
}

int main(int argc, char* argv[]) {
    if (argc < 2) {
        std::cerr << "Usage: " << argv[0] << " <xclbin_file> [stimulus_dir] [options] [max_layers]" << std::endl;
        std::cerr << "Options:" << std::endl;
        std::cerr << "  --isolated : Test each layer independently with pre-computed inputs" << std::endl;
        std::cerr << "  --no-batch : Disable multi-OG batching (1 OG per kernel call)" << std::endl;
        std::cerr << "  max_layers : Run only first N layers (for debugging)" << std::endl;
        return 1;
    }

    std::string xclbin_file = argv[1];

    // Parse arguments
    for (int i = 2; i < argc; i++) {
        std::string arg = argv[i];
        if (arg == "--isolated" || arg == "-i") {
            g_isolated_mode = true;
        } else if (arg == "--no-batch") {
            g_no_batch = true;
        } else if (arg[0] != '-') {
            // Check if it's a number (max_layers) or a path (stimulus_dir)
            if (std::isdigit(arg[0])) {
                g_max_layers = std::stoi(arg);
            } else {
                g_stimulus_dir = arg;
            }
        }
    }

    std::cout << "========================================" << std::endl;
    if (g_isolated_mode) {
        std::cout << " TinyYOLOv3 ISOLATED Layer Tests" << std::endl;
        std::cout << " (Each layer uses pre-computed inputs)" << std::endl;
    } else {
        std::cout << " TinyYOLOv3 Full Inference (13 Layers)" << std::endl;
    }
    std::cout << "========================================" << std::endl;
    std::cout << "XCLBIN: " << xclbin_file << std::endl;
    std::cout << "Stimulus: " << g_stimulus_dir << std::endl;
    if (g_max_layers > 0) {
        std::cout << "Max layers: " << g_max_layers << std::endl;
    }
    if (g_no_batch) {
        std::cout << "NO-BATCH MODE: 1 OG per kernel call (disables multi-OG batching)" << std::endl;
    }

    try {
        // Initialize XRT
        std::cout << "\nInitializing XRT device..." << std::endl;
        xrt::device device(0);
        std::cout << "  Device: " << device.get_info<xrt::info::device::name>() << std::endl;

        auto uuid = device.load_xclbin(xclbin_file);
        xrt::kernel kernel(device, uuid, "TinyYOLOV3_HW_Complete");
        std::cout << "  Kernel loaded" << std::endl;

        int total_mismatches = 0;
        auto total_start = std::chrono::high_resolution_clock::now();

        // Storage for layer outputs
        std::vector<uint8_t> layer_output;
        std::vector<uint8_t> padded_input;

        // Saved intermediate outputs for routing/concat
        std::vector<uint8_t> layer4_conv_output;  // 26x26x256 (before maxpool, for concat)
        std::vector<uint8_t> layer7_output;       // 13x13x256 (for route to layer 10)

        // Track per-layer results for summary
        std::vector<int> layer_mismatches(NUM_LAYERS, -1);  // -1 = not run

        int layers_to_run = (g_max_layers > 0) ? std::min(g_max_layers, NUM_LAYERS) : NUM_LAYERS;
        for (int i = 0; i < layers_to_run; i++) {
            const LayerConfig& cfg = LAYERS[i];
            std::string layer_dir = g_stimulus_dir + "/layer" + std::to_string(i);
            std::vector<uint8_t> pixels;

            if (g_isolated_mode) {
                // ISOLATED MODE: Load pre-computed inputs from stimulus file
                // This tests each layer with known-good inputs (from Python golden model)
                std::cout << "  [ISOLATED] Loading pixels from stimulus" << std::endl;
                pixels = read_binary_file(layer_dir + "/pixels.bin");
            }
            else if (i == 0) {
                // Layer 0: Load from image file (already padded in stimulus)
                pixels = read_binary_file(layer_dir + "/pixels.bin");
            }
            else if (i == 10) {
                // Layer 10: Input from saved layer 7 output (ROUTE operation)
                // 1x1 conv, no spatial padding needed
                std::cout << "  [ROUTE] Using saved Layer 7 output as input" << std::endl;
                pixels = layer7_output;
            }
            else if (i == 11) {
                // Layer 11: Upsample layer 10 output + concat with layer 4 saved
                std::cout << "  [UPSAMPLE] Layer 10 output: 13x13x128 → 26x26x128" << std::endl;
                std::vector<uint8_t> upsampled(26 * 26 * 128);
                cpu_upsample_2x(layer_output.data(), upsampled.data(), 13, 13, 128);

                std::cout << "  [CONCAT] Upsampled (128ch) + Layer4 saved (256ch) → 384ch" << std::endl;
                std::vector<uint8_t> concat_out(26 * 26 * 384);
                cpu_concat_channels(upsampled.data(), 128,
                                   layer4_conv_output.data(), 256,
                                   concat_out.data(), 26, 26);

                // Pad for 3x3 conv (26x26 → 28x28)
                pad_spatial(concat_out, 26, 26, 384, pixels);
            }
            else {
                // Normal sequential chaining: pad previous layer output
                int prev_h = LAYERS[i-1].out_h;
                int prev_w = LAYERS[i-1].out_w;
                int prev_c = LAYERS[i-1].cout;

                // For 1x1 conv, no spatial padding needed
                if (cfg.kernel_1x1) {
                    pixels = layer_output;
                } else if (cfg.maxpool_stride == 1) {
                    // Stride-1 maxpool: pad to (H+3)x(W+3) for (H+1)x(W+1) conv output
                    pad_spatial_stride1(layer_output, prev_h, prev_w, prev_c, pixels);
                } else {
                    // Normal 3x3 conv padding: (H+2)x(W+2)
                    pad_spatial(layer_output, prev_h, prev_w, prev_c, pixels);
                }
            }

            // Run layer
            int mismatches = run_layer(device, kernel, cfg, pixels, layer_output, layer_dir);
            if (mismatches < 0) {
                std::cerr << "Layer " << i << " failed!" << std::endl;
                return 1;
            }
            total_mismatches += mismatches;
            layer_mismatches[i] = mismatches;

            // Optional: stop on first layer with significant mismatches
            if (g_stop_on_mismatch && mismatches > 0) {
                std::cout << "\n*** STOPPING: Layer " << i << " has " << mismatches << " mismatches ***" << std::endl;
                break;
            }

            // Save intermediate outputs for routing/concat (only in chained mode)
            if (!g_isolated_mode) {
                if (i == 4) {
                    // Save layer 4 conv output BEFORE maxpool (already done by HW)
                    // But HW applies maxpool, so we need the pre-maxpool output
                    // Actually, the current HW outputs 13x13 with maxpool.
                    // We need to run layer 4 without maxpool to get 26x26 output.
                    // For now, load from stimulus file as a workaround.
                    std::string layer4_conv_path = g_stimulus_dir + "/layer4_conv.bin";
                    std::ifstream test_file(layer4_conv_path);
                    if (test_file.good()) {
                        test_file.close();
                        layer4_conv_output = read_binary_file(layer4_conv_path);
                        std::cout << "  [SAVE] Loaded Layer 4 conv output (26x26x256) from file" << std::endl;
                    } else {
                        // Fallback: use layer 4 expected conv output from stimulus
                        // This is model.layer_outputs[8] in hardware_sim.py (NPZ 8, before maxpool)
                        std::cout << "  [WARN] Layer 4 conv output file not found, using stimulus expected" << std::endl;
                        // Load all expected_og files and reconstruct
                        layer4_conv_output.resize(26 * 26 * 256);
                        // For now, we'll generate this file separately
                    }
                }
                if (i == 7) {
                    // Save layer 7 output (13x13x256) for route to layer 10
                    layer7_output = layer_output;
                    std::cout << "  [SAVE] Layer 7 output (13x13x256) for route" << std::endl;
                }
            }
        }

        auto total_end = std::chrono::high_resolution_clock::now();
        auto total_ms = std::chrono::duration_cast<std::chrono::milliseconds>(total_end - total_start).count();

        // Summary
        std::cout << "\n========================================" << std::endl;
        if (g_isolated_mode) {
            std::cout << " ISOLATED LAYER TEST SUMMARY" << std::endl;
        } else {
            std::cout << " CHAIN TEST SUMMARY" << std::endl;
        }
        std::cout << "========================================" << std::endl;

        // Print per-layer results table
        std::cout << "\n Layer |   Config      | Mismatches | Status" << std::endl;
        std::cout << "-------+---------------+------------+--------" << std::endl;
        int passed = 0, failed = 0;
        for (int i = 0; i < layers_to_run; i++) {
            const LayerConfig& cfg = LAYERS[i];
            std::string config = std::to_string(cfg.cin) + "→" + std::to_string(cfg.cout);
            config += cfg.kernel_1x1 ? " 1x1" : " 3x3";

            std::cout << "   " << std::setw(2) << i << "  | " << std::setw(13) << std::left << config << std::right << " | ";
            if (layer_mismatches[i] < 0) {
                std::cout << std::setw(10) << "N/A" << " | SKIP" << std::endl;
            } else if (layer_mismatches[i] == 0) {
                std::cout << std::setw(10) << "0" << " | PASS" << std::endl;
                passed++;
            } else {
                std::cout << std::setw(10) << layer_mismatches[i] << " | FAIL" << std::endl;
                failed++;
            }
        }
        std::cout << "-------+---------------+------------+--------" << std::endl;
        std::cout << "\nTotal time: " << total_ms << " ms" << std::endl;
        std::cout << "Passed: " << passed << "/" << layers_to_run << ", Failed: " << failed << std::endl;
        std::cout << "Total mismatches: " << total_mismatches << std::endl;

        if (total_mismatches == 0) {
            std::cout << "\n*** ALL LAYERS PASSED ***" << std::endl;
            return 0;
        } else {
            if (g_isolated_mode) {
                std::cout << "\n*** ISOLATED TEST FAILED ***" << std::endl;
                std::cout << "Layers with errors have RTL issues (inputs were golden)" << std::endl;
            } else {
                std::cout << "\n*** CHAIN TEST FAILED ***" << std::endl;
                std::cout << "Run with --isolated to check if errors are RTL or propagation" << std::endl;
            }
            return 1;
        }

    } catch (const std::exception& e) {
        std::cerr << "Error: " << e.what() << std::endl;
        return 1;
    }

    return 0;
}
