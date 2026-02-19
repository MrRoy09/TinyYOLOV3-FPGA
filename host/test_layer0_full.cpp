/*
 * test_layer0_full.cpp - Full TinyYOLOv3 Layer 0 Test
 *
 * Layer 0: 3->16 channels, 3x3 conv, batch_norm, leaky ReLU, maxpool stride-2
 * Hardware: Pin=8, Pout=8, ci_groups=1, co_groups=2
 *
 * This test runs both output groups (0 and 1) to produce all 16 output channels.
 * Input:  8x8x3 image (padded to 10x10x8)
 * Output: 4x4x16 after maxpool (stored as 2 x 4x4x8)
 *
 * Build: g++ -std=c++17 -O2 -g -Wall -I/usr/include -o test_layer0_full test_layer0_full.cpp -lxrt_coreutil -lpthread -lrt -ldl -luuid
 * Run:   ./test_layer0_full <xclbin_file>
 */

#include <iostream>
#include <fstream>
#include <sstream>
#include <vector>
#include <string>
#include <cstring>
#include <cstdint>
#include <iomanip>
#include <chrono>
#include <cmath>

// XRT includes
#include "xrt/xrt_device.h"
#include "xrt/xrt_kernel.h"
#include "xrt/xrt_bo.h"
#include "ert.h"

// Layer 0 Configuration
constexpr int IMG_H = 8;
constexpr int IMG_W = 8;
constexpr int PAD = 1;
constexpr int PADDED_H = IMG_H + 2 * PAD;  // 10
constexpr int PADDED_W = IMG_W + 2 * PAD;  // 10
constexpr int CIN = 3;
constexpr int CIN_PAD = 8;
constexpr int COUT = 16;
constexpr int CI_GROUPS = 1;
constexpr int CO_GROUPS = 2;
constexpr int POUT = 8;

// Output dimensions after maxpool stride-2
constexpr int OUT_H = (PADDED_H - 2) / 2;  // 4
constexpr int OUT_W = (PADDED_W - 2) / 2;  // 4

// Memory sizes per output group
constexpr int NUM_WEIGHTS = 64;        // 64 x 72-bit words per output group
constexpr int NUM_BIASES = 8;          // 8 x 32-bit words per output group
constexpr int NUM_PIXELS = 100;        // 10x10 x 64-bit words
constexpr int NUM_OUTPUTS = 16;        // 4x4 x 64-bit words (after maxpool)

// Byte sizes for AXI transfers
constexpr int WEIGHT_BYTES = NUM_WEIGHTS * 16;  // 72-bit padded to 128-bit
constexpr int BIAS_BYTES = NUM_BIASES * 4;      // 32-bit = 4 bytes each
constexpr int PIXEL_BYTES = NUM_PIXELS * 8;     // 64-bit = 8 bytes each
constexpr int OUTPUT_BYTES = NUM_OUTPUTS * 8;   // 64-bit = 8 bytes each

// Quantization parameters for each output group
constexpr uint32_t QUANT_M[CO_GROUPS] = {0x00002AF9, 0x000020A2};
constexpr uint32_t QUANT_N[CO_GROUPS] = {16, 16};

std::string g_stimulus_dir = "stimulus";

// Read hex file into vector of 64-bit values
std::vector<uint64_t> read_hex_file_64(const std::string& filename) {
    std::vector<uint64_t> data;
    std::ifstream file(filename);
    if (!file.is_open()) {
        throw std::runtime_error("Cannot open file: " + filename);
    }
    std::string line;
    while (std::getline(file, line)) {
        if (line.empty()) continue;
        uint64_t val = std::stoull(line, nullptr, 16);
        data.push_back(val);
    }
    return data;
}

// Read hex file into vector of 32-bit values
std::vector<int32_t> read_hex_file_32(const std::string& filename) {
    std::vector<int32_t> data;
    std::ifstream file(filename);
    if (!file.is_open()) {
        throw std::runtime_error("Cannot open file: " + filename);
    }
    std::string line;
    while (std::getline(file, line)) {
        if (line.empty()) continue;
        uint32_t val = std::stoul(line, nullptr, 16);
        data.push_back(static_cast<int32_t>(val));
    }
    return data;
}

