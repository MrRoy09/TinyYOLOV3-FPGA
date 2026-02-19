/*
 * test_conv.cpp - XRT Host Application for TinyYOLOV3 Conv Accelerator Testing
 *
 * This test loads pre-generated stimulus from scripts/stimulus/*.hex files,
 * runs the accelerator for one output group (8 filters), and verifies the
 * output against expected values.
 *
 * Build: g++ -o test_conv test_conv.cpp -I$XILINX_XRT/include -L$XILINX_XRT/lib -lxrt_coreutil -pthread
 * Run:   ./test_conv <xclbin_file> [output_group]
 */

#include <iostream>
#include <fstream>
#include <sstream>
#include <vector>
#include <string>
#include <cstring>
#include <cstdint>
#include <iomanip>

// XRT includes
#include "xrt/xrt_device.h"
#include "xrt/xrt_kernel.h"
#include "xrt/xrt_bo.h"
#include "ert.h"  // For ERT_CMD_STATE_*

// Test configuration (matches scripts/gen_layer0_stimulus.py)
constexpr int IMG_H = 8;
constexpr int IMG_W = 8;
constexpr int PAD = 1;
constexpr int PADDED_H = IMG_H + 2 * PAD;  // 10
constexpr int PADDED_W = IMG_W + 2 * PAD;  // 10
constexpr int CIN_PAD = 8;
constexpr int CI_GROUPS = 1;
constexpr int POUT = 8;

// Memory sizes
constexpr int NUM_WEIGHTS = 64;        // 64 x 72-bit words per output group
constexpr int NUM_BIASES = 8;          // 8 x 32-bit words per output group
constexpr int NUM_PIXELS = 100;        // 10x10 x 64-bit words
constexpr int NUM_OUTPUTS = 16;        // 4x4 x 64-bit words (after maxpool)

// Byte sizes for AXI transfers
constexpr int WEIGHT_BYTES = NUM_WEIGHTS * 16;  // 72-bit padded to 128-bit (16 bytes each)
constexpr int BIAS_BYTES = NUM_BIASES * 4;      // 32-bit = 4 bytes each
constexpr int PIXEL_BYTES = NUM_PIXELS * 8;     // 64-bit = 8 bytes each
constexpr int OUTPUT_BYTES = NUM_OUTPUTS * 8;   // 64-bit = 8 bytes each

// Quantization parameters from quant_params.txt
constexpr uint32_t QUANT_M_OG0 = 0x00002AF9;
constexpr uint32_t QUANT_N_OG0 = 16;
constexpr uint32_t QUANT_M_OG1 = 0x000020A2;
constexpr uint32_t QUANT_N_OG1 = 16;

std::string g_stimulus_dir = "../scripts/stimulus";

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

        // Parse 72-bit value (18 hex chars)
        // Store as 16 bytes (128-bit), lower 9 bytes contain data
        uint8_t bytes[16] = {0};

        // Parse hex string from LSB to MSB
        int hex_len = line.length();
        for (int i = 0; i < 9 && i * 2 < hex_len; i++) {
            int hex_pos = hex_len - 2 - i * 2;
            if (hex_pos < 0) hex_pos = 0;
            std::string byte_str = line.substr(std::max(0, hex_pos),
                                               (hex_pos < 0) ? 1 : 2);
            bytes[i] = static_cast<uint8_t>(std::stoul(byte_str, nullptr, 16));
        }

        // Append all 16 bytes
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

    // Pack 4 biases per 128-bit word
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
    for (size_t i = 0; i < std::min(len, size_t(64)); i++) {
        std::cout << std::hex << std::setw(2) << std::setfill('0')
                  << static_cast<int>(data[i]) << " ";
        if ((i + 1) % 16 == 0) std::cout << std::endl;
    }
    if (len > 64) std::cout << "... (" << (len - 64) << " more bytes)" << std::endl;
    std::cout << std::dec << std::endl;
}

