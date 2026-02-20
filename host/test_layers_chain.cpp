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
 * Run:   ./test_layers_chain <xclbin_file> [stimulus_dir]
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

// CPU stride-1 maxpool matching hardware_sim.py golden model
// Pads right and bottom with -128, maintains spatial size
void cpu_maxpool_stride1(const uint8_t* input, uint8_t* output, int h, int w, int c) {
    // For each output position, compute 2x2 max
    // Edge handling: treat out-of-bounds as -128
    for (int y = 0; y < h; y++) {
        for (int x = 0; x < w; x++) {
            for (int ch = 0; ch < c; ch++) {
                int8_t vals[4];

                // Get 2x2 window values, -128 for out-of-bounds
                vals[0] = static_cast<int8_t>(input[(y * w + x) * c + ch]);
                vals[1] = (x + 1 < w) ? static_cast<int8_t>(input[(y * w + x + 1) * c + ch]) : -128;
                vals[2] = (y + 1 < h) ? static_cast<int8_t>(input[((y + 1) * w + x) * c + ch]) : -128;
                vals[3] = (x + 1 < w && y + 1 < h) ? static_cast<int8_t>(input[((y + 1) * w + x + 1) * c + ch]) : -128;

                // Find max
                int8_t max_val = vals[0];
                for (int i = 1; i < 4; i++) {
                    if (vals[i] > max_val) max_val = vals[i];
                }

                output[(y * w + x) * c + ch] = static_cast<uint8_t>(max_val);
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

    // Note: We load weights per-OG (not per-chunk), so cfg_wt_base_addr is always 0.
    // Each OG's weights fit in ci_groups URAM addresses. Even layer 6 with ci_groups=64
    // only needs 64 addresses per OG, well within the 4096 URAM depth.

    // Maxpool handling:
    // - stride=0: no maxpool, HW output = cfg.out_h
    // - stride=1: CPU maxpool, HW outputs cfg.img_h, then CPU reduces to cfg.out_h
    // - stride=2: HW maxpool, HW output = cfg.out_h
    bool use_cpu_maxpool = (cfg.maxpool_stride == 1);
    int hw_out_h = use_cpu_maxpool ? cfg.img_h : cfg.out_h;
    int hw_out_w = use_cpu_maxpool ? cfg.img_w : cfg.out_w;

    if (use_cpu_maxpool) {
        std::cout << "  NOTE: CPU stride-1 maxpool (HW outputs " << hw_out_h << "x" << hw_out_w << ")" << std::endl;
    } else if (cfg.maxpool_stride == 0) {
        std::cout << "  NOTE: No maxpool (conv only)" << std::endl;
    }

    // Calculate sizes
    size_t pixel_bytes = cfg.padded_h * cfg.padded_w * cfg.cin_pad;
    size_t hw_output_bytes_per_og = hw_out_h * hw_out_w * 8;  // HW output (conv for stride-1)
    size_t final_output_bytes_per_og = cfg.out_h * cfg.out_w * 8;  // Final output (after CPU maxpool if needed)
    size_t weight_bytes_per_og = cfg.ci_groups * 8 * 8 * 16;  // ci_groups * 8 banks * 8 urams * 16 bytes

    // Allocate device buffers
    size_t weight_buf_size = ((weight_bytes_per_og + 4095) / 4096) * 4096;
    size_t bias_buf_size = 4096;
    size_t pixel_buf_size = ((pixel_bytes + 4095) / 4096) * 4096;
    size_t output_buf_size = ((hw_output_bytes_per_og + 4095) / 4096) * 4096;

    // Temp buffer for CPU maxpool
    std::vector<uint8_t> cpu_maxpool_out;

    xrt::bo weight_bo(device, weight_buf_size, kernel.group_id(19));
    xrt::bo bias_bo(device, bias_buf_size, kernel.group_id(20));
    xrt::bo pixel_bo(device, pixel_buf_size, kernel.group_id(21));
    xrt::bo output_bo(device, output_buf_size, kernel.group_id(22));

    auto weight_ptr = weight_bo.map<uint8_t*>();
    auto bias_ptr = bias_bo.map<uint8_t*>();
    auto pixel_ptr = pixel_bo.map<uint8_t*>();
    auto output_ptr = output_bo.map<uint8_t*>();

    // Copy pixels
    std::memset(pixel_ptr, 0, pixel_buf_size);
    std::memcpy(pixel_ptr, pixels.data(), std::min(pixels.size(), pixel_buf_size));
    pixel_bo.sync(XCL_BO_SYNC_BO_TO_DEVICE);

    // Prepare output buffer
    layer_output.resize(cfg.out_h * cfg.out_w * cfg.cout);
    int total_mismatches = 0;

    auto layer_start = std::chrono::high_resolution_clock::now();

    // Process each output group
    for (int og = 0; og < cfg.co_groups; og++) {
        // Load weights
        std::string weights_path = layer_dir + "/weights_og" + std::to_string(og) + ".bin";
        auto weights = read_binary_file(weights_path);

        std::string biases_path = layer_dir + "/biases_og" + std::to_string(og) + ".bin";
        auto biases = read_binary_file(biases_path);

        // Copy to device
        std::memset(weight_ptr, 0, weight_buf_size);
        std::memset(bias_ptr, 0, bias_buf_size);
        std::memset(output_ptr, 0, output_buf_size);

        std::memcpy(weight_ptr, weights.data(), weights.size());
        std::memcpy(bias_ptr, biases.data(), biases.size());

        weight_bo.sync(XCL_BO_SYNC_BO_TO_DEVICE);
        bias_bo.sync(XCL_BO_SYNC_BO_TO_DEVICE);
        output_bo.sync(XCL_BO_SYNC_BO_TO_DEVICE);

        // Configure kernel
        xrt::run run(kernel);
        run.set_arg(0, weight_bo.address());
        run.set_arg(1, bias_bo.address());
        run.set_arg(2, pixel_bo.address());
        run.set_arg(3, output_bo.address());

        run.set_arg(4, static_cast<uint32_t>(weights.size()));
        run.set_arg(5, static_cast<uint32_t>(biases.size()));
        run.set_arg(6, static_cast<uint32_t>(pixel_bytes));
        run.set_arg(7, static_cast<uint32_t>(hw_output_bytes_per_og));  // HW output size

        run.set_arg(8, static_cast<uint32_t>(cfg.ci_groups));
        run.set_arg(9, static_cast<uint32_t>(0));  // CRITICAL: Must be 0 for per-OG bias loading
        run.set_arg(10, static_cast<uint32_t>(0)); // wt_base_addr
        run.set_arg(11, static_cast<uint32_t>(cfg.cin_pad));
        run.set_arg(12, static_cast<uint32_t>(cfg.padded_w));

        // Maxpool config: stride-1 done on CPU, stride-2 in HW, 0=disabled
        bool enable_hw_maxpool = (cfg.maxpool_stride == 2);
        run.set_arg(13, static_cast<uint32_t>(enable_hw_maxpool ? 1 : 0)); // use_maxpool
        run.set_arg(14, static_cast<uint32_t>(cfg.maxpool_stride == 2 ? 1 : 0)); // stride_2
        run.set_arg(15, cfg.quant_m);
        run.set_arg(16, cfg.quant_n);
        run.set_arg(17, static_cast<uint32_t>(cfg.use_relu));     // use_relu from config
        run.set_arg(18, static_cast<uint32_t>(cfg.kernel_1x1));   // kernel_1x1 from config

        run.set_arg(19, weight_bo);
        run.set_arg(20, bias_bo);
        run.set_arg(21, pixel_bo);
        run.set_arg(22, output_bo);

        // Execute
        run.start();
        auto state = run.wait(std::chrono::seconds(120));

        if (state == ERT_CMD_STATE_TIMEOUT) {
            std::cerr << "TIMEOUT on layer " << cfg.hw_layer << " OG " << og << std::endl;
            return -1;
        }

        // Read output
        output_bo.sync(XCL_BO_SYNC_BO_FROM_DEVICE);

        // For stride-1: apply CPU maxpool to match golden model
        const uint8_t* final_output_ptr = output_ptr;
        if (use_cpu_maxpool) {
            cpu_maxpool_out.resize(final_output_bytes_per_og);
            cpu_maxpool_stride1(output_ptr, cpu_maxpool_out.data(), hw_out_h, hw_out_w, 8);
            final_output_ptr = cpu_maxpool_out.data();
        }

        // Store in layer output (interleaved by output group)
        // Handle 255 output channels: last OG has only 7 valid channels
        int valid_channels = std::min(8, cfg.cout - og * 8);
        for (int y = 0; y < cfg.out_h; y++) {
            for (int x = 0; x < cfg.out_w; x++) {
                for (int ch = 0; ch < valid_channels; ch++) {
                    int src_idx = (y * cfg.out_w + x) * 8 + ch;
                    int dst_idx = (y * cfg.out_w + x) * cfg.cout + og * 8 + ch;
                    layer_output[dst_idx] = final_output_ptr[src_idx];
                }
            }
        }

        // Compare with expected
        std::string expected_path = layer_dir + "/expected_og" + std::to_string(og) + ".bin";
        auto expected = read_binary_file(expected_path);

        // Enable verbose for Layer 0 (first 2 OGs) to debug mismatches
        bool verbose_debug = (cfg.hw_layer == 0 && og <= 1);
        int mismatches = compare_outputs(final_output_ptr, expected.data(),
                                        final_output_bytes_per_og, 3,
                                        "  OG" + std::to_string(og), verbose_debug);

        // Print first 16 bytes for debugging Layer 0 OG0
        if (verbose_debug) {
            std::cout << "    First 16 bytes actual:   ";
            for (int k = 0; k < 16; k++) {
                std::cout << std::setw(4) << static_cast<int>(static_cast<int8_t>(final_output_ptr[k])) << " ";
            }
            std::cout << std::endl;
            std::cout << "    First 16 bytes expected: ";
            for (int k = 0; k < 16; k++) {
                std::cout << std::setw(4) << static_cast<int>(static_cast<int8_t>(expected[k])) << " ";
            }
            std::cout << std::endl;
        }
        total_mismatches += mismatches;
    }

    auto layer_end = std::chrono::high_resolution_clock::now();
    auto layer_ms = std::chrono::duration_cast<std::chrono::milliseconds>(layer_end - layer_start).count();

    std::cout << "  Layer " << cfg.hw_layer << " total: " << cfg.co_groups << " OGs in "
              << layer_ms << " ms, mismatches=" << total_mismatches << std::endl;

    return total_mismatches;
}

int main(int argc, char* argv[]) {
    if (argc < 2) {
        std::cerr << "Usage: " << argv[0] << " <xclbin_file> [stimulus_dir]" << std::endl;
        return 1;
    }

    std::string xclbin_file = argv[1];
    if (argc > 2) {
        g_stimulus_dir = argv[2];
    }

    std::cout << "========================================" << std::endl;
    std::cout << " TinyYOLOv3 Full Inference (13 Layers)" << std::endl;
    std::cout << "========================================" << std::endl;
    std::cout << "XCLBIN: " << xclbin_file << std::endl;
    std::cout << "Stimulus: " << g_stimulus_dir << std::endl;

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

        // Enable chained mode: output of layer N feeds into layer N+1
        #define USE_CHAINED_INPUT 1

        for (int i = 0; i < NUM_LAYERS; i++) {
            const LayerConfig& cfg = LAYERS[i];
            std::string layer_dir = g_stimulus_dir + "/layer" + std::to_string(i);
            std::vector<uint8_t> pixels;

            #if USE_CHAINED_INPUT
            if (i == 0) {
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
                } else {
                    pad_spatial(layer_output, prev_h, prev_w, prev_c, pixels);
                }
            }
            #else
            // Load from stimulus file for each layer (independent mode)
            pixels = read_binary_file(layer_dir + "/pixels.bin");
            #endif

            // Run layer
            int mismatches = run_layer(device, kernel, cfg, pixels, layer_output, layer_dir);
            if (mismatches < 0) {
                std::cerr << "Layer " << i << " failed!" << std::endl;
                return 1;
            }
            total_mismatches += mismatches;

            #if USE_CHAINED_INPUT
            // Save intermediate outputs for routing/concat
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
            #endif
        }

        auto total_end = std::chrono::high_resolution_clock::now();
        auto total_ms = std::chrono::duration_cast<std::chrono::milliseconds>(total_end - total_start).count();

        // Summary
        std::cout << "\n========================================" << std::endl;
        std::cout << " Chain Test Complete" << std::endl;
        std::cout << "========================================" << std::endl;
        std::cout << "Total time: " << total_ms << " ms" << std::endl;
        std::cout << "Total mismatches: " << total_mismatches << std::endl;

        if (total_mismatches == 0) {
            std::cout << "\n*** ALL LAYERS PASSED ***" << std::endl;
            return 0;
        } else {
            std::cout << "\n*** CHAIN TEST FAILED ***" << std::endl;
            return 1;
        }

    } catch (const std::exception& e) {
        std::cerr << "Error: " << e.what() << std::endl;
        return 1;
    }

    return 0;
}
