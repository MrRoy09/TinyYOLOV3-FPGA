# TINY-YOLOV3 FPGA Accelerator Architecture (NHWC / Channel-Last)

## Target Platform: Kria KV260

### Available Resources
| Resource | Available |
|----------|-----------|
| DSP48E2 | 1,248 |
| LUTs | 117,120 |
| FFs | 234,240 |
| BRAM36K | 144 (5 MB) |
| URAM | 64 (2.25 MB) |
| DDR4 Bandwidth | ~10 GB/s |

---

## Parallelism Strategy: $P_{in}=8, P_{out}=8$

To balance the **128-bit AXI Bus** of the KV260 and the available **DSP** resources, the architecture uses a 2D parallelism scheme:

- **Input Parallelism ($P_{in} = 8$):** Processes 8 input channels in parallel every cycle.
- **Output Parallelism ($P_{out} = 8$):** Computes 8 different output filters in parallel.
- **Total Throughput:** 64 MACs/cycle.
- **Arithmetic Intensity:** Processes one 64-bit "Super-Pixel" (8 channels) per cycle.

---

## High-Level Architecture (NHWC)

```
                                    DDR4 (NHWC Format)
                                           │
                ┌──────────────────────────┼──────────────────────────┐
                │                          │                          │
                ▼                          ▼                          ▼
        ┌──────────────┐          ┌──────────────┐          ┌──────────────┐
        │ Weight DMA   │          │ Input DMA    │          │ Output DMA   │
        │ (AXI-MM)     │          │ (AXI-Stream) │          │ (AXI-Stream) │
        └──────┬───────┘          └──────┬───────┘          └──────▲───────┘
               │                         │                         │
               │                         ▼                         │
               │               ┌─────────────────┐                 │
               │               │  Line Buffer    │                 │
               │               │ (2 Rows, 64-bit)│                 │
               │               └────────┬────────┘                 │
               │                        │ 3 streams (64-bit)       │
               │                        ▼                          │
               │               ┌─────────────────┐                 │
               │               │  Window Gen     │                 │
               │               │ (w/ Delay Lines)│                 │
               │               └────────┬────────┘                 │
               │                        │ 9 × 64-bit vectors       │
               │                        ▼ (Broadcast)              │
               │  ┌─────────────────────────────────────────────┐  │
               │  │           8 FILTER CLUSTERS                 │  │
               │  │                                             │  │
               └──┼──┐  ┌──────┐ ┌──────┐       ┌──────┐       │  │
                  │  │  │URAM 0│ │URAM 1│  ...  │URAM 7│       │  │
                  │  │  └──┬───┘ └──┬───┘       └──┬───┘       │  │
                  │  │     │72b    │72b          │72b         │  │
                  │  │     ▼       ▼             ▼            │  │
                  │  │  ┌──────┐ ┌──────┐       ┌──────┐       │  │
                  │  │  │9 Dot │ │9 Dot │  ...  │9 Dot │       │  │
                  │  │  │Prods │ │Prods │       │Prods │       │  │
                  │  │  └──┬───┘ └──┬───┘       └──┬───┘       │  │
                  │  │     ▼       ▼             ▼            │  │
                  │  │  ┌──────┐ ┌──────┐       ┌──────┐       │  │
                  │  │  │ ACC  │ │ ACC  │  ...  │ ACC  │       │  │
                  │  │  └──┬───┘ └──┬───┘       └──┬───┘       │  │
                  │  │     ▼       ▼             ▼            │  │
                  │  │  ┌──────┐ ┌──────┐       ┌──────┐       │  │
                  │  │  │QUANT │ │QUANT │  ...  │QUANT │       │  │
                  │  └─────┼───────┼─────────────┼────────────┘  │
                  │        └───────┴──────┬──────┘               │
                  │                       │ 8 × INT8 (64-bit)    │
                  │                       ▼                      │
                  │              ┌─────────────────┐             │
                  │              │   MaxPool Unit  │             │
                  │              └────────┬────────┘             │
                  └───────────────────────┴──────────────────────┘
                                          │
                                          ▼
                                    To Output DMA
```

---

## Component Details