int main(int argc, char* argv[]) {
    if (argc < 2) {
        std::cerr << "Usage: " << argv[0] << " <xclbin_file> [output_group]" << std::endl;
        std::cerr << "  output_group: 0 or 1 (default: 0)" << std::endl;
        return 1;
    }

    std::string xclbin_file = argv[1];
    int output_group = (argc > 2) ? std::stoi(argv[2]) : 0;

    if (output_group < 0 || output_group > 1) {
        std::cerr << "Error: output_group must be 0 or 1" << std::endl;
        return 1;
    }

    std::cout << "========================================" << std::endl;
    std::cout << " TinyYOLOV3 Conv Accelerator Test" << std::endl;
    std::cout << "========================================" << std::endl;
    std::cout << "XCLBIN: " << xclbin_file << std::endl;
    std::cout << "Output Group: " << output_group << std::endl;
    std::cout << std::endl;

    // Select quantization parameters based on output group
    uint32_t quant_m = (output_group == 0) ? QUANT_M_OG0 : QUANT_M_OG1;
    uint32_t quant_n = (output_group == 0) ? QUANT_N_OG0 : QUANT_N_OG1;

    try {
        // ================================================================
        // 1. Load test data from hex files
        // ================================================================
        std::cout << "Loading test data..." << std::endl;

        std::string suffix = std::to_string(output_group);

        auto weights = read_weights_padded(g_stimulus_dir + "/weights_og" + suffix + ".hex");
        auto biases = read_biases_packed(g_stimulus_dir + "/biases_og" + suffix + ".hex");
        auto pixels_vec = read_hex_file_64(g_stimulus_dir + "/pixels_og" + suffix + ".hex");
        auto expected_vec = read_hex_file_64(g_stimulus_dir + "/expected_og" + suffix + ".hex");

        std::cout << "  Weights: " << weights.size() << " bytes (" << NUM_WEIGHTS << " entries)" << std::endl;
        std::cout << "  Biases:  " << biases.size() << " bytes (" << NUM_BIASES << " entries)" << std::endl;
        std::cout << "  Pixels:  " << pixels_vec.size() << " entries" << std::endl;
        std::cout << "  Expected:" << expected_vec.size() << " entries" << std::endl;
        std::cout << std::endl;

        // Convert pixels to byte array
        std::vector<uint8_t> pixels(pixels_vec.size() * 8);
        for (size_t i = 0; i < pixels_vec.size(); i++) {
            uint64_t val = pixels_vec[i];
            for (int j = 0; j < 8; j++) {
                pixels[i * 8 + j] = (val >> (j * 8)) & 0xFF;
            }
        }

        // ================================================================
        // 2. Initialize XRT and load xclbin
        // ================================================================
        std::cout << "Initializing XRT device..." << std::endl;

        xrt::device device(0);  // Use first device
        std::cout << "  Device: " << device.get_info<xrt::info::device::name>() << std::endl;

        std::cout << "Loading xclbin..." << std::endl;
        auto uuid = device.load_xclbin(xclbin_file);
        std::cout << "  UUID: " << uuid << std::endl;

        // Get kernel handle
        xrt::kernel kernel(device, uuid, "TinyYOLOV3_HW_Complete");
        std::cout << "  Kernel: TinyYOLOV3_HW_Complete loaded" << std::endl;
        std::cout << std::endl;

        // ================================================================
        // 3. Allocate device buffers
        // ================================================================
        std::cout << "Allocating device buffers..." << std::endl;

        // Buffer sizes (ensure alignment to 4KB for efficient DMA)
        size_t weight_buf_size = ((weights.size() + 4095) / 4096) * 4096;
        size_t bias_buf_size = ((biases.size() + 4095) / 4096) * 4096;
        size_t pixel_buf_size = ((pixels.size() + 4095) / 4096) * 4096;
        size_t output_buf_size = 4096;  // At least 4KB

        // Allocate buffers - args 19-22 are the AXI buffer pointers
        xrt::bo weight_bo(device, weight_buf_size, kernel.group_id(19));
        xrt::bo bias_bo(device, bias_buf_size, kernel.group_id(20));
        xrt::bo pixel_bo(device, pixel_buf_size, kernel.group_id(21));
        xrt::bo output_bo(device, output_buf_size, kernel.group_id(22));

        std::cout << "  Weight buffer: " << weight_buf_size << " bytes" << std::endl;
        std::cout << "  Bias buffer:   " << bias_buf_size << " bytes" << std::endl;
        std::cout << "  Pixel buffer:  " << pixel_buf_size << " bytes" << std::endl;
        std::cout << "  Output buffer: " << output_buf_size << " bytes" << std::endl;
        std::cout << std::endl;

        // ================================================================
        // 4. Copy input data to device
        // ================================================================
        std::cout << "Copying input data to device..." << std::endl;

        // Map buffers for host access
        auto weight_ptr = weight_bo.map<uint8_t*>();
        auto bias_ptr = bias_bo.map<uint8_t*>();
        auto pixel_ptr = pixel_bo.map<uint8_t*>();
        auto output_ptr = output_bo.map<uint8_t*>();

        // Clear buffers
        std::memset(weight_ptr, 0, weight_buf_size);
        std::memset(bias_ptr, 0, bias_buf_size);
        std::memset(pixel_ptr, 0, pixel_buf_size);
        std::memset(output_ptr, 0, output_buf_size);

        // Copy data
        std::memcpy(weight_ptr, weights.data(), weights.size());
        std::memcpy(bias_ptr, biases.data(), biases.size());
        std::memcpy(pixel_ptr, pixels.data(), pixels.size());

        // Sync to device
        weight_bo.sync(XCL_BO_SYNC_BO_TO_DEVICE);
        bias_bo.sync(XCL_BO_SYNC_BO_TO_DEVICE);
        pixel_bo.sync(XCL_BO_SYNC_BO_TO_DEVICE);

        std::cout << "  Data synced to device" << std::endl;
        std::cout << std::endl;

        // Debug: print first few weights
        print_hex_dump(weight_ptr, 32, "First weights");

        // ================================================================
        // 5. Set kernel arguments and run
        // ================================================================
        std::cout << "Configuring kernel..." << std::endl;

        // Get device addresses of buffer objects
        uint64_t weight_addr = weight_bo.address();
        uint64_t bias_addr = bias_bo.address();
        uint64_t pixel_addr = pixel_bo.address();
        uint64_t output_addr = output_bo.address();

        std::cout << "  Buffer addresses:" << std::endl;
        std::cout << "    Weights: 0x" << std::hex << weight_addr << std::dec << std::endl;
        std::cout << "    Biases:  0x" << std::hex << bias_addr << std::dec << std::endl;
        std::cout << "    Pixels:  0x" << std::hex << pixel_addr << std::dec << std::endl;
        std::cout << "    Output:  0x" << std::hex << output_addr << std::dec << std::endl;

        // Set kernel arguments explicitly for better compatibility with older XRT
        xrt::run run(kernel);

        // Args 0-3: Scalar addresses (use same address as buffers)
        run.set_arg(0, weight_addr);
        run.set_arg(1, bias_addr);
        run.set_arg(2, pixel_addr);
        run.set_arg(3, output_addr);

        // Args 4-7: Transfer sizes in bytes
        run.set_arg(4, static_cast<uint32_t>(weights.size()));
        run.set_arg(5, static_cast<uint32_t>(biases.size()));
        run.set_arg(6, static_cast<uint32_t>(pixels.size()));
        run.set_arg(7, static_cast<uint32_t>(expected_vec.size() * 8));

        // Args 8-18: Configuration
        run.set_arg(8, static_cast<uint32_t>(CI_GROUPS));
        run.set_arg(9, static_cast<uint32_t>(1));  // cfg_co_groups
        run.set_arg(10, static_cast<uint32_t>(0)); // cfg_wt_base_addr
        run.set_arg(11, static_cast<uint32_t>(CIN_PAD));
        run.set_arg(12, static_cast<uint32_t>(PADDED_W));
        run.set_arg(13, static_cast<uint32_t>(1)); // cfg_use_maxpool
        run.set_arg(14, static_cast<uint32_t>(1)); // cfg_use_stride2 (stride-2 maxpool: 8x8 -> 4x4)
        run.set_arg(15, quant_m);
        run.set_arg(16, quant_n);
        run.set_arg(17, static_cast<uint32_t>(1)); // cfg_use_relu
        run.set_arg(18, static_cast<uint32_t>(0)); // cfg_kernel_1x1

        // Args 19-22: AXI buffer pointers (pass buffer objects)
        run.set_arg(19, weight_bo);
        run.set_arg(20, bias_bo);
        run.set_arg(21, pixel_bo);
        run.set_arg(22, output_bo);

        std::cout << "  Configuration:" << std::endl;
        std::cout << "    ci_groups:    " << CI_GROUPS << std::endl;
        std::cout << "    in_channels:  " << CIN_PAD << std::endl;
        std::cout << "    img_width:    " << PADDED_W << std::endl;
        std::cout << "    use_maxpool:  1" << std::endl;
        std::cout << "    quant_m:      0x" << std::hex << quant_m << std::dec << std::endl;
        std::cout << "    quant_n:      " << quant_n << std::endl;
        std::cout << std::endl;

        std::cout << "Starting kernel..." << std::endl;
        // Start the kernel
        run.start();
        std::cout << "  Kernel started, waiting with 5s timeout..." << std::endl;
        auto start = std::chrono::high_resolution_clock::now();

        // Wait with timeout
        auto state = run.wait(std::chrono::seconds(5));

        auto end = std::chrono::high_resolution_clock::now();
        auto duration = std::chrono::duration_cast<std::chrono::microseconds>(end - start);

        if (state == ERT_CMD_STATE_TIMEOUT) {
            std::cerr << "  TIMEOUT after " << duration.count() << " us!" << std::endl;
            std::cerr << "  Kernel hung - checking output buffer anyway..." << std::endl;
        } else if (state != ERT_CMD_STATE_COMPLETED) {
            std::cerr << "  Kernel ended with state: " << state << " in " << duration.count() << " us" << std::endl;
        } else {
            std::cout << "  Kernel completed in " << duration.count() << " us" << std::endl;
        }
        std::cout << std::endl;

        // ================================================================
        // 6. Read back results and verify
        // ================================================================
        std::cout << "Reading results..." << std::endl;
        output_bo.sync(XCL_BO_SYNC_BO_FROM_DEVICE);

        // Compare output with expected
        int mismatches = 0;
        std::cout << std::endl;
        std::cout << "Verification Results:" << std::endl;
        std::cout << "---------------------" << std::endl;

        for (size_t i = 0; i < expected_vec.size(); i++) {
            uint64_t actual = 0;
            for (int j = 0; j < 8; j++) {
                actual |= static_cast<uint64_t>(output_ptr[i * 8 + j]) << (j * 8);
            }
            uint64_t expected = expected_vec[i];

            if (actual != expected) {
                mismatches++;
                if (mismatches <= 10) {
                    std::cout << "  MISMATCH at pixel " << i << ": " << std::endl;
                    std::cout << "    Expected: 0x" << std::hex << std::setw(16)
                              << std::setfill('0') << expected << std::endl;
                    std::cout << "    Actual:   0x" << std::setw(16)
                              << std::setfill('0') << actual << std::dec << std::endl;
                }
            }
        }

        if (mismatches == 0) {
            std::cout << "  *** ALL " << expected_vec.size() << " OUTPUT WORDS MATCH! ***" << std::endl;
            std::cout << std::endl;
            std::cout << "TEST PASSED" << std::endl;
        } else {
            std::cout << std::endl;
            std::cout << "  Total mismatches: " << mismatches << " / " << expected_vec.size() << std::endl;
            std::cout << std::endl;
            std::cout << "TEST FAILED" << std::endl;
            return 1;
        }

    } catch (const std::exception& e) {
        std::cerr << "Error: " << e.what() << std::endl;
        return 1;
    }

    return 0;
}
