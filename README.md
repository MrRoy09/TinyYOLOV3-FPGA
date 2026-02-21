# Bharat-ARM: TinyYOLOv3 FPGA Accelerator

A high-performance FPGA accelerator for real-time TinyYOLOv3 object detection on the Xilinx Kria KV260 edge platform.

## Results

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

# Use Icarus Verilog instead
make tb_conv_pe SIM=iverilog

# Clean artifacts
make clean
```

### Using wrapper scripts

```bash
./scripts/run_tb.sh tb_conv_pe
./scripts/run_axi_tb_layer.sh 0   # AXI testbench for layer 0
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
| **FPGA Accelerator** | **99 ms** | **10.1** | **276x** |

## Documentation

- [TECHNICAL_REPORT.md](TECHNICAL_REPORT.md) - Comprehensive design report with benchmarks
- [architecture.md](architecture.md) - Detailed hardware architecture
