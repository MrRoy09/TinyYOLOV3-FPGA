# Bharat-ARM: TinyYOLOv3 FPGA Accelerator

A high-performance FPGA accelerator for real-time TinyYOLOv3 object detection on the Xilinx Kria KV260 edge platform.

## Results

- **448x speedup** over ARM Cortex-A53 CPU baseline
- **~16 FPS** inference throughput (61ms per frame)
- **61ms** inference latency (vs 27.3s on CPU)
- **INT8 quantization** calibrated on 100 COCO val2017 images
- **Real-time camera demo** with EMA-smoothed bounding box tracking

## Platform

- **Board:** Xilinx Kria KV260 Vision AI Starter Kit
- **SoC:** Zynq UltraScale+ MPSoC (ZU5EV)
- **Clock:** 250 MHz kernel frequency
- **Resources:** 756 DSPs (60.6%), 64 URAMs (100%), 53K LUTs (45.5%)

## Architecture

The accelerator uses an NHWC (channel-last) pipelined architecture with 8-way input and output parallelism:

- **8 parallel Processing Elements** computing 576 MACs/cycle
- **URAM-based weight storage** (64 URAMs, 2.25 MB)
- **Fused convolution + maxpool** for layers 0-5
- **INT8 datapath** with INT32 accumulation

See [architecture.md](architecture.md) for detailed design documentation.

## Directory Structure

```
arm-bharat/
├── hdl/                    # RTL source files
│   ├── conv_top.sv         # Top-level convolution wrapper
│   ├── conv_pe.sv          # Processing element (72 DSPs)
│   ├── weight_manager.sv   # URAM weight storage
│   ├── axi_conv_wrapper.sv # AXI interface wrapper
│   └── testbenches/        # SystemVerilog testbenches
├── host/                   # CPU host code
│   ├── yolo_inference.cpp  # FPGA inference driver
│   ├── yolo_camera.cpp     # Live camera demo with tracking
│   ├── yolo_arm_native.cpp # ARM CPU baseline
│   └── yolo_postprocess.hpp # Detection decoding & NMS
├── scripts/                # Stimulus generation & utilities
│   └── prepare_full_inference.py  # Generate FPGA stimulus
├── sim/hardware-ai/        # Quantization & golden reference
│   ├── hardware_sim.py     # Python golden model + calibration
│   ├── fold_weights.py     # Batch norm folding
│   └── quantized_params.npz
├── architecture.md         # Detailed architecture docs
└── TECHNICAL_REPORT.md     # Full technical report
```

## Quick Start

### Build Host Programs (on Kria)

```bash
cd host
make fpga    # Build FPGA programs (requires XRT)
make arm     # Build ARM-native baseline (no XRT needed)
```

### Run FPGA Inference

```bash
./yolo_inference <xclbin> <weights_dir> <image.jpg> [--profile]
```

### Run Live Camera Demo

```bash
DISPLAY=:1 ./yolo_camera <xclbin> <weights_dir> [--conf 0.5]
```

Controls: `q`/ESC = quit, `s` = save frame, `p` = pause

### Run ARM CPU Baseline

```bash
python3 export_weights_for_cpu.py ../sim/hardware-ai/quantized_params.npz ./weights_cpu
./yolo_arm_native ./weights_cpu test_image.jpg
```

### Recalibrate Quantization

```bash
cd sim/hardware-ai
# Download COCO val2017 to ./val2017/
python3 hardware_sim.py --calibrate --calib-dir ./val2017 --max-images 100 --test
# Then regenerate stimulus
cd ../..
python3 scripts/prepare_full_inference.py scripts/test_image.jpg --output-dir scripts/stimulus_full
```

## Running Testbenches

Testbenches are located in `hdl/testbenches/` and use Vivado xsim by default.

### Using the Makefile (recommended)

```bash
cd hdl/testbenches

# Run a single testbench
make tb_conv_pe
make tb_axi_conv_wrapper

# Run test suites
make unit_tests        # Fast, focused tests
make integration_tests # Slower, comprehensive tests
make all_tests         # Everything with summary

# Clean artifacts
make clean
```

### Available Testbenches

| Type | Testbenches |
|------|-------------|
| Unit | `tb_conv_pe`, `tb_conv_3x3_nhwc`, `tb_quantizer`, `tb_maxpool`, `tb_kernel_window`, `tb_weight_bank`, `tb_bias_store` |
| Integration | `tb_conv_controller`, `tb_conv_top_batch`, `tb_conv_top_1x1`, `tb_conv_top_multi_og` |
| E2E | `tb_conv_top_e2e_batch`, `tb_axi_conv_wrapper` |

## Performance Summary

| Implementation | Inference Time | FPS | Speedup |
|----------------|----------------|-----|---------|
| Naive ARM Cortex-A53 | 27,339 ms | 0.037 | 1x |
| **FPGA @ 250 MHz** | **61 ms** | **~16** | **448x** |

### Per-Layer Breakdown (FPGA @ 250 MHz)

| Layer | Cin→Cout | OGs | Time (ms) |
|-------|----------|-----|-----------|
| 0 | 3→16 | 2 | 6 |
| 1 | 16→32 | 4 | 4 |
| 2 | 32→64 | 8 | 3 |
| 3 | 64→128 | 16 | 2 |
| 4 | 128→256 | 32 | 3 |
| 5 | 256→512 | 64 | 4 |
| 6 | 512→1024 | 128 | 12 |
| 7 | 1024→256 | 32 | 4 |
| 8 | 256→512 | 64 | 3 |
| 9 | 512→255 | 32 | 2 |
| 10 | 256→128 | 16 | 1 |
| 11 | 384→256 | 32 | 7 |
| 12 | 256→255 | 32 | 4 |
| **Total** | | **448** | **61** |

## Documentation

- [TECHNICAL_REPORT.md](TECHNICAL_REPORT.md) - Comprehensive design report with benchmarks
- [architecture.md](architecture.md) - Detailed hardware architecture
