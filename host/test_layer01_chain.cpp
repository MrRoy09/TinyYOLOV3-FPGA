/*
 * test_layer01_chain.cpp - Chain Layer 0 and Layer 1 execution
 *
 * Runs layer 0 (416x416x3 -> 208x208x16) then layer 1 (208x208x16 -> 104x104x32)
 * using hardware output from layer 0 as input to layer 1.
 *
 * This tests the dataflow staging between layers.
 *
 * Build: make test_layer01_chain TARGET=hw
 * Run:   ./test_layer01_chain <xclbin_file> <l0_stimulus_dir> <l1_stimulus_dir>
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

// ============================================================================
// Layer Configurations
// ============================================================================

struct LayerConfig {
    int img_h, img_w;
    int padded_h, padded_w;
    int cin, cin_pad;
    int cout;
    int ci_groups, co_groups;
    int out_h, out_w;
    bool use_maxpool;
    int maxpool_stride;
    std::string name;
    // Calibrated quantization params from hardware_sim.py (per-layer, same for all OGs)
    uint32_t calib_M;
    uint32_t calib_n;
};

// Layer 0: Conv 3->16 + MaxPool stride-2
// Calibrated M=0xC0 from quantized_params.npz
LayerConfig layer0_cfg = {
    .img_h = 416, .img_w = 416,
    .padded_h = 418, .padded_w = 418,
    .cin = 3, .cin_pad = 8,
    .cout = 16,
    .ci_groups = 1, .co_groups = 2,
    .out_h = 208, .out_w = 208,
    .use_maxpool = true,
    .maxpool_stride = 2,
    .name = "Layer0",
    .calib_M = 0xC0,  // CALIBRATED: hardware_sim.py l0_M
    .calib_n = 16
};

// Layer 2 (NPZ): Conv 16->32 + MaxPool stride-2
// This is what we call "Layer1" in the chain (second conv layer)
// Calibrated M=0x2BC from quantized_params.npz
LayerConfig layer1_cfg = {
    .img_h = 208, .img_w = 208,
    .padded_h = 210, .padded_w = 210,
    .cin = 16, .cin_pad = 16,
    .cout = 32,
    .ci_groups = 2, .co_groups = 4,
    .out_h = 104, .out_w = 104,
    .use_maxpool = true,
    .maxpool_stride = 2,
    .name = "Layer1",
    .calib_M = 0x2BC,  // CALIBRATED: hardware_sim.py l2_M (NPZ layer 2)
    .calib_n = 16
};

// ============================================================================
// Utility Functions
// ============================================================================

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

void write_binary_file(const std::string& path, const uint8_t* data, size_t size) {
    std::ofstream file(path, std::ios::binary);
    if (!file.is_open()) {
        throw std::runtime_error("Cannot create file: " + path);
    }
    file.write(reinterpret_cast<const char*>(data), size);
}

struct QuantParams {
    uint32_t M;
    uint32_t n;
};

std::vector<QuantParams> load_quant_params(const std::string& path, int co_groups,
                                           uint32_t fallback_M, uint32_t fallback_n) {
    std::vector<QuantParams> params(co_groups);

    // Initialize with fallback (calibrated) values
    for (int i = 0; i < co_groups; i++) {
        params[i].M = fallback_M;
        params[i].n = fallback_n;
    }

    std::ifstream file(path);
    if (!file.is_open()) {
        std::cout << "  Note: No quant_params.txt found, using calibrated M=0x"
                  << std::hex << fallback_M << std::dec << " n=" << fallback_n << std::endl;
        return params;
    }

    std::string line;
    int og = 0;
    while (std::getline(file, line) && og < co_groups) {
        if (line.empty() || line[0] == '#') continue;

        // Parse "ogN: M=0xXXXXXXXX n=YY"
        size_t m_pos = line.find("M=0x");
        size_t n_pos = line.find("n=");
        if (m_pos != std::string::npos && n_pos != std::string::npos) {
            params[og].M = std::stoul(line.substr(m_pos + 4, 8), nullptr, 16);
            params[og].n = std::stoul(line.substr(n_pos + 2));
            og++;
        }
    }

    // Verify all OGs use same M (per-layer quantization from hardware_sim.py)
    bool all_same = true;
    for (int i = 1; i < co_groups; i++) {
        if (params[i].M != params[0].M) all_same = false;
    }
    if (all_same) {
        std::cout << "  Using per-layer M=0x" << std::hex << params[0].M
                  << std::dec << " n=" << params[0].n << " (calibrated)" << std::endl;
    }

    return params;
}

int compare_outputs(const uint8_t* actual, const uint8_t* expected, size_t size,
                    int tolerance, int out_w) {
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
            if (mismatches <= 5) {
                size_t pixel = i / 8;
                size_t ch = i % 8;
                int y = pixel / out_w;
                int x = pixel % out_w;
                std::cout << "    MISMATCH [" << y << "," << x << "," << ch << "]: "
                          << "exp=" << static_cast<int>(exp)
                          << " act=" << static_cast<int>(act)
                          << " diff=" << diff << std::endl;
            }
        }
    }

    size_t exact = size - mismatches - close_matches;
    std::cout << "    Total: " << size << ", Exact: " << exact
              << " (" << std::fixed << std::setprecision(1) << (100.0 * exact / size) << "%)"
              << ", Within tol: " << close_matches
              << ", Mismatch: " << mismatches
              << ", MaxDiff: " << max_diff << std::endl;

    return mismatches;
}

// ============================================================================
// Run Single Layer
// ============================================================================

int run_layer(xrt::device& device,
              xrt::kernel& kernel,
              const LayerConfig& cfg,
              const std::string& stim_dir,
              const std::vector<uint8_t>& input_pixels,  // Use this if non-empty
              std::vector<uint8_t>& output_data,
              bool verify_expected) {

    std::cout << "\n========================================" << std::endl;
    std::cout << " " << cfg.name << ": " << cfg.cin << "->" << cfg.cout
              << " channels, " << cfg.img_h << "x" << cfg.img_w
              << " -> " << cfg.out_h << "x" << cfg.out_w << std::endl;
    std::cout << "========================================" << std::endl;

    // Load quant params (with calibrated fallback)
    auto quant_params = load_quant_params(stim_dir + "/quant_params.txt", cfg.co_groups,
                                          cfg.calib_M, cfg.calib_n);

    // Load or use provided pixels
    std::vector<uint8_t> pixels;
    if (input_pixels.empty()) {
        pixels = read_binary_file(stim_dir + "/pixels.bin");
        std::cout << "Loaded pixels from file: " << pixels.size() << " bytes" << std::endl;
    } else {
        // Convert previous layer output to padded input
        // Previous output is (out_h, out_w, cout) int8
        // Need to add spatial padding for conv (1 pixel border)
        size_t prev_h = cfg.img_h;
        size_t prev_w = cfg.img_w;
        size_t prev_c = cfg.cin_pad;

        pixels.resize(cfg.padded_h * cfg.padded_w * cfg.cin_pad, 0);

        // Copy with padding (1 pixel border)
        for (size_t y = 0; y < prev_h; y++) {
            for (size_t x = 0; x < prev_w; x++) {
                for (size_t c = 0; c < prev_c; c++) {
                    size_t src_idx = (y * prev_w + x) * prev_c + c;
                    size_t dst_idx = ((y + 1) * cfg.padded_w + (x + 1)) * cfg.cin_pad + c;
                    pixels[dst_idx] = input_pixels[src_idx];
                }
            }
        }
        std::cout << "Padded previous output: " << prev_h << "x" << prev_w << "x" << prev_c
                  << " -> " << cfg.padded_h << "x" << cfg.padded_w << "x" << cfg.cin_pad << std::endl;
    }

    // Load expected outputs for verification
    std::vector<std::vector<uint8_t>> expected(cfg.co_groups);
    if (verify_expected) {
        for (int og = 0; og < cfg.co_groups; og++) {
            try {
                expected[og] = read_binary_file(stim_dir + "/expected_og" + std::to_string(og) + ".bin");
            } catch (...) {
                std::cout << "Warning: No expected file for OG" << og << std::endl;
            }
        }
    }

    // Calculate sizes
    size_t pixel_bytes = pixels.size();
    size_t output_bytes_per_og = cfg.out_h * cfg.out_w * 8;  // 8 channels per OG
    size_t weight_bytes_per_og = cfg.ci_groups * 8 * 8 * 9;  // ci_groups * 8 banks * 8 urams * 9 bytes
    // Round up to 16-byte alignment
    weight_bytes_per_og = ((weight_bytes_per_og + 15) / 16) * 16;
    (void)weight_bytes_per_og;  // Used for reference, actual size from file

    std::cout << "Pixel bytes: " << pixel_bytes << std::endl;
    std::cout << "Output bytes per OG: " << output_bytes_per_og << std::endl;
    std::cout << "Weight bytes per OG: " << weight_bytes_per_og << std::endl;

    // Allocate device buffers (4KB aligned)
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

    // Copy pixels (same for all output groups)
    std::memset(pixel_ptr, 0, pixel_buf_size);
    std::memcpy(pixel_ptr, pixels.data(), pixels.size());
    pixel_bo.sync(XCL_BO_SYNC_BO_TO_DEVICE);

    // Prepare output storage
    output_data.resize(cfg.co_groups * output_bytes_per_og);
    int total_mismatches = 0;

    auto total_start = std::chrono::high_resolution_clock::now();

    // Run each output group
    for (int og = 0; og < cfg.co_groups; og++) {
        std::cout << "\n--- Output Group " << og << " ---" << std::endl;

        // Load weights and biases
        auto weights = read_binary_file(stim_dir + "/weights_og" + std::to_string(og) + ".bin");
        auto biases = read_binary_file(stim_dir + "/biases_og" + std::to_string(og) + ".bin");

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
        // cfg_co_groups is used as cfg_output_group for bias addressing
        // Since we load biases per-OG to addresses 0,1 each time, always use 0
        run.set_arg(9, static_cast<uint32_t>(0));
        run.set_arg(10, static_cast<uint32_t>(0)); // wt_base_addr
        run.set_arg(11, static_cast<uint32_t>(cfg.cin_pad));
        run.set_arg(12, static_cast<uint32_t>(cfg.padded_w));

        run.set_arg(13, static_cast<uint32_t>(cfg.use_maxpool ? 1 : 0));
        run.set_arg(14, static_cast<uint32_t>(cfg.maxpool_stride == 2 ? 1 : 0));
        run.set_arg(15, quant_params[og].M);
        run.set_arg(16, quant_params[og].n);
        run.set_arg(17, static_cast<uint32_t>(1));  // use_relu (leaky)
        run.set_arg(18, static_cast<uint32_t>(0));  // kernel_1x1 = 0 (3x3)

        run.set_arg(19, weight_bo);
        run.set_arg(20, bias_bo);
        run.set_arg(21, pixel_bo);
        run.set_arg(22, output_bo);

        std::cout << "  M=0x" << std::hex << quant_params[og].M << std::dec
                  << " n=" << quant_params[og].n << std::endl;

        // Execute
        auto start = std::chrono::high_resolution_clock::now();
        run.start();
        auto state = run.wait(std::chrono::seconds(120));
        auto end = std::chrono::high_resolution_clock::now();
        auto duration_ms = std::chrono::duration_cast<std::chrono::milliseconds>(end - start).count();

        if (state == ERT_CMD_STATE_TIMEOUT) {
            std::cerr << "  TIMEOUT!" << std::endl;
            return -1;
        }
        std::cout << "  Kernel time: " << duration_ms << " ms" << std::endl;

        // Read output
        output_bo.sync(XCL_BO_SYNC_BO_FROM_DEVICE);

        // Store output
        std::memcpy(output_data.data() + og * output_bytes_per_og, output_ptr, output_bytes_per_og);

        // Print first 8 sample outputs for manual verification against expected_samples.txt
        std::cout << "  Sample outputs (compare with expected_samples.txt):" << std::endl;
        for (int sample = 0; sample < 8 && sample < cfg.out_w; sample++) {
            int r = 0;  // First row (pre-maxpool position, post-maxpool it's different)
            int c = sample;
            std::cout << "    og" << og << " [" << std::setw(3) << r << "," << std::setw(3) << c << "]:";
            for (int ch = 0; ch < 8; ch++) {
                size_t idx = (r * cfg.out_w + c) * 8 + ch;
                int8_t val = static_cast<int8_t>(output_ptr[idx]);
                std::cout << std::setw(5) << static_cast<int>(val);
            }
            std::cout << std::endl;
        }

        // Verify if expected data available
        if (verify_expected && !expected[og].empty()) {
            int mismatches = compare_outputs(output_ptr, expected[og].data(),
                                            output_bytes_per_og, 3, cfg.out_w);
            total_mismatches += mismatches;
        }
    }

    auto total_end = std::chrono::high_resolution_clock::now();
    auto total_ms = std::chrono::duration_cast<std::chrono::milliseconds>(total_end - total_start).count();

    std::cout << "\n" << cfg.name << " complete: " << total_ms << " ms total" << std::endl;
    std::cout << "Output: " << cfg.out_h << "x" << cfg.out_w << "x" << cfg.cout
              << " = " << (cfg.out_h * cfg.out_w * cfg.cout) << " values" << std::endl;

    return total_mismatches;
}

// ============================================================================
// Main
// ============================================================================

int main(int argc, char* argv[]) {
    if (argc < 4) {
        std::cerr << "Usage: " << argv[0]
                  << " <xclbin_file> <l0_stimulus_dir> <l1_stimulus_dir>" << std::endl;
        return 1;
    }

    std::string xclbin_file = argv[1];
    std::string l0_stim_dir = argv[2];
    std::string l1_stim_dir = argv[3];

    std::cout << "========================================" << std::endl;
    std::cout << " TinyYOLOv3 Layer 0+1 Chain Test" << std::endl;
    std::cout << "========================================" << std::endl;
    std::cout << "XCLBIN: " << xclbin_file << std::endl;
    std::cout << "L0 Stimulus: " << l0_stim_dir << std::endl;
    std::cout << "L1 Stimulus: " << l1_stim_dir << std::endl;

    try {
        // Initialize XRT
        std::cout << "\nInitializing XRT device..." << std::endl;
        xrt::device device(0);
        std::cout << "Device: " << device.get_info<xrt::info::device::name>() << std::endl;

        auto uuid = device.load_xclbin(xclbin_file);
        std::cout << "XCLBIN loaded" << std::endl;

        xrt::kernel kernel(device, uuid, "TinyYOLOV3_HW_Complete");
        std::cout << "Kernel loaded" << std::endl;

        // Run Layer 0
        std::vector<uint8_t> layer0_output;
        int l0_mismatches = run_layer(device, kernel, layer0_cfg, l0_stim_dir,
                                      {}, layer0_output, true);

        // Run Layer 1 using Layer 0 output
        std::vector<uint8_t> layer1_output;
        int l1_mismatches = run_layer(device, kernel, layer1_cfg, l1_stim_dir,
                                      layer0_output, layer1_output, true);

        // Summary
        std::cout << "\n========================================" << std::endl;
        std::cout << " SUMMARY" << std::endl;
        std::cout << "========================================" << std::endl;
        std::cout << "Layer 0: " << (l0_mismatches == 0 ? "PASS" : "FAIL")
                  << " (" << l0_mismatches << " mismatches)" << std::endl;
        std::cout << "Layer 1: " << (l1_mismatches == 0 ? "PASS" : "FAIL")
                  << " (" << l1_mismatches << " mismatches)" << std::endl;

        // Save layer 1 output for potential layer 2 use
        write_binary_file("layer1_output.bin", layer1_output.data(), layer1_output.size());
        std::cout << "\nLayer 1 output saved to: layer1_output.bin" << std::endl;

        return (l0_mismatches == 0 && l1_mismatches == 0) ? 0 : 1;

    } catch (const std::exception& e) {
        std::cerr << "Error: " << e.what() << std::endl;
        return 1;
    }
}
