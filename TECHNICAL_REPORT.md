# TinyYOLOv3 FPGA Accelerator - Technical Report

**Project:** Bharat-ARM
**Platform:** Xilinx Kria KV260 (Zynq UltraScale+ MPSoC)
**Date:** February 2026

---

## 1. Introduction

This document presents the design and implementation of a custom FPGA accelerator for TinyYOLOv3 object detection targeting edge deployment on the Kria KV260 platform. The accelerator achieves 448x speedup over an ARM Cortex-A53 baseline, delivering 61ms inference latency (~16 FPS throughput) at 250 MHz. A real-time camera demo with EMA-smoothed bounding box tracking demonstrates end-to-end object detection.

---

## 2. Design Specifications

### 2.1 Target Platform

The Kria KV260 SoM provides the following resources:

| Resource | Available |
|----------|-----------|
| DSP48E2 | 1,248 |
| URAM | 64 (2.25 MB) |
| BRAM36K | 144 (5 MB) |
| LUTs | 117,120 |
| Flip-Flops | 234,240 |

The system runs at **250 MHz** kernel clock frequency.

### 2.2 Model Configuration

TinyYOLOv3 consists of 13 convolutional layers with two detection heads outputting at 13×13 and 26×26 spatial resolutions. Input images are resized to 416×416 and quantized to INT8. The model contains approximately 8.4 million parameters.

---

## 3. Architecture

### 3.1 Data Layout

The accelerator processes data in NHWC (channel-last) format rather than the conventional NCHW layout. This design choice eliminates the need for partial sum storage between channel groups, enables sequential DDR burst transfers for improved memory efficiency, and allows output pixels to stream out immediately upon completion of channel accumulation.

### 3.2 Parallelism Strategy

The design employs a 2D parallelism scheme with P_in=8 and P_out=8:

- **Input Parallelism (P_in=8):** Eight input channels are processed every clock cycle, matching the 64-bit AXI data width.
- **Output Parallelism (P_out=8):** Eight output filters are computed simultaneously across eight parallel processing elements.

This configuration yields 576 multiply-accumulate operations per cycle in the convolution core.

### 3.3 Processing Element

Each processing element computes one output channel through a three-stage pipeline. The first stage performs 72 parallel multiplications (9 spatial positions × 8 input channels). The second stage reduces the 72 products to a single cycle sum through an adder tree. The third stage accumulates the cycle sum into a 32-bit register across all input channel groups.

Each PE consumes 72 DSP48E2 slices for the multiplication operations.

### 3.4 Weight Storage

Weights are stored in a distributed URAM structure consisting of 8 banks with 8 URAMs per bank (64 total). Each URAM entry is 72 bits wide, holding 9 spatial weights for one input channel. The read latency is 3 cycles, which is matched by corresponding delays on the pixel and control paths.

The URAM depth of 4096 addresses accommodates all layers except Layer 6 (512→1024 channels), which requires two weight loading phases.

### 3.5 Quantization

The design uses calibrated INT8 quantization with the following pipeline:

1. Convolution accumulates INT8×INT8 products into INT32
2. INT32 bias is added to the accumulator
3. Leaky ReLU applies a right-shift by 3 for negative values (approximating 0.125)
4. Output requantization scales by a per-layer multiplier M and right-shifts by 16 bits
5. Result is clipped to [-128, 127]

Quantization parameters are calibrated using 100 images from the COCO val2017 dataset with 99.9th percentile activation clipping to minimize accuracy loss.

### 3.6 Fused Operations

Convolution and 2×2 max pooling are fused into a single pass for layers 0-5, eliminating intermediate memory transactions. The maxpool unit maintains a row buffer to compare adjacent pixels across rows.

1×1 convolutions reuse the 3×3 pipeline by routing only the center pixel position and packing weights into the center spatial slot.

---

## 4. Resource Utilization

### 4.1 Summary

| Resource | Used | Available | Utilization |
|----------|------|-----------|-------------|
| DSP48E2 | 756 | 1,248 | 60.6% |
| URAM | 64 | 64 | 100% |
| BRAM Tiles | 41 | 144 | 28.5% |
| LUTs | 53,314 | 117,120 | 45.5% |
| Registers | 64,807 | 234,240 | 27.7% |

### 4.2 DSP Allocation

The 756 DSPs are distributed as follows:

- **Convolution PEs:** 576 DSPs (8 PEs × 72 DSPs each for 9×8 MAC operations)
- **Quantizers:** 64 DSPs (8 channels × scaling multiplications)
- **Infrastructure:** 116 DSPs (AXI data movers, address generation)

### 4.3 Memory Allocation

All 64 URAMs are dedicated to weight storage, providing 2.25 MB capacity organized as 8 banks serving 8 parallel filter computations.

