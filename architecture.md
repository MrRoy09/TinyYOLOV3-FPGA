# TinyYOLOv3 FPGA Accelerator Architecture

## Target Platform: Kria KV260

| Resource | Available | Used | Utilization |
|----------|-----------|------|-------------|
| DSP48E2 | 1,248 | 756 | 60.6% |
| URAM | 64 (2.25 MB) | 64 | 100% |
| BRAM36K | 144 (5 MB) | 41 | 28.5% |
| LUTs | 117,120 | 53,314 | 45.5% |
| FFs | 234,240 | 64,807 | 27.7% |

Clock: 200 MHz

---

## Parallelism: P_in=8, P_out=8

- **Input Parallelism (P_in=8):** 8 input channels processed per cycle (64-bit vector)
- **Output Parallelism (P_out=8):** 8 output filters computed in parallel
- **Throughput:** 576 MACs/cycle (8 PEs × 72 MACs each)

---

## Data Layout: NHWC (Channel-Last)

All data flows in `[H][W][C]` format:
- Sequential DDR bursts (no strided access)
- Register-based accumulation (no partial sum memory)
- Output pixels stream out as soon as channel accumulation completes

---

## Module Hierarchy

```
TinyYOLOV3_HW                          # Top-level RTL kernel
├── TinyYOLOV3_HW_control_s_axi        # AXI-Lite registers
└── axi_conv_wrapper                   # AXI-Stream bridge + control FSM
    └── conv_top                       # Convolution datapath
        ├── bias_store                 # 128-bit×256 BRAM (dual-port)
        ├── weight_manager             # 8 banks × 8 URAMs (64 total)
        ├── conv_controller            # FSM: IDLE→LOAD_BIAS→CONV→DRAIN
        ├── kernel_window              # 3×3 sliding window generator
        ├── conv_3x3                   # 8 parallel output channels
        │   └── conv_pe [×8]           # 72 DSPs each (9 spatial × 8 channels)
        ├── quantizer [×8]             # INT32→INT8 scaling + LeakyReLU
        └── maxpool                    # 2×2 max pooling (optional)
```

---

## AXI Interfaces

| Interface | Type | Width | Purpose |
|-----------|------|-------|---------|
| `s_axi_control` | AXI4-Lite | 32-bit | Configuration registers |
| `m_axi_gmem*` | AXI4-MM | 128-bit | DDR read/write (weights, bias, pixels, output) |

---

## AXI-Lite Register Map

| Address | Name | Description |
|---------|------|-------------|
| 0x00 | AP_CTRL | ap_start[0], ap_done[1], ap_idle[2] |
| 0x10 | weights_addr | DDR address for weights |
| 0x1C | bias_addr | DDR address for biases |
| 0x28 | pixels_addr | DDR address for input pixels |
| 0x34 | output_addr | DDR address for output |
| 0x40 | cfg_ci_groups | Input channel groups (C_in / 8) |
| 0x4C | cfg_co_groups | Output channel groups (C_out / 8) |
| 0x58 | cfg_in_channels | Total input channels |
| 0x64 | cfg_img_width | Padded image width |
| 0x70 | cfg_img_height | Padded image height |
| 0x7C | cfg_use_maxpool | Enable 2×2 max pooling |
| 0x88 | cfg_stride_2 | MaxPool stride (0=stride-1, 1=stride-2) |
| 0x94 | cfg_quant_m | Quantization multiplier M |
| 0xA0 | cfg_quant_n | Quantization shift N |
| 0xAC | cfg_use_relu | Enable LeakyReLU |
| 0xB8 | cfg_kernel_1x1 | 1×1 convolution mode |
| 0xC4 | num_output_groups | Total OGs to process |

---

## Weight Storage (URAM)

- **Structure:** 8 banks × 8 URAMs per bank = 64 URAMs
- **Entry width:** 72 bits (9 spatial weights × 8-bit)
- **Depth:** 4096 addresses per URAM
- **Read latency:** 3 cycles

Weight packing order (for each 72-bit word):
```
bits [7:0]   = spatial[0][0], bits [15:8]  = spatial[0][1], bits [23:16] = spatial[0][2]
bits [31:24] = spatial[1][0], bits [39:32] = spatial[1][1], bits [47:40] = spatial[1][2]
bits [55:48] = spatial[2][0], bits [63:56] = spatial[2][1], bits [71:64] = spatial[2][2]
```

---

## Bias Storage (BRAM)

- **Structure:** 128-bit × 256 deep, dual-port
- **Entry:** 4 × INT32 biases packed per 128-bit word
- **Read:** Two rows read simultaneously via dual-port (8 biases total)

---

## Processing Element (conv_pe)

Each PE computes one output channel:

1. **Multiply stage:** 72 parallel INT8×INT8 multiplications (9 spatial × 8 channels)
2. **Reduce stage:** Adder tree reduces 72 products to single sum
3. **Accumulate stage:** 32-bit accumulator sums across all input channel groups

DSP usage: 72 DSP48E2 per PE × 8 PEs = 576 DSPs for convolution

---

## Quantization Pipeline

```
INT32 accumulator
    → Add INT32 bias
    → LeakyReLU (if negative: right-shift by 3, approximating ×0.125)
    → Multiply by M (16-bit)
    → Right-shift by N (typically 8)
    → Clip to [-128, 127]
    → INT8 output
```

Calibrated parameters from `sim/hardware-ai/quantized_params.npz` are required.

---

## 1×1 Convolution Mode

Reuses 3×3 pipeline:
- Weights packed into spatial position 4 (center) only
- Pixel mux routes only center pixel; others zeroed
- Set `cfg_kernel_1x1 = 1`

---

## Pipeline Latencies

| Stage | Latency |
|-------|---------|
| Weight URAM read | 3 cycles |
| Pixel delay (3×3 mode) | 3 cycles |
| Pixel delay (1×1 mode) | 4 cycles |
| conv_pe internal | 3 cycles |
| Quantizer | 1 cycle |
| **Total drain depth** | **7 cycles** |

---

## Layer Execution (FPGA vs CPU)

| Operation | Executor |
|-----------|----------|
| 3×3 / 1×1 Convolution | FPGA |
| Batch normalization | FPGA (folded into weights) |
| LeakyReLU | FPGA |
| 2×2 MaxPool | FPGA (fused with conv) |
| INT8 requantization | FPGA |
| 2× Upsampling | CPU |
| Route/Concat | CPU (DMA addressing) |
| Layer sequencing | CPU |
| Post-processing (NMS) | CPU |

---

## Key Files

| File | Purpose |
|------|---------|
| `hdl/conv_top.sv` | Convolution datapath top |
| `hdl/axi_conv_wrapper.sv` | AXI wrapper + multi-OG FSM |
| `hdl/conv_pe.sv` | Processing element |
| `hdl/weight_manager.sv` | URAM weight storage |
| `hdl/bias_store.sv` | BRAM bias storage |
| `hdl/quantizer.sv` | Requantization + ReLU |
| `hdl/maxpool.sv` | 2×2 max pooling |
| `hdl/kernel_window.sv` | 3×3 window generator |
| `sim/hardware-ai/hardware_sim.py` | Golden reference model |
| `sim/hardware-ai/quantized_params.npz` | Calibrated INT8 parameters |
