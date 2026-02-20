# Bharat-ARM: TinyYOLOv3 FPGA Accelerator

A high-performance FPGA accelerator for real-time TinyYOLOv3 object detection on the Xilinx Kria KV260 edge platform.

## Key Achievements

- **276x speedup** over ARM Cortex-A53 CPU baseline
- **10 FPS** real-time inference (1080x720 camera to display)
- **99ms** inference latency (vs 27.3s on CPU)
- **INT8 quantization** with preserved detection accuracy

## Platform

- **Board:** Xilinx Kria KV260 Vision AI Starter Kit
- **SoC:** Zynq UltraScale+ MPSoC (ZU5EV)
- **Clock:** 200 MHz kernel frequency
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
│   └── yolo_arm_native.cpp # ARM CPU baseline
├── scripts/                # Stimulus generation & utilities
│   ├── stimulus/           # Test vectors
│   └── gen_layer*_stimulus.py
├── sim/hardware-ai/        # Quantization & golden reference
│   ├── hardware_sim.py     # Python golden model
│   └── quantized_params.npz
├── architecture.md         # Detailed architecture docs
└── TECHNICAL_REPORT.md     # Full technical report
```

## Quick Start

### Build Host Programs (on Kria)

```bash
cd host
make
```

### Run FPGA Inference

```bash
./yolo_inference ../TinyYOLOV3_HW.xclbin ../stimulus_full/ ./test_image.jpg
```

### Run ARM CPU Baseline

```bash
python3 export_weights_for_cpu.py ../sim/hardware-ai/quantized_params.npz ./weights_cpu
./yolo_arm_native ./weights_cpu test_image.jpg
```

## Performance Summary

| Implementation | Inference Time | FPS | Speedup |
|----------------|----------------|-----|---------|
| Naive ARM Cortex-A53 | 27,339 ms | 0.037 | 1x |
| **FPGA Accelerator** | **99 ms** | **10.1** | **276x** |

## Documentation

- [TECHNICAL_REPORT.md](TECHNICAL_REPORT.md) - Comprehensive design report with benchmarks
- [architecture.md](architecture.md) - Detailed hardware architecture