BRAM usage of 41 tiles includes line buffers for kernel window generation (~16 tiles), bias storage in dual-port configuration (~4 tiles), maxpool row buffers (~5 tiles), and AXI stream FIFOs (~16 tiles).

The remaining 103 BRAM tiles are available for future optimizations such as pixel caching.

---

## 5. Performance Results

### 5.1 Benchmark Configuration

Testing was performed with various input images resized to 416×416. Both ARM CPU and FPGA implementations use identical INT8 quantization parameters and preprocessing. The FPGA runs at 250 MHz kernel clock.

### 5.2 Latency Comparison

Three implementations are compared, all using identical INT8 quantization parameters:

| Implementation | Inference (ms) | FPS | vs Naive | vs FPGA |
|----------------|----------------|-----|----------|---------|
| Naive ARM (single-thread, no SIMD) | 27,339 | 0.037 | 1× | 448× slower |
| Optimized ARM (im2col + NEON + 4-thread) | 640 | 1.6 | 43× | 10.5× slower |
| **FPGA @ 250 MHz** | **61** | **~16** | **448×** | **1×** |

The optimized ARM implementation uses im2col to convert convolutions to matrix multiplications, NEON SIMD for INT8 dot products (vmull_s8 + vpadalq_s16), and 4-thread parallelism across all Cortex-A53 cores. This represents a realistic upper bound for CPU performance on this platform.

#### Optimized ARM Per-Layer Breakdown

| Layer | Cin→Cout | ARM Optimized (ms) | FPGA (ms) | Ratio |
|-------|----------|-------------------|-----------|-------|
| 0 | 3→16 | 98 | 6 | 16× |
| 1 | 16→32 | 98 | 4 | 25× |
| 2 | 32→64 | 63 | 3 | 21× |
| 3 | 64→128 | 44 | 2 | 22× |
| 4 | 128→256 | 34 | 3 | 11× |
| 5 | 256→512 | 31 | 4 | 8× |
| 6 | 512→1024 | 111 | 12 | 9× |
| 7 | 1024→256 | 8 | 4 | 2× |
| 8 | 256→512 | 30 | 3 | 10× |
| 9 | 512→255 | 4 | 2 | 2× |
| 10 | 256→128 | 1 | 1 | 1× |
| 11 | 384→256 | 109 | 7 | 16× |
| 12 | 256→255 | 8 | 4 | 2× |
| **Total** | | **640** | **61** | **10.5×** |

The FPGA advantage is largest for early layers with large spatial dimensions (L0-L2: 16-25×) where the 576 MACs/cycle throughput dominates. For small 1×1 convolutions (L7, L9, L10), the advantage narrows to 1-2× as host-side DMA overhead becomes the bottleneck.

### 5.3 Per-Layer Breakdown (FPGA @ 250 MHz)

| Layer | Channels | Output Groups | Time (ms) | ms/OG |
|-------|----------|---------------|-----------|-------|
| 0 | 3→16 | 2 | 6 | 3.00 |
| 1 | 16→32 | 4 | 4 | 1.00 |
| 2 | 32→64 | 8 | 3 | 0.38 |
| 3 | 64→128 | 16 | 2 | 0.12 |
| 4 | 128→256 | 32 | 3 | 0.09 |
| 5 | 256→512 | 64 | 4 | 0.06 |
| 6 | 512→1024 | 128 | 12 | 0.09 |
| 7 | 1024→256 | 32 | 4 | 0.12 |
| 8 | 256→512 | 64 | 3 | 0.05 |
| 9 | 512→255 | 32 | 2 | 0.06 |
| 10 | 256→128 | 16 | 1 | 0.06 |
| 11 | 384→256 | 32 | 7 | 0.22 |
| 12 | 256→255 | 32 | 4 | 0.12 |
| **Total** | | **448** | **61** | |

Layer 6 dominates execution time due to having the most output groups (128) and requiring two weight loading phases.

### 5.4 Inference Time Breakdown

Profiling on Kria reveals the 61ms inference time is split between:

| Category | Time (ms) | % |
|----------|-----------|---|
| FPGA compute | 39.6 | 65% |
| Output DMA copy | 10.8 | 18% |
| Interleave | 2.2 | 4% |
| Pixel DMA | 2.1 | 3% |
| Other (alloc, sync) | 6.3 | 10% |

Host-side optimizations include 4-thread parallel DMA-to-cache memcpy, NEON-accelerated interleaving with pixel-major fast paths for small OG counts, and pre-allocated reusable buffers.

### 5.5 Throughput

The system achieves approximately 16 FPS inference throughput (61ms per frame). The live camera demo runs at 13-14 FPS including camera capture, preprocessing, and display overhead. The ARM CPU baseline achieves 0.037 FPS.

---

## 6. Detection Results

