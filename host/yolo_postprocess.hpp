/*
 * yolo_postprocess.hpp - TinyYOLOv3 Post-processing
 *
 * Decodes detection head outputs to bounding boxes with NMS.
 */

#ifndef YOLO_POSTPROCESS_HPP
#define YOLO_POSTPROCESS_HPP

#include <vector>
#include <string>
#include <cmath>
#include <algorithm>
#include <cstdint>

// COCO class names (80 classes)
const char* COCO_CLASSES[] = {
    "person", "bicycle", "car", "motorcycle", "airplane", "bus", "train", "truck",
    "boat", "traffic light", "fire hydrant", "stop sign", "parking meter", "bench",
    "bird", "cat", "dog", "horse", "sheep", "cow", "elephant", "bear", "zebra",
    "giraffe", "backpack", "umbrella", "handbag", "tie", "suitcase", "frisbee",
    "skis", "snowboard", "sports ball", "kite", "baseball bat", "baseball glove",
    "skateboard", "surfboard", "tennis racket", "bottle", "wine glass", "cup",
    "fork", "knife", "spoon", "bowl", "banana", "apple", "sandwich", "orange",
    "broccoli", "carrot", "hot dog", "pizza", "donut", "cake", "chair", "couch",
    "potted plant", "bed", "dining table", "toilet", "tv", "laptop", "mouse",
    "remote", "keyboard", "cell phone", "microwave", "oven", "toaster", "sink",
    "refrigerator", "book", "clock", "vase", "scissors", "teddy bear", "hair drier",
    "toothbrush"
};

struct BBox {
    float x, y, w, h;      // Center x, y, width, height (in pixels, 416x416 scale)
    float confidence;       // Objectness * class_prob
    int class_id;
    const char* class_name;
};

// TinyYOLOv3 anchors (width, height pairs)
// 13x13 grid uses larger anchors (for detecting large objects)
const float ANCHORS_13x13[][2] = {{81, 82}, {135, 169}, {344, 319}};
// 26x26 grid uses smaller anchors (for detecting small objects)
const float ANCHORS_26x26[][2] = {{10, 14}, {23, 27}, {37, 58}};

// Quantization scales from hardware_sim.py calibration
// Detection Head 1 (Layer 9, 13x13): o_scale = 5.316
// Detection Head 2 (Layer 12, 26x26): o_scale = 5.409
const float DEQUANT_SCALE_13x13 = 5.3159403800964355f;
const float DEQUANT_SCALE_26x26 = 5.409017562866211f;

// Sigmoid function
inline float sigmoid(float x) {
    return 1.0f / (1.0f + std::exp(-x));
}

// Dequantize INT8 to float using proper scale from quantization
inline float dequant(int8_t val, float scale) {
    return static_cast<float>(val) / scale;
}

// Decode a single detection grid
void decode_detections(const uint8_t* data, int grid_h, int grid_w,
                       const float anchors[][2], int num_anchors,
                       float dequant_scale, float conf_threshold, int img_size,
                       std::vector<BBox>& detections) {

    const int num_classes = 80;
    const int box_attrs = 5 + num_classes;  // tx, ty, tw, th, obj, 80 classes

    float stride = static_cast<float>(img_size) / grid_h;

    for (int y = 0; y < grid_h; y++) {
        for (int x = 0; x < grid_w; x++) {
            for (int a = 0; a < num_anchors; a++) {
                int base_idx = (y * grid_w + x) * (num_anchors * box_attrs) + a * box_attrs;

                // Get raw values (INT8) and dequantize
                float tx = dequant(static_cast<int8_t>(data[base_idx + 0]), dequant_scale);
                float ty = dequant(static_cast<int8_t>(data[base_idx + 1]), dequant_scale);
                float tw = dequant(static_cast<int8_t>(data[base_idx + 2]), dequant_scale);
                float th = dequant(static_cast<int8_t>(data[base_idx + 3]), dequant_scale);
                float obj = dequant(static_cast<int8_t>(data[base_idx + 4]), dequant_scale);

                // Apply sigmoid to objectness
                float objectness = sigmoid(obj);

                // Early skip if objectness too low
                if (objectness < conf_threshold) continue;

                // Find best class
                int best_class = 0;
                float best_class_score = -1e9f;
                for (int c = 0; c < num_classes; c++) {
                    float class_score = dequant(static_cast<int8_t>(data[base_idx + 5 + c]), dequant_scale);
                    if (class_score > best_class_score) {
                        best_class_score = class_score;
                        best_class = c;
                    }
                }

                // Apply sigmoid to class score
                float class_prob = sigmoid(best_class_score);
                float confidence = objectness * class_prob;

                if (confidence < conf_threshold) continue;

                // Decode box coordinates
                float bx = (sigmoid(tx) + x) * stride;
                float by = (sigmoid(ty) + y) * stride;
                float bw = std::exp(tw) * anchors[a][0];
                float bh = std::exp(th) * anchors[a][1];

                BBox box;
                box.x = bx;
                box.y = by;
                box.w = bw;
                box.h = bh;
                box.confidence = confidence;
                box.class_id = best_class;
                box.class_name = COCO_CLASSES[best_class];

                detections.push_back(box);
            }
        }
    }
}