// Read 72-bit weight hex file and pad to 128-bit for AXI transfer
std::vector<uint8_t> read_weights_padded(const std::string& filename) {
    std::vector<uint8_t> data;
    std::ifstream file(filename);
    if (!file.is_open()) {
        throw std::runtime_error("Cannot open file: " + filename);
    }
    std::string line;
    while (std::getline(file, line)) {
        if (line.empty()) continue;
        uint8_t bytes[16] = {0};
        int hex_len = line.length();
        for (int i = 0; i < 9 && i * 2 < hex_len; i++) {
            int hex_pos = hex_len - 2 - i * 2;
            if (hex_pos < 0) hex_pos = 0;
            std::string byte_str = line.substr(std::max(0, hex_pos),
                                               (hex_pos < 0) ? 1 : 2);
            bytes[i] = static_cast<uint8_t>(std::stoul(byte_str, nullptr, 16));
        }
        for (int i = 0; i < 16; i++) {
            data.push_back(bytes[i]);
        }
    }
    return data;
}

// Read biases and pack into 128-bit words (4 biases per word)
std::vector<uint8_t> read_biases_packed(const std::string& filename) {
    auto biases = read_hex_file_32(filename);
    std::vector<uint8_t> data;
    for (size_t i = 0; i < biases.size(); i += 4) {
        for (int j = 0; j < 4; j++) {
            int32_t bias = (i + j < biases.size()) ? biases[i + j] : 0;
            uint32_t ubias = static_cast<uint32_t>(bias);
            data.push_back((ubias >> 0) & 0xFF);
            data.push_back((ubias >> 8) & 0xFF);
            data.push_back((ubias >> 16) & 0xFF);
            data.push_back((ubias >> 24) & 0xFF);
        }
    }
    return data;
}

void print_hex_dump(const uint8_t* data, size_t len, const std::string& label) {
    std::cout << label << " (" << len << " bytes):" << std::endl;
    for (size_t i = 0; i < std::min(len, size_t(32)); i++) {
        std::cout << std::hex << std::setw(2) << std::setfill('0')
                  << static_cast<int>(data[i]) << " ";
        if ((i + 1) % 16 == 0) std::cout << std::endl;
    }
    if (len > 32) std::cout << "..." << std::endl;
    std::cout << std::dec << std::endl;
}

