/*
 * yolo_camera.cpp - Pipelined TinyYOLOv3 Live Camera Inference
 *
 * 3-stage pipeline: capture → FPGA inference → display with bounding boxes
 *
 * Build: make yolo_camera TARGET=hw
 * Run:   ./yolo_camera <xclbin_file> <weights_dir> [options]
 *
 * Controls: 'q'/ESC=quit, 's'=save frame, 'p'=pause
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
#include <thread>
#include <mutex>
#include <condition_variable>
#include <atomic>
#include <queue>
#include <sstream>

#include <opencv2/core.hpp>
#include <opencv2/imgcodecs.hpp>
#include <opencv2/imgproc.hpp>
#include <opencv2/highgui.hpp>
#include <opencv2/videoio.hpp>

#ifdef __ARM_NEON
#include <arm_neon.h>
#endif

#include "xrt/xrt_device.h"
#include "xrt/xrt_kernel.h"
#include "xrt/xrt_bo.h"
#include "ert.h"

#include "yolo_postprocess.hpp"

struct AppConfig {
    std::string xclbin_file;
    std::string weights_dir;
    int camera_id = 0;
    int capture_width = 640;
    int capture_height = 480;
    std::string camera_format = "yuyv";  // "yuyv", "mjpeg", or "auto"
    float conf_threshold = 0.25f;
    float nms_threshold = 0.45f;
    bool no_batch = false;
    bool headless = false;
    bool verbose = false;
};

AppConfig g_config;
std::atomic<bool> g_running{true};
std::atomic<bool> g_paused{false};

template<typename T>
class ThreadSafeQueue {
public:
    ThreadSafeQueue(size_t max_size = 3) : max_size_(max_size) {}

    bool push(T item) {
        std::unique_lock<std::mutex> lock(mutex_);
        if (queue_.size() >= max_size_) {
            queue_.pop();  // drop oldest to prevent latency buildup
        }
        queue_.push(std::move(item));
        lock.unlock();
        cond_.notify_one();
        return true;
    }

    bool pop(T& item, int timeout_ms = 100) {
        std::unique_lock<std::mutex> lock(mutex_);
        if (!cond_.wait_for(lock, std::chrono::milliseconds(timeout_ms),
                           [this] { return !queue_.empty(); })) {
            return false;
        }
        item = std::move(queue_.front());
        queue_.pop();
        return true;
    }

    size_t size() const {
        std::lock_guard<std::mutex> lock(mutex_);
        return queue_.size();
    }

    void clear() {
        std::lock_guard<std::mutex> lock(mutex_);
        while (!queue_.empty()) queue_.pop();
    }

private:
    std::queue<T> queue_;
    mutable std::mutex mutex_;
    std::condition_variable cond_;
    size_t max_size_;
};

struct CapturedFrame {
    cv::Mat image;
    int64_t timestamp_ms;
    int frame_id;
};

struct InferenceResult {
    cv::Mat image;
    std::vector<BBox> detections;
    float inference_time_ms;
    float preprocess_time_ms;
    float postprocess_time_ms;
    int frame_id;
};

ThreadSafeQueue<CapturedFrame> g_capture_queue(2);
ThreadSafeQueue<InferenceResult> g_display_queue(2);

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

struct ChunkWeights {
    std::vector<uint8_t> weights;
    std::vector<uint8_t> biases;
    int num_ogs;
};

struct PreloadedWeights {
    std::vector<std::vector<std::vector<uint8_t>>> layer_weights;  // [layer][og]
    std::vector<std::vector<std::vector<uint8_t>>> layer_biases;   // [layer][og]
    std::vector<std::vector<ChunkWeights>> chunks;                 // [layer][chunk]
};

void preload_all_weights(const std::string& weights_dir, PreloadedWeights& pw) {
    pw.layer_weights.resize(NUM_LAYERS);
    pw.layer_biases.resize(NUM_LAYERS);

    for (int i = 0; i < NUM_LAYERS; i++) {
        const LayerConfig& cfg = LAYERS[i];
        std::string layer_dir = weights_dir + "/layer" + std::to_string(i);

        pw.layer_weights[i].resize(cfg.co_groups);
        pw.layer_biases[i].resize(cfg.co_groups);

        for (int og = 0; og < cfg.co_groups; og++) {
            pw.layer_weights[i][og] = read_binary_file(
                layer_dir + "/weights_og" + std::to_string(og) + ".bin");
            pw.layer_biases[i][og] = read_binary_file(
                layer_dir + "/biases_og" + std::to_string(og) + ".bin");
        }
    }

        pw.chunks.resize(NUM_LAYERS);
    for (int layer = 0; layer < NUM_LAYERS; layer++) {
        const LayerConfig& cfg = LAYERS[layer];
        size_t wt_per_og = static_cast<size_t>(cfg.ci_groups) * 8 * 8 * 16;
        int auto_max = 4096 / cfg.ci_groups;
        int num_chunks = (cfg.co_groups + auto_max - 1) / auto_max;

        pw.chunks[layer].resize(num_chunks);
        for (int c = 0; c < num_chunks; c++) {
            int chunk_start_og = c * auto_max;
            int ogs = std::min(auto_max, cfg.co_groups - chunk_start_og);

            auto& cw = pw.chunks[layer][c];
            cw.num_ogs = ogs;
            cw.weights.resize(ogs * wt_per_og);
            cw.biases.resize(ogs * 32);

            for (int og = 0; og < ogs; og++) {
                int global_og = chunk_start_og + og;
                std::memcpy(cw.weights.data() + og * wt_per_og,
                           pw.layer_weights[layer][global_og].data(),
                           std::min(pw.layer_weights[layer][global_og].size(), wt_per_og));
                std::memcpy(cw.biases.data() + og * 32,
                           pw.layer_biases[layer][global_og].data(),
                           std::min(pw.layer_biases[layer][global_og].size(), static_cast<size_t>(32)));
            }
        }
    }
}

struct InferenceBuffers {
    xrt::bo weight_bo[2];
    xrt::bo bias_bo[2];
    xrt::bo pixel_bo;
    xrt::bo output_bo;
    xrt::run run;

    uint8_t* weight_ptr[2];
    uint8_t* bias_ptr[2];
    uint8_t* pixel_ptr;
    uint8_t* output_ptr;

    size_t pixel_buf_size;
    size_t weight_buf_size;
    size_t bias_buf_size;
    size_t output_buf_size;
    std::vector<uint8_t> scratch;
};

void init_buffers(xrt::device& device, xrt::kernel& kernel, InferenceBuffers& bufs) {
    bufs.weight_buf_size = 8 * 1024 * 1024;   // 8MB
    bufs.bias_buf_size   = 128 * 32;           // 4KB
    bufs.pixel_buf_size  = 2 * 1024 * 1024;   // 2MB
    bufs.output_buf_size = 2 * 1024 * 1024;   // 2MB

    for (int b = 0; b < 2; b++) {
        bufs.weight_bo[b] = xrt::bo(device, bufs.weight_buf_size, kernel.group_id(19));
        bufs.bias_bo[b]   = xrt::bo(device, bufs.bias_buf_size,   kernel.group_id(20));
        bufs.weight_ptr[b] = bufs.weight_bo[b].map<uint8_t*>();
        bufs.bias_ptr[b]   = bufs.bias_bo[b].map<uint8_t*>();
    }
    bufs.pixel_bo  = xrt::bo(device, bufs.pixel_buf_size,  kernel.group_id(21));
    bufs.output_bo = xrt::bo(device, bufs.output_buf_size, kernel.group_id(22));
    bufs.pixel_ptr  = bufs.pixel_bo.map<uint8_t*>();
    bufs.output_ptr = bufs.output_bo.map<uint8_t*>();

    bufs.scratch.resize(bufs.output_buf_size);

    bufs.run = xrt::run(kernel);
    bufs.run.set_arg(19, bufs.weight_bo[0]);
    bufs.run.set_arg(20, bufs.bias_bo[0]);
    bufs.run.set_arg(21, bufs.pixel_bo);
    bufs.run.set_arg(22, bufs.output_bo);
}

void prepare_weights_in_buf(InferenceBuffers& bufs, PreloadedWeights& pw,
                            int layer_idx, int chunk_start_og, int ogs_in_chunk,
                            int buf_idx) {
    const LayerConfig& cfg = LAYERS[layer_idx];
    size_t wt_per_og = static_cast<size_t>(cfg.ci_groups) * 8 * 8 * 16;
    size_t actual_wt = static_cast<size_t>(ogs_in_chunk) * wt_per_og;
    size_t actual_bias = static_cast<size_t>(ogs_in_chunk) * 32;

    int auto_max = 4096 / cfg.ci_groups;
    int chunk_idx = chunk_start_og / auto_max;

    if (chunk_idx < static_cast<int>(pw.chunks[layer_idx].size())) {
        const auto& cw = pw.chunks[layer_idx][chunk_idx];
        std::memcpy(bufs.weight_ptr[buf_idx], cw.weights.data(), actual_wt);
        std::memcpy(bufs.bias_ptr[buf_idx], cw.biases.data(), actual_bias);
    } else {
        for (int og = 0; og < ogs_in_chunk; og++) {
            int global_og = chunk_start_og + og;
            std::memcpy(bufs.weight_ptr[buf_idx] + og * wt_per_og,
                       pw.layer_weights[layer_idx][global_og].data(),
                       std::min(pw.layer_weights[layer_idx][global_og].size(), wt_per_og));
            std::memcpy(bufs.bias_ptr[buf_idx] + og * 32,
                       pw.layer_biases[layer_idx][global_og].data(),
                       std::min(pw.layer_biases[layer_idx][global_og].size(), static_cast<size_t>(32)));
        }
    }

    bufs.weight_bo[buf_idx].sync(XCL_BO_SYNC_BO_TO_DEVICE, actual_wt, 0);
    bufs.bias_bo[buf_idx].sync(XCL_BO_SYNC_BO_TO_DEVICE, actual_bias, 0);
}

void preprocess_frame(const cv::Mat& frame, std::vector<uint8_t>& output) {
    int crop_size = std::min(frame.cols, frame.rows);
    int x_offset = (frame.cols - crop_size) / 2;
    int y_offset = (frame.rows - crop_size) / 2;

    cv::Rect roi(x_offset, y_offset, crop_size, crop_size);
    cv::Mat cropped = frame(roi);

    cv::Mat resized;
    cv::resize(cropped, resized, cv::Size(416, 416), 0, 0, cv::INTER_LINEAR);

    cv::Mat rgb;
    cv::cvtColor(resized, rgb, cv::COLOR_BGR2RGB);

    int padded_h = 418, padded_w = 418, cin_pad = 8;
    output.assign(padded_h * padded_w * cin_pad, 0);

    for (int y = 0; y < 416; y++) {
        const uint8_t* row = rgb.ptr<uint8_t>(y);
        uint8_t* dst_row = output.data() + ((y + 1) * padded_w + 1) * cin_pad;
        for (int x = 0; x < 416; x++) {
            dst_row[0] = (row[0] + 1) >> 1;
            dst_row[1] = (row[1] + 1) >> 1;
            dst_row[2] = (row[2] + 1) >> 1;
            row += 3;
            dst_row += cin_pad;
        }
    }
}

void pad_spatial(const std::vector<uint8_t>& input, int h, int w, int c,
                 std::vector<uint8_t>& output) {
    int padded_h = h + 2;
    int padded_w = w + 2;
    output.assign(padded_h * padded_w * c, 0);
    for (int y = 0; y < h; y++)
        std::memcpy(&output[((y + 1) * padded_w + 1) * c], &input[y * w * c], w * c);
}

void pad_spatial_stride1(const std::vector<uint8_t>& input, int h, int w, int c,
                         std::vector<uint8_t>& output) {
    int padded_h = h + 3;
    int padded_w = w + 3;
    output.assign(padded_h * padded_w * c, 0);
    for (int y = 0; y < h; y++)
        std::memcpy(&output[((y + 1) * padded_w + 1) * c], &input[y * w * c], w * c);
}

void cpu_upsample_2x(const uint8_t* input, uint8_t* output,
                     int in_h, int in_w, int channels) {
    int out_w = in_w * 2;
    for (int y = 0; y < in_h; y++) {
        for (int x = 0; x < in_w; x++) {
            int src_idx = (y * in_w + x) * channels;
            int dst_idx00 = ((y*2) * out_w + (x*2)) * channels;
            int dst_idx01 = ((y*2) * out_w + (x*2+1)) * channels;
            int dst_idx10 = ((y*2+1) * out_w + (x*2)) * channels;
            int dst_idx11 = ((y*2+1) * out_w + (x*2+1)) * channels;
            std::memcpy(&output[dst_idx00], &input[src_idx], channels);
            std::memcpy(&output[dst_idx01], &input[src_idx], channels);
            std::memcpy(&output[dst_idx10], &input[src_idx], channels);
            std::memcpy(&output[dst_idx11], &input[src_idx], channels);
        }
    }
}

void cpu_concat_channels(const uint8_t* a, int a_ch,
                         const uint8_t* b, int b_ch,
                         uint8_t* out, int h, int w) {
    int out_ch = a_ch + b_ch;
    for (int y = 0; y < h; y++) {
        for (int x = 0; x < w; x++) {
            int pixel_idx = y * w + x;
            int out_idx = pixel_idx * out_ch;
            std::memcpy(&out[out_idx], &a[pixel_idx * a_ch], a_ch);
            std::memcpy(&out[out_idx + a_ch], &b[pixel_idx * b_ch], b_ch);
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

void neon_interleave_from_scratch(const uint8_t* scratch, size_t og_data_size,
                                   uint8_t* dst, int dst_pixel_stride,
                                   int num_pixels, int num_ogs, int og_channel_offset) {
#ifdef __ARM_NEON
    if (num_ogs == 2 && og_channel_offset == 0 && dst_pixel_stride == 16) {
        const uint8_t* s0 = scratch;
        const uint8_t* s1 = scratch + og_data_size;
        for (int p = 0; p < num_pixels; p++) {
            vst1_u8(dst + p * 16, vld1_u8(s0 + p * 8));
            vst1_u8(dst + p * 16 + 8, vld1_u8(s1 + p * 8));
        }
    } else if (num_ogs == 4 && og_channel_offset == 0 && dst_pixel_stride == 32) {
        const uint8_t* s0 = scratch;
        const uint8_t* s1 = scratch + og_data_size;
        const uint8_t* s2 = scratch + 2 * og_data_size;
        const uint8_t* s3 = scratch + 3 * og_data_size;
        for (int p = 0; p < num_pixels; p++) {
            vst1_u8(dst + p * 32, vld1_u8(s0 + p * 8));
            vst1_u8(dst + p * 32 + 8, vld1_u8(s1 + p * 8));
            vst1_u8(dst + p * 32 + 16, vld1_u8(s2 + p * 8));
            vst1_u8(dst + p * 32 + 24, vld1_u8(s3 + p * 8));
        }
    } else {
        for (int og = 0; og < num_ogs; og++) {
            const uint8_t* s = scratch + og * og_data_size;
            int ch_offset = og_channel_offset + og * 8;
            int valid_ch = std::min(8, dst_pixel_stride - ch_offset);
            uint8_t* d = dst + ch_offset;
            if (valid_ch == 8) {
                for (int p = 0; p < num_pixels; p++) {
                    vst1_u8(d, vld1_u8(s));
                    s += 8;
                    d += dst_pixel_stride;
                }
            } else {
                for (int p = 0; p < num_pixels; p++) {
                    std::memcpy(d, s, valid_ch);
                    s += 8;
                    d += dst_pixel_stride;
                }
            }
        }
    }
#else
    for (int og = 0; og < num_ogs; og++) {
        const uint8_t* s = scratch + og * og_data_size;
        int ch_offset = og_channel_offset + og * 8;
        int valid_ch = std::min(8, dst_pixel_stride - ch_offset);
        uint8_t* d = dst + ch_offset;
        for (int p = 0; p < num_pixels; p++) {
            std::memcpy(d, s, valid_ch);
            s += 8;
            d += dst_pixel_stride;
        }
    }
#endif
}

int run_layer(const LayerConfig& cfg,
              const std::vector<uint8_t>& pixels, std::vector<uint8_t>& output,
              InferenceBuffers& bufs, PreloadedWeights& pw, int layer_idx,
              int wt_buf, int next_layer_idx) {

    int auto_max = 4096 / cfg.ci_groups;
    int max_og_per_chunk = g_config.no_batch ? 1 : auto_max;
    int num_chunks = (cfg.co_groups + max_og_per_chunk - 1) / max_og_per_chunk;

    int actual_padded_h = (cfg.maxpool_stride == 1) ? (cfg.out_h + 3) : cfg.padded_h;
    int actual_padded_w = (cfg.maxpool_stride == 1) ? (cfg.out_w + 3) : cfg.padded_w;
    size_t pixel_bytes = actual_padded_h * actual_padded_w * cfg.cin_pad;

    int num_pixels = cfg.out_h * cfg.out_w;
    size_t weight_bytes_per_og = cfg.ci_groups * 8 * 8 * 16;
    size_t output_bytes_per_og = num_pixels * 8;
    size_t output_stride_per_og = ((output_bytes_per_og + 4095) / 4096) * 4096;

    std::memcpy(bufs.pixel_ptr, pixels.data(), std::min(pixels.size(), pixel_bytes));
    bufs.pixel_bo.sync(XCL_BO_SYNC_BO_TO_DEVICE, pixel_bytes, 0);

    output.resize(num_pixels * cfg.cout);

    int cur_buf = wt_buf;

    for (int chunk = 0; chunk < num_chunks; chunk++) {
        int chunk_start_og = chunk * max_og_per_chunk;
        int ogs_in_chunk = std::min(max_og_per_chunk, cfg.co_groups - chunk_start_og);

        bufs.run.set_arg(19, bufs.weight_bo[cur_buf]);
        bufs.run.set_arg(20, bufs.bias_bo[cur_buf]);

        bufs.run.set_arg(0, bufs.weight_bo[cur_buf].address());
        bufs.run.set_arg(1, bufs.bias_bo[cur_buf].address());
        bufs.run.set_arg(2, bufs.pixel_bo.address());
        bufs.run.set_arg(3, bufs.output_bo.address());
        bufs.run.set_arg(4, static_cast<uint32_t>(weight_bytes_per_og));
        bufs.run.set_arg(5, static_cast<uint32_t>(32));
        bufs.run.set_arg(6, static_cast<uint32_t>(pixel_bytes));
        bufs.run.set_arg(7, static_cast<uint32_t>(output_bytes_per_og));
        bufs.run.set_arg(8, static_cast<uint32_t>(cfg.ci_groups));
        bufs.run.set_arg(9, static_cast<uint32_t>(ogs_in_chunk));
        bufs.run.set_arg(10, static_cast<uint32_t>(0));
        bufs.run.set_arg(11, static_cast<uint32_t>(cfg.cin_pad));
        bufs.run.set_arg(12, static_cast<uint32_t>(actual_padded_w));

        bool enable_hw_maxpool = (cfg.maxpool_stride != 0);
        bufs.run.set_arg(13, static_cast<uint32_t>(enable_hw_maxpool ? 1 : 0));
        bufs.run.set_arg(14, static_cast<uint32_t>(cfg.maxpool_stride == 2 ? 1 : 0));
        bufs.run.set_arg(15, cfg.quant_m);
        bufs.run.set_arg(16, cfg.quant_n);
        bufs.run.set_arg(17, static_cast<uint32_t>(cfg.use_relu));
        bufs.run.set_arg(18, static_cast<uint32_t>(cfg.kernel_1x1));

        bufs.run.start();

        // Async: prepare next weights in alternate buffer
        int next_buf = 1 - cur_buf;
        std::thread wt_thread;
        bool launched_async = false;

        if (chunk + 1 < num_chunks) {
            int next_cs = (chunk + 1) * max_og_per_chunk;
            int next_ogs = std::min(max_og_per_chunk, cfg.co_groups - next_cs);
            wt_thread = std::thread([&bufs, &pw, layer_idx, next_cs, next_ogs, next_buf]() {
                prepare_weights_in_buf(bufs, pw, layer_idx, next_cs, next_ogs, next_buf);
            });
            launched_async = true;
        } else if (next_layer_idx >= 0) {
            const LayerConfig& ncfg = LAYERS[next_layer_idx];
            int nauto = 4096 / ncfg.ci_groups;
            int nmax = g_config.no_batch ? 1 : nauto;
            int nogs = std::min(nmax, ncfg.co_groups);
            wt_thread = std::thread([&bufs, &pw, next_layer_idx, nogs, next_buf]() {
                prepare_weights_in_buf(bufs, pw, next_layer_idx, 0, nogs, next_buf);
            });
            launched_async = true;
        }

        bufs.run.wait(std::chrono::seconds(300));

        size_t actual_output_bytes = static_cast<size_t>(ogs_in_chunk) * output_stride_per_og;
        bufs.output_bo.sync(XCL_BO_SYNC_BO_FROM_DEVICE, actual_output_bytes, 0);

        size_t og_out_size = num_pixels * 8;
        int num_copy_threads = std::min(4, ogs_in_chunk);
        if (num_copy_threads >= 2 && og_out_size >= 4096) {
            std::thread threads[3];
            for (int t = 1; t < num_copy_threads; t++) {
                int og_start = t * ogs_in_chunk / num_copy_threads;
                int og_end = (t + 1) * ogs_in_chunk / num_copy_threads;
                threads[t-1] = std::thread([&bufs, og_out_size, output_stride_per_og, og_start, og_end]() {
                    for (int og = og_start; og < og_end; og++) {
                        std::memcpy(bufs.scratch.data() + og * og_out_size,
                                   bufs.output_ptr + og * output_stride_per_og,
                                   og_out_size);
                    }
                });
            }
            int og_end_main = ogs_in_chunk / num_copy_threads;
            for (int og = 0; og < og_end_main; og++) {
                std::memcpy(bufs.scratch.data() + og * og_out_size,
                           bufs.output_ptr + og * output_stride_per_og,
                           og_out_size);
            }
            for (int t = 1; t < num_copy_threads; t++) threads[t-1].join();
        } else {
            for (int og = 0; og < ogs_in_chunk; og++) {
                std::memcpy(bufs.scratch.data() + og * og_out_size,
                           bufs.output_ptr + og * output_stride_per_og,
                           og_out_size);
            }
        }
        int og_channel_offset = chunk_start_og * 8;
        neon_interleave_from_scratch(bufs.scratch.data(), og_out_size,
                                      output.data(), cfg.cout,
                                      num_pixels, ogs_in_chunk, og_channel_offset);

        if (launched_async && wt_thread.joinable()) wt_thread.join();
        cur_buf = next_buf;
    }

    return cur_buf;
}

void run_inference(const std::vector<uint8_t>& input_pixels,
                   InferenceBuffers& bufs, PreloadedWeights& pw,
                   std::vector<uint8_t>& layer9_output,
                   std::vector<uint8_t>& layer12_output) {

    std::vector<uint8_t> layer_output;
    layer_output.reserve(208 * 208 * 16);  // max output size (L0: 692KB)
    std::vector<uint8_t> layer4_conv_output;
    std::vector<uint8_t> layer7_output;

    {
        const LayerConfig& cfg0 = LAYERS[0];
        int auto0 = 4096 / cfg0.ci_groups;
        int nmax0 = g_config.no_batch ? 1 : auto0;
        int nogs0 = std::min(nmax0, cfg0.co_groups);
        prepare_weights_in_buf(bufs, pw, 0, 0, nogs0, 0);
    }
    int wt_buf = 0;

    for (int i = 0; i < NUM_LAYERS; i++) {
        const LayerConfig& cfg = LAYERS[i];
        int next_layer_idx = (i + 1 < NUM_LAYERS) ? (i + 1) : -1;

        const std::vector<uint8_t>* pixel_ref = nullptr;
        std::vector<uint8_t> pixels_buf;

        if (i == 0) {
            pixel_ref = &input_pixels;
        } else if (i == 10) {
            pixel_ref = &layer7_output;
        } else if (i == 11) {
            std::vector<uint8_t> upsampled(26 * 26 * 128);
            cpu_upsample_2x(layer_output.data(), upsampled.data(), 13, 13, 128);
            std::vector<uint8_t> concat_out(26 * 26 * 384);
            cpu_concat_channels(upsampled.data(), 128,
                               layer4_conv_output.data(), 256,
                               concat_out.data(), 26, 26);
            pad_spatial(concat_out, 26, 26, 384, pixels_buf);
            pixel_ref = &pixels_buf;
        } else {
            int prev_h = LAYERS[i-1].out_h;
            int prev_w = LAYERS[i-1].out_w;
            int prev_c = LAYERS[i-1].cout;

            if (cfg.kernel_1x1) {
                pixel_ref = &layer_output;
            } else if (cfg.maxpool_stride == 1) {
                pad_spatial_stride1(layer_output, prev_h, prev_w, prev_c, pixels_buf);
                pixel_ref = &pixels_buf;
            } else {
                pad_spatial(layer_output, prev_h, prev_w, prev_c, pixels_buf);
                pixel_ref = &pixels_buf;
            }
        }

        if (i == 4) {
            LayerConfig cfg_no_mp = cfg;
            cfg_no_mp.maxpool_stride = 0;
            cfg_no_mp.out_h = 26;
            cfg_no_mp.out_w = 26;

            wt_buf = run_layer(cfg_no_mp, *pixel_ref, layer_output, bufs, pw, i,
                               wt_buf, next_layer_idx);
            layer4_conv_output = layer_output;

            std::vector<uint8_t> pooled_output(13 * 13 * 256);
            cpu_maxpool_stride2(layer_output.data(), pooled_output.data(), 26, 26, 256);
            layer_output = pooled_output;
        } else {
            wt_buf = run_layer(cfg, *pixel_ref, layer_output, bufs, pw, i,
                               wt_buf, next_layer_idx);
        }

        if (i == 7) layer7_output = layer_output;
        if (i == 9) layer9_output = layer_output;
        if (i == 12) layer12_output = layer_output;
    }
}

void capture_thread_func(int camera_id, int width, int height) {
    cv::VideoCapture cap;

    cap.open(camera_id, cv::CAP_V4L2);
    if (!cap.isOpened()) {
        cap.open(camera_id, cv::CAP_ANY);
    }

    if (!cap.isOpened()) {
        std::cerr << "Error: Cannot open camera " << camera_id << std::endl;
        g_running = false;
        return;
    }

    if (g_config.camera_format == "mjpeg") {
        cap.set(cv::CAP_PROP_FOURCC, cv::VideoWriter::fourcc('M', 'J', 'P', 'G'));
    } else if (g_config.camera_format == "yuyv") {
        cap.set(cv::CAP_PROP_FOURCC, cv::VideoWriter::fourcc('Y', 'U', 'Y', 'V'));
    }

    cap.set(cv::CAP_PROP_FRAME_WIDTH, width);
    cap.set(cv::CAP_PROP_FRAME_HEIGHT, height);
    cap.set(cv::CAP_PROP_BUFFERSIZE, 2);

    int actual_w = static_cast<int>(cap.get(cv::CAP_PROP_FRAME_WIDTH));
    int actual_h = static_cast<int>(cap.get(cv::CAP_PROP_FRAME_HEIGHT));

    int fourcc = static_cast<int>(cap.get(cv::CAP_PROP_FOURCC));
    char fourcc_str[5] = {
        static_cast<char>(fourcc & 0xFF),
        static_cast<char>((fourcc >> 8) & 0xFF),
        static_cast<char>((fourcc >> 16) & 0xFF),
        static_cast<char>((fourcc >> 24) & 0xFF),
        '\0'
    };

    std::cout << "Camera opened: " << actual_w << "x" << actual_h
              << " @ " << cap.get(cv::CAP_PROP_FPS) << " FPS"
              << " [" << fourcc_str << "]" << std::endl;

    if (actual_w != width || actual_h != height) {
        std::cout << "  (Requested " << width << "x" << height
                  << " but got " << actual_w << "x" << actual_h << ")" << std::endl;
    }

    int frame_id = 0;
    while (g_running) {
        if (g_paused) {
            std::this_thread::sleep_for(std::chrono::milliseconds(50));
            continue;
        }

        cv::Mat frame;
        if (!cap.read(frame)) {
            std::cerr << "Warning: Failed to capture frame" << std::endl;
            std::this_thread::sleep_for(std::chrono::milliseconds(10));
            continue;
        }

        CapturedFrame cf;
        cf.image = frame.clone();
        cf.timestamp_ms = std::chrono::duration_cast<std::chrono::milliseconds>(
            std::chrono::steady_clock::now().time_since_epoch()).count();
        cf.frame_id = frame_id++;

        g_capture_queue.push(std::move(cf));
    }

    cap.release();
}

void inference_thread_func(InferenceBuffers& bufs, PreloadedWeights& pw) {
    while (g_running) {
        CapturedFrame cf;
        if (!g_capture_queue.pop(cf, 100)) {
            continue;
        }

        auto preprocess_start = std::chrono::high_resolution_clock::now();
        std::vector<uint8_t> input_pixels;
        preprocess_frame(cf.image, input_pixels);
        auto preprocess_end = std::chrono::high_resolution_clock::now();

        auto infer_start = std::chrono::high_resolution_clock::now();
        std::vector<uint8_t> layer9_output, layer12_output;
        run_inference(input_pixels, bufs, pw, layer9_output, layer12_output);
        auto infer_end = std::chrono::high_resolution_clock::now();

        auto postprocess_start = std::chrono::high_resolution_clock::now();
        std::vector<BBox> detections;

        decode_detections(layer9_output.data(), 13, 13, ANCHORS_13x13, 3,
                         DEQUANT_SCALE_13x13, g_config.conf_threshold, 416, detections);

        decode_detections(layer12_output.data(), 26, 26, ANCHORS_26x26, 3,
                         DEQUANT_SCALE_26x26, g_config.conf_threshold, 416, detections);

        detections = nms(detections, g_config.nms_threshold);
        auto postprocess_end = std::chrono::high_resolution_clock::now();

        InferenceResult result;
        result.image = cf.image;
        result.detections = std::move(detections);
        result.preprocess_time_ms = std::chrono::duration<float, std::milli>(
            preprocess_end - preprocess_start).count();
        result.inference_time_ms = std::chrono::duration<float, std::milli>(
            infer_end - infer_start).count();
        result.postprocess_time_ms = std::chrono::duration<float, std::milli>(
            postprocess_end - postprocess_start).count();
        result.frame_id = cf.frame_id;

        g_display_queue.push(std::move(result));
    }
}

const cv::Scalar COLORS[] = {
    cv::Scalar(255, 0, 0),     cv::Scalar(0, 255, 0),
    cv::Scalar(0, 0, 255),     cv::Scalar(255, 255, 0),
    cv::Scalar(255, 0, 255),   cv::Scalar(0, 255, 255),
    cv::Scalar(128, 0, 255),   cv::Scalar(255, 128, 0),
};

void draw_detections(cv::Mat& frame, const std::vector<BBox>& detections,
                     float scale_x, float scale_y) {
    for (const auto& det : detections) {
        float cx = det.x * scale_x;
        float cy = det.y * scale_y;
        float w = det.w * scale_x;
        float h = det.h * scale_y;

        int x1 = std::max(0, static_cast<int>(cx - w / 2));
        int y1 = std::max(0, static_cast<int>(cy - h / 2));
        int x2 = std::min(frame.cols - 1, static_cast<int>(cx + w / 2));
        int y2 = std::min(frame.rows - 1, static_cast<int>(cy + h / 2));

        cv::Scalar color = COLORS[det.class_id % 8];

        cv::rectangle(frame, cv::Point(x1, y1), cv::Point(x2, y2), color, 2);

        std::string label = std::string(det.class_name) + " " +
                           std::to_string(static_cast<int>(det.confidence * 100)) + "%";
        int baseline;
        cv::Size label_size = cv::getTextSize(label, cv::FONT_HERSHEY_SIMPLEX,
                                              0.5, 1, &baseline);
        int label_y = std::max(y1, label_size.height + 5);
        cv::rectangle(frame,
                     cv::Point(x1, label_y - label_size.height - 5),
                     cv::Point(x1 + label_size.width + 5, label_y + 3),
                     color, cv::FILLED);

        cv::putText(frame, label, cv::Point(x1 + 2, label_y - 2),
                   cv::FONT_HERSHEY_SIMPLEX, 0.5, cv::Scalar(255, 255, 255), 1);
    }
}

void draw_stats(cv::Mat& frame, float preprocess_ms, float inference_ms,
                float postprocess_ms, int num_detections) {
    float fps = 1000.0f / inference_ms;

    std::stringstream ss;
    ss << std::fixed << std::setprecision(1);
    ss << "FPS: " << fps << " (" << inference_ms << "ms)";
    ss << " | Det: " << num_detections;

    cv::putText(frame, ss.str(), cv::Point(10, 25),
               cv::FONT_HERSHEY_SIMPLEX, 0.6, cv::Scalar(0, 255, 0), 2);

    if (g_config.no_batch) {
        cv::putText(frame, "NO-BATCH", cv::Point(frame.cols - 100, 25),
                   cv::FONT_HERSHEY_SIMPLEX, 0.5, cv::Scalar(0, 0, 255), 2);
    }
}

// Simple detection tracker with EMA smoothing
struct TrackedBox {
    BBox box;
    int age;         // frames since last matched
    int hits;        // total frames matched
};

class BoxTracker {
    std::vector<TrackedBox> tracks;
    static constexpr float EMA_ALPHA = 0.4f;  // smoothing factor (lower = smoother)
    static constexpr int MAX_AGE = 3;          // drop track after N unmatched frames
    static constexpr float MATCH_IOU = 0.3f;   // min IoU to match

public:
    std::vector<BBox> update(const std::vector<BBox>& detections) {
        // Mark all tracks as unmatched
        std::vector<bool> track_matched(tracks.size(), false);
        std::vector<bool> det_matched(detections.size(), false);

        // Match detections to existing tracks (greedy, by IoU)
        for (size_t d = 0; d < detections.size(); d++) {
            float best_iou_val = MATCH_IOU;
            int best_t = -1;
            for (size_t t = 0; t < tracks.size(); t++) {
                if (track_matched[t]) continue;
                if (tracks[t].box.class_id != detections[d].class_id) continue;
                float v = iou(tracks[t].box, detections[d]);
                if (v > best_iou_val) {
                    best_iou_val = v;
                    best_t = static_cast<int>(t);
                }
            }
            if (best_t >= 0) {
                // EMA smooth the box position
                auto& tb = tracks[best_t].box;
                const auto& db = detections[d];
                tb.x = EMA_ALPHA * db.x + (1 - EMA_ALPHA) * tb.x;
                tb.y = EMA_ALPHA * db.y + (1 - EMA_ALPHA) * tb.y;
                tb.w = EMA_ALPHA * db.w + (1 - EMA_ALPHA) * tb.w;
                tb.h = EMA_ALPHA * db.h + (1 - EMA_ALPHA) * tb.h;
                tb.confidence = EMA_ALPHA * db.confidence + (1 - EMA_ALPHA) * tb.confidence;
                tracks[best_t].age = 0;
                tracks[best_t].hits++;
                track_matched[best_t] = true;
                det_matched[d] = true;
            }
        }

        // Add unmatched detections as new tracks
        for (size_t d = 0; d < detections.size(); d++) {
            if (!det_matched[d]) {
                tracks.push_back({detections[d], 0, 1});
            }
        }

        // Age unmatched tracks and remove stale ones
        for (size_t t = 0; t < tracks.size(); ) {
            if (t < track_matched.size() && !track_matched[t]) {
                tracks[t].age++;
            }
            if (tracks[t].age > MAX_AGE) {
                tracks.erase(tracks.begin() + t);
                if (t < track_matched.size()) track_matched.erase(track_matched.begin() + t);
            } else {
                t++;
            }
        }

        // Return tracks that have been seen at least 2 frames
        std::vector<BBox> result;
        for (const auto& t : tracks) {
            if (t.hits >= 2 && t.age == 0) {
                result.push_back(t.box);
            }
        }
        return result;
    }
};

void display_thread_func() {
    if (!g_config.headless) {
        cv::namedWindow("TinyYOLOv3 Live", cv::WINDOW_AUTOSIZE);
    }

    int save_counter = 0;
    BoxTracker tracker;

    while (g_running) {
        InferenceResult result;
        if (!g_display_queue.pop(result, 100)) {
            continue;
        }

        // Smooth detections across frames
        std::vector<BBox> smoothed = tracker.update(result.detections);

        float scale_x = static_cast<float>(result.image.cols) / 416.0f;
        float scale_y = static_cast<float>(result.image.rows) / 416.0f;

        draw_detections(result.image, smoothed, scale_x, scale_y);
        draw_stats(result.image, result.preprocess_time_ms, result.inference_time_ms,
                  result.postprocess_time_ms, smoothed.size());

        if (g_config.headless) {
            if (!result.detections.empty()) {
                std::cout << "Frame " << result.frame_id << ": "
                          << result.detections.size() << " detections";
                for (const auto& det : result.detections) {
                    std::cout << " [" << det.class_name << " "
                              << static_cast<int>(det.confidence * 100) << "%]";
                }
                std::cout << std::endl;
            }
        } else {
            cv::imshow("TinyYOLOv3 Live", result.image);

            int key = cv::waitKey(1) & 0xFF;
            if (key == 'q' || key == 27) {
                g_running = false;
            } else if (key == 's') {
                std::string filename = "capture_" + std::to_string(save_counter++) + ".jpg";
                cv::imwrite(filename, result.image);
                std::cout << "Saved: " << filename << std::endl;
            } else if (key == 'p') {
                g_paused = !g_paused;
                std::cout << (g_paused ? "Paused" : "Resumed") << std::endl;
            }
        }
    }

    if (!g_config.headless) {
        cv::destroyAllWindows();
    }
}

void print_usage(const char* prog) {
    std::cerr << "Usage: " << prog << " <xclbin_file> <weights_dir> [options]\n"
              << "\nOptions:\n"
              << "  --camera <id>     Camera device ID (default: 0)\n"
              << "  --no-batch        Disable multi-OG batching\n"
              << "  --width <w>       Camera capture width (default: 640)\n"
              << "  --height <h>      Camera capture height (default: 480)\n"
              << "  --format <fmt>    Camera format: yuyv, mjpeg, auto (default: yuyv)\n"
              << "  --conf <thresh>   Confidence threshold 0.0-1.0 (default: 0.25)\n"
              << "  --headless        Run without display\n"
              << "  --verbose         Print detailed timing info\n"
              << "\nControls:\n"
              << "  'q' or ESC : Quit\n"
              << "  's'        : Save current frame\n"
              << "  'p'        : Pause/resume\n";
}

int main(int argc, char* argv[]) {
    if (argc < 3) {
        print_usage(argv[0]);
        return 1;
    }

    g_config.xclbin_file = argv[1];
    g_config.weights_dir = argv[2];

    for (int i = 3; i < argc; i++) {
        std::string arg = argv[i];
        if (arg == "--camera" && i + 1 < argc) {
            g_config.camera_id = std::stoi(argv[++i]);
        } else if (arg == "--no-batch") {
            g_config.no_batch = true;
        } else if (arg == "--width" && i + 1 < argc) {
            g_config.capture_width = std::stoi(argv[++i]);
        } else if (arg == "--height" && i + 1 < argc) {
            g_config.capture_height = std::stoi(argv[++i]);
        } else if (arg == "--format" && i + 1 < argc) {
            g_config.camera_format = argv[++i];
            if (g_config.camera_format != "yuyv" && g_config.camera_format != "mjpeg" && g_config.camera_format != "auto") {
                std::cerr << "Invalid format: " << g_config.camera_format << " (use yuyv, mjpeg, or auto)\n";
                return 1;
            }
        } else if (arg == "--conf" && i + 1 < argc) {
            g_config.conf_threshold = std::stof(argv[++i]);
        } else if (arg == "--headless") {
            g_config.headless = true;
        } else if (arg == "--verbose") {
            g_config.verbose = true;
        } else if (arg == "--help" || arg == "-h") {
            print_usage(argv[0]);
            return 0;
        }
    }

    std::cout << "========================================\n";
    std::cout << " TinyYOLOv3 Live Camera Demo\n";
    std::cout << "========================================\n";
    std::cout << "XCLBIN:  " << g_config.xclbin_file << "\n";
    std::cout << "Weights: " << g_config.weights_dir << "\n";
    std::cout << "Camera:  " << g_config.camera_id << " ("
              << g_config.capture_width << "x" << g_config.capture_height
              << ", " << g_config.camera_format << ")\n";
    std::cout << "Conf:    " << g_config.conf_threshold << "\n";
    if (g_config.no_batch) {
        std::cout << "Mode:    NO-BATCH (1 OG per kernel call)\n";
    }
    std::cout << "========================================\n\n";

    try {
        std::cout << "Initializing FPGA..." << std::endl;
        xrt::device device(0);
        auto uuid = device.load_xclbin(g_config.xclbin_file);
        xrt::kernel kernel(device, uuid, "TinyYOLOV3_HW_Complete");
        std::cout << "  Device: " << device.get_info<xrt::info::device::name>() << std::endl;

        InferenceBuffers bufs;
        init_buffers(device, kernel, bufs);
        std::cout << "  Buffers allocated" << std::endl;

        std::cout << "Loading weights..." << std::endl;
        PreloadedWeights pw;
        preload_all_weights(g_config.weights_dir, pw);
        std::cout << "  Weights loaded for " << NUM_LAYERS << " layers" << std::endl;

        std::cout << "\nStarting pipeline...\n" << std::endl;

        std::thread capture_thread(capture_thread_func, g_config.camera_id,
                                   g_config.capture_width, g_config.capture_height);
        std::thread inference_thread(inference_thread_func,
                                     std::ref(bufs), std::ref(pw));
        std::thread display_thread(display_thread_func);

        capture_thread.join();
        inference_thread.join();
        display_thread.join();

        std::cout << "\nShutdown complete." << std::endl;

    } catch (const std::exception& e) {
        std::cerr << "Error: " << e.what() << std::endl;
        g_running = false;
        return 1;
    }

    return 0;
}
