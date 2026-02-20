/*
 * yolo_inference.cpp - Standalone TinyYOLOv3 Inference
 *
 * Loads image and weights directly, runs full inference on FPGA.
 * No pre-generated stimulus files needed.
 *
 * Build: make yolo_inference TARGET=hw
 * Run:   ./yolo_inference <xclbin_file> <weights_dir> <image_path>
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
#include <sstream>

#include "xrt/xrt_device.h"
#include "xrt/xrt_kernel.h"
#include "xrt/xrt_bo.h"
#include "ert.h"

#define STB_IMAGE_IMPLEMENTATION
#include "stb_image.h"

#include "yolo_postprocess.hpp"

struct LayerConfig {
    int hw_layer;
    int cin, cout;
    int cin_pad;
    int ci_groups, co_groups;
    int img_h, img_w;
    int padded_h, padded_w;
    int out_h, out_w;
    int maxpool_stride;
    uint32_t quant_m;
    uint32_t quant_n;
    int kernel_1x1;
    int use_relu;
};

const LayerConfig LAYERS[] = {
    {0,   3,   16,    8,   1,   2, 416, 416, 418, 418, 208, 208, 2, 0x000000C0, 16, 0, 1},
    {1,  16,   32,   16,   2,   4, 208, 208, 210, 210, 104, 104, 2, 0x000002BC, 16, 0, 1},
    {2,  32,   64,   32,   4,   8, 104, 104, 106, 106,  52,  52, 2, 0x000003CA, 16, 0, 1},
    {3,  64,  128,   64,   8,  16,  52,  52,  54,  54,  26,  26, 2, 0x0000022B, 16, 0, 1},
    {4, 128,  256,  128,  16,  32,  26,  26,  28,  28,  13,  13, 2, 0x00000230, 16, 0, 1},
    {5, 256,  512,  256,  32,  64,  13,  13,  15,  15,  13,  13, 1, 0x00000173, 16, 0, 1},
    {6,  512, 1024,  512,  64, 128,  13,  13,  15,  15,  13,  13, 0, 0x0000014E, 16, 0, 1},
    {7, 1024,  256, 1024, 128,  32,  13,  13,  13,  13,  13,  13, 0, 0x000003BD, 16, 1, 1},
    {8,  256,  512,  256,  32,  64,  13,  13,  15,  15,  13,  13, 0, 0x000000B7, 16, 0, 1},
    {9,  512,  255,  512,  64,  32,  13,  13,  13,  13,  13,  13, 0, 0x00000107, 16, 1, 0},
    {10, 256,  128,  256,  32,  16,  13,  13,  13,  13,  13,  13, 0, 0x0000047B, 16, 1, 1},
    {11, 384,  256,  384,  48,  32,  26,  26,  28,  28,  26,  26, 0, 0x000000A3, 16, 0, 1},
    {12, 256,  255,  256,  32,  32,  26,  26,  26,  26,  26,  26, 0, 0x000000B6, 16, 1, 0},
};
const int NUM_LAYERS = sizeof(LAYERS) / sizeof(LAYERS[0]);

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

// Load and preprocess image to 416x416 INT8 NHWC format with padding
std::vector<uint8_t> load_and_preprocess_image(const std::string& path, int target_size = 416) {
    int width, height, channels;
    unsigned char* img = stbi_load(path.c_str(), &width, &height, &channels, 3);
    if (!img) {
        throw std::runtime_error("Cannot load image: " + path);
    }

    std::cout << "Loaded image: " << width << "x" << height << "x" << channels << std::endl;

    // Resize to target_size x target_size using simple bilinear interpolation
    std::vector<float> resized(target_size * target_size * 3);
    float x_ratio = static_cast<float>(width) / target_size;
    float y_ratio = static_cast<float>(height) / target_size;

    for (int y = 0; y < target_size; y++) {
        for (int x = 0; x < target_size; x++) {
            float src_x = x * x_ratio;
            float src_y = y * y_ratio;
            int x0 = static_cast<int>(src_x);
            int y0 = static_cast<int>(src_y);
            int x1 = std::min(x0 + 1, width - 1);
            int y1 = std::min(y0 + 1, height - 1);
            float x_frac = src_x - x0;
            float y_frac = src_y - y0;

            for (int c = 0; c < 3; c++) {
                float v00 = img[(y0 * width + x0) * 3 + c];
                float v01 = img[(y0 * width + x1) * 3 + c];
                float v10 = img[(y1 * width + x0) * 3 + c];
                float v11 = img[(y1 * width + x1) * 3 + c];

                float v0 = v00 * (1 - x_frac) + v01 * x_frac;
                float v1 = v10 * (1 - x_frac) + v11 * x_frac;
                float v = v0 * (1 - y_frac) + v1 * y_frac;

                // BGR to RGB swap (YOLO expects RGB)
                int dst_c = (c == 0) ? 2 : (c == 2) ? 0 : c;
                resized[(y * target_size + x) * 3 + dst_c] = v;
            }
        }
    }
    stbi_image_free(img);

    // Normalize to [0, 1] and quantize to INT8 with scale=127
    // Output format: NHWC with 1-pixel zero padding (418x418x8)
    int padded_size = target_size + 2;
    int cin_pad = 8;  // Pad channels from 3 to 8
    std::vector<uint8_t> output(padded_size * padded_size * cin_pad, 0);

    for (int y = 0; y < target_size; y++) {
        for (int x = 0; x < target_size; x++) {
            for (int c = 0; c < 3; c++) {
                float val = resized[(y * target_size + x) * 3 + c] / 255.0f;
                int8_t qval = static_cast<int8_t>(std::round(val * 127.0f));
                int dst_idx = ((y + 1) * padded_size + (x + 1)) * cin_pad + c;
                output[dst_idx] = static_cast<uint8_t>(qval);
            }
        }
    }

    return output;
}

void pad_spatial(const std::vector<uint8_t>& input, int h, int w, int c,
                 std::vector<uint8_t>& output) {
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

void cpu_maxpool_stride1(const uint8_t* input, uint8_t* output, int h, int w, int c) {
    // Simple version - the maxpool is called per-OG (c=8), so not a huge cost
    for (int y = 0; y < h; y++) {
        for (int x = 0; x < w; x++) {
            for (int ch = 0; ch < c; ch++) {
                int8_t v0 = static_cast<int8_t>(input[(y * w + x) * c + ch]);
                int8_t v1 = (x + 1 < w) ? static_cast<int8_t>(input[(y * w + x + 1) * c + ch]) : -128;
                int8_t v2 = (y + 1 < h) ? static_cast<int8_t>(input[((y + 1) * w + x) * c + ch]) : -128;
                int8_t v3 = (x + 1 < w && y + 1 < h) ? static_cast<int8_t>(input[((y + 1) * w + x + 1) * c + ch]) : -128;
                int8_t max_val = v0;
                if (v1 > max_val) max_val = v1;
                if (v2 > max_val) max_val = v2;
                if (v3 > max_val) max_val = v3;
                output[(y * w + x) * c + ch] = static_cast<uint8_t>(max_val);
            }
        }
    }
}

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

void cpu_upsample_2x(const uint8_t* input, uint8_t* output, int h, int w, int c) {
    for (int y = 0; y < h; y++) {
        for (int x = 0; x < w; x++) {
            for (int ch = 0; ch < c; ch++) {
                uint8_t val = input[(y * w + x) * c + ch];
                output[((y*2  ) * (w*2) + (x*2  )) * c + ch] = val;
                output[((y*2  ) * (w*2) + (x*2+1)) * c + ch] = val;
                output[((y*2+1) * (w*2) + (x*2  )) * c + ch] = val;
                output[((y*2+1) * (w*2) + (x*2+1)) * c + ch] = val;
            }
        }
    }
}

void cpu_concat_channels(const uint8_t* a, int ca, const uint8_t* b, int cb,
                         uint8_t* output, int h, int w) {
    int c_out = ca + cb;
    for (int y = 0; y < h; y++) {
        for (int x = 0; x < w; x++) {
            for (int ch = 0; ch < ca; ch++) {
                output[(y * w + x) * c_out + ch] = a[(y * w + x) * ca + ch];
            }
            for (int ch = 0; ch < cb; ch++) {
                output[(y * w + x) * c_out + ca + ch] = b[(y * w + x) * cb + ch];
            }
        }
    }
}

// Pre-allocated buffers for inference (allocated once, reused across layers)
struct InferenceBuffers {
    xrt::bo weight_bo;
    xrt::bo bias_bo;
    xrt::bo pixel_bo;
    xrt::bo output_bo;
    uint8_t* weight_ptr;
    uint8_t* bias_ptr;
    uint8_t* pixel_ptr;
    uint8_t* output_ptr;
    size_t weight_buf_size;
    size_t bias_buf_size;
    size_t pixel_buf_size;
    size_t output_buf_size;
    bool initialized = false;
};

// Pre-loaded weights and biases (loaded once at startup)
struct PreloadedWeights {
    // weights[layer][og] = vector of weight data
    std::vector<std::vector<std::vector<uint8_t>>> weights;
    std::vector<std::vector<std::vector<uint8_t>>> biases;
    bool loaded = false;
};

void preload_all_weights(const std::string& weights_dir, PreloadedWeights& pw) {
    std::cout << "Preloading weights..." << std::flush;
    pw.weights.resize(NUM_LAYERS);
    pw.biases.resize(NUM_LAYERS);

    size_t total_bytes = 0;
    for (int layer = 0; layer < NUM_LAYERS; layer++) {
        const LayerConfig& cfg = LAYERS[layer];
        pw.weights[layer].resize(cfg.co_groups);
        pw.biases[layer].resize(cfg.co_groups);

        std::ostringstream layer_path;
        layer_path << weights_dir << "/layer" << cfg.hw_layer;

        for (int og = 0; og < cfg.co_groups; og++) {
            std::string wpath = layer_path.str() + "/weights_og" + std::to_string(og) + ".bin";
            pw.weights[layer][og] = read_binary_file(wpath);
            total_bytes += pw.weights[layer][og].size();

            std::string bpath = layer_path.str() + "/biases_og" + std::to_string(og) + ".bin";
            pw.biases[layer][og] = read_binary_file(bpath);
            total_bytes += pw.biases[layer][og].size();
        }
    }
    pw.loaded = true;
    std::cout << " done (" << (total_bytes / 1024 / 1024) << " MB)" << std::endl;
}

void init_buffers(xrt::device& device, xrt::kernel& kernel, InferenceBuffers& bufs) {
    // Allocate for largest layer requirements
    // Layer 0: pixels = 418*418*8 = 1.4MB, weights = 1*128*8*8 = 8KB
    // Layer 6: pixels = 15*15*512 = 115KB, weights = 64*128*8*8 = 524KB
    bufs.weight_buf_size = 1024 * 1024;      // 1MB (enough for largest ci_groups=128)
    bufs.bias_buf_size = 4096;
    bufs.pixel_buf_size = 2 * 1024 * 1024;   // 2MB (enough for 418*418*8)
    bufs.output_buf_size = 512 * 1024;       // 512KB (enough for 208*208*8)

    bufs.weight_bo = xrt::bo(device, bufs.weight_buf_size, kernel.group_id(19));
    bufs.bias_bo = xrt::bo(device, bufs.bias_buf_size, kernel.group_id(20));
    bufs.pixel_bo = xrt::bo(device, bufs.pixel_buf_size, kernel.group_id(21));
    bufs.output_bo = xrt::bo(device, bufs.output_buf_size, kernel.group_id(22));

    bufs.weight_ptr = bufs.weight_bo.map<uint8_t*>();
    bufs.bias_ptr = bufs.bias_bo.map<uint8_t*>();
    bufs.pixel_ptr = bufs.pixel_bo.map<uint8_t*>();
    bufs.output_ptr = bufs.output_bo.map<uint8_t*>();
    bufs.initialized = true;
}

void run_layer(xrt::device& device, xrt::kernel& kernel, const LayerConfig& cfg,
               const std::vector<uint8_t>& pixels, std::vector<uint8_t>& layer_output,
               int layer_idx, InferenceBuffers& bufs, PreloadedWeights& pw) {

    bool use_cpu_maxpool = (cfg.maxpool_stride == 1);
    int hw_out_h = use_cpu_maxpool ? cfg.img_h : cfg.out_h;
    int hw_out_w = use_cpu_maxpool ? cfg.img_w : cfg.out_w;

    size_t pixel_bytes = cfg.padded_h * cfg.padded_w * cfg.cin_pad;
    size_t hw_output_bytes_per_og = hw_out_h * hw_out_w * 8;
    size_t final_output_bytes_per_og = cfg.out_h * cfg.out_w * 8;

    std::vector<uint8_t> cpu_maxpool_out;

    // Use pre-allocated buffers
    auto dma_start = std::chrono::high_resolution_clock::now();
    std::memcpy(bufs.pixel_ptr, pixels.data(), std::min(pixels.size(), pixel_bytes));
    bufs.pixel_bo.sync(XCL_BO_SYNC_BO_TO_DEVICE);
    auto dma_end = std::chrono::high_resolution_clock::now();
    auto dma_ms = std::chrono::duration_cast<std::chrono::microseconds>(dma_end - dma_start).count();

    if (layer_idx <= 2) {
        std::cout << "  L" << layer_idx << " pixel DMA: " << (dma_ms/1000.0) << "ms (" << (pixel_bytes/1024) << "KB)" << std::endl;
    }

    layer_output.resize(cfg.out_h * cfg.out_w * cfg.cout);

    for (int og = 0; og < cfg.co_groups; og++) {
        auto og_start = std::chrono::high_resolution_clock::now();

        // Use preloaded weights from memory (no file I/O!)
        const auto& weights = pw.weights[layer_idx][og];
        const auto& biases = pw.biases[layer_idx][og];

        auto wt_start = std::chrono::high_resolution_clock::now();
        std::memcpy(bufs.weight_ptr, weights.data(), weights.size());
        std::memcpy(bufs.bias_ptr, biases.data(), biases.size());
        bufs.weight_bo.sync(XCL_BO_SYNC_BO_TO_DEVICE);
        bufs.bias_bo.sync(XCL_BO_SYNC_BO_TO_DEVICE);
        auto wt_end = std::chrono::high_resolution_clock::now();

        if (layer_idx == 0 && og == 0) {
            auto wt_us = std::chrono::duration_cast<std::chrono::microseconds>(wt_end - wt_start).count();
            std::cout << "  L0 OG0: weight_dma=" << (wt_us/1000.0) << "ms (" << weights.size() << " bytes)" << std::endl;
        }

        auto setarg_start = std::chrono::high_resolution_clock::now();
        xrt::run run(kernel);
        run.set_arg(0, bufs.weight_bo.address());
        run.set_arg(1, bufs.bias_bo.address());
        run.set_arg(2, bufs.pixel_bo.address());
        run.set_arg(3, bufs.output_bo.address());
        run.set_arg(4, static_cast<uint32_t>(weights.size()));
        run.set_arg(5, static_cast<uint32_t>(biases.size()));
        run.set_arg(6, static_cast<uint32_t>(pixel_bytes));
        run.set_arg(7, static_cast<uint32_t>(hw_output_bytes_per_og));
        run.set_arg(8, static_cast<uint32_t>(cfg.ci_groups));
        run.set_arg(9, static_cast<uint32_t>(0));
        run.set_arg(10, static_cast<uint32_t>(0));
        run.set_arg(11, static_cast<uint32_t>(cfg.cin_pad));
        run.set_arg(12, static_cast<uint32_t>(cfg.padded_w));
        run.set_arg(13, static_cast<uint32_t>(cfg.maxpool_stride == 2 ? 1 : 0));
        run.set_arg(14, static_cast<uint32_t>(cfg.maxpool_stride == 2 ? 1 : 0));
        run.set_arg(15, cfg.quant_m);
        run.set_arg(16, cfg.quant_n);
        run.set_arg(17, static_cast<uint32_t>(cfg.use_relu));
        run.set_arg(18, static_cast<uint32_t>(cfg.kernel_1x1));
        run.set_arg(19, bufs.weight_bo);
        run.set_arg(20, bufs.bias_bo);
        run.set_arg(21, bufs.pixel_bo);
        run.set_arg(22, bufs.output_bo);
        auto setarg_end = std::chrono::high_resolution_clock::now();

        auto compute_start = std::chrono::high_resolution_clock::now();
        run.start();
        run.wait(std::chrono::seconds(120));
        auto compute_end = std::chrono::high_resolution_clock::now();

        if (layer_idx == 0 && og == 0) {
            auto setarg_us = std::chrono::duration_cast<std::chrono::microseconds>(setarg_end - setarg_start).count();
            std::cout << "  L0 OG0: set_args=" << (setarg_us/1000.0) << "ms" << std::endl;
        }

        bufs.output_bo.sync(XCL_BO_SYNC_BO_FROM_DEVICE);
        auto output_end = std::chrono::high_resolution_clock::now();

        if (layer_idx == 0 && og == 0) {
            auto compute_us = std::chrono::duration_cast<std::chrono::microseconds>(compute_end - compute_start).count();
            auto output_us = std::chrono::duration_cast<std::chrono::microseconds>(output_end - compute_end).count();
            std::cout << "  L0 OG0: compute=" << (compute_us/1000.0) << "ms, output_dma=" << (output_us/1000.0) << "ms" << std::endl;
        }

        const uint8_t* final_output_ptr = bufs.output_ptr;
        if (use_cpu_maxpool) {
            cpu_maxpool_out.resize(final_output_bytes_per_og);
            cpu_maxpool_stride1(bufs.output_ptr, cpu_maxpool_out.data(), hw_out_h, hw_out_w, 8);
            final_output_ptr = cpu_maxpool_out.data();
        }

        auto copy_start = std::chrono::high_resolution_clock::now();
        int valid_channels = std::min(8, cfg.cout - og * 8);
        int pixels = cfg.out_h * cfg.out_w;

        // Ultra-fast copy using 64-bit moves for 8 channels
        if (cfg.cout == 8) {
            // Single OG: direct bulk copy
            std::memcpy(layer_output.data(), final_output_ptr, pixels * 8);
        } else if (valid_channels == 8) {
            // Full 8 channels per OG: use 64-bit copy
            const uint64_t* src = reinterpret_cast<const uint64_t*>(final_output_ptr);
            uint8_t* dst_base = layer_output.data() + og * 8;
            for (int p = 0; p < pixels; p++) {
                *reinterpret_cast<uint64_t*>(dst_base + p * cfg.cout) = src[p];
            }
        } else {
            // Partial channels (last OG with cout not multiple of 8)
            const uint8_t* src = final_output_ptr;
            uint8_t* dst_base = layer_output.data() + og * 8;
            for (int p = 0; p < pixels; p++) {
                std::memcpy(dst_base + p * cfg.cout, src + p * 8, valid_channels);
            }
        }
        auto copy_end = std::chrono::high_resolution_clock::now();

        if (layer_idx == 0 && og == 0) {
            auto copy_us = std::chrono::duration_cast<std::chrono::microseconds>(copy_end - copy_start).count();
            auto og_us = std::chrono::duration_cast<std::chrono::microseconds>(copy_end - og_start).count();
            std::cout << "  L0 OG0: output_copy=" << (copy_us/1000.0) << "ms" << std::endl;
            std::cout << "  L0 OG0: TOTAL=" << (og_us/1000.0) << "ms" << std::endl;
        }
    }
}

int main(int argc, char* argv[]) {
    if (argc < 4) {
        std::cerr << "Usage: " << argv[0] << " <xclbin_file> <weights_dir> <image_path>" << std::endl;
        std::cerr << "  weights_dir: directory containing layer0/, layer1/, ... with weights_og*.bin files" << std::endl;
        return 1;
    }

    std::string xclbin_file = argv[1];
    std::string weights_dir = argv[2];
    std::string image_path = argv[3];

    std::cout << "TinyYOLOv3 Inference" << std::endl;
    std::cout << "  XCLBIN: " << xclbin_file << std::endl;
    std::cout << "  Weights: " << weights_dir << std::endl;
    std::cout << "  Image: " << image_path << std::endl;

    try {
        // Load and preprocess image
        std::cout << "\nPreprocessing image..." << std::endl;
        auto preprocess_start = std::chrono::high_resolution_clock::now();
        std::vector<uint8_t> input_pixels = load_and_preprocess_image(image_path);
        auto preprocess_end = std::chrono::high_resolution_clock::now();
        auto preprocess_ms = std::chrono::duration_cast<std::chrono::milliseconds>(preprocess_end - preprocess_start).count();
        std::cout << "Preprocessing: " << preprocess_ms << " ms" << std::endl;

        // Initialize XRT
        std::cout << "\nInitializing FPGA..." << std::endl;
        xrt::device device(0);
        auto uuid = device.load_xclbin(xclbin_file);
        xrt::kernel kernel(device, uuid, "TinyYOLOV3_HW_Complete");

        // Pre-allocate buffers (done once)
        InferenceBuffers bufs;
        init_buffers(device, kernel, bufs);
        std::cout << "FPGA ready (buffers pre-allocated)" << std::endl;

        // Preload all weights into memory (done once)
        PreloadedWeights pw;
        preload_all_weights(weights_dir, pw);

        // Run inference
        std::cout << "\nRunning inference..." << std::endl;
        auto infer_start = std::chrono::high_resolution_clock::now();

        std::vector<uint8_t> layer_output;
        std::vector<uint8_t> layer4_conv_output;
        std::vector<uint8_t> layer7_output;
        std::vector<uint8_t> layer9_output;
        std::vector<uint8_t> layer12_output;

        std::vector<long> layer_times(NUM_LAYERS);

        for (int i = 0; i < NUM_LAYERS; i++) {
            auto layer_start = std::chrono::high_resolution_clock::now();

            const LayerConfig& cfg = LAYERS[i];
            std::vector<uint8_t> pixels;

            if (i == 0) {
                pixels = input_pixels;
            }
            else if (i == 10) {
                pixels = layer7_output;
            }
            else if (i == 11) {
                std::vector<uint8_t> upsampled(26 * 26 * 128);
                cpu_upsample_2x(layer_output.data(), upsampled.data(), 13, 13, 128);
                std::vector<uint8_t> concat_out(26 * 26 * 384);
                cpu_concat_channels(upsampled.data(), 128,
                                   layer4_conv_output.data(), 256,
                                   concat_out.data(), 26, 26);
                pad_spatial(concat_out, 26, 26, 384, pixels);
            }
            else {
                int prev_h = LAYERS[i-1].out_h;
                int prev_w = LAYERS[i-1].out_w;
                int prev_c = LAYERS[i-1].cout;
                if (cfg.kernel_1x1) {
                    pixels = layer_output;
                } else {
                    pad_spatial(layer_output, prev_h, prev_w, prev_c, pixels);
                }
            }

            if (i == 4) {
                // Special handling for layer 4: run without HW maxpool, save conv output, then CPU maxpool
                // Create modified config with no maxpool
                LayerConfig cfg_no_mp = cfg;
                cfg_no_mp.maxpool_stride = 0;
                cfg_no_mp.out_h = 26;  // Conv output before maxpool
                cfg_no_mp.out_w = 26;

                // Run layer 4 without maxpool
                run_layer(device, kernel, cfg_no_mp, pixels, layer_output, i, bufs, pw);

                // Save conv output for concat at layer 11
                layer4_conv_output = layer_output;

                // Apply CPU stride-2 maxpool to get 13x13 output for layer 5
                std::vector<uint8_t> pooled_output(13 * 13 * 256);
                cpu_maxpool_stride2(layer_output.data(), pooled_output.data(), 26, 26, 256);
                layer_output = pooled_output;
            } else {
                run_layer(device, kernel, cfg, pixels, layer_output, i, bufs, pw);
            }
            if (i == 7) {
                layer7_output = layer_output;
            }
            if (i == 9) {
                layer9_output = layer_output;
            }
            if (i == 12) {
                layer12_output = layer_output;
            }

            auto layer_end = std::chrono::high_resolution_clock::now();
            layer_times[i] = std::chrono::duration_cast<std::chrono::milliseconds>(layer_end - layer_start).count();
        }

        auto infer_end = std::chrono::high_resolution_clock::now();
        auto infer_ms = std::chrono::duration_cast<std::chrono::milliseconds>(infer_end - infer_start).count();

        std::cout << "\n=== Inference Complete: " << infer_ms << " ms ===" << std::endl;

        // Per-layer timing breakdown
        std::cout << "\nPer-layer timing:" << std::endl;
        std::cout << "Layer | Cin→Cout | OGs | Time(ms) | ms/OG" << std::endl;
        std::cout << "------+----------+-----+----------+------" << std::endl;
        for (int i = 0; i < NUM_LAYERS; i++) {
            const LayerConfig& cfg = LAYERS[i];
            float ms_per_og = static_cast<float>(layer_times[i]) / cfg.co_groups;
            std::cout << std::setw(5) << i << " | "
                      << std::setw(4) << cfg.cin << "→" << std::setw(4) << cfg.cout << " | "
                      << std::setw(3) << cfg.co_groups << " | "
                      << std::setw(8) << layer_times[i] << " | "
                      << std::fixed << std::setprecision(2) << std::setw(5) << ms_per_og
                      << std::endl;
        }
        std::cout << "------+----------+-----+----------+------" << std::endl;

        // Post-processing
        auto postproc_start = std::chrono::high_resolution_clock::now();
        std::vector<BBox> detections = yolo_postprocess(
            layer9_output.data(),
            layer12_output.data(),
            416,
            0.25f,
            0.45f
        );
        auto postproc_end = std::chrono::high_resolution_clock::now();
        auto postproc_ms = std::chrono::duration_cast<std::chrono::milliseconds>(postproc_end - postproc_start).count();

        print_detections(detections);

        std::cout << "\nTiming Summary:" << std::endl;
        std::cout << "  Preprocessing: " << preprocess_ms << " ms" << std::endl;
        std::cout << "  FPGA Inference: " << infer_ms << " ms" << std::endl;
        std::cout << "  Post-processing: " << postproc_ms << " ms" << std::endl;
        std::cout << "  Total: " << (preprocess_ms + infer_ms + postproc_ms) << " ms" << std::endl;

    } catch (const std::exception& e) {
        std::cerr << "Error: " << e.what() << std::endl;
        return 1;
    }

    return 0;
}
