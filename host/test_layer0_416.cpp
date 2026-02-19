/*
 * test_layer0_416.cpp - Full 416x416 Layer 0 Test
 *
 * Tests layer 0 on real 416x416 image against hardware_sim.py reference.
 *
 * Layer 0: 3->16 channels, 3x3 conv, batch_norm, leaky ReLU, maxpool stride-2
 * Hardware: Pin=8, Pout=8, ci_groups=1, co_groups=2
 *
 * Input:  416x416x3 image (padded to 418x418x8)
 * Output: 208x208x16 after maxpool
 *
 * Uses quantization parameters from hardware_sim.py (golden standard):
 *   M = 0x000000C0 (192)
 *   n = 16
 *
 * Build: make test_layer0_416 TARGET=hw
 * Run:   ./test_layer0_416 <xclbin_file> [stimulus_dir]
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

// Layer 0 Configuration for 416x416
constexpr int IMG_H = 416;
constexpr int IMG_W = 416;
constexpr int PAD = 1;
constexpr int PADDED_H = IMG_H + 2 * PAD;  // 418
constexpr int PADDED_W = IMG_W + 2 * PAD;  // 418
constexpr int CIN = 3;
constexpr int CIN_PAD = 8;
constexpr int COUT = 16;
constexpr int CI_GROUPS = 1;
constexpr int CO_GROUPS = 2;
constexpr int POUT = 8;

// Output dimensions after maxpool stride-2
constexpr int OUT_H = (PADDED_H - 2) / 2;  // 208
constexpr int OUT_W = (PADDED_W - 2) / 2;  // 208

// Memory sizes
constexpr size_t NUM_PIXELS = PADDED_H * PADDED_W;           // 174724 pixels (64-bit each)
constexpr size_t NUM_OUTPUTS_PER_OG = OUT_H * OUT_W;         // 43264 pixels per output group
constexpr size_t NUM_WEIGHTS_PER_OG = CI_GROUPS * 8 * 8;     // 64 weight words per OG

// Byte sizes
constexpr size_t PIXEL_BYTES = NUM_PIXELS * 8;               // 1,397,792 bytes
constexpr size_t OUTPUT_BYTES_PER_OG = NUM_OUTPUTS_PER_OG * 8;  // 346,112 bytes
constexpr size_t WEIGHT_BYTES_PER_OG = NUM_WEIGHTS_PER_OG * 16; // 1,024 bytes (128-bit padded)
constexpr size_t BIAS_BYTES_PER_OG = 32;                     // 2 x 128-bit words

// Quantization parameters from hardware_sim.py (golden standard)
// SAME M and n for both output groups
constexpr uint32_t QUANT_M = 0x000000C0;  // 192
constexpr uint32_t QUANT_N = 16;

std::string g_stimulus_dir = "scripts/stimulus_416";

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

int compare_outputs(const uint8_t* actual, const uint8_t* expected, size_t size,
                    int tolerance, const std::string& label) {
    int mismatches = 0;
    int close_matches = 0;
    int max_diff = 0;

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
            if (mismatches <= 10) {
                size_t pixel = i / 8;
                size_t ch = i % 8;
                int y = pixel / OUT_W;
                int x = pixel % OUT_W;
                std::cout << "  MISMATCH [" << y << "," << x << "," << ch << "]: "
                          << "exp=" << static_cast<int>(exp)
                          << " act=" << static_cast<int>(act)
                          << " diff=" << diff << std::endl;
            }
        }
    }

    size_t exact = size - mismatches - close_matches;
    std::cout << label << ":" << std::endl;
    std::cout << "  Total values:      " << size << std::endl;
    std::cout << "  Exact matches:     " << exact << " ("
              << std::fixed << std::setprecision(1) << (100.0 * exact / size) << "%)" << std::endl;
    std::cout << "  Within tolerance:  " << close_matches << std::endl;
    std::cout << "  Mismatches:        " << mismatches << std::endl;
    std::cout << "  Max difference:    " << max_diff << std::endl;

    return mismatches;
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
    std::cout << " TinyYOLOv3 Layer 0 - 416x416 Test" << std::endl;
    std::cout << "========================================" << std::endl;
    std::cout << "XCLBIN: " << xclbin_file << std::endl;
    std::cout << "Stimulus: " << g_stimulus_dir << std::endl;
    std::cout << std::endl;
    std::cout << "Configuration:" << std::endl;
    std::cout << "  Input:  " << IMG_H << "x" << IMG_W << "x" << CIN
              << " (padded to " << PADDED_H << "x" << PADDED_W << "x" << CIN_PAD << ")" << std::endl;
    std::cout << "  Output: " << OUT_H << "x" << OUT_W << "x" << COUT << std::endl;
    std::cout << "  Quant:  M=0x" << std::hex << QUANT_M << std::dec
              << " n=" << QUANT_N << std::endl;
    std::cout << std::endl;

    try {
        // ================================================================
        // 1. Load test data
        // ================================================================
        std::cout << "Loading test data..." << std::endl;

        auto pixels = read_binary_file(g_stimulus_dir + "/pixels.bin");
        std::cout << "  Pixels: " << pixels.size() << " bytes" << std::endl;

        std::vector<uint8_t> weights[CO_GROUPS];
        std::vector<uint8_t> biases[CO_GROUPS];
        std::vector<uint8_t> expected[CO_GROUPS];

        for (int og = 0; og < CO_GROUPS; og++) {
            weights[og] = read_binary_file(g_stimulus_dir + "/weights_og" + std::to_string(og) + ".bin");
            biases[og] = read_binary_file(g_stimulus_dir + "/biases_og" + std::to_string(og) + ".bin");
            expected[og] = read_binary_file(g_stimulus_dir + "/expected_og" + std::to_string(og) + ".bin");

            std::cout << "  OG" << og << ": weights=" << weights[og].size()
                      << "B, biases=" << biases[og].size()
                      << "B, expected=" << expected[og].size() << "B" << std::endl;
        }
        std::cout << std::endl;

        // ================================================================
        // 2. Initialize XRT
        // ================================================================
        std::cout << "Initializing XRT device..." << std::endl;
        xrt::device device(0);
        std::cout << "  Device: " << device.get_info<xrt::info::device::name>() << std::endl;

        std::cout << "Loading xclbin..." << std::endl;
        auto uuid = device.load_xclbin(xclbin_file);
        std::cout << "  UUID: " << uuid << std::endl;

        xrt::kernel kernel(device, uuid, "TinyYOLOV3_HW_Complete");
        std::cout << "  Kernel loaded" << std::endl;
        std::cout << std::endl;

        // ================================================================
        // 3. Allocate device buffers
        // ================================================================
        std::cout << "Allocating device buffers..." << std::endl;

        // Size buffers appropriately (round up to 4KB alignment)
        size_t weight_buf_size = ((WEIGHT_BYTES_PER_OG + 4095) / 4096) * 4096;
        size_t bias_buf_size = 4096;
        size_t pixel_buf_size = ((PIXEL_BYTES + 4095) / 4096) * 4096;
        size_t output_buf_size = ((OUTPUT_BYTES_PER_OG + 4095) / 4096) * 4096;

        std::cout << "  Weight buffer:  " << weight_buf_size << " bytes" << std::endl;
        std::cout << "  Bias buffer:    " << bias_buf_size << " bytes" << std::endl;
        std::cout << "  Pixel buffer:   " << pixel_buf_size << " bytes" << std::endl;
        std::cout << "  Output buffer:  " << output_buf_size << " bytes" << std::endl;

        xrt::bo weight_bo(device, weight_buf_size, kernel.group_id(19));
        xrt::bo bias_bo(device, bias_buf_size, kernel.group_id(20));
        xrt::bo pixel_bo(device, pixel_buf_size, kernel.group_id(21));
        xrt::bo output_bo(device, output_buf_size, kernel.group_id(22));

        auto weight_ptr = weight_bo.map<uint8_t*>();
        auto bias_ptr = bias_bo.map<uint8_t*>();
        auto pixel_ptr = pixel_bo.map<uint8_t*>();
        auto output_ptr = output_bo.map<uint8_t*>();

        // Copy pixels (same for both output groups)
        std::memset(pixel_ptr, 0, pixel_buf_size);
        std::memcpy(pixel_ptr, pixels.data(), pixels.size());
        pixel_bo.sync(XCL_BO_SYNC_BO_TO_DEVICE);
        std::cout << "  Pixels copied to device" << std::endl;
        std::cout << std::endl;

        // ================================================================
        // 4. Run kernel for each output group
        // ================================================================
        std::vector<uint8_t> all_outputs(CO_GROUPS * OUTPUT_BYTES_PER_OG);
        int total_mismatches = 0;
        auto total_start = std::chrono::high_resolution_clock::now();

        for (int og = 0; og < CO_GROUPS; og++) {
            std::cout << "--- Output Group " << og << " ---" << std::flush;
            std::cout << std::endl;

            // Copy weights and biases
            std::cout << "  Clearing buffers..." << std::flush;
            std::memset(weight_ptr, 0, weight_buf_size);
            std::memset(bias_ptr, 0, bias_buf_size);
            std::memset(output_ptr, 0, output_buf_size);
            std::cout << " done" << std::endl;

            std::cout << "  Copying weights (" << weights[og].size() << " bytes)..." << std::flush;
            std::memcpy(weight_ptr, weights[og].data(), weights[og].size());
            std::cout << " done" << std::endl;

            std::cout << "  Copying biases (" << biases[og].size() << " bytes)..." << std::flush;
            std::memcpy(bias_ptr, biases[og].data(), biases[og].size());
            std::cout << " done" << std::endl;

            std::cout << "  Syncing weight_bo..." << std::flush;
            weight_bo.sync(XCL_BO_SYNC_BO_TO_DEVICE);
            std::cout << " done" << std::endl;

            std::cout << "  Syncing bias_bo..." << std::flush;
            bias_bo.sync(XCL_BO_SYNC_BO_TO_DEVICE);
            std::cout << " done" << std::endl;

            std::cout << "  Syncing output_bo..." << std::flush;
            output_bo.sync(XCL_BO_SYNC_BO_TO_DEVICE);
            std::cout << " done" << std::endl;

            // Note: pixel_bo already synced before loop

            // Configure kernel
            std::cout << "  Creating run object..." << std::flush;
            xrt::run run(kernel);
            std::cout << " done" << std::endl;

            std::cout << "  Setting arguments..." << std::endl;
            std::cout << "    arg0-3: buffer addresses" << std::endl;
            run.set_arg(0, weight_bo.address());
            run.set_arg(1, bias_bo.address());
            run.set_arg(2, pixel_bo.address());
            run.set_arg(3, output_bo.address());

            std::cout << "    arg4: weight_bytes=" << weights[og].size() << std::endl;
            std::cout << "    arg5: bias_bytes=" << biases[og].size() << std::endl;
            std::cout << "    arg6: pixel_bytes=" << pixels.size() << std::endl;
            std::cout << "    arg7: output_bytes=" << OUTPUT_BYTES_PER_OG << std::endl;
            run.set_arg(4, static_cast<uint32_t>(weights[og].size()));
            run.set_arg(5, static_cast<uint32_t>(biases[og].size()));
            run.set_arg(6, static_cast<uint32_t>(pixels.size()));
            run.set_arg(7, static_cast<uint32_t>(OUTPUT_BYTES_PER_OG));

            std::cout << "    arg8: ci_groups=" << CI_GROUPS << std::endl;
            // NOTE: arg9 is mapped to cfg_output_group in AXI wrapper (NOT co_groups)
            // Since we load biases per-OG to addresses 0,1, this MUST be 0
            std::cout << "    arg9: cfg_output_group=0 (bias addressing)" << std::endl;
            std::cout << "    arg10: wt_base_addr=0" << std::endl;
            std::cout << "    arg11: in_channels=" << CIN_PAD << std::endl;
            std::cout << "    arg12: img_width=" << PADDED_W << std::endl;
            run.set_arg(8, static_cast<uint32_t>(CI_GROUPS));
            run.set_arg(9, static_cast<uint32_t>(0));  // CRITICAL: Must be 0 for per-OG bias loading
            run.set_arg(10, static_cast<uint32_t>(0)); // wt_base_addr
            run.set_arg(11, static_cast<uint32_t>(CIN_PAD));
            run.set_arg(12, static_cast<uint32_t>(PADDED_W));

            std::cout << "    arg13: use_maxpool=1" << std::endl;
            std::cout << "    arg14: use_stride2=1" << std::endl;
            std::cout << "    arg15: quant_M=0x" << std::hex << QUANT_M << std::dec << std::endl;
            std::cout << "    arg16: quant_N=" << QUANT_N << std::endl;
            std::cout << "    arg17: use_relu=1" << std::endl;
            std::cout << "    arg18: kernel_1x1=0" << std::endl;
            run.set_arg(13, static_cast<uint32_t>(1)); // use_maxpool
            run.set_arg(14, static_cast<uint32_t>(1)); // use_stride2
            run.set_arg(15, QUANT_M);
            run.set_arg(16, QUANT_N);
            run.set_arg(17, static_cast<uint32_t>(1)); // use_relu (leaky)
            run.set_arg(18, static_cast<uint32_t>(0)); // kernel_1x1 = 0 (3x3)

            std::cout << "    arg19-22: buffer objects" << std::endl;
            run.set_arg(19, weight_bo);
            run.set_arg(20, bias_bo);
            run.set_arg(21, pixel_bo);
            run.set_arg(22, output_bo);

            // Execute
            std::cout << "  Starting kernel..." << std::flush;
            auto start = std::chrono::high_resolution_clock::now();
            run.start();
            std::cout << " started" << std::endl;

            std::cout << "  Waiting for completion (timeout=120s)..." << std::flush;
            auto state = run.wait(std::chrono::seconds(120));
            auto end = std::chrono::high_resolution_clock::now();
            auto duration_ms = std::chrono::duration_cast<std::chrono::milliseconds>(end - start).count();

            if (state == ERT_CMD_STATE_TIMEOUT) {
                std::cerr << "\n  TIMEOUT after " << duration_ms << " ms!" << std::endl;
                return 1;
            }
            std::cout << " done (" << duration_ms << " ms)" << std::endl;

            // Read output
            output_bo.sync(XCL_BO_SYNC_BO_FROM_DEVICE);

            // Store output
            std::memcpy(all_outputs.data() + og * OUTPUT_BYTES_PER_OG, output_ptr, OUTPUT_BYTES_PER_OG);

            // Compare with expected
            int mismatches = compare_outputs(output_ptr, expected[og].data(),
                                            OUTPUT_BYTES_PER_OG, 3,
                                            "  Verification (tolerance=3)");
            total_mismatches += mismatches;
            std::cout << std::endl;
        }

        auto total_end = std::chrono::high_resolution_clock::now();
        auto total_ms = std::chrono::duration_cast<std::chrono::milliseconds>(total_end - total_start).count();

        // ================================================================
        // 5. Summary
        // ================================================================
        std::cout << "========================================" << std::endl;
        std::cout << " Layer 0 Complete" << std::endl;
        std::cout << "========================================" << std::endl;
        std::cout << "Total execution time: " << total_ms << " ms" << std::endl;
        std::cout << "Output: " << OUT_H << "x" << OUT_W << "x" << COUT
                  << " = " << (OUT_H * OUT_W * COUT) << " values" << std::endl;
        std::cout << std::endl;

        // Print statistics
        int8_t min_val = 127, max_val = -128;
        for (size_t i = 0; i < all_outputs.size(); i++) {
            int8_t val = static_cast<int8_t>(all_outputs[i]);
            min_val = std::min(min_val, val);
            max_val = std::max(max_val, val);
        }
        std::cout << "Output range: [" << static_cast<int>(min_val) << ", "
                  << static_cast<int>(max_val) << "]" << std::endl;
        std::cout << std::endl;

        if (total_mismatches == 0) {
            std::cout << "*** LAYER 0 TEST PASSED ***" << std::endl;
            return 0;
        } else {
            std::cout << "Total mismatches: " << total_mismatches << std::endl;
            std::cout << "*** LAYER 0 TEST FAILED ***" << std::endl;
            return 1;
        }

    } catch (const std::exception& e) {
        std::cerr << "Error: " << e.what() << std::endl;
        return 1;
    }

    return 0;
}