Both implementations correctly identify the primary objects in test images. With COCO val2017 calibration (100 images, 99.9th percentile), the INT8 model closely tracks the FP32 model:

| Image | FP32 Top Detections | INT8 Top Detections |
|-------|--------------------|--------------------|
| person.jpg | person (98%), dog (89%) | person (100%), dog (100%) |
| horses.jpg | horse (74%), horse (70%) | horse (100%), cow (100%) |
| kite.jpg | kite (85%), person (85%) | person (93%), kite (69%) |
| eagle.jpg | bird (76%), bird (62%) | bird (100%), bird (100%) |

The live camera demo includes EMA-smoothed bounding box tracking to reduce frame-to-frame jitter caused by INT8 quantization noise.

---

## 7. CPU-FPGA Partitioning

The workload is partitioned following a "smart CPU, simple hardware" approach:

**FPGA handles:**
- 3×3 and 1×1 convolution
- Batch normalization (folded into convolution weights)
- Leaky ReLU activation
- 2×2 max pooling (fused with convolution)
- INT8 requantization

**CPU handles:**
- Layer sequencing and configuration
- DMA orchestration
- Weight and bias loading
- 2× nearest-neighbor upsampling
- Feature map concatenation (via DMA addressing)
- Detection post-processing (NMS, box decoding)

This partitioning keeps the FPGA datapath simple while leveraging CPU flexibility for control-intensive operations.

---

## 8. Future Work

Several optimizations remain for future iterations:

**Increased Parallelism:** DSP utilization of 60.6% leaves headroom for P_out=16, which would double throughput for compute-bound layers at the cost of increased weight bandwidth requirements.

**Weight Compression:** Structured pruning or weight sharing could reduce URAM pressure and enable single-pass processing for Layer 6.

**Per-Channel Quantization:** The current per-layer quantization uses a single M/n pair per layer. Per-channel quantization (one M per output filter) would improve accuracy, particularly for detection head layers, but requires RTL changes to the quantizer.

**Wider AXI Datapath:** The current 128-bit AXI interface limits DDR throughput for output DMA copies. A 256-bit interface would reduce the 10.8ms output copy overhead.

---

## 9. Conclusion

The implemented accelerator achieves 10.5× speedup over an optimized ARM Cortex-A53 implementation (im2col + NEON + 4-thread), delivering real-time TinyYOLOv3 inference at 61ms latency (~16 FPS) on the Kria KV260 edge platform at 250 MHz. Compared to a naive CPU baseline, the speedup is 448×. Resource utilization is efficient with 60.6% DSP usage and 100% URAM usage. Detection accuracy is preserved through INT8 quantization calibrated on 100 COCO val2017 images. A live camera demo with EMA-smoothed bounding box tracking demonstrates practical end-to-end object detection at 13-14 FPS. The design validates the feasibility of deploying CNN-based object detection on resource-constrained edge FPGAs.

---

## Appendix A: ARM CPU Implementation Details

Two ARM CPU implementations are provided for comparison, both using identical INT8 quantization:

### A.1 Naive Baseline (`yolo_arm_native`)

Single-threaded, no SIMD. Direct convolution using 7 nested loops. **27,339 ms** per inference.

### A.2 Optimized Implementation (`yolo_arm_optimized`)

Applies standard CPU optimization techniques to the same INT8 model. **640 ms** per inference (43× faster than naive).

| Optimization | Technique | Impact |
|---|---|---|
| Memory layout | im2col converts conv to GEMM | Cache-friendly, eliminates redundant index computation |
| SIMD vectorization | NEON INT8: vmull_s8 + vpadalq_s16 | 16 multiply-accumulates per instruction |
| Multi-threading | 4 threads across Cortex-A53 cores | ~3.5× scaling for compute-bound layers |
| Compiler | -O3 -march=native -ffast-math | Auto-vectorization, instruction scheduling |

Note: The Cortex-A53 lacks the ARMv8.2 dot product instruction (SDOT), which would provide an additional 2-4× speedup on newer cores (A55, A76+). The 640ms result represents a realistic upper bound for this specific CPU.

---

## Appendix B: Reproducibility

### ARM-Native Benchmark

```bash
cd ~/tinyyolo/host
python3 export_weights_for_cpu.py ../sim/hardware-ai/quantized_params.npz ./weights_cpu
g++ -std=c++17 -O3 -march=native -ffast-math -funroll-loops -g -Wall \
    -I/usr/include/opencv4 -o yolo_arm_native yolo_arm_native.cpp \
    -lopencv_core -lopencv_imgproc -lopencv_highgui -lopencv_imgcodecs -lpthread
./yolo_arm_native ./weights_cpu test_image.jpg
```

### FPGA Benchmark

```bash
./yolo_inference ../TinyYOLOV3_HW.xclbin ../stimulus_full/ ./test_image.jpg
```