### 1. Input DMA + NHWC Line Buffer
Processes data as a stream of **64-bit vectors**.
- **Line Buffer:** Stores $W \times (C_{in}/8)$ vectors.
- **BRAM Usage:** Max layer is $416 \times 3 \text{ channels} = 1.2 \text{ KB}$. Deep layers like $13 \times 1024$ use $13.3 \text{ KB}$. Both fit comfortably in BRAM36K.
- **Zero-Padding (TODO):** The kernel window generator has no internal padding logic — it produces "valid"-only outputs and wraps left-edge data circularly. The **Input DMA must insert zero-padding** before streaming each layer:
  - **Top/Bottom:** One extra row of zero vectors ($W \times C_{in}/8$ zeros) at the top and bottom.
  - **Left/Right:** $C_{in}/8$ zero vectors at the start and end of every row.
  - This expands the effective input from $H \times W$ to $(H+2) \times (W+2)$, so the kernel window produces the full $H \times W$ spatial output ("same" padding).
  - `conv_layer.cfg_img_width` / `cfg_img_height` should be set to the **padded** dimensions ($W+2$, $H+2$).

### 2. Window Generator (Spatial-Temporal)
Unlike NCHW, the horizontal neighbor is not the previous cycle's data.
- **Horizontal Delay Lines:** To get the "Left" pixel, we delay the stream by $D = C_{in}/8$ cycles.
- **Implementation:** Uses **SRL32** or **Distributed RAM** for variable-depth delays.
- **Output:** A 3x3 grid of 64-bit vectors ($9 \times 64 = 576$ bits total).

### 3. Weight Storage (Distributed URAM)
- **Bandwidth Requirement:** Each filter cluster needs $9 \times 8 = 72$ bytes of weights every cycle.
- **Solution:** 64 URAMs are partitioned. Each of the 8 filter clusters is served by **8 private URAMs**.
- **Width:** Each URAM provides 72 bits (9 spatial weights for 1 input channel).
- **Access:** 8 URAMs read in parallel to provide $8 \text{ channels} \times 9 \text{ spatial weights}$ per filter.

### 4. Filter Cluster (×8)
Each cluster computes 1 output channel.
- **Dot-Product Engine:** 9 spatial positions. Each position performs a dot product of an 8-channel input vector and 8-channel weight vector.
- **Accumulator:** A single 32-bit register per filter. It accumulates the 9 dot-products for $D$ cycles until all $C_{in}$ channels are processed.
- **DSP Usage:** $9 \text{ spatial} \times 8 \text{ channels} = 72 \text{ DSPs}$ per filter cluster.
- **Total DSPs:** $8 \text{ clusters} \times 72 = 576$ DSPs.

### 5. MaxPool Unit (NHWC)
- **Fused Operation:** Performs 2x2 max pooling on the NHWC stream.
- **Row Buffer:** Stores the maximum values for the entire row of channels ($W_{out} \times 8$ channels being currently processed).

---

## Timing Analysis ($P_{in}=8, P_{out}=8$)

**Formula:** `Cycles = H_conv × W_conv × (C_in / 8) × (C_out / 8)`

| Layer | H×W (Conv) | C_in | C_out | Cycles | @200MHz |
|-------|------------|------|-------|--------|---------|
| 0+pool| 416×416 | 3*    | 16 | 64,896 | 0.32 ms |
| 2+pool| 208×208 | 16 | 32 | 86,528 | 0.43 ms |
| 4+pool| 104×104 | 32 | 64 | 86,528 | 0.43 ms |
| 6+pool| 52×52 | 64 | 128 | 86,528 | 0.43 ms |
| 8+pool| 26×26 | 128 | 256 | 86,528 | 0.43 ms |
| 10+pool| 13×13 | 256 | 512 | 86,528 | 0.43 ms |
| 12    | 13×13 | 512 | 1024 | 346,112| 1.73 ms |
| **Total** | | | | **~830K** | **~4.2 ms** |

*\*Note: Layer 0 has Cin=3, but hardware processes in chunks of 8 (padded).*

**Performance Estimate:**
- **Backbone Inference:** ~4.2 ms
- **FPS:** **>200 FPS** (excluding DMA overhead and weight loading).
- **Bandwidth:** 200 MHz * 8 bytes = **1.6 GB/s** (Well within KV260's 10 GB/s limit).

---

## Summary of NHWC Benefits
1. **No Partial Sum Memory:** Accumulation is register-based.
2. **Sequential DDR Bursts:** Maximize memory throughput.
3. **Low Latency:** Output pixels begin appearing as soon as the first input pixel's channels are streamed.
4. **Scalability:** Easy to scale by increasing $P_{in}$ (Bus usage) or $P_{out}$ (DSP usage).