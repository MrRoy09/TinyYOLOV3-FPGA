/*
 * yolo_inference.cpp - Standalone TinyYOLOv3 Inference
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

#include <opencv2/core.hpp>
#include <opencv2/imgcodecs.hpp>
#include <opencv2/imgproc.hpp>

#ifdef __ARM_NEON
#include <arm_neon.h>
#endif

#include "xrt/xrt_device.h"
#include "xrt/xrt_kernel.h"
#include "xrt/xrt_bo.h"
#include "ert.h"

#define STB_IMAGE_IMPLEMENTATION
#include "stb_image.h"

#include "yolo_postprocess.hpp"

void neon_batch_interleave(const std::vector<std::vector<uint8_t>>& og_outputs,
                           uint8_t* dst, int num_pixels, int num_ogs, int cout) {
#ifdef __ARM_NEON
    if (num_ogs == 2 && cout == 16) {
        const uint8_t* src0 = og_outputs[0].data();
        const uint8_t* src1 = og_outputs[1].data();
        for (int p = 0; p < num_pixels; p++) {
            vst1_u8(dst + p * 16, vld1_u8(src0 + p * 8));
            vst1_u8(dst + p * 16 + 8, vld1_u8(src1 + p * 8));
        }
    } else if (num_ogs == 4 && cout == 32) {
        const uint8_t* src0 = og_outputs[0].data();
        const uint8_t* src1 = og_outputs[1].data();
        const uint8_t* src2 = og_outputs[2].data();
        const uint8_t* src3 = og_outputs[3].data();
        for (int p = 0; p < num_pixels; p++) {
            vst1_u8(dst + p * 32, vld1_u8(src0 + p * 8));
            vst1_u8(dst + p * 32 + 8, vld1_u8(src1 + p * 8));
            vst1_u8(dst + p * 32 + 16, vld1_u8(src2 + p * 8));
            vst1_u8(dst + p * 32 + 24, vld1_u8(src3 + p * 8));
        }
    } else {
        for (int p = 0; p < num_pixels; p++) {
            uint8_t* pixel_dst = dst + p * cout;
            for (int og = 0; og < num_ogs; og++) {
                int valid_ch = std::min(8, cout - og * 8);
                if (valid_ch == 8) {
                    vst1_u8(pixel_dst + og * 8, vld1_u8(og_outputs[og].data() + p * 8));
                } else {
                    std::memcpy(pixel_dst + og * 8, og_outputs[og].data() + p * 8, valid_ch);
                }
            }
        }
    }
#else
    for (int p = 0; p < num_pixels; p++) {
        uint8_t* pixel_dst = dst + p * cout;
        for (int og = 0; og < num_ogs; og++) {
            int valid_ch = std::min(8, cout - og * 8);
            std::memcpy(pixel_dst + og * 8, og_outputs[og].data() + p * 8, valid_ch);
        }
    }
#endif
}

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

bool g_no_batch = false;
bool g_optimal_batch = false;

const int OPTIMAL_BATCH[13] = {2, 4, 8, 16, 32, 64, 64, 32, 64, 32, 16, 32, 32};

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

// Normalize [0,255] to INT8 [0,127], pad channels 3→8, add 1-pixel zero border
std::vector<uint8_t> load_and_preprocess_image(const std::string& path, int target_size = 416) {
    cv::Mat img = cv::imread(path, cv::IMREAD_COLOR);
    if (img.empty()) {
        throw std::runtime_error("Cannot load image: " + path);
    }

    std::cout << "Loaded image: " << img.cols << "x" << img.rows << "x" << img.channels() << std::endl;

    cv::Mat resized;
    cv::resize(img, resized, cv::Size(target_size, target_size), 0, 0, cv::INTER_LINEAR);

    cv::Mat rgb;
    cv::cvtColor(resized, rgb, cv::COLOR_BGR2RGB);

    int padded_size = target_size + 2;
    int cin_pad = 8;
    std::vector<uint8_t> output(padded_size * padded_size * cin_pad, 0);

    for (int y = 0; y < target_size; y++) {
        const uint8_t* row = rgb.ptr<uint8_t>(y);
        uint8_t* dst_row = output.data() + ((y + 1) * padded_size + 1) * cin_pad;
        for (int x = 0; x < target_size; x++) {
            dst_row[0] = (row[0] + 1) >> 1;  // R
            dst_row[1] = (row[1] + 1) >> 1;  // G
            dst_row[2] = (row[2] + 1) >> 1;  // B
            row += 3;
            dst_row += cin_pad;
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

// Stride-1 maxpool: RTL skips row 0/col 0 of conv output.
// Pad to (H+3)x(W+3) so conv produces (H+1)x(W+1), maxpool yields HxH.
void pad_spatial_stride1(const std::vector<uint8_t>& input, int h, int w, int c,
                         std::vector<uint8_t>& output) {
    int padded_h = h + 3;
    int padded_w = w + 3;
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

struct PreloadedWeights {
    std::vector<std::vector<std::vector<uint8_t>>> weights;  // [layer][og]
    std::vector<std::vector<std::vector<uint8_t>>> biases;   // [layer][og]
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
    bufs.weight_buf_size = 8 * 1024 * 1024;   // 8MB
    bufs.bias_buf_size = 128 * 32;             // 4KB
    bufs.pixel_buf_size = 2 * 1024 * 1024;    // 2MB
    bufs.output_buf_size = 2 * 1024 * 1024;   // 2MB

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

    // URAM depth=4096, each OG needs ci_groups addresses
    int auto_max = 4096 / cfg.ci_groups;
    int max_og_per_chunk;
    if (g_no_batch)
        max_og_per_chunk = 1;
    else if (g_optimal_batch && layer_idx < 13 && OPTIMAL_BATCH[layer_idx] > 0)
        max_og_per_chunk = std::min(OPTIMAL_BATCH[layer_idx], auto_max);
    else
        max_og_per_chunk = auto_max;
    int num_chunks = (cfg.co_groups + max_og_per_chunk - 1) / max_og_per_chunk;

    int actual_padded_h = (cfg.maxpool_stride == 1) ? (cfg.out_h + 3) : cfg.padded_h;
    int actual_padded_w = (cfg.maxpool_stride == 1) ? (cfg.out_w + 3) : cfg.padded_w;

    size_t pixel_bytes = actual_padded_h * actual_padded_w * cfg.cin_pad;
    size_t weight_bytes_per_og = cfg.ci_groups * 8 * 8 * 16;  // ci_groups * 8banks * 8urams * 16B
    size_t output_bytes_per_og = cfg.out_h * cfg.out_w * 8;
    size_t output_stride_per_og = ((output_bytes_per_og + 4095) / 4096) * 4096;  // 4K aligned
    int num_pixels = cfg.out_h * cfg.out_w;

    auto dma_start = std::chrono::high_resolution_clock::now();
    std::memcpy(bufs.pixel_ptr, pixels.data(), std::min(pixels.size(), pixel_bytes));
    bufs.pixel_bo.sync(XCL_BO_SYNC_BO_TO_DEVICE, pixel_bytes, 0);
    auto dma_end = std::chrono::high_resolution_clock::now();

    if (layer_idx <= 2) {
        auto dma_us = std::chrono::duration_cast<std::chrono::microseconds>(dma_end - dma_start).count();
        std::cout << "  L" << layer_idx << " pixel DMA: " << (dma_us/1000.0) << "ms ("
                  << (pixel_bytes/1024) << "KB), batching: " << num_chunks << " chunk(s), "
                  << "max " << max_og_per_chunk << " OGs/chunk" << std::endl;
    }

    layer_output.resize(cfg.out_h * cfg.out_w * cfg.cout);

    std::vector<std::vector<uint8_t>> og_outputs(cfg.co_groups);

    for (int chunk = 0; chunk < num_chunks; chunk++) {
        int chunk_start_og = chunk * max_og_per_chunk;
        int ogs_in_chunk = std::min(max_og_per_chunk, cfg.co_groups - chunk_start_og);

        auto chunk_start = std::chrono::high_resolution_clock::now();

        for (int og_in_chunk = 0; og_in_chunk < ogs_in_chunk; og_in_chunk++) {
            int global_og = chunk_start_og + og_in_chunk;

            const auto& weights = pw.weights[layer_idx][global_og];
            const auto& biases = pw.biases[layer_idx][global_og];

            std::memcpy(bufs.weight_ptr + og_in_chunk * weight_bytes_per_og,
                       weights.data(),
                       std::min(weights.size(), weight_bytes_per_og));

            std::memcpy(bufs.bias_ptr + og_in_chunk * 32,
                       biases.data(),
                       std::min(biases.size(), static_cast<size_t>(32)));
        }

        size_t actual_weight_bytes = static_cast<size_t>(ogs_in_chunk) * weight_bytes_per_og;
        size_t actual_bias_bytes = static_cast<size_t>(ogs_in_chunk) * 32;
        bufs.weight_bo.sync(XCL_BO_SYNC_BO_TO_DEVICE, actual_weight_bytes, 0);
        bufs.bias_bo.sync(XCL_BO_SYNC_BO_TO_DEVICE, actual_bias_bytes, 0);

        xrt::run run(kernel);
        run.set_arg(0, bufs.weight_bo.address());
        run.set_arg(1, bufs.bias_bo.address());
        run.set_arg(2, bufs.pixel_bo.address());
        run.set_arg(3, bufs.output_bo.address());
        run.set_arg(4, static_cast<uint32_t>(weight_bytes_per_og));
        run.set_arg(5, static_cast<uint32_t>(32));
        run.set_arg(6, static_cast<uint32_t>(pixel_bytes));
        run.set_arg(7, static_cast<uint32_t>(output_bytes_per_og));
        run.set_arg(8, static_cast<uint32_t>(cfg.ci_groups));
        run.set_arg(9, static_cast<uint32_t>(ogs_in_chunk));
        run.set_arg(10, static_cast<uint32_t>(0));
        run.set_arg(11, static_cast<uint32_t>(cfg.cin_pad));
        run.set_arg(12, static_cast<uint32_t>(actual_padded_w));

        bool enable_hw_maxpool = (cfg.maxpool_stride != 0);
        run.set_arg(13, static_cast<uint32_t>(enable_hw_maxpool ? 1 : 0));
        run.set_arg(14, static_cast<uint32_t>(cfg.maxpool_stride == 2 ? 1 : 0));
        run.set_arg(15, cfg.quant_m);
        run.set_arg(16, cfg.quant_n);
        run.set_arg(17, static_cast<uint32_t>(cfg.use_relu));
        run.set_arg(18, static_cast<uint32_t>(cfg.kernel_1x1));
        run.set_arg(19, bufs.weight_bo);
        run.set_arg(20, bufs.bias_bo);
        run.set_arg(21, bufs.pixel_bo);
        run.set_arg(22, bufs.output_bo);

        auto compute_start = std::chrono::high_resolution_clock::now();
        run.start();
        run.wait(std::chrono::seconds(300));
        auto compute_end = std::chrono::high_resolution_clock::now();

        size_t actual_output_bytes = static_cast<size_t>(ogs_in_chunk) * output_stride_per_og;
        bufs.output_bo.sync(XCL_BO_SYNC_BO_FROM_DEVICE, actual_output_bytes, 0);

        for (int og_in_chunk = 0; og_in_chunk < ogs_in_chunk; og_in_chunk++) {
            int global_og = chunk_start_og + og_in_chunk;
            const uint8_t* og_output_ptr = bufs.output_ptr + og_in_chunk * output_stride_per_og;

            og_outputs[global_og].resize(num_pixels * 8);
            std::memcpy(og_outputs[global_og].data(), og_output_ptr, num_pixels * 8);
        }

        auto chunk_end = std::chrono::high_resolution_clock::now();
        if (layer_idx <= 2 || layer_idx == 6) {
            auto chunk_us = std::chrono::duration_cast<std::chrono::microseconds>(chunk_end - chunk_start).count();
            auto compute_us = std::chrono::duration_cast<std::chrono::microseconds>(compute_end - compute_start).count();
            std::cout << "  L" << layer_idx << " chunk " << chunk << ": " << ogs_in_chunk
                      << " OGs, compute=" << (compute_us/1000.0) << "ms, total="
                      << (chunk_us/1000.0) << "ms" << std::endl;
        }
    }

    auto interleave_start = std::chrono::high_resolution_clock::now();
    if (cfg.cout <= 8) {
        std::memcpy(layer_output.data(), og_outputs[0].data(), num_pixels * std::min(8, cfg.cout));
    } else {
        neon_batch_interleave(og_outputs, layer_output.data(), num_pixels, cfg.co_groups, cfg.cout);
    }
    auto interleave_end = std::chrono::high_resolution_clock::now();

    if (layer_idx <= 2) {
        auto interleave_us = std::chrono::duration_cast<std::chrono::microseconds>(interleave_end - interleave_start).count();
        std::cout << "  L" << layer_idx << " interleave: " << (interleave_us/1000.0) << "ms ("
                  << cfg.co_groups << " OGs)" << std::endl;
    }
}

int main(int argc, char* argv[]) {
    if (argc < 4) {
        std::cerr << "Usage: " << argv[0] << " <xclbin_file> <weights_dir> <image_path> [--no-batch]" << std::endl;
        std::cerr << "  --no-batch      : disable multi-OG batching (1 OG per kernel call)" << std::endl;
        std::cerr << "  --optimal-batch : use per-layer optimal batch limits" << std::endl;
        return 1;
    }

    std::string xclbin_file = argv[1];
    std::string weights_dir = argv[2];
    std::string image_path = argv[3];

    for (int i = 4; i < argc; i++) {
        if (std::string(argv[i]) == "--no-batch") {
            g_no_batch = true;
        } else if (std::string(argv[i]) == "--optimal-batch") {
            g_optimal_batch = true;
        }
    }

    std::cout << "TinyYOLOv3 Inference" << std::endl;
    if (g_no_batch) {
        std::cout << "  NO-BATCH MODE: 1 OG per kernel call" << std::endl;
    }
    if (g_optimal_batch) {
        std::cout << "  OPTIMAL-BATCH MODE: per-layer limits" << std::endl;
    }
    std::cout << "  XCLBIN: " << xclbin_file << std::endl;
    std::cout << "  Weights: " << weights_dir << std::endl;
    std::cout << "  Image: " << image_path << std::endl;

    try {
        std::cout << "\nPreprocessing image..." << std::endl;
        auto preprocess_start = std::chrono::high_resolution_clock::now();
        std::vector<uint8_t> input_pixels = load_and_preprocess_image(image_path);
        auto preprocess_end = std::chrono::high_resolution_clock::now();
        auto preprocess_ms = std::chrono::duration_cast<std::chrono::milliseconds>(preprocess_end - preprocess_start).count();
        std::cout << "Preprocessing: " << preprocess_ms << " ms" << std::endl;

        std::cout << "\nInitializing FPGA..." << std::endl;
        xrt::device device(0);
        auto uuid = device.load_xclbin(xclbin_file);
        xrt::kernel kernel(device, uuid, "TinyYOLOV3_HW_Complete");

        InferenceBuffers bufs;
        init_buffers(device, kernel, bufs);
        std::cout << "FPGA ready (buffers pre-allocated)" << std::endl;

        PreloadedWeights pw;
        preload_all_weights(weights_dir, pw);

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
                } else if (cfg.maxpool_stride == 1) {
                    pad_spatial_stride1(layer_output, prev_h, prev_w, prev_c, pixels);
                } else {
                    pad_spatial(layer_output, prev_h, prev_w, prev_c, pixels);
                }
            }

            if (i == 4) {
                // Run without HW maxpool, save conv output for layer 11 concat, then CPU maxpool
                LayerConfig cfg_no_mp = cfg;
                cfg_no_mp.maxpool_stride = 0;
                cfg_no_mp.out_h = 26;
                cfg_no_mp.out_w = 26;

                run_layer(device, kernel, cfg_no_mp, pixels, layer_output, i, bufs, pw);
                layer4_conv_output = layer_output;

                std::vector<uint8_t> pooled_output(13 * 13 * 256);
                cpu_maxpool_stride2(layer_output.data(), pooled_output.data(), 26, 26, 256);
                layer_output = pooled_output;
            } else {
                run_layer(device, kernel, cfg, pixels, layer_output, i, bufs, pw);
            }
            if (i == 7) layer7_output = layer_output;
            if (i == 9) layer9_output = layer_output;
            if (i == 12) layer12_output = layer_output;

            auto layer_end = std::chrono::high_resolution_clock::now();
            layer_times[i] = std::chrono::duration_cast<std::chrono::milliseconds>(layer_end - layer_start).count();
        }

        auto infer_end = std::chrono::high_resolution_clock::now();
        auto infer_ms = std::chrono::duration_cast<std::chrono::milliseconds>(infer_end - infer_start).count();

        std::cout << "\n=== Inference Complete: " << infer_ms << " ms ===" << std::endl;

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
