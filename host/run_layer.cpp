/*
 * run_layer.cpp - Generic TinyYOLOv3 Layer Execution
 *
 * Executes a single convolution layer on the FPGA for one output group.
 * Designed to be called by Python orchestrator for full inference.
 *
 * Usage:
 *   ./run_layer <xclbin> <layer_idx> <og_idx> <weights.bin> <biases.bin> \
 *               <pixels.bin> <output.bin> [config.json]
 *
 * Arguments:
 *   xclbin      - Path to FPGA bitstream
 *   layer_idx   - Layer index (0, 2, 4, 6, 8, 10, 12, 13, 14, 15, 18, 21, 22)
 *   og_idx      - Output group index (0 to co_groups-1)
 *   weights.bin - Binary weights file (72-bit padded to 128-bit)
 *   biases.bin  - Binary biases file (32-bit packed to 128-bit)
 *   pixels.bin  - Input pixels (64-bit NHWC)
 *   output.bin  - Output file path
 *   config.json - Optional layer config (otherwise uses built-in defaults)
 *
 * Build: make run_layer
 *
 * Output format:
 *   Binary INT8 data in NHWC format (H * W * 8 bytes per output group)
 */

#include <iostream>
#include <fstream>
#include <sstream>
#include <vector>
#include <string>
#include <cstring>
#include <cstdint>
#include <cstdlib>
#include <chrono>

#include "xrt/xrt_device.h"
#include "xrt/xrt_kernel.h"
#include "xrt/xrt_bo.h"
#include "ert.h"

// Layer configuration structure
struct LayerConfig {
    int layer_idx;
    int cin;
    int cout;
    int cin_padded;
    int ci_groups;
    int co_groups;
    int kernel_size;      // 1 or 3
    int img_width;        // Input spatial width (after padding)
    int img_height;       // Input spatial height (after padding)
    bool use_maxpool;
    int maxpool_stride;   // 1 or 2 (0 = no maxpool)
    bool use_relu;        // leaky ReLU
    uint32_t quant_m;     // Quantization multiplier
    uint32_t quant_n;     // Quantization shift
};