// Calculate IoU (Intersection over Union)
float iou(const BBox& a, const BBox& b) {
    float a_x1 = a.x - a.w / 2, a_y1 = a.y - a.h / 2;
    float a_x2 = a.x + a.w / 2, a_y2 = a.y + a.h / 2;
    float b_x1 = b.x - b.w / 2, b_y1 = b.y - b.h / 2;
    float b_x2 = b.x + b.w / 2, b_y2 = b.y + b.h / 2;

    float inter_x1 = std::max(a_x1, b_x1);
    float inter_y1 = std::max(a_y1, b_y1);
    float inter_x2 = std::min(a_x2, b_x2);
    float inter_y2 = std::min(a_y2, b_y2);

    float inter_w = std::max(0.0f, inter_x2 - inter_x1);
    float inter_h = std::max(0.0f, inter_y2 - inter_y1);
    float inter_area = inter_w * inter_h;

    float a_area = a.w * a.h;
    float b_area = b.w * b.h;
    float union_area = a_area + b_area - inter_area;

    return inter_area / (union_area + 1e-6f);
}

// Non-Maximum Suppression
std::vector<BBox> nms(std::vector<BBox>& detections, float iou_threshold) {
    // Sort by confidence (descending)
    std::sort(detections.begin(), detections.end(),
              [](const BBox& a, const BBox& b) { return a.confidence > b.confidence; });

    std::vector<bool> suppressed(detections.size(), false);
    std::vector<BBox> result;

    for (size_t i = 0; i < detections.size(); i++) {
        if (suppressed[i]) continue;

        result.push_back(detections[i]);

        for (size_t j = i + 1; j < detections.size(); j++) {
            if (suppressed[j]) continue;
            // Only suppress if same class
            if (detections[i].class_id == detections[j].class_id) {
                if (iou(detections[i], detections[j]) > iou_threshold) {
                    suppressed[j] = true;
                }
            }
        }
    }

    return result;
}

// Main post-processing function
std::vector<BBox> yolo_postprocess(const uint8_t* det_head1,  // 13x13x255
                                    const uint8_t* det_head2,  // 26x26x255
                                    int img_size = 416,
                                    float conf_threshold = 0.3f,
                                    float nms_threshold = 0.45f) {

    std::vector<BBox> all_detections;

    // Decode 13x13 grid (large objects) with proper dequantization scale
    decode_detections(det_head1, 13, 13, ANCHORS_13x13, 3,
                      DEQUANT_SCALE_13x13, conf_threshold, img_size, all_detections);

    // Decode 26x26 grid (small objects) with proper dequantization scale
    decode_detections(det_head2, 26, 26, ANCHORS_26x26, 3,
                      DEQUANT_SCALE_26x26, conf_threshold, img_size, all_detections);

    // Apply NMS
    std::vector<BBox> final_detections = nms(all_detections, nms_threshold);

    return final_detections;
}

// Print detections
void print_detections(const std::vector<BBox>& detections) {
    std::cout << "\nDetections (" << detections.size() << " objects):" << std::endl;
    std::cout << "--------------------------------------------" << std::endl;

    for (size_t i = 0; i < detections.size(); i++) {
        const BBox& d = detections[i];
        float x1 = d.x - d.w / 2;
        float y1 = d.y - d.h / 2;
        float x2 = d.x + d.w / 2;
        float y2 = d.y + d.h / 2;

        std::cout << "[" << i << "] " << d.class_name
                  << " (" << static_cast<int>(d.confidence * 100) << "%)"
                  << " @ [" << static_cast<int>(x1) << "," << static_cast<int>(y1)
                  << "," << static_cast<int>(x2) << "," << static_cast<int>(y2) << "]"
                  << std::endl;
    }

    if (detections.empty()) {
        std::cout << "  (no objects detected)" << std::endl;
    }
    std::cout << "--------------------------------------------" << std::endl;
}

#endif // YOLO_POSTPROCESS_HPP
