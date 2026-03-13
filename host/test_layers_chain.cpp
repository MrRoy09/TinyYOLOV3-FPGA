/*
 * test_layers_chain.cpp - Full TinyYOLOv3 Layer-by-Layer Test
 *
 * Runs all 13 layers with per-OG verification against golden expected outputs.
 *
 * Build: make test_layers_chain TARGET=hw
 * Run:   ./test_layers_chain <xclbin> [stimulus_dir] [options] [max_layers]
 *
 * Options:
 *   --isolated      : Test each layer independently using pre-computed inputs
 *   --no-batch      : 1 OG per kernel call
 *   --sweep-batch   : Test batch sizes 1,2,4,... per layer
 *   --optimal-batch : Use per-layer optimal batch limits
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
#include <algorithm>
#include <cctype>

#include "xrt/xrt_device.h"
#include "xrt/xrt_kernel.h"
#include "xrt/xrt_bo.h"
#include "ert.h"

struct LayerConfig {
    int hw_layer;
    int cin, cout;
    int cin_pad;
    int ci_groups, co_groups;
    int img_h, img_w;
    int padded_h, padded_w;
    int out_h, out_w;
    int maxpool_stride;  // 0=none, 1=stride-1, 2=stride-2
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
int g_max_layers = 0;
bool g_stop_on_mismatch = false;
bool g_isolated_mode = false;
bool g_no_batch = false;
int g_max_batch = 0;  // 0=auto (4096/ci_groups)
bool g_sweep_batch = false;
bool g_optimal_batch = false;

int g_per_layer_batch[13] = {2, 4, 8, 16, 32, 64, 64, 32, 64, 32, 16, 32, 32};

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

void cpu_concat_channels(const uint8_t* a, int ca,
                         const uint8_t* b, int cb,
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

    // URAM depth=4096, each OG needs ci_groups addresses
    int auto_max = 4096 / cfg.ci_groups;
    int max_og_per_chunk = g_no_batch ? 1 : (g_max_batch > 0 ? std::min(g_max_batch, auto_max) : auto_max);
    int num_chunks = (cfg.co_groups + max_og_per_chunk - 1) / max_og_per_chunk;

    std::cout << "  BATCHING: max_og_per_chunk=" << max_og_per_chunk
              << ", num_chunks=" << num_chunks << std::endl;

    int hw_out_h = cfg.out_h;
    int hw_out_w = cfg.out_w;

    if (cfg.maxpool_stride == 1) {
        std::cout << "  NOTE: HW stride-1 maxpool (conv produces " << (cfg.out_h + 1) << "x" << (cfg.out_w + 1) << ")" << std::endl;
    } else if (cfg.maxpool_stride == 0) {
        std::cout << "  NOTE: No maxpool (conv only)" << std::endl;
    }

    int actual_padded_h = (cfg.maxpool_stride == 1) ? (cfg.out_h + 3) : cfg.padded_h;
    int actual_padded_w = (cfg.maxpool_stride == 1) ? (cfg.out_w + 3) : cfg.padded_w;
    size_t pixel_bytes = actual_padded_h * actual_padded_w * cfg.cin_pad;
    size_t output_bytes_per_og = hw_out_h * hw_out_w * 8;
    size_t weight_bytes_per_og = cfg.ci_groups * 8 * 8 * 16;

    size_t output_stride_per_og = ((output_bytes_per_og + 4095) / 4096) * 4096;

    int chunk_size = std::min(max_og_per_chunk, cfg.co_groups);
    size_t total_weight_bytes = chunk_size * weight_bytes_per_og;
    size_t total_bias_bytes = chunk_size * 32;
    size_t total_output_bytes = chunk_size * output_stride_per_og;

    size_t weight_buf_size = ((total_weight_bytes + 4095) / 4096) * 4096;
    size_t bias_buf_size = ((total_bias_bytes + 4095) / 4096) * 4096;
    size_t pixel_buf_size = ((pixel_bytes + 4095) / 4096) * 4096;
    size_t output_buf_size = ((total_output_bytes + 4095) / 4096) * 4096;

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
    pixel_bo.sync(XCL_BO_SYNC_BO_TO_DEVICE, std::min(pixels.size(), pixel_buf_size), 0);

    layer_output.resize(cfg.out_h * cfg.out_w * cfg.cout);
    int total_mismatches = 0;

    auto layer_start = std::chrono::high_resolution_clock::now();

    for (int chunk = 0; chunk < num_chunks; chunk++) {
        int chunk_start_og = chunk * max_og_per_chunk;
        int ogs_in_chunk = std::min(max_og_per_chunk, cfg.co_groups - chunk_start_og);

        std::cout << "  Chunk " << chunk << ": OGs " << chunk_start_og
                  << "-" << (chunk_start_og + ogs_in_chunk - 1) << std::endl;

        std::memset(weight_ptr, 0, weight_buf_size);
        std::memset(bias_ptr, 0, bias_buf_size);
        std::memset(output_ptr, 0, output_buf_size);

        for (int og_in_chunk = 0; og_in_chunk < ogs_in_chunk; og_in_chunk++) {
            int global_og = chunk_start_og + og_in_chunk;

            std::string weights_path = layer_dir + "/weights_og" + std::to_string(global_og) + ".bin";
            auto weights = read_binary_file(weights_path);
            std::memcpy(weight_ptr + og_in_chunk * weight_bytes_per_og,
                       weights.data(),
                       std::min(weights.size(), weight_bytes_per_og));

            std::string biases_path = layer_dir + "/biases_og" + std::to_string(global_og) + ".bin";
            auto biases = read_binary_file(biases_path);
            std::memcpy(bias_ptr + og_in_chunk * 32,
                       biases.data(),
                       std::min(biases.size(), static_cast<size_t>(32)));
        }

        size_t actual_wt_bytes = static_cast<size_t>(ogs_in_chunk) * weight_bytes_per_og;
        size_t actual_bias_bytes = static_cast<size_t>(ogs_in_chunk) * 32;
        size_t actual_out_bytes = static_cast<size_t>(ogs_in_chunk) * output_stride_per_og;
        weight_bo.sync(XCL_BO_SYNC_BO_TO_DEVICE, actual_wt_bytes, 0);
        bias_bo.sync(XCL_BO_SYNC_BO_TO_DEVICE, actual_bias_bytes, 0);
        output_bo.sync(XCL_BO_SYNC_BO_TO_DEVICE, actual_out_bytes, 0);

        xrt::run run(kernel);
        run.set_arg(0, weight_bo.address());
        run.set_arg(1, bias_bo.address());
        run.set_arg(2, pixel_bo.address());
        run.set_arg(3, output_bo.address());
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
        run.set_arg(19, weight_bo);
        run.set_arg(20, bias_bo);
        run.set_arg(21, pixel_bo);
        run.set_arg(22, output_bo);

        run.start();
        auto state = run.wait(std::chrono::seconds(300));

        if (state == ERT_CMD_STATE_TIMEOUT) {
            std::cerr << "TIMEOUT on layer " << cfg.hw_layer << " chunk " << chunk << std::endl;
            return -1;
        }

        output_bo.sync(XCL_BO_SYNC_BO_FROM_DEVICE, actual_out_bytes, 0);

        for (int og_in_chunk = 0; og_in_chunk < ogs_in_chunk; og_in_chunk++) {
            int global_og = chunk_start_og + og_in_chunk;
            const uint8_t* og_output_ptr = output_ptr + og_in_chunk * output_stride_per_og;

            int valid_channels = std::min(8, cfg.cout - global_og * 8);
            for (int y = 0; y < cfg.out_h; y++) {
                for (int x = 0; x < cfg.out_w; x++) {
                    for (int ch = 0; ch < valid_channels; ch++) {
                        int src_idx = (y * cfg.out_w + x) * 8 + ch;
                        int dst_idx = (y * cfg.out_w + x) * cfg.cout + global_og * 8 + ch;
                        layer_output[dst_idx] = og_output_ptr[src_idx];
                    }
                }
            }

            std::string expected_path = layer_dir + "/expected_og" + std::to_string(global_og) + ".bin";
            auto expected = read_binary_file(expected_path);

            int mismatches = compare_outputs(og_output_ptr, expected.data(),
                                            output_bytes_per_og, 3,
                                            "  OG" + std::to_string(global_og), false);
            total_mismatches += mismatches;
        }
    }

    auto layer_end = std::chrono::high_resolution_clock::now();
    auto layer_ms = std::chrono::duration_cast<std::chrono::milliseconds>(layer_end - layer_start).count();

    std::cout << "  Layer " << cfg.hw_layer << " total: " << cfg.co_groups << " OGs in "
              << layer_ms << " ms (" << num_chunks << " kernel calls), mismatches=" << total_mismatches << std::endl;

    return total_mismatches;
}

int main(int argc, char* argv[]) {
    if (argc < 2) {
        std::cerr << "Usage: " << argv[0] << " <xclbin_file> [stimulus_dir] [options] [max_layers]" << std::endl;
        std::cerr << "Options:" << std::endl;
        std::cerr << "  --isolated      : Test each layer independently with pre-computed inputs" << std::endl;
        std::cerr << "  --no-batch      : 1 OG per kernel call" << std::endl;
        std::cerr << "  --sweep-batch   : Test batch sizes 1,2,4,... per layer" << std::endl;
        std::cerr << "  --optimal-batch : Use per-layer optimal batch limits" << std::endl;
        return 1;
    }

    std::string xclbin_file = argv[1];

    for (int i = 2; i < argc; i++) {
        std::string arg = argv[i];
        if (arg == "--isolated" || arg == "-i") {
            g_isolated_mode = true;
        } else if (arg == "--no-batch") {
            g_no_batch = true;
        } else if (arg.substr(0, 12) == "--max-batch=") {
            g_max_batch = std::stoi(arg.substr(12));
        } else if (arg == "--sweep-batch") {
            g_sweep_batch = true;
            g_isolated_mode = true;
        } else if (arg == "--optimal-batch") {
            g_optimal_batch = true;
        } else if (arg[0] != '-') {
            if (std::isdigit(arg[0])) {
                g_max_layers = std::stoi(arg);
            } else {
                g_stimulus_dir = arg;
            }
        }
    }

    std::cout << "========================================" << std::endl;
    if (g_isolated_mode) {
        std::cout << " TinyYOLOv3 ISOLATED Layer Tests" << std::endl;
    } else {
        std::cout << " TinyYOLOv3 Full Inference (13 Layers)" << std::endl;
    }
    std::cout << "========================================" << std::endl;
    std::cout << "XCLBIN: " << xclbin_file << std::endl;
    std::cout << "Stimulus: " << g_stimulus_dir << std::endl;
    if (g_max_layers > 0) std::cout << "Max layers: " << g_max_layers << std::endl;
    if (g_no_batch) std::cout << "NO-BATCH MODE" << std::endl;
    if (g_max_batch > 0) std::cout << "MAX-BATCH: " << g_max_batch << std::endl;
    if (g_sweep_batch) std::cout << "SWEEP-BATCH MODE" << std::endl;
    if (g_optimal_batch) {
        std::cout << "OPTIMAL-BATCH: {";
        for (int i = 0; i < 13; i++) {
            if (i > 0) std::cout << ",";
            std::cout << g_per_layer_batch[i];
        }
        std::cout << "}" << std::endl;
    }

    try {
        std::cout << "\nInitializing XRT device..." << std::endl;
        xrt::device device(0);
        std::cout << "  Device: " << device.get_info<xrt::info::device::name>() << std::endl;

        auto uuid = device.load_xclbin(xclbin_file);
        xrt::kernel kernel(device, uuid, "TinyYOLOV3_HW_Complete");
        std::cout << "  Kernel loaded" << std::endl;

        // Sweep batch mode: test each layer at multiple batch sizes
        if (g_sweep_batch) {
            int layers_to_run = (g_max_layers > 0) ? std::min(g_max_layers, NUM_LAYERS) : NUM_LAYERS;

            struct SweepEntry {
                int batch_size;
                int mismatches;
                double time_ms;
            };
            struct LayerSweep {
                int max_safe_batch;
                double time_at_1;
                double time_at_max;
                std::vector<SweepEntry> entries;
            };
            std::vector<LayerSweep> results(layers_to_run);

            std::cout << "\n========================================" << std::endl;
            std::cout << " BATCH SIZE SWEEP (Isolated Mode)" << std::endl;
            std::cout << "========================================" << std::endl;

            for (int i = 0; i < layers_to_run; i++) {
                const LayerConfig& cfg = LAYERS[i];
                std::string layer_dir = g_stimulus_dir + "/layer" + std::to_string(i);
                auto pixels = read_binary_file(layer_dir + "/pixels.bin");
                std::vector<uint8_t> layer_output;

                int auto_max = 4096 / cfg.ci_groups;
                int max_batch = std::min(auto_max, cfg.co_groups);

                std::cout << "\n--- Layer " << i << ": " << cfg.cin << ">" << cfg.cout
                          << " ci=" << cfg.ci_groups << " co=" << cfg.co_groups
                          << " max_possible=" << max_batch << " ---" << std::endl;

                results[i].max_safe_batch = 0;
                results[i].time_at_1 = 0;
                results[i].time_at_max = 0;

                std::vector<int> batch_sizes;
                for (int bs = 1; bs <= max_batch; bs *= 2) {
                    batch_sizes.push_back(bs);
                }
                if (batch_sizes.back() < max_batch) {
                    batch_sizes.push_back(max_batch);
                }

                for (int bs : batch_sizes) {
                    g_max_batch = bs;

                    auto t0 = std::chrono::high_resolution_clock::now();
                    int mismatches = run_layer(device, kernel, cfg, pixels, layer_output, layer_dir);
                    auto t1 = std::chrono::high_resolution_clock::now();
                    double ms = std::chrono::duration<double, std::milli>(t1 - t0).count();

                    results[i].entries.push_back({bs, mismatches, ms});

                    if (bs == 1) results[i].time_at_1 = ms;

                    if (mismatches == 0) {
                        results[i].max_safe_batch = bs;
                        results[i].time_at_max = ms;
                        std::cout << "  batch=" << std::setw(5) << bs
                                  << ": PASS  " << std::fixed << std::setprecision(1) << ms << " ms"
                                  << "  (" << ((cfg.co_groups + bs - 1) / bs) << " kernel calls)" << std::endl;
                    } else {
                        std::cout << "  batch=" << std::setw(5) << bs
                                  << ": FAIL  " << mismatches << " mismatches, "
                                  << std::fixed << std::setprecision(1) << ms << " ms" << std::endl;
                        break;
                    }
                }
            }

            // Summary table
            std::cout << "\n========================================" << std::endl;
            std::cout << " SWEEP RESULTS SUMMARY" << std::endl;
            std::cout << "========================================" << std::endl;
            std::cout << "\n Layer | ci  | co  | MaxBatch | Calls@1 | Calls@Max | Time@1   | Time@Max | Speedup" << std::endl;
            std::cout << "-------+-----+-----+----------+---------+-----------+----------+----------+--------" << std::endl;

            double total_t1 = 0, total_tmax = 0;
            for (int i = 0; i < layers_to_run; i++) {
                const LayerConfig& cfg = LAYERS[i];
                int max_safe = results[i].max_safe_batch;
                double t1 = results[i].time_at_1;
                double tmax = results[i].time_at_max;
                if (tmax <= 0) tmax = t1;

                int calls_at_1 = cfg.co_groups;
                int calls_at_max = max_safe > 0 ? (cfg.co_groups + max_safe - 1) / max_safe : cfg.co_groups;

                total_t1 += t1;
                total_tmax += tmax;

                double speedup = (tmax > 0) ? t1 / tmax : 1.0;
                std::cout << "   " << std::setw(2) << i
                          << "  | " << std::setw(3) << cfg.ci_groups
                          << " | " << std::setw(3) << cfg.co_groups
                          << " | " << std::setw(8) << max_safe
                          << " | " << std::setw(7) << calls_at_1
                          << " | " << std::setw(9) << calls_at_max
                          << " | " << std::setw(7) << std::fixed << std::setprecision(1) << t1 << "ms"
                          << " | " << std::setw(7) << std::fixed << std::setprecision(1) << tmax << "ms"
                          << " | " << std::setprecision(2) << speedup << "x" << std::endl;
            }
            std::cout << "-------+-----+-----+----------+---------+-----------+----------+----------+--------" << std::endl;
            double total_speedup = (total_tmax > 0) ? total_t1 / total_tmax : 1.0;
            std::cout << " TOTAL |     |     |          | "
                      << std::setw(7) << "" << " | " << std::setw(9) << ""
                      << " | " << std::setw(7) << std::fixed << std::setprecision(1) << total_t1 << "ms"
                      << " | " << std::setw(7) << total_tmax << "ms"
                      << " | " << std::setprecision(2) << total_speedup << "x" << std::endl;

            std::cout << "\nint g_per_layer_batch[13] = {";
            for (int i = 0; i < NUM_LAYERS; i++) {
                if (i > 0) std::cout << ", ";
                if (i < layers_to_run) std::cout << results[i].max_safe_batch;
                else std::cout << "1";
            }
            std::cout << "};" << std::endl;

            return 0;
        }

        int total_mismatches = 0;
        auto total_start = std::chrono::high_resolution_clock::now();

        std::vector<uint8_t> layer_output;
        std::vector<uint8_t> padded_input;

        std::vector<uint8_t> layer4_conv_output;  // 26x26x256 (before maxpool, for concat)
        std::vector<uint8_t> layer7_output;       // 13x13x256 (for route to layer 10)

        std::vector<int> layer_mismatches(NUM_LAYERS, -1);
        std::vector<double> layer_times(NUM_LAYERS, 0);

        int layers_to_run = (g_max_layers > 0) ? std::min(g_max_layers, NUM_LAYERS) : NUM_LAYERS;
        for (int i = 0; i < layers_to_run; i++) {
            const LayerConfig& cfg = LAYERS[i];
            std::string layer_dir = g_stimulus_dir + "/layer" + std::to_string(i);
            std::vector<uint8_t> pixels;

            if (g_optimal_batch && i < 13) {
                g_max_batch = g_per_layer_batch[i];
            }

            if (g_isolated_mode) {
                std::cout << "  [ISOLATED] Loading pixels from stimulus" << std::endl;
                pixels = read_binary_file(layer_dir + "/pixels.bin");
            }
            else if (i == 0) {
                pixels = read_binary_file(layer_dir + "/pixels.bin");
            }
            else if (i == 10) {
                std::cout << "  [ROUTE] Using saved Layer 7 output" << std::endl;
                pixels = layer7_output;
            }
            else if (i == 11) {
                std::cout << "  [UPSAMPLE+CONCAT] Layer 10 (13x13x128) → 26x26x128 + Layer4 (26x26x256) → 384ch" << std::endl;
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

            auto layer_t0 = std::chrono::high_resolution_clock::now();
            int mismatches = run_layer(device, kernel, cfg, pixels, layer_output, layer_dir);
            auto layer_t1 = std::chrono::high_resolution_clock::now();
            layer_times[i] = std::chrono::duration<double, std::milli>(layer_t1 - layer_t0).count();

            if (mismatches < 0) {
                std::cerr << "Layer " << i << " failed!" << std::endl;
                return 1;
            }
            total_mismatches += mismatches;
            layer_mismatches[i] = mismatches;

            if (g_stop_on_mismatch && mismatches > 0) {
                std::cout << "\n*** STOPPING: Layer " << i << " has " << mismatches << " mismatches ***" << std::endl;
                break;
            }

            if (!g_isolated_mode) {
                if (i == 4) {
                    std::string layer4_conv_path = g_stimulus_dir + "/layer4_conv.bin";
                    std::ifstream test_file(layer4_conv_path);
                    if (test_file.good()) {
                        test_file.close();
                        layer4_conv_output = read_binary_file(layer4_conv_path);
                        std::cout << "  [SAVE] Loaded Layer 4 conv output (26x26x256) from file" << std::endl;
                    } else {
                        std::cout << "  [WARN] Layer 4 conv output file not found" << std::endl;
                        layer4_conv_output.resize(26 * 26 * 256);
                    }
                }
                if (i == 7) {
                    layer7_output = layer_output;
                    std::cout << "  [SAVE] Layer 7 output (13x13x256) for route" << std::endl;
                }
            }
        }

        auto total_end = std::chrono::high_resolution_clock::now();
        auto total_ms = std::chrono::duration_cast<std::chrono::milliseconds>(total_end - total_start).count();

        std::cout << "\n========================================" << std::endl;
        if (g_isolated_mode) {
            std::cout << " ISOLATED LAYER TEST SUMMARY" << std::endl;
        } else {
            std::cout << " CHAIN TEST SUMMARY" << std::endl;
        }
        std::cout << "========================================" << std::endl;

        std::cout << "\n Layer |   Config      | Batch | Mismatches |  Time   | Status" << std::endl;
        std::cout << "-------+---------------+-------+------------+---------+--------" << std::endl;
        int passed = 0, failed = 0;
        for (int i = 0; i < layers_to_run; i++) {
            const LayerConfig& cfg = LAYERS[i];
            std::string config = std::to_string(cfg.cin) + ">" + std::to_string(cfg.cout);
            config += cfg.kernel_1x1 ? " 1x1" : " 3x3";

            int batch_used = g_no_batch ? 1 : (g_optimal_batch && i < 13 ? g_per_layer_batch[i] : g_max_batch);
            if (batch_used <= 0) {
                int auto_max = 4096 / cfg.ci_groups;
                batch_used = std::min(auto_max, cfg.co_groups);
            }

            std::cout << "   " << std::setw(2) << i
                      << "  | " << std::setw(13) << std::left << config << std::right
                      << " | " << std::setw(5) << batch_used << " | ";
            if (layer_mismatches[i] < 0) {
                std::cout << std::setw(10) << "N/A" << " | " << std::setw(7) << "N/A" << " | SKIP" << std::endl;
            } else if (layer_mismatches[i] == 0) {
                std::cout << std::setw(10) << "0" << " | " << std::setw(5) << std::fixed << std::setprecision(1)
                          << layer_times[i] << "ms | PASS" << std::endl;
                passed++;
            } else {
                std::cout << std::setw(10) << layer_mismatches[i] << " | " << std::setw(5) << std::fixed << std::setprecision(1)
                          << layer_times[i] << "ms | FAIL" << std::endl;
                failed++;
            }
        }
        std::cout << "-------+---------------+-------+------------+---------+--------" << std::endl;
        std::cout << "\nTotal time: " << total_ms << " ms" << std::endl;
        std::cout << "Passed: " << passed << "/" << layers_to_run << ", Failed: " << failed << std::endl;
        std::cout << "Total mismatches: " << total_mismatches << std::endl;

        if (total_mismatches == 0) {
            std::cout << "\n*** ALL LAYERS PASSED ***" << std::endl;
            return 0;
        } else {
            if (g_isolated_mode) {
                std::cout << "\n*** ISOLATED TEST FAILED ***" << std::endl;
            } else {
                std::cout << "\n*** CHAIN TEST FAILED ***" << std::endl;
                std::cout << "Run with --isolated to check if errors are RTL or propagation" << std::endl;
            }
            return 1;
        }

    } catch (const std::exception& e) {
        std::cerr << "Error: " << e.what() << std::endl;
        return 1;
    }

    return 0;
}