// Built-in layer configurations for TinyYOLOv3
// Updated dynamically based on actual spatial dimensions
LayerConfig getDefaultConfig(int layer_idx) {
    LayerConfig cfg = {};
    cfg.layer_idx = layer_idx;

    switch (layer_idx) {
        case 0:  // 416->208 (after maxpool)
            cfg.cin = 3; cfg.cout = 16;
            cfg.cin_padded = 8; cfg.ci_groups = 1; cfg.co_groups = 2;
            cfg.kernel_size = 3; cfg.img_width = 418; cfg.img_height = 418;
            cfg.use_maxpool = true; cfg.maxpool_stride = 2; cfg.use_relu = true;
            break;
        case 2:  // 208->104
            cfg.cin = 16; cfg.cout = 32;
            cfg.cin_padded = 16; cfg.ci_groups = 2; cfg.co_groups = 4;
            cfg.kernel_size = 3; cfg.img_width = 210; cfg.img_height = 210;
            cfg.use_maxpool = true; cfg.maxpool_stride = 2; cfg.use_relu = true;
            break;
        case 4:  // 104->52
            cfg.cin = 32; cfg.cout = 64;
            cfg.cin_padded = 32; cfg.ci_groups = 4; cfg.co_groups = 8;
            cfg.kernel_size = 3; cfg.img_width = 106; cfg.img_height = 106;
            cfg.use_maxpool = true; cfg.maxpool_stride = 2; cfg.use_relu = true;
            break;
        case 6:  // 52->26
            cfg.cin = 64; cfg.cout = 128;
            cfg.cin_padded = 64; cfg.ci_groups = 8; cfg.co_groups = 16;
            cfg.kernel_size = 3; cfg.img_width = 54; cfg.img_height = 54;
            cfg.use_maxpool = true; cfg.maxpool_stride = 2; cfg.use_relu = true;
            break;
        case 8:  // 26->13
            cfg.cin = 128; cfg.cout = 256;
            cfg.cin_padded = 128; cfg.ci_groups = 16; cfg.co_groups = 32;
            cfg.kernel_size = 3; cfg.img_width = 28; cfg.img_height = 28;
            cfg.use_maxpool = true; cfg.maxpool_stride = 2; cfg.use_relu = true;
            break;
        case 10: // 13->13 (stride-1 maxpool)
            cfg.cin = 256; cfg.cout = 512;
            cfg.cin_padded = 256; cfg.ci_groups = 32; cfg.co_groups = 64;
            cfg.kernel_size = 3; cfg.img_width = 15; cfg.img_height = 15;
            cfg.use_maxpool = true; cfg.maxpool_stride = 1; cfg.use_relu = true;
            break;
        case 12: // 13->13
            cfg.cin = 512; cfg.cout = 1024;
            cfg.cin_padded = 512; cfg.ci_groups = 64; cfg.co_groups = 128;
            cfg.kernel_size = 3; cfg.img_width = 15; cfg.img_height = 15;
            cfg.use_maxpool = false; cfg.maxpool_stride = 0; cfg.use_relu = true;
            break;
        case 13: // 1x1 conv, 1024->256
            cfg.cin = 1024; cfg.cout = 256;
            cfg.cin_padded = 1024; cfg.ci_groups = 128; cfg.co_groups = 32;
            cfg.kernel_size = 1; cfg.img_width = 13; cfg.img_height = 13;
            cfg.use_maxpool = false; cfg.maxpool_stride = 0; cfg.use_relu = true;
            break;
        case 14: // 3x3 conv, 256->512
            cfg.cin = 256; cfg.cout = 512;
            cfg.cin_padded = 256; cfg.ci_groups = 32; cfg.co_groups = 64;
            cfg.kernel_size = 3; cfg.img_width = 15; cfg.img_height = 15;
            cfg.use_maxpool = false; cfg.maxpool_stride = 0; cfg.use_relu = true;
            break;
        case 15: // 1x1 conv, 512->255 (detection head 1, linear)
            cfg.cin = 512; cfg.cout = 255;
            cfg.cin_padded = 512; cfg.ci_groups = 64; cfg.co_groups = 32;
            cfg.kernel_size = 1; cfg.img_width = 13; cfg.img_height = 13;
            cfg.use_maxpool = false; cfg.maxpool_stride = 0; cfg.use_relu = false;
            break;
        case 18: // 1x1 conv, 256->128
            cfg.cin = 256; cfg.cout = 128;
            cfg.cin_padded = 256; cfg.ci_groups = 32; cfg.co_groups = 16;
            cfg.kernel_size = 1; cfg.img_width = 13; cfg.img_height = 13;
            cfg.use_maxpool = false; cfg.maxpool_stride = 0; cfg.use_relu = true;
            break;
        case 21: // 3x3 conv, 384->256 (after concat)
            cfg.cin = 384; cfg.cout = 256;
            cfg.cin_padded = 384; cfg.ci_groups = 48; cfg.co_groups = 32;
            cfg.kernel_size = 3; cfg.img_width = 28; cfg.img_height = 28;
            cfg.use_maxpool = false; cfg.maxpool_stride = 0; cfg.use_relu = true;
            break;
        case 22: // 1x1 conv, 256->255 (detection head 2, linear)
            cfg.cin = 256; cfg.cout = 255;
            cfg.cin_padded = 256; cfg.ci_groups = 32; cfg.co_groups = 32;
            cfg.kernel_size = 1; cfg.img_width = 26; cfg.img_height = 26;
            cfg.use_maxpool = false; cfg.maxpool_stride = 0; cfg.use_relu = false;
            break;
        default:
            std::cerr << "Unknown layer index: " << layer_idx << std::endl;
            exit(1);
    }

    return cfg;
}

