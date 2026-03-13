/*
 * yolo_arm_optimized.cpp - Optimized ARM INT8 TinyYOLOv3 Inference
 *
 * Same INT8 quantization as FPGA (M, n=16, leaky ReLU >>3).
 * Optimizations: im2col + NEON GEMM, 4-thread parallelism, cache-friendly layout.
 *
 * Build: make yolo_arm_optimized
 * Run:   ./yolo_arm_optimized <weights_dir> <image_path> [--benchmark N]
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
#include <thread>

#include <opencv2/core.hpp>
#include <opencv2/imgcodecs.hpp>
#include <opencv2/imgproc.hpp>

#ifdef __ARM_NEON
#include <arm_neon.h>
#endif

#include "yolo_postprocess.hpp"

static constexpr int NUM_THREADS = 4;

struct LayerConfig {
    int hw_layer, cin, cout, kernel, stride, pad, use_relu;
    int maxpool_stride;  // 0=none, 1=stride-1, 2=stride-2
    int img_h, img_w, out_h, out_w;
};

const LayerConfig LAYERS[] = {
    {  0,    3,   16,  3, 1, 1, 1, 2, 416, 416, 208, 208},
    {  1,   16,   32,  3, 1, 1, 1, 2, 208, 208, 104, 104},
    {  2,   32,   64,  3, 1, 1, 1, 2, 104, 104,  52,  52},
    {  3,   64,  128,  3, 1, 1, 1, 2,  52,  52,  26,  26},
    {  4,  128,  256,  3, 1, 1, 1, 2,  26,  26,  13,  13},
    {  5,  256,  512,  3, 1, 1, 1, 1,  13,  13,  13,  13},
    {  6,  512, 1024,  3, 1, 1, 1, 0,  13,  13,  13,  13},
    {  7, 1024,  256,  1, 1, 0, 1, 0,  13,  13,  13,  13},
    {  8,  256,  512,  3, 1, 1, 1, 0,  13,  13,  13,  13},
    {  9,  512,  255,  1, 1, 0, 0, 0,  13,  13,  13,  13},
    { 10,  256,  128,  1, 1, 0, 1, 0,  13,  13,  13,  13},
    { 11,  384,  256,  3, 1, 1, 1, 0,  26,  26,  26,  26},
    { 12,  256,  255,  1, 1, 0, 0, 0,  26,  26,  26,  26},
};
const int NUM_LAYERS = sizeof(LAYERS) / sizeof(LAYERS[0]);

struct LayerWeights {
    std::vector<int8_t> weights;   // [cout, cin, kh, kw]
    std::vector<int32_t> biases;   // [cout]
    uint32_t M, n;
    float o_scale;
    int use_relu;
};

struct ModelWeights {
    std::vector<LayerWeights> layers;
    float input_scale;
    float dequant_13x13, dequant_26x26;
};

template<typename T>
std::vector<T> read_binary_file(const std::string& path) {
    std::ifstream file(path, std::ios::binary | std::ios::ate);
    if (!file.is_open()) throw std::runtime_error("Cannot open: " + path);
    size_t sz = file.tellg();
    file.seekg(0);
    std::vector<T> data(sz / sizeof(T));
    file.read(reinterpret_cast<char*>(data.data()), sz);
    return data;
}

void load_model_weights(const std::string& dir, ModelWeights& model) {
    model.layers.resize(NUM_LAYERS);
    model.input_scale = 127.0f;

    for (int i = 0; i < NUM_LAYERS; i++) {
        std::string ld = dir + "/layer" + std::to_string(LAYERS[i].hw_layer);
        auto& lw = model.layers[i];
        lw.weights = read_binary_file<int8_t>(ld + "/weights.bin");
        lw.biases = read_binary_file<int32_t>(ld + "/biases.bin");

        std::ifstream cf(ld + "/config.bin", std::ios::binary);
        if (!cf.is_open()) throw std::runtime_error("Cannot open config: " + ld + "/config.bin");
        cf.read(reinterpret_cast<char*>(&lw.M), 4);
        cf.read(reinterpret_cast<char*>(&lw.n), 4);
        cf.read(reinterpret_cast<char*>(&lw.o_scale), 4);
        uint8_t flags[4];
        cf.read(reinterpret_cast<char*>(flags), 4);
        lw.use_relu = flags[0];
    }

    std::ifstream df(dir + "/dequant_scales.bin", std::ios::binary);
    if (df.is_open()) {
        df.read(reinterpret_cast<char*>(&model.dequant_13x13), 4);
        df.read(reinterpret_cast<char*>(&model.dequant_26x26), 4);
    } else {
        model.dequant_13x13 = DEQUANT_SCALE_13x13;
        model.dequant_26x26 = DEQUANT_SCALE_26x26;
    }
}

std::vector<int8_t> load_and_preprocess_image(const std::string& path) {
    cv::Mat img = cv::imread(path, cv::IMREAD_COLOR);
    if (img.empty()) throw std::runtime_error("Cannot load: " + path);
    std::cout << "Loaded image: " << img.cols << "x" << img.rows << "x3" << std::endl;

    cv::Mat resized, rgb;
    cv::resize(img, resized, cv::Size(416, 416));
    cv::cvtColor(resized, rgb, cv::COLOR_BGR2RGB);

    std::vector<int8_t> out(3 * 416 * 416);
    for (int y = 0; y < 416; y++) {
        const uint8_t* row = rgb.ptr<uint8_t>(y);
        for (int x = 0; x < 416; x++) {
            out[0 * 416 * 416 + y * 416 + x] = static_cast<int8_t>((row[0] + 1) >> 1);
            out[1 * 416 * 416 + y * 416 + x] = static_cast<int8_t>((row[1] + 1) >> 1);
            out[2 * 416 * 416 + y * 416 + x] = static_cast<int8_t>((row[2] + 1) >> 1);
            row += 3;
        }
    }
    return out;
}

// ============================================================================
// im2col: Extract patches into a matrix for GEMM-based convolution
// Input: NCHW [C, H, W], Output: [out_h*out_w, C*K*K]
// ============================================================================
void im2col(const int8_t* input, int in_c, int in_h, int in_w,
            int kernel, int pad, int stride,
            int out_h, int out_w, int8_t* col) {
    const int k_half = pad ? kernel / 2 : 0;
    const int col_w = in_c * kernel * kernel;

    for (int oy = 0; oy < out_h; oy++) {
        for (int ox = 0; ox < out_w; ox++) {
            int8_t* dst = col + (oy * out_w + ox) * col_w;
            for (int ic = 0; ic < in_c; ic++) {
                const int8_t* src = input + ic * in_h * in_w;
                for (int ky = 0; ky < kernel; ky++) {
                    int iy = oy * stride + ky - k_half;
                    for (int kx = 0; kx < kernel; kx++) {
                        int ix = ox * stride + kx - k_half;
                        if (iy >= 0 && iy < in_h && ix >= 0 && ix < in_w) {
                            *dst++ = src[iy * in_w + ix];
                        } else {
                            *dst++ = 0;
                        }
                    }
                }
            }
        }
    }
}

// For 1x1 conv, im2col is just a transpose/repack — input already contiguous
void im2col_1x1(const int8_t* input, int in_c, int in_h, int in_w,
                int8_t* col) {
    // col[spatial, channel] = input[channel, spatial]
    const int spatial = in_h * in_w;
    for (int s = 0; s < spatial; s++) {
        for (int c = 0; c < in_c; c++) {
            col[s * in_c + c] = input[c * spatial + s];
        }
    }
}

// ============================================================================
// NEON-accelerated INT8 dot product (A53: no dotprod, use vmull+vpadal)
// Computes dot product of two int8 vectors of length K
// ============================================================================
#ifdef __ARM_NEON
static inline int32_t neon_dot_i8(const int8_t* a, const int8_t* b, int K) {
    int32x4_t acc = vdupq_n_s32(0);
    int k = 0;

    // Process 16 elements at a time
    for (; k + 15 < K; k += 16) {
        int8x16_t va = vld1q_s8(a + k);
        int8x16_t vb = vld1q_s8(b + k);

        // Multiply low 8 elements: int8→int16
        int16x8_t prod_lo = vmull_s8(vget_low_s8(va), vget_low_s8(vb));
        // Multiply high 8 elements
        int16x8_t prod_hi = vmull_s8(vget_high_s8(va), vget_high_s8(vb));

        // Pairwise add int16→int32 and accumulate
        acc = vpadalq_s16(acc, prod_lo);
        acc = vpadalq_s16(acc, prod_hi);
    }

    // Process 8 elements
    for (; k + 7 < K; k += 8) {
        int8x8_t va = vld1_s8(a + k);
        int8x8_t vb = vld1_s8(b + k);
        int16x8_t prod = vmull_s8(va, vb);
        acc = vpadalq_s16(acc, prod);
    }

    // Horizontal sum
    int32_t sum = vaddvq_s32(acc);

    // Scalar remainder
    for (; k < K; k++) {
        sum += static_cast<int32_t>(a[k]) * static_cast<int32_t>(b[k]);
    }

    return sum;
}
#endif

// ============================================================================
// GEMM: C[M,N] = A[M,K] * B[N,K]^T + bias, with quantization
// A = weights [out_c, K], B = col [spatial, K], C = output [out_c, spatial]
// Threaded: each thread handles a range of output channels
// ============================================================================
void gemm_int8_quantize(const int8_t* weights, const int8_t* col,
                        const int32_t* biases, int out_c, int spatial, int K,
                        uint32_t M, uint32_t n, int use_relu,
                        int8_t* output,
                        int oc_start, int oc_end) {
    for (int oc = oc_start; oc < oc_end; oc++) {
        const int8_t* w_row = weights + oc * K;
        int32_t bias = biases[oc];

        for (int s = 0; s < spatial; s++) {
            const int8_t* col_row = col + s * K;

#ifdef __ARM_NEON
            int32_t acc = neon_dot_i8(w_row, col_row, K);
#else
            int32_t acc = 0;
            for (int k = 0; k < K; k++) {
                acc += static_cast<int32_t>(w_row[k]) * static_cast<int32_t>(col_row[k]);
            }
#endif

            acc += bias;

            if (use_relu && acc < 0) acc >>= 3;

            int64_t scaled = (static_cast<int64_t>(acc) * M) >> n;
            scaled = std::max<int64_t>(-128, std::min<int64_t>(127, scaled));

            output[oc * spatial + s] = static_cast<int8_t>(scaled);
        }
    }
}

// ============================================================================
// Multi-threaded convolution: im2col → parallel GEMM
// ============================================================================
void conv2d_optimized(const int8_t* input, int in_h, int in_w, int in_c,
                      const int8_t* weights, const int32_t* biases,
                      int out_c, int kernel, int pad,
                      uint32_t M, uint32_t n, int use_relu,
                      int8_t* output, int out_h, int out_w) {

    const int spatial = out_h * out_w;
    const int K = in_c * kernel * kernel;

    // im2col: [spatial, K]
    std::vector<int8_t> col(spatial * K);
    if (kernel == 1) {
        im2col_1x1(input, in_c, in_h, in_w, col.data());
    } else {
        im2col(input, in_c, in_h, in_w, kernel, pad, 1, out_h, out_w, col.data());
    }

    // Parallel GEMM across output channels
    int nt = std::min(NUM_THREADS, out_c);
    if (nt <= 1 || out_c < 16) {
        gemm_int8_quantize(weights, col.data(), biases, out_c, spatial, K,
                           M, n, use_relu, output, 0, out_c);
    } else {
        std::thread threads[NUM_THREADS - 1];
        for (int t = 0; t < nt; t++) {
            int oc_start = t * out_c / nt;
            int oc_end = (t + 1) * out_c / nt;
            if (t < nt - 1) {
                threads[t] = std::thread(gemm_int8_quantize,
                    weights, col.data(), biases, out_c, spatial, K,
                    M, n, use_relu, output, oc_start, oc_end);
            } else {
                gemm_int8_quantize(weights, col.data(), biases, out_c, spatial, K,
                                   M, n, use_relu, output, oc_start, oc_end);
            }
        }
        for (int t = 0; t < nt - 1; t++) threads[t].join();
    }
}

// ============================================================================
// Maxpool / upsample / concat (same as reference)
// ============================================================================
void maxpool_2x2_stride2(const int8_t* in, int h, int w, int c, int8_t* out) {
    int oh = h / 2, ow = w / 2;
    for (int ch = 0; ch < c; ch++) {
        const int8_t* src = in + ch * h * w;
        int8_t* dst = out + ch * oh * ow;
        for (int oy = 0; oy < oh; oy++) {
            for (int ox = 0; ox < ow; ox++) {
                int8_t a = src[(oy*2)*w + ox*2];
                int8_t b = src[(oy*2)*w + ox*2+1];
                int8_t c_ = src[(oy*2+1)*w + ox*2];
                int8_t d = src[(oy*2+1)*w + ox*2+1];
                dst[oy*ow + ox] = std::max({a, b, c_, d});
            }
        }
    }
}

void maxpool_2x2_stride1(const int8_t* in, int h, int w, int c, int8_t* out) {
    for (int ch = 0; ch < c; ch++) {
        const int8_t* s = in + ch * h * w;
        int8_t* d = out + ch * h * w;
        for (int oy = 0; oy < h; oy++) {
            for (int ox = 0; ox < w; ox++) {
                int8_t v00 = s[oy * w + ox];
                int8_t v01 = (ox+1 < w) ? s[oy * w + ox + 1] : -128;
                int8_t v10 = (oy+1 < h) ? s[(oy+1) * w + ox] : -128;
                int8_t v11 = (ox+1 < w && oy+1 < h) ? s[(oy+1) * w + ox + 1] : -128;
                d[oy * w + ox] = std::max({v00, v01, v10, v11});
            }
        }
    }
}

void upsample_2x(const int8_t* in, int h, int w, int c, int8_t* out) {
    for (int ch = 0; ch < c; ch++) {
        for (int iy = 0; iy < h; iy++) {
            for (int ix = 0; ix < w; ix++) {
                int8_t v = in[ch * h * w + iy * w + ix];
                int oy = iy * 2, ox = ix * 2, w2 = w * 2;
                int base = ch * (h*2) * w2;
                out[base + oy * w2 + ox] = v;
                out[base + oy * w2 + ox + 1] = v;
                out[base + (oy+1) * w2 + ox] = v;
                out[base + (oy+1) * w2 + ox + 1] = v;
            }
        }
    }
}

struct InferenceResult {
    std::vector<int8_t> head1;  // 13x13x255
    std::vector<int8_t> head2;  // 26x26x255
};

InferenceResult run_inference(const std::vector<int8_t>& input, const ModelWeights& model) {
    std::vector<int8_t> buf_a, buf_b;
    std::vector<int8_t>* cur_in = nullptr;
    std::vector<int8_t>* cur_out = nullptr;
    std::vector<int8_t> layer4_conv, layer7_out;
    InferenceResult result;

    buf_a = input;
    cur_in = &buf_a;
    cur_out = &buf_b;

    for (int li = 0; li < NUM_LAYERS; li++) {
        const auto& cfg = LAYERS[li];
        const auto& lw = model.layers[li];
        int in_h = cfg.img_h, in_w = cfg.img_w, in_c = cfg.cin;

        if (li == 10) {
            *cur_in = layer7_out;
            in_h = 13; in_w = 13;
        } else if (li == 11) {
            std::vector<int8_t> up(128 * 26 * 26);
            upsample_2x(cur_out->data(), 13, 13, 128, up.data());
            cur_in->resize(384 * 26 * 26);
            std::memcpy(cur_in->data(), up.data(), 128 * 26 * 26);
            std::memcpy(cur_in->data() + 128 * 26 * 26, layer4_conv.data(), 256 * 26 * 26);
            in_h = 26; in_w = 26; in_c = 384;
        }

        auto t0 = std::chrono::high_resolution_clock::now();

        bool need_conv_save = (li == 4);

        if (cfg.maxpool_stride == 0 && !need_conv_save) {
            cur_out->resize(cfg.cout * cfg.out_h * cfg.out_w);
            conv2d_optimized(cur_in->data(), in_h, in_w, in_c,
                             lw.weights.data(), lw.biases.data(),
                             cfg.cout, cfg.kernel, cfg.pad,
                             lw.M, lw.n, lw.use_relu,
                             cur_out->data(), cfg.out_h, cfg.out_w);
        } else {
            // Conv to spatial size, then maxpool
            int conv_h = in_h, conv_w = in_w;
            std::vector<int8_t> temp(cfg.cout * conv_h * conv_w);
            conv2d_optimized(cur_in->data(), in_h, in_w, in_c,
                             lw.weights.data(), lw.biases.data(),
                             cfg.cout, cfg.kernel, cfg.pad,
                             lw.M, lw.n, lw.use_relu,
                             temp.data(), conv_h, conv_w);

            if (need_conv_save) layer4_conv = temp;

            cur_out->resize(cfg.cout * cfg.out_h * cfg.out_w);
            if (cfg.maxpool_stride == 2) {
                maxpool_2x2_stride2(temp.data(), conv_h, conv_w, cfg.cout, cur_out->data());
            } else if (cfg.maxpool_stride == 1) {
                maxpool_2x2_stride1(temp.data(), conv_h, conv_w, cfg.cout, cur_out->data());
            } else {
                *cur_out = temp;  // layer 4: save conv, then maxpool
                maxpool_2x2_stride2(temp.data(), conv_h, conv_w, cfg.cout, cur_out->data());
            }
        }

        auto t1 = std::chrono::high_resolution_clock::now();
        float ms = std::chrono::duration<float, std::milli>(t1 - t0).count();
        std::cout << "  L" << li << " (" << cfg.cin << "→" << cfg.cout << "): "
                  << std::fixed << std::setprecision(1) << ms << " ms" << std::endl;

        if (li == 7) layer7_out = *cur_out;
        if (li == 9) result.head1 = *cur_out;
        else if (li == 12) result.head2 = *cur_out;

        std::swap(cur_in, cur_out);
    }

    return result;
}

std::vector<uint8_t> nchw_to_nhwc(const std::vector<int8_t>& nchw, int h, int w, int c) {
    std::vector<uint8_t> nhwc(h * w * c);
    for (int y = 0; y < h; y++)
        for (int x = 0; x < w; x++)
            for (int ch = 0; ch < c; ch++)
                nhwc[(y * w + x) * c + ch] = static_cast<uint8_t>(nchw[ch * h * w + y * w + x]);
    return nhwc;
}

int main(int argc, char* argv[]) {
    if (argc < 3) {
        std::cerr << "Usage: " << argv[0] << " <weights_dir> <image_path> [--benchmark N]" << std::endl;
        return 1;
    }

    std::string weights_dir = argv[1];
    std::string image_path = argv[2];
    int benchmark_iters = 0;

    for (int i = 3; i < argc; i++) {
        if (std::string(argv[i]) == "--benchmark" && i + 1 < argc) {
            benchmark_iters = std::stoi(argv[++i]);
        }
    }

    std::cout << "==========================================" << std::endl;
    std::cout << "TinyYOLOv3 ARM Optimized INT8 Inference" << std::endl;
    std::cout << "==========================================" << std::endl;
    std::cout << "  Optimizations: im2col + NEON GEMM, " << NUM_THREADS << " threads" << std::endl;
#ifdef __ARM_NEON
    std::cout << "  NEON: enabled" << std::endl;
#else
    std::cout << "  NEON: disabled (scalar fallback)" << std::endl;
#endif
    std::cout << "  Weights: " << weights_dir << std::endl;
    std::cout << "  Image: " << image_path << std::endl;
    std::cout << std::endl;

    try {
        ModelWeights model;
        load_model_weights(weights_dir, model);

        auto pp_start = std::chrono::high_resolution_clock::now();
        std::vector<int8_t> input = load_and_preprocess_image(image_path);
        auto pp_end = std::chrono::high_resolution_clock::now();
        float pp_ms = std::chrono::duration<float, std::milli>(pp_end - pp_start).count();
        std::cout << "  Preprocessing: " << static_cast<int>(pp_ms) << " ms\n" << std::endl;

        std::cout << "Running inference..." << std::endl;

        InferenceResult result;
        std::vector<float> iter_times;

        int num_iters = std::max(1, benchmark_iters);
        for (int iter = 0; iter < num_iters; iter++) {
            if (iter > 0) std::cout << "\n--- Iteration " << (iter+1) << " ---" << std::endl;
            auto t0 = std::chrono::high_resolution_clock::now();
            result = run_inference(input, model);
            auto t1 = std::chrono::high_resolution_clock::now();
            float ms = std::chrono::duration<float, std::milli>(t1 - t0).count();
            iter_times.push_back(ms);
            std::cout << "  Total inference: " << static_cast<int>(ms) << " ms" << std::endl;
        }

        if (benchmark_iters > 1) {
            float total = 0, mn = iter_times[0], mx = iter_times[0];
            for (float t : iter_times) { total += t; mn = std::min(mn, t); mx = std::max(mx, t); }
            float avg = total / iter_times.size();
            std::cout << "\n=== Benchmark (" << num_iters << " iterations) ===" << std::endl;
            std::cout << "  Average: " << static_cast<int>(avg) << " ms" << std::endl;
            std::cout << "  Min:     " << static_cast<int>(mn) << " ms" << std::endl;
            std::cout << "  Max:     " << static_cast<int>(mx) << " ms" << std::endl;
            std::cout << "  FPS:     " << std::fixed << std::setprecision(2) << (1000.0f / avg) << std::endl;
        }

        auto head1_nhwc = nchw_to_nhwc(result.head1, 13, 13, 255);
        auto head2_nhwc = nchw_to_nhwc(result.head2, 26, 26, 255);

        auto det_start = std::chrono::high_resolution_clock::now();
        auto detections = yolo_postprocess(head1_nhwc.data(), head2_nhwc.data(), 416, 0.25f, 0.45f);
        auto det_end = std::chrono::high_resolution_clock::now();

        print_detections(detections);

        std::cout << "\n=== Summary ===" << std::endl;
        std::cout << "  Preprocessing:   " << static_cast<int>(pp_ms) << " ms" << std::endl;
        std::cout << "  Inference:       " << static_cast<int>(iter_times[0]) << " ms" << std::endl;
        std::cout << "  FPGA equivalent: 61 ms (448x faster would be "
                  << static_cast<int>(iter_times[0]) << "/" << 61 << " = "
                  << std::fixed << std::setprecision(0) << (iter_times[0] / 61.0f)
                  << "x speedup)" << std::endl;

    } catch (const std::exception& e) {
        std::cerr << "Error: " << e.what() << std::endl;
        return 1;
    }
    return 0;
}
