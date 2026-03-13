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
    int capture_width = 1280;
    int capture_height = 720;
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

struct PreloadedWeights {
    std::vector<std::vector<std::vector<uint8_t>>> layer_weights;  // [layer][og]
    std::vector<std::vector<std::vector<uint8_t>>> layer_biases;   // [layer][og]
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
}

struct InferenceBuffers {
    xrt::bo pixel_bo;
    xrt::bo weight_bo;
    xrt::bo bias_bo;
    xrt::bo output_bo;

    uint8_t* pixel_ptr;
    uint8_t* weight_ptr;
    uint8_t* bias_ptr;
    uint8_t* output_ptr;

    size_t pixel_buf_size;
    size_t weight_buf_size;
    size_t bias_buf_size;
    size_t output_buf_size;
};

void init_buffers(xrt::device& device, xrt::kernel& kernel, InferenceBuffers& bufs) {
    bufs.weight_buf_size = 8 * 1024 * 1024;   // 8MB
    bufs.bias_buf_size   = 128 * 32;           // 4KB
    bufs.pixel_buf_size  = 2 * 1024 * 1024;   // 2MB
    bufs.output_buf_size = 2 * 1024 * 1024;   // 2MB

    bufs.weight_bo = xrt::bo(device, bufs.weight_buf_size, kernel.group_id(19));
    bufs.bias_bo   = xrt::bo(device, bufs.bias_buf_size,   kernel.group_id(20));
    bufs.pixel_bo  = xrt::bo(device, bufs.pixel_buf_size,  kernel.group_id(21));
    bufs.output_bo = xrt::bo(device, bufs.output_buf_size, kernel.group_id(22));

    bufs.weight_ptr = bufs.weight_bo.map<uint8_t*>();
    bufs.bias_ptr   = bufs.bias_bo.map<uint8_t*>();
    bufs.pixel_ptr  = bufs.pixel_bo.map<uint8_t*>();
    bufs.output_ptr = bufs.output_bo.map<uint8_t*>();
}

// Crop center square, resize to 416x416, normalize to INT8, pad to 418x418x8
void preprocess_frame(const cv::Mat& frame, std::vector<uint8_t>& output) {
    int min_dim = std::min(frame.cols, frame.rows);
    int crop_size = min_dim;
    int x_offset = (frame.cols - crop_size) / 2 - 40;
    int y_offset = (frame.rows - crop_size) / 2 - 40;

    x_offset = std::max(0, std::min(x_offset, frame.cols - crop_size));
    y_offset = std::max(0, std::min(y_offset, frame.rows - crop_size));

    cv::Rect roi(x_offset, y_offset, crop_size, crop_size);
    cv::Mat cropped = frame(roi);

    cv::Mat resized;
    cv::resize(cropped, resized, cv::Size(416, 416), 0, 0, cv::INTER_LINEAR);

    cv::Mat rgb;
    cv::cvtColor(resized, rgb, cv::COLOR_BGR2RGB);

    int padded_h = 418, padded_w = 418, channels = 8;
    output.resize(padded_h * padded_w * channels, 0);

    for (int y = 0; y < 416; y++) {
        const uint8_t* row = rgb.ptr<uint8_t>(y);
        uint8_t* dst_row = output.data() + ((y + 1) * padded_w + 1) * channels;
        for (int x = 0; x < 416; x++) {
            dst_row[0] = (row[0] + 1) >> 1;
            dst_row[1] = (row[1] + 1) >> 1;
            dst_row[2] = (row[2] + 1) >> 1;
            row += 3;
            dst_row += channels;
        }
    }
}