std::vector<uint8_t> readBinaryFile(const std::string& path) {
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

void writeBinaryFile(const std::string& path, const uint8_t* data, size_t size) {
    std::ofstream file(path, std::ios::binary);
    if (!file.is_open()) {
        throw std::runtime_error("Cannot create file: " + path);
    }
    file.write(reinterpret_cast<const char*>(data), size);
}

int main(int argc, char* argv[]) {
    if (argc < 8) {
        std::cerr << "Usage: " << argv[0] << " <xclbin> <layer_idx> <og_idx> "
                  << "<weights.bin> <biases.bin> <pixels.bin> <output.bin> "
                  << "[quant_m] [quant_n]" << std::endl;
        return 1;
    }

    std::string xclbin_file = argv[1];
    int layer_idx = std::atoi(argv[2]);
    int og_idx = std::atoi(argv[3]);
    std::string weights_file = argv[4];
    std::string biases_file = argv[5];
    std::string pixels_file = argv[6];
    std::string output_file = argv[7];

    // Get default config
    LayerConfig cfg = getDefaultConfig(layer_idx);

    // Optional: override quant params from command line
    if (argc >= 10) {
        cfg.quant_m = std::stoul(argv[8], nullptr, 0);
        cfg.quant_n = std::stoul(argv[9], nullptr, 0);
    }

    std::cout << "========================================" << std::endl;
    std::cout << " TinyYOLOv3 Layer " << layer_idx << " OG " << og_idx << std::endl;
    std::cout << "========================================" << std::endl;
    std::cout << "Config:" << std::endl;
    std::cout << "  cin=" << cfg.cin << " cout=" << cfg.cout << std::endl;
    std::cout << "  ci_groups=" << cfg.ci_groups << " co_groups=" << cfg.co_groups << std::endl;
    std::cout << "  kernel=" << cfg.kernel_size << "x" << cfg.kernel_size << std::endl;
    std::cout << "  img_size=" << cfg.img_width << "x" << cfg.img_height << std::endl;
    std::cout << "  maxpool=" << (cfg.use_maxpool ? "yes" : "no");
    if (cfg.use_maxpool) std::cout << " stride=" << cfg.maxpool_stride;
    std::cout << std::endl;
    std::cout << "  relu=" << (cfg.use_relu ? "leaky" : "linear") << std::endl;
    std::cout << "  quant_m=0x" << std::hex << cfg.quant_m << std::dec
              << " quant_n=" << cfg.quant_n << std::endl;

    try {
        // Load data files
        std::cout << "\nLoading data files..." << std::endl;
        auto weights = readBinaryFile(weights_file);
        auto biases = readBinaryFile(biases_file);
        auto pixels = readBinaryFile(pixels_file);

        std::cout << "  Weights: " << weights.size() << " bytes" << std::endl;
        std::cout << "  Biases:  " << biases.size() << " bytes" << std::endl;
        std::cout << "  Pixels:  " << pixels.size() << " bytes" << std::endl;

        // Calculate expected output size
        int out_h = cfg.img_height - (cfg.kernel_size == 3 ? 2 : 0);
        int out_w = cfg.img_width - (cfg.kernel_size == 3 ? 2 : 0);
        if (cfg.use_maxpool) {
            if (cfg.maxpool_stride == 2) {
                out_h /= 2;
                out_w /= 2;
            }
            // stride-1 keeps same size (with padding in maxpool)
        }
        size_t num_outputs = out_h * out_w;  // Number of 64-bit output words
        size_t output_bytes = num_outputs * 8;

        std::cout << "  Expected output: " << out_h << "x" << out_w << "x8 = "
                  << output_bytes << " bytes" << std::endl;

        // Initialize XRT
        std::cout << "\nInitializing XRT..." << std::endl;
        xrt::device device(0);
        std::cout << "  Device: " << device.get_info<xrt::info::device::name>() << std::endl;

        auto uuid = device.load_xclbin(xclbin_file);
        xrt::kernel kernel(device, uuid, "TinyYOLOV3_HW_Complete");
        std::cout << "  Kernel loaded" << std::endl;

        // Allocate buffers
        size_t weight_buf_size = std::max(weights.size(), size_t(4096));
        size_t bias_buf_size = std::max(biases.size(), size_t(4096));
        size_t pixel_buf_size = std::max(pixels.size(), size_t(4096));
        size_t output_buf_size = std::max(output_bytes, size_t(4096));

        xrt::bo weight_bo(device, weight_buf_size, kernel.group_id(19));
        xrt::bo bias_bo(device, bias_buf_size, kernel.group_id(20));
        xrt::bo pixel_bo(device, pixel_buf_size, kernel.group_id(21));
        xrt::bo output_bo(device, output_buf_size, kernel.group_id(22));

        auto weight_ptr = weight_bo.map<uint8_t*>();
        auto bias_ptr = bias_bo.map<uint8_t*>();
        auto pixel_ptr = pixel_bo.map<uint8_t*>();
        auto output_ptr = output_bo.map<uint8_t*>();

        // Copy input data
        std::memset(weight_ptr, 0, weight_buf_size);
        std::memset(bias_ptr, 0, bias_buf_size);
        std::memset(pixel_ptr, 0, pixel_buf_size);
        std::memset(output_ptr, 0, output_buf_size);

        std::memcpy(weight_ptr, weights.data(), weights.size());
        std::memcpy(bias_ptr, biases.data(), biases.size());
        std::memcpy(pixel_ptr, pixels.data(), pixels.size());

        weight_bo.sync(XCL_BO_SYNC_BO_TO_DEVICE);
        bias_bo.sync(XCL_BO_SYNC_BO_TO_DEVICE);
        pixel_bo.sync(XCL_BO_SYNC_BO_TO_DEVICE);
        output_bo.sync(XCL_BO_SYNC_BO_TO_DEVICE);

        // Configure and run kernel
        std::cout << "\nRunning kernel..." << std::endl;
        xrt::run run(kernel);

        // Set scalar arguments
        run.set_arg(0, weight_bo.address());
        run.set_arg(1, bias_bo.address());
        run.set_arg(2, pixel_bo.address());
        run.set_arg(3, output_bo.address());

        run.set_arg(4, static_cast<uint32_t>(weights.size()));
        run.set_arg(5, static_cast<uint32_t>(biases.size()));
        run.set_arg(6, static_cast<uint32_t>(pixels.size()));
        run.set_arg(7, static_cast<uint32_t>(output_bytes));

        run.set_arg(8, static_cast<uint32_t>(cfg.ci_groups));
        run.set_arg(9, static_cast<uint32_t>(1));  // Process 1 output group at a time
        run.set_arg(10, static_cast<uint32_t>(0)); // wt_base_addr (always 0 for single OG)
        run.set_arg(11, static_cast<uint32_t>(cfg.cin_padded));
        run.set_arg(12, static_cast<uint32_t>(cfg.img_width));
        run.set_arg(13, static_cast<uint32_t>(cfg.use_maxpool ? 1 : 0));
        run.set_arg(14, static_cast<uint32_t>(cfg.maxpool_stride == 2 ? 1 : 0));
        run.set_arg(15, cfg.quant_m);
        run.set_arg(16, cfg.quant_n);
        run.set_arg(17, static_cast<uint32_t>(cfg.use_relu ? 1 : 0));
        run.set_arg(18, static_cast<uint32_t>(cfg.kernel_size == 1 ? 1 : 0));

        run.set_arg(19, weight_bo);
        run.set_arg(20, bias_bo);
        run.set_arg(21, pixel_bo);
        run.set_arg(22, output_bo);

        auto start = std::chrono::high_resolution_clock::now();
        run.start();
        auto state = run.wait(std::chrono::seconds(30));
        auto end = std::chrono::high_resolution_clock::now();

        if (state == ERT_CMD_STATE_TIMEOUT) {
            std::cerr << "ERROR: Kernel timeout!" << std::endl;
            return 1;
        }

        auto duration_us = std::chrono::duration_cast<std::chrono::microseconds>(end - start).count();
        std::cout << "  Kernel completed in " << duration_us << " us" << std::endl;

        // Read output
        output_bo.sync(XCL_BO_SYNC_BO_FROM_DEVICE);

        // Write output file
        writeBinaryFile(output_file, output_ptr, output_bytes);
        std::cout << "\nOutput written to: " << output_file << std::endl;

        // Print first few output values for debugging
        std::cout << "First output pixels:" << std::endl;
        for (int i = 0; i < std::min(4, (int)(output_bytes / 8)); i++) {
            std::cout << "  [" << i << "]: ";
            for (int ch = 0; ch < 8; ch++) {
                int8_t val = static_cast<int8_t>(output_ptr[i * 8 + ch]);
                std::cout << std::setw(4) << static_cast<int>(val) << " ";
            }
            std::cout << std::endl;
        }

        std::cout << "\n*** SUCCESS ***" << std::endl;
        return 0;

    } catch (const std::exception& e) {
        std::cerr << "Error: " << e.what() << std::endl;
        return 1;
    }
}