int compare_outputs_with_tolerance(const uint8_t* actual, const std::vector<uint64_t>& expected,
                                    int tolerance, const std::string& label) {
    int mismatches = 0;
    int close_matches = 0;

    std::cout << label << ":" << std::endl;

    for (size_t i = 0; i < expected.size(); i++) {
        uint64_t act_val = 0;
        for (int j = 0; j < 8; j++) {
            act_val |= static_cast<uint64_t>(actual[i * 8 + j]) << (j * 8);
        }
        uint64_t exp_val = expected[i];

        // Compare byte by byte with tolerance
        bool exact_match = (act_val == exp_val);
        bool within_tolerance = true;
        int max_diff = 0;

        for (int ch = 0; ch < 8; ch++) {
            int8_t act_byte = (act_val >> (ch * 8)) & 0xFF;
            int8_t exp_byte = (exp_val >> (ch * 8)) & 0xFF;
            int diff = std::abs(static_cast<int>(act_byte) - static_cast<int>(exp_byte));
            max_diff = std::max(max_diff, diff);
            if (diff > tolerance) {
                within_tolerance = false;
            }
        }

        if (!exact_match) {
            if (within_tolerance) {
                close_matches++;
            } else {
                mismatches++;
                if (mismatches <= 5) {
                    std::cout << "  MISMATCH pixel " << i << ": exp=0x"
                              << std::hex << std::setw(16) << std::setfill('0') << exp_val
                              << " act=0x" << std::setw(16) << act_val
                              << std::dec << " (max_diff=" << max_diff << ")" << std::endl;
                }
            }
        }
    }

    std::cout << "  Exact matches: " << (expected.size() - mismatches - close_matches) << "/" << expected.size() << std::endl;
    std::cout << "  Within tolerance (+/-" << tolerance << "): " << close_matches << std::endl;
    std::cout << "  Mismatches: " << mismatches << std::endl;

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
    std::cout << " TinyYOLOv3 Layer 0 Full Test" << std::endl;
    std::cout << "========================================" << std::endl;
    std::cout << "XCLBIN: " << xclbin_file << std::endl;
    std::cout << "Stimulus: " << g_stimulus_dir << std::endl;
    std::cout << std::endl;
    std::cout << "Layer 0 Config:" << std::endl;
    std::cout << "  Input:  " << IMG_H << "x" << IMG_W << "x" << CIN
              << " (padded to " << PADDED_H << "x" << PADDED_W << "x" << CIN_PAD << ")" << std::endl;
    std::cout << "  Output: " << OUT_H << "x" << OUT_W << "x" << COUT
              << " (2 output groups x 8 channels)" << std::endl;
    std::cout << "  Maxpool: 2x2 stride-2" << std::endl;
    std::cout << std::endl;

    try {
        // ================================================================
        // 1. Load test data for both output groups
        // ================================================================
        std::cout << "Loading test data..." << std::endl;

        // Pixels are the same for both output groups
        auto pixels_vec = read_hex_file_64(g_stimulus_dir + "/pixels_og0.hex");
        std::vector<uint8_t> pixels(pixels_vec.size() * 8);
        for (size_t i = 0; i < pixels_vec.size(); i++) {
            uint64_t val = pixels_vec[i];
            for (int j = 0; j < 8; j++) {
                pixels[i * 8 + j] = (val >> (j * 8)) & 0xFF;
            }
        }
        std::cout << "  Pixels: " << pixels_vec.size() << " entries" << std::endl;

        // Load weights and biases for each output group
        std::vector<uint8_t> weights[CO_GROUPS];
        std::vector<uint8_t> biases[CO_GROUPS];
        std::vector<uint64_t> expected[CO_GROUPS];

        for (int og = 0; og < CO_GROUPS; og++) {
            std::string suffix = std::to_string(og);
            weights[og] = read_weights_padded(g_stimulus_dir + "/weights_og" + suffix + ".hex");
            biases[og] = read_biases_packed(g_stimulus_dir + "/biases_og" + suffix + ".hex");
            expected[og] = read_hex_file_64(g_stimulus_dir + "/expected_og" + suffix + ".hex");

            std::cout << "  OG" << og << " - Weights: " << weights[og].size()
                      << "B, Biases: " << biases[og].size()
                      << "B, Expected: " << expected[og].size() << " entries"
                      << ", Quant M=0x" << std::hex << QUANT_M[og] << std::dec
                      << " n=" << QUANT_N[og] << std::endl;
        }
        std::cout << std::endl;

        // ================================================================
        // 2. Initialize XRT and load xclbin
        // ================================================================
        std::cout << "Initializing XRT device..." << std::endl;
        xrt::device device(0);
        std::cout << "  Device: " << device.get_info<xrt::info::device::name>() << std::endl;

        std::cout << "Loading xclbin..." << std::endl;
        auto uuid = device.load_xclbin(xclbin_file);
        std::cout << "  UUID: " << uuid << std::endl;

        xrt::kernel kernel(device, uuid, "TinyYOLOV3_HW_Complete");
        std::cout << "  Kernel: TinyYOLOV3_HW_Complete loaded" << std::endl;
        std::cout << std::endl;

        // ================================================================
        // 3. Allocate device buffers
        // ================================================================
        std::cout << "Allocating device buffers..." << std::endl;

        size_t weight_buf_size = 4096;
        size_t bias_buf_size = 4096;
        size_t pixel_buf_size = 4096;
        size_t output_buf_size = 4096;

        xrt::bo weight_bo(device, weight_buf_size, kernel.group_id(19));
        xrt::bo bias_bo(device, bias_buf_size, kernel.group_id(20));
        xrt::bo pixel_bo(device, pixel_buf_size, kernel.group_id(21));
        xrt::bo output_bo(device, output_buf_size, kernel.group_id(22));

        auto weight_ptr = weight_bo.map<uint8_t*>();
        auto bias_ptr = bias_bo.map<uint8_t*>();
        auto pixel_ptr = pixel_bo.map<uint8_t*>();
        auto output_ptr = output_bo.map<uint8_t*>();

        std::cout << "  Buffers allocated" << std::endl;

        // Copy pixels to device (same for all output groups)
        std::memset(pixel_ptr, 0, pixel_buf_size);
        std::memcpy(pixel_ptr, pixels.data(), pixels.size());
        pixel_bo.sync(XCL_BO_SYNC_BO_TO_DEVICE);
        std::cout << "  Pixels copied to device (" << pixels.size() << " bytes)" << std::endl;
        std::cout << std::endl;

        // ================================================================
        // 4. Run kernel for each output group
        // ================================================================
        std::vector<uint8_t> all_outputs(CO_GROUPS * NUM_OUTPUTS * 8);
        int total_mismatches = 0;
        auto total_start = std::chrono::high_resolution_clock::now();

        for (int og = 0; og < CO_GROUPS; og++) {
            std::cout << "--- Output Group " << og << " ---" << std::endl;

            // Copy weights and biases for this output group
            std::memset(weight_ptr, 0, weight_buf_size);
            std::memset(bias_ptr, 0, bias_buf_size);
            std::memset(output_ptr, 0, output_buf_size);

            std::memcpy(weight_ptr, weights[og].data(), weights[og].size());
            std::memcpy(bias_ptr, biases[og].data(), biases[og].size());

            weight_bo.sync(XCL_BO_SYNC_BO_TO_DEVICE);
            bias_bo.sync(XCL_BO_SYNC_BO_TO_DEVICE);
            output_bo.sync(XCL_BO_SYNC_BO_TO_DEVICE);

            // Configure and run kernel
            xrt::run run(kernel);

            run.set_arg(0, weight_bo.address());
            run.set_arg(1, bias_bo.address());
            run.set_arg(2, pixel_bo.address());
            run.set_arg(3, output_bo.address());

            run.set_arg(4, static_cast<uint32_t>(weights[og].size()));
            run.set_arg(5, static_cast<uint32_t>(biases[og].size()));
            run.set_arg(6, static_cast<uint32_t>(pixels.size()));
            run.set_arg(7, static_cast<uint32_t>(expected[og].size() * 8));

            run.set_arg(8, static_cast<uint32_t>(CI_GROUPS));
            run.set_arg(9, static_cast<uint32_t>(1));  // co_groups (process 1 at a time)
            run.set_arg(10, static_cast<uint32_t>(0)); // wt_base_addr
            run.set_arg(11, static_cast<uint32_t>(CIN_PAD));
            run.set_arg(12, static_cast<uint32_t>(PADDED_W));
            run.set_arg(13, static_cast<uint32_t>(1)); // use_maxpool
            run.set_arg(14, static_cast<uint32_t>(1)); // use_stride2
            run.set_arg(15, QUANT_M[og]);
            run.set_arg(16, QUANT_N[og]);
            run.set_arg(17, static_cast<uint32_t>(1)); // use_relu
            run.set_arg(18, static_cast<uint32_t>(0)); // kernel_1x1

            run.set_arg(19, weight_bo);
            run.set_arg(20, bias_bo);
            run.set_arg(21, pixel_bo);
            run.set_arg(22, output_bo);

            auto start = std::chrono::high_resolution_clock::now();
            run.start();
            auto state = run.wait(std::chrono::seconds(5));
            auto end = std::chrono::high_resolution_clock::now();
            auto duration = std::chrono::duration_cast<std::chrono::microseconds>(end - start);

            if (state == ERT_CMD_STATE_TIMEOUT) {
                std::cerr << "  TIMEOUT!" << std::endl;
                return 1;
            }
            std::cout << "  Kernel completed in " << duration.count() << " us" << std::endl;

            // Read back results
            output_bo.sync(XCL_BO_SYNC_BO_FROM_DEVICE);

            // Store outputs
            std::memcpy(all_outputs.data() + og * NUM_OUTPUTS * 8, output_ptr, NUM_OUTPUTS * 8);

            // Verify with tolerance
            int mismatches = compare_outputs_with_tolerance(output_ptr, expected[og], 3,
                                                            "  Verification (tolerance=3)");
            total_mismatches += mismatches;
            std::cout << std::endl;
        }

        auto total_end = std::chrono::high_resolution_clock::now();
        auto total_duration = std::chrono::duration_cast<std::chrono::microseconds>(total_end - total_start);

        // ================================================================
        // 5. Summary
        // ================================================================
        std::cout << "========================================" << std::endl;
        std::cout << " Layer 0 Complete" << std::endl;
        std::cout << "========================================" << std::endl;
        std::cout << "Total execution time: " << total_duration.count() << " us" << std::endl;
        std::cout << "Output shape: " << OUT_H << "x" << OUT_W << "x" << COUT
                  << " = " << (OUT_H * OUT_W * COUT) << " values" << std::endl;
        std::cout << std::endl;

        // Print first few output values
        std::cout << "First output pixels (all 16 channels):" << std::endl;
        for (int og = 0; og < CO_GROUPS; og++) {
            std::cout << "  OG" << og << " [0,0]: 0x";
            for (int ch = 7; ch >= 0; ch--) {
                std::cout << std::hex << std::setw(2) << std::setfill('0')
                          << static_cast<int>(all_outputs[og * NUM_OUTPUTS * 8 + ch]);
            }
            std::cout << std::dec << std::endl;
        }
        std::cout << std::endl;

        if (total_mismatches == 0) {
            std::cout << "*** LAYER 0 TEST PASSED (all outputs within tolerance) ***" << std::endl;
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
