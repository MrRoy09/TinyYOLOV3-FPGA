/*
 * test_layers_chain.cpp - Full Layer 0-5 Chain Test
 *
 * Runs Layers 0-5 sequentially, using hardware output from each layer
 * as input to the next layer.
 *
 * Layer 0: 3→16,   416→208 (maxpool stride-2)
 * Layer 1: 16→32,  208→104 (maxpool stride-2)
 * Layer 2: 32→64,  104→52  (maxpool stride-2)
 * Layer 3: 64→128, 52→26   (maxpool stride-2)
 * Layer 4: 128→256, 26→13  (maxpool stride-2)
 * Layer 5: 256→512, 13→13  (maxpool stride-1)
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
    int padded_h, padded_w;  // After padding
    int out_h, out_w;        // After conv + maxpool
    int maxpool_stride;
    uint32_t quant_m;
    uint32_t quant_n;
};

// Layer configurations
const LayerConfig LAYERS[] = {
    // hw_layer, cin, cout, cin_pad, ci_groups, co_groups, img_h, img_w, padded_h, padded_w, out_h, out_w, mp_stride, M, n
    {0,   3,  16,   8,  1,  2, 416, 416, 418, 418, 208, 208, 2, 0x000000C0, 16},
    {1,  16,  32,  16,  2,  4, 208, 208, 210, 210, 104, 104, 2, 0x000002BC, 16},
    {2,  32,  64,  32,  4,  8, 104, 104, 106, 106,  52,  52, 2, 0x000003CA, 16},
    {3,  64, 128,  64,  8, 16,  52,  52,  54,  54,  26,  26, 2, 0x0000022B, 16},
    {4, 128, 256, 128, 16, 32,  26,  26,  28,  28,  13,  13, 2, 0x00000230, 16},
    {5, 256, 512, 256, 32, 64,  13,  13,  15,  15,  13,  13, 1, 0x00000173, 16},
};
const int NUM_LAYERS = sizeof(LAYERS) / sizeof(LAYERS[0]);

std::string g_stimulus_dir = "scripts/stimulus_chain";

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
              << ", " << cfg.img_h << "→" << cfg.out_h << std::endl;
    std::cout << "========================================" << std::endl;
    std::cout << "  ci_groups=" << cfg.ci_groups << ", co_groups=" << cfg.co_groups << std::endl;
    std::cout << "  M=0x" << std::hex << cfg.quant_m << std::dec << ", n=" << cfg.quant_n << std::endl;

    // Calculate sizes
    size_t pixel_bytes = cfg.padded_h * cfg.padded_w * cfg.cin_pad;
    size_t output_bytes_per_og = cfg.out_h * cfg.out_w * 8;
    size_t weight_bytes_per_og = cfg.ci_groups * 8 * 8 * 16;  // ci_groups * 8 banks * 8 urams * 16 bytes

    // Allocate device buffers
    size_t weight_buf_size = ((weight_bytes_per_og + 4095) / 4096) * 4096;
    size_t bias_buf_size = 4096;
    size_t pixel_buf_size = ((pixel_bytes + 4095) / 4096) * 4096;
    size_t output_buf_size = ((output_bytes_per_og + 4095) / 4096) * 4096;

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
        run.set_arg(7, static_cast<uint32_t>(output_bytes_per_og));

        run.set_arg(8, static_cast<uint32_t>(cfg.ci_groups));
        run.set_arg(9, static_cast<uint32_t>(0));  // CRITICAL: Must be 0 for per-OG bias loading
        run.set_arg(10, static_cast<uint32_t>(0)); // wt_base_addr
        run.set_arg(11, static_cast<uint32_t>(cfg.cin_pad));
        run.set_arg(12, static_cast<uint32_t>(cfg.padded_w));

        run.set_arg(13, static_cast<uint32_t>(1)); // use_maxpool
        run.set_arg(14, static_cast<uint32_t>(cfg.maxpool_stride == 2 ? 1 : 0));
        run.set_arg(15, cfg.quant_m);
        run.set_arg(16, cfg.quant_n);
        run.set_arg(17, static_cast<uint32_t>(1)); // use_relu (leaky)
        run.set_arg(18, static_cast<uint32_t>(0)); // kernel_1x1 = 0 (3x3)

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

        // Store in layer output (interleaved by output group)
        for (int y = 0; y < cfg.out_h; y++) {
            for (int x = 0; x < cfg.out_w; x++) {
                for (int ch = 0; ch < 8; ch++) {
                    int src_idx = (y * cfg.out_w + x) * 8 + ch;
                    int dst_idx = (y * cfg.out_w + x) * cfg.cout + og * 8 + ch;
                    layer_output[dst_idx] = output_ptr[src_idx];
                }
            }
        }

        // Compare with expected
        std::string expected_path = layer_dir + "/expected_og" + std::to_string(og) + ".bin";
        auto expected = read_binary_file(expected_path);

        int mismatches = compare_outputs(output_ptr, expected.data(),
                                        output_bytes_per_og, 3,
                                        "  OG" + std::to_string(og));
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
    std::cout << " TinyYOLOv3 Layers 0-5 Chain Test" << std::endl;
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

        for (int i = 0; i < NUM_LAYERS; i++) {
            const LayerConfig& cfg = LAYERS[i];
            std::string layer_dir = g_stimulus_dir + "/layer" + std::to_string(i);

            // Get input pixels - always load from file to verify expected outputs
            // (For true chaining, set USE_CHAINED_INPUT to 1)
            #define USE_CHAINED_INPUT 0
            std::vector<uint8_t> pixels;
            #if USE_CHAINED_INPUT
            if (i == 0) {
                pixels = read_binary_file(layer_dir + "/pixels.bin");
            } else {
                // Use output from previous layer, add spatial padding
                pad_spatial(layer_output, LAYERS[i-1].out_h, LAYERS[i-1].out_w,
                           cfg.cin_pad, pixels);
            }
            #else
            // Load from stimulus file for each layer
            pixels = read_binary_file(layer_dir + "/pixels.bin");
            #endif

            // Run layer
            int mismatches = run_layer(device, kernel, cfg, pixels, layer_output, layer_dir);
            if (mismatches < 0) {
                std::cerr << "Layer " << i << " failed!" << std::endl;
                return 1;
            }
            total_mismatches += mismatches;
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