void pad_spatial(const std::vector<uint8_t>& input, int h, int w, int c,
                 std::vector<uint8_t>& output) {
    int padded_h = h + 2;
    int padded_w = w + 2;
    output.resize(padded_h * padded_w * c, 0);
    for (int y = 0; y < h; y++) {
        for (int x = 0; x < w; x++) {
            int src_idx = (y * w + x) * c;
            int dst_idx = ((y + 1) * padded_w + (x + 1)) * c;
            std::memcpy(&output[dst_idx], &input[src_idx], c);
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
            int src_idx = (y * w + x) * c;
            int dst_idx = ((y + 1) * padded_w + (x + 1)) * c;
            std::memcpy(&output[dst_idx], &input[src_idx], c);
        }
    }
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

void neon_batch_interleave(const std::vector<std::vector<uint8_t>>& og_outputs,
                           uint8_t* dst, int num_pixels, int num_ogs, int cout) {
#ifdef __ARM_NEON
    for (int p = 0; p < num_pixels; p++) {
        uint8_t* pixel_dst = dst + p * cout;
        for (int og = 0; og < num_ogs; og++) {
            int valid_ch = std::min(8, cout - og * 8);
            if (valid_ch == 8) {
                vst1_u8(pixel_dst + og * 8, vld1_u8(og_outputs[og].data() + p * 8));
            } else if (valid_ch > 0) {
                std::memcpy(pixel_dst + og * 8, og_outputs[og].data() + p * 8, valid_ch);
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

void run_layer(xrt::kernel& kernel, const LayerConfig& cfg,
               const std::vector<uint8_t>& pixels, std::vector<uint8_t>& output,
               InferenceBuffers& bufs, PreloadedWeights& pw, int layer_idx) {

    int max_og_per_chunk = g_config.no_batch ? 1 : (4096 / cfg.ci_groups);
    int num_chunks = (cfg.co_groups + max_og_per_chunk - 1) / max_og_per_chunk;

    int actual_padded_h = (cfg.maxpool_stride == 1) ? (cfg.out_h + 3) : cfg.padded_h;
    int actual_padded_w = (cfg.maxpool_stride == 1) ? (cfg.out_w + 3) : cfg.padded_w;
    size_t pixel_bytes = actual_padded_h * actual_padded_w * cfg.cin_pad;

    int num_pixels = cfg.out_h * cfg.out_w;
    size_t weight_bytes_per_og = cfg.ci_groups * 8 * 8 * 16;
    size_t output_bytes_per_og = num_pixels * 8;
    size_t output_stride_per_og = ((output_bytes_per_og + 4095) / 4096) * 4096;

    std::memcpy(bufs.pixel_ptr, pixels.data(), pixel_bytes);
    bufs.pixel_bo.sync(XCL_BO_SYNC_BO_TO_DEVICE, pixel_bytes, 0);

    std::vector<std::vector<uint8_t>> og_outputs(cfg.co_groups);
    for (int og = 0; og < cfg.co_groups; og++) {
        og_outputs[og].resize(output_bytes_per_og);
    }

    for (int chunk = 0; chunk < num_chunks; chunk++) {
        int chunk_start_og = chunk * max_og_per_chunk;
        int ogs_in_chunk = std::min(max_og_per_chunk, cfg.co_groups - chunk_start_og);

        for (int og = 0; og < ogs_in_chunk; og++) {
            int global_og = chunk_start_og + og;
            std::memcpy(bufs.weight_ptr + og * weight_bytes_per_og,
                       pw.layer_weights[layer_idx][global_og].data(),
                       weight_bytes_per_og);
            std::memcpy(bufs.bias_ptr + og * 32,
                       pw.layer_biases[layer_idx][global_og].data(),
                       std::min((size_t)32, pw.layer_biases[layer_idx][global_og].size()));
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

        run.start();
        run.wait();

        size_t actual_output_bytes = static_cast<size_t>(ogs_in_chunk) * output_stride_per_og;
        bufs.output_bo.sync(XCL_BO_SYNC_BO_FROM_DEVICE, actual_output_bytes, 0);

        for (int og = 0; og < ogs_in_chunk; og++) {
            int global_og = chunk_start_og + og;
            std::memcpy(og_outputs[global_og].data(),
                       bufs.output_ptr + og * output_stride_per_og,
                       output_bytes_per_og);
        }
    }

    output.resize(num_pixels * cfg.cout);
    if (cfg.co_groups == 1) {
        std::memcpy(output.data(), og_outputs[0].data(), num_pixels * std::min(8, cfg.cout));
    } else {
        neon_batch_interleave(og_outputs, output.data(), num_pixels, cfg.co_groups, cfg.cout);
    }
}

void run_inference(const std::vector<uint8_t>& input_pixels,
                   xrt::kernel& kernel, InferenceBuffers& bufs,
                   PreloadedWeights& pw,
                   std::vector<uint8_t>& layer9_output,
                   std::vector<uint8_t>& layer12_output) {

    std::vector<uint8_t> layer_output;
    std::vector<uint8_t> layer4_conv_output;
    std::vector<uint8_t> layer7_output;

    for (int i = 0; i < NUM_LAYERS; i++) {
        const LayerConfig& cfg = LAYERS[i];
        std::vector<uint8_t> pixels;

        if (i == 0) {
            pixels = input_pixels;
        } else if (i == 10) {
            pixels = layer7_output;
        } else if (i == 11) {
            std::vector<uint8_t> upsampled(26 * 26 * 128);
            cpu_upsample_2x(layer_output.data(), upsampled.data(), 13, 13, 128);
            std::vector<uint8_t> concat_out(26 * 26 * 384);
            cpu_concat_channels(upsampled.data(), 128,
                               layer4_conv_output.data(), 256,
                               concat_out.data(), 26, 26);
            pad_spatial(concat_out, 26, 26, 384, pixels);
        } else {
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

            run_layer(kernel, cfg_no_mp, pixels, layer_output, bufs, pw, i);
            layer4_conv_output = layer_output;

            std::vector<uint8_t> pooled_output(13 * 13 * 256);
            cpu_maxpool_stride2(layer_output.data(), pooled_output.data(), 26, 26, 256);
            layer_output = pooled_output;
        } else {
            run_layer(kernel, cfg, pixels, layer_output, bufs, pw, i);
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

    cap.set(cv::CAP_PROP_FOURCC, cv::VideoWriter::fourcc('M', 'J', 'P', 'G'));
    cap.set(cv::CAP_PROP_FRAME_WIDTH, width);
    cap.set(cv::CAP_PROP_FRAME_HEIGHT, height);
    cap.set(cv::CAP_PROP_BUFFERSIZE, 2);

    int actual_w = static_cast<int>(cap.get(cv::CAP_PROP_FRAME_WIDTH));
    int actual_h = static_cast<int>(cap.get(cv::CAP_PROP_FRAME_HEIGHT));

    std::cout << "Camera opened: " << actual_w << "x" << actual_h
              << " @ " << cap.get(cv::CAP_PROP_FPS) << " FPS" << std::endl;

    if (actual_w != width || actual_h != height) {
        std::cout << "  (Requested " << width << "x" << height
                  << " but camera doesn't support it)" << std::endl;
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

void inference_thread_func(xrt::kernel& kernel, InferenceBuffers& bufs,
                           PreloadedWeights& pw) {
    while (g_running) {
        CapturedFrame cf;
        if (!g_capture_queue.pop(cf, 100)) {
            continue;
        }

        auto total_start = std::chrono::high_resolution_clock::now();

        auto preprocess_start = std::chrono::high_resolution_clock::now();
        std::vector<uint8_t> input_pixels;
        preprocess_frame(cf.image, input_pixels);
        auto preprocess_end = std::chrono::high_resolution_clock::now();

        auto infer_start = std::chrono::high_resolution_clock::now();
        std::vector<uint8_t> layer9_output, layer12_output;
        run_inference(input_pixels, kernel, bufs, pw, layer9_output, layer12_output);
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
    float total_ms = preprocess_ms + inference_ms + postprocess_ms;
    float fps = 1000.0f / total_ms;

    std::stringstream ss;
    ss << std::fixed << std::setprecision(1);
    ss << "FPS: " << fps << " | Infer: " << inference_ms << "ms";
    ss << " | Det: " << num_detections;

    cv::putText(frame, ss.str(), cv::Point(10, 25),
               cv::FONT_HERSHEY_SIMPLEX, 0.6, cv::Scalar(0, 255, 0), 2);

    if (g_config.no_batch) {
        cv::putText(frame, "NO-BATCH", cv::Point(frame.cols - 100, 25),
                   cv::FONT_HERSHEY_SIMPLEX, 0.5, cv::Scalar(0, 0, 255), 2);
    }
}

void display_thread_func() {
    if (!g_config.headless) {
        cv::namedWindow("TinyYOLOv3 Live", cv::WINDOW_AUTOSIZE);
    }

    int save_counter = 0;

    while (g_running) {
        InferenceResult result;
        if (!g_display_queue.pop(result, 100)) {
            continue;
        }

        float scale_x = static_cast<float>(result.image.cols) / 416.0f;
        float scale_y = static_cast<float>(result.image.rows) / 416.0f;

        draw_detections(result.image, result.detections, scale_x, scale_y);
        draw_stats(result.image, result.preprocess_time_ms, result.inference_time_ms,
                  result.postprocess_time_ms, result.detections.size());

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
              << g_config.capture_width << "x" << g_config.capture_height << ")\n";
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
        std::thread inference_thread(inference_thread_func, std::ref(kernel),
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
