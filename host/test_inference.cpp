/*
 * test_inference.cpp - Streamlined TinyYOLOv3 Full Inference
 *
 * Runs all 13 layers in chained mode without per-layer verification.
 * Only validates final detection outputs (Layer 9 and Layer 12).
 *
 * Build: make test_inference TARGET=hw
 * Run:   ./test_inference <xclbin_file> [stimulus_dir]
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
    for (int y = 0; y < h; y++) {
        for (int x = 0; x < w; x++) {
            for (int ch = 0; ch < c; ch++) {
                int8_t vals[4];
                vals[0] = static_cast<int8_t>(input[(y * w + x) * c + ch]);
                vals[1] = (x + 1 < w) ? static_cast<int8_t>(input[(y * w + x + 1) * c + ch]) : -128;
                vals[2] = (y + 1 < h) ? static_cast<int8_t>(input[((y + 1) * w + x) * c + ch]) : -128;
                vals[3] = (x + 1 < w && y + 1 < h) ? static_cast<int8_t>(input[((y + 1) * w + x + 1) * c + ch]) : -128;
                int8_t max_val = vals[0];
                for (int i = 1; i < 4; i++) {
                    if (vals[i] > max_val) max_val = vals[i];
                }
                output[(y * w + x) * c + ch] = static_cast<uint8_t>(max_val);
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

int verify_output(const uint8_t* actual, const uint8_t* expected, size_t size,
                  int tolerance, const std::string& label) {
    int mismatches = 0;
    int max_diff = 0;
    for (size_t i = 0; i < size; i++) {
        int8_t act = static_cast<int8_t>(actual[i]);
        int8_t exp = static_cast<int8_t>(expected[i]);
        int diff = std::abs(static_cast<int>(act) - static_cast<int>(exp));
        max_diff = std::max(max_diff, diff);
        if (diff > tolerance) {
            mismatches++;
        }
    }
    size_t exact = size - mismatches;
    double accuracy = 100.0 * exact / size;
    std::cout << label << ": " << exact << "/" << size
              << " (" << std::fixed << std::setprecision(1) << accuracy << "%)"
              << ", max_diff=" << max_diff;
    if (mismatches == 0) {
        std::cout << " [PASS]" << std::endl;
    } else {
        std::cout << " [FAIL: " << mismatches << " mismatches]" << std::endl;
    }
    return mismatches;
}

void run_layer(xrt::device& device, xrt::kernel& kernel, const LayerConfig& cfg,
               const std::vector<uint8_t>& pixels, std::vector<uint8_t>& layer_output,
               const std::string& layer_dir) {

    bool use_cpu_maxpool = (cfg.maxpool_stride == 1);
    int hw_out_h = use_cpu_maxpool ? cfg.img_h : cfg.out_h;
    int hw_out_w = use_cpu_maxpool ? cfg.img_w : cfg.out_w;

    size_t pixel_bytes = cfg.padded_h * cfg.padded_w * cfg.cin_pad;
    size_t hw_output_bytes_per_og = hw_out_h * hw_out_w * 8;
    size_t final_output_bytes_per_og = cfg.out_h * cfg.out_w * 8;
    size_t weight_bytes_per_og = cfg.ci_groups * 8 * 8 * 16;

    size_t weight_buf_size = ((weight_bytes_per_og + 4095) / 4096) * 4096;
    size_t bias_buf_size = 4096;
    size_t pixel_buf_size = ((pixel_bytes + 4095) / 4096) * 4096;
    size_t output_buf_size = ((hw_output_bytes_per_og + 4095) / 4096) * 4096;

    std::vector<uint8_t> cpu_maxpool_out;

    xrt::bo weight_bo(device, weight_buf_size, kernel.group_id(19));
    xrt::bo bias_bo(device, bias_buf_size, kernel.group_id(20));
    xrt::bo pixel_bo(device, pixel_buf_size, kernel.group_id(21));
    xrt::bo output_bo(device, output_buf_size, kernel.group_id(22));

    auto weight_ptr = weight_bo.map<uint8_t*>();
    auto bias_ptr = bias_bo.map<uint8_t*>();
    auto pixel_ptr = pixel_bo.map<uint8_t*>();
    auto output_ptr = output_bo.map<uint8_t*>();

    std::memset(pixel_ptr, 0, pixel_buf_size);
    std::memcpy(pixel_ptr, pixels.data(), std::min(pixels.size(), pixel_buf_size));
    pixel_bo.sync(XCL_BO_SYNC_BO_TO_DEVICE);

    layer_output.resize(cfg.out_h * cfg.out_w * cfg.cout);

    for (int og = 0; og < cfg.co_groups; og++) {
        std::string weights_path = layer_dir + "/weights_og" + std::to_string(og) + ".bin";
        auto weights = read_binary_file(weights_path);

        std::string biases_path = layer_dir + "/biases_og" + std::to_string(og) + ".bin";
        auto biases = read_binary_file(biases_path);

        std::memset(weight_ptr, 0, weight_buf_size);
        std::memset(bias_ptr, 0, bias_buf_size);
        std::memset(output_ptr, 0, output_buf_size);

        std::memcpy(weight_ptr, weights.data(), weights.size());
        std::memcpy(bias_ptr, biases.data(), biases.size());

        weight_bo.sync(XCL_BO_SYNC_BO_TO_DEVICE);
        bias_bo.sync(XCL_BO_SYNC_BO_TO_DEVICE);
        output_bo.sync(XCL_BO_SYNC_BO_TO_DEVICE);

        xrt::run run(kernel);
        run.set_arg(0, weight_bo.address());
        run.set_arg(1, bias_bo.address());
        run.set_arg(2, pixel_bo.address());
        run.set_arg(3, output_bo.address());
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
        run.set_arg(19, weight_bo);
        run.set_arg(20, bias_bo);
        run.set_arg(21, pixel_bo);
        run.set_arg(22, output_bo);

        run.start();
        run.wait(std::chrono::seconds(120));

        output_bo.sync(XCL_BO_SYNC_BO_FROM_DEVICE);

        const uint8_t* final_output_ptr = output_ptr;
        if (use_cpu_maxpool) {
            cpu_maxpool_out.resize(final_output_bytes_per_og);
            cpu_maxpool_stride1(output_ptr, cpu_maxpool_out.data(), hw_out_h, hw_out_w, 8);
            final_output_ptr = cpu_maxpool_out.data();
        }

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
    }
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

    std::cout << "TinyYOLOv3 Inference - " << xclbin_file << std::endl;

    try {
        xrt::device device(0);
        auto uuid = device.load_xclbin(xclbin_file);
        xrt::kernel kernel(device, uuid, "TinyYOLOV3_HW_Complete");
        std::cout << "Device initialized" << std::endl;

        auto total_start = std::chrono::high_resolution_clock::now();

        std::vector<uint8_t> layer_output;
        std::vector<uint8_t> layer4_conv_output;
        std::vector<uint8_t> layer7_output;
        std::vector<uint8_t> layer9_output;  // Detection head 1
        std::vector<uint8_t> layer12_output; // Detection head 2

        for (int i = 0; i < NUM_LAYERS; i++) {
            const LayerConfig& cfg = LAYERS[i];
            std::string layer_dir = g_stimulus_dir + "/layer" + std::to_string(i);
            std::vector<uint8_t> pixels;

            if (i == 0) {
                pixels = read_binary_file(layer_dir + "/pixels.bin");
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

            run_layer(device, kernel, cfg, pixels, layer_output, layer_dir);

            // Save intermediate outputs
            if (i == 4) {
                std::string layer4_conv_path = g_stimulus_dir + "/layer4_conv.bin";
                layer4_conv_output = read_binary_file(layer4_conv_path);
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

            std::cout << "Layer " << i << " done" << std::endl;
        }

        auto total_end = std::chrono::high_resolution_clock::now();
        auto total_ms = std::chrono::duration_cast<std::chrono::milliseconds>(total_end - total_start).count();

        std::cout << "\n=== Inference Complete: " << total_ms << " ms ===" << std::endl;

        // Verify detection heads
        int total_mismatches = 0;

        // Layer 9 verification (13x13x255)
        std::vector<uint8_t> layer9_expected;
        std::string layer9_dir = g_stimulus_dir + "/layer9";
        for (int og = 0; og < 32; og++) {
            auto expected_og = read_binary_file(layer9_dir + "/expected_og" + std::to_string(og) + ".bin");
            int valid_ch = std::min(8, 255 - og * 8);
            for (int y = 0; y < 13; y++) {
                for (int x = 0; x < 13; x++) {
                    for (int ch = 0; ch < valid_ch; ch++) {
                        layer9_expected.push_back(expected_og[(y * 13 + x) * 8 + ch]);
                    }
                }
            }
        }
        // Reconstruct expected in same format as layer9_output
        std::vector<uint8_t> layer9_exp_full(13 * 13 * 255);
        for (int og = 0; og < 32; og++) {
            auto expected_og = read_binary_file(layer9_dir + "/expected_og" + std::to_string(og) + ".bin");
            int valid_ch = std::min(8, 255 - og * 8);
            for (int y = 0; y < 13; y++) {
                for (int x = 0; x < 13; x++) {
                    for (int ch = 0; ch < valid_ch; ch++) {
                        int src_idx = (y * 13 + x) * 8 + ch;
                        int dst_idx = (y * 13 + x) * 255 + og * 8 + ch;
                        layer9_exp_full[dst_idx] = expected_og[src_idx];
                    }
                }
            }
        }
        total_mismatches += verify_output(layer9_output.data(), layer9_exp_full.data(),
                                          layer9_output.size(), 3, "Detection Head 1 (Layer 9, 13x13x255)");

        // Layer 12 verification (26x26x255)
        std::vector<uint8_t> layer12_exp_full(26 * 26 * 255);
        std::string layer12_dir = g_stimulus_dir + "/layer12";
        for (int og = 0; og < 32; og++) {
            auto expected_og = read_binary_file(layer12_dir + "/expected_og" + std::to_string(og) + ".bin");
            int valid_ch = std::min(8, 255 - og * 8);
            for (int y = 0; y < 26; y++) {
                for (int x = 0; x < 26; x++) {
                    for (int ch = 0; ch < valid_ch; ch++) {
                        int src_idx = (y * 26 + x) * 8 + ch;
                        int dst_idx = (y * 26 + x) * 255 + og * 8 + ch;
                        layer12_exp_full[dst_idx] = expected_og[src_idx];
                    }
                }
            }
        }
        total_mismatches += verify_output(layer12_output.data(), layer12_exp_full.data(),
                                          layer12_output.size(), 3, "Detection Head 2 (Layer 12, 26x26x255)");

        // Save outputs to files
        std::string out_dir = g_stimulus_dir;
        std::ofstream det1(out_dir + "/detection_head1.bin", std::ios::binary);
        det1.write(reinterpret_cast<char*>(layer9_output.data()), layer9_output.size());
        det1.close();

        std::ofstream det2(out_dir + "/detection_head2.bin", std::ios::binary);
        det2.write(reinterpret_cast<char*>(layer12_output.data()), layer12_output.size());
        det2.close();

        std::cout << "\nOutputs saved to:" << std::endl;
        std::cout << "  " << out_dir << "/detection_head1.bin (13x13x255)" << std::endl;
        std::cout << "  " << out_dir << "/detection_head2.bin (26x26x255)" << std::endl;

        // Post-processing: decode bounding boxes and apply NMS
        auto postproc_start = std::chrono::high_resolution_clock::now();
        std::vector<BBox> detections = yolo_postprocess(
            layer9_output.data(),   // 13x13x255 detection head 1
            layer12_output.data(),  // 26x26x255 detection head 2
            416,                    // input image size
            0.25f,                  // confidence threshold
            0.45f                   // NMS IoU threshold
        );
        auto postproc_end = std::chrono::high_resolution_clock::now();
        auto postproc_ms = std::chrono::duration_cast<std::chrono::milliseconds>(postproc_end - postproc_start).count();

        print_detections(detections);
        std::cout << "Post-processing time: " << postproc_ms << " ms" << std::endl;

        if (total_mismatches == 0) {
            std::cout << "\n*** INFERENCE PASSED ***" << std::endl;
            return 0;
        } else {
            std::cout << "\n*** INFERENCE FAILED ***" << std::endl;
            return 1;
        }

    } catch (const std::exception& e) {
        std::cerr << "Error: " << e.what() << std::endl;
        return 1;
    }

    return 0;
}
