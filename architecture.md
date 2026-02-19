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

---

## CPU–Hardware Interface: Pre-Layer Setup

The design philosophy is **dumb hardware, smart CPU**. All bookkeeping (loop counts, completion detection, layer configuration) lives in the CPU driver. The hardware modules are simple storage devices with auto-incrementing write ports and externally-addressed read ports.

### Bias Loading (`bias_store`)

- **Storage:** True dual-port BRAM, 128 bits wide × 256 deep.
- **Write:** CPU streams 128-bit words via DMA. Each word packs 4 × INT32 biases. Hardware auto-increments the write address.
- **Read:** Conv controller supplies an output group index. Hardware reads two consecutive rows (using `{group, 1'b0}` and `{group, 1'b1}` addressing) in a single cycle via dual-port, returning 8 biases with 1-cycle latency.

**CPU stream order for biases:**
```
for co = 0 .. C_out-1, step 4:
    stream 128-bit word = {bias[co+3], bias[co+2], bias[co+1], bias[co+0]}
```
Total beats: `C_out / 4`.

### Weight Loading (`weight_manager`)

- **Storage:** 8 banks × 8 URAMs per bank. Each URAM entry is 72 bits (9 spatial positions × 8-bit weight).
- **Write:** CPU streams 72-bit words (packed in 128-bit bus beats, upper bits zeroed). Hardware uses a single auto-incrementing counter with bit-slice routing:
  - `cnt[2:0]` → `uram_sel` (which input channel within $P_{in}$ group)
  - `cnt[5:3]` → `bank_sel` (which output filter within $P_{out}$ group)
  - `cnt[ADDR_WIDTH+5:6]` → `waddr` (BRAM address)
- **Read:** Conv controller supplies `rd_en` + `rd_addr`. All 8 banks read the same address simultaneously. 3-cycle read latency (matches `conv_pe` pipeline).

**CPU stream order for weights:**
```
for addr = 0 .. (co_groups * ci_groups - 1):       // BRAM address
    for bank = 0 .. 7:                              // output filter within Pout group
        for uram = 0 .. 7:                          // input channel within Pin group
            stream 72-bit word = 9 spatial weights for:
                filter  = (addr / ci_groups) * 8 + bank
                in_chan = (addr % ci_groups) * 8 + uram
```
Total beats: `co_groups × ci_groups × 64`. Bus efficiency: 72/128 = 56%.

**Mapping to physical weight tensor:** Given a weight tensor `W[co][ci][ky][kx]` (INT8), each 72-bit word is packed as:
```
word = {W[f][c][2][2], W[f][c][2][1], W[f][c][2][0],
        W[f][c][1][2], W[f][c][1][1], W[f][c][1][0],
        W[f][c][0][2], W[f][c][0][1], W[f][c][0][0]}   // 9 bytes, spatial raster order
```

---

## Conv Controller (`conv_controller`) and CPU Driver Flow

### Design Philosophy

The CPU owns **all outer loops and layer sequencing**. The hardware conv_controller handles **one output group at a time**: it reads biases, processes all pixels × all input channel groups for that output group, then signals completion. The CPU repeats for each output group.

### CPU Register Interface

The CPU configures these registers before pulsing `go`:

| Register | Width | Description |
|----------|-------|-------------|
| `cfg_ci_groups` | 10 bits | $C_{in} / 8$ for this layer |
| `cfg_output_group` | 7 bits | Which output group (0 .. $C_{out}/8 - 1$) |
| `cfg_wt_base_addr` | 12 bits | Precomputed: `output_group × ci_groups` (avoids multiplier in hardware) |
| `go` | 1 bit | Pulse to start processing this output group |

Status signals read by CPU:

| Signal | Description |
|--------|-------------|
| `busy` | High while controller is processing |
| `done` | Pulse when output group is complete (pipeline fully drained) |

### Per-Layer CPU Driver Pseudocode

```
def run_layer(layer):
    ci_groups = layer.C_in // 8
    co_groups = layer.C_out // 8
    max_og_per_load = URAM_DEPTH // ci_groups   # 4096 / ci_groups

    # Phase 1: load biases (once per layer, all output groups fit)
    pulse bias_wr_addr_rst
    stream biases to bias_store        # C_out/4 × 128-bit beats

    # Phase 2: process output groups in chunks that fit in URAM
    for chunk_start in range(0, co_groups, max_og_per_load):
        chunk_end = min(chunk_start + max_og_per_load, co_groups)

        # reload weights for this chunk of output groups
        pulse wt_wr_addr_rst
        stream weights for og [chunk_start .. chunk_end-1]
        # beats = (chunk_end - chunk_start) × ci_groups × 64

        # process each output group in this chunk
        for og in range(chunk_start, chunk_end):
            write cfg_ci_groups    = ci_groups
            write cfg_output_group = og
            write cfg_wt_base_addr = (og - chunk_start) * ci_groups

            start_pixel_dma(layer.input_addr, layer.H, layer.W, layer.C_in)
            pulse go
            poll until done == 1
```

### Weight Capacity and Multi-Pass Loading

The weight URAM has a fixed depth of 4096 addresses. Each address holds weights for one (output_group, input_ch_group) pair. The maximum number of output groups that fit in one load:

```
max_og_per_load = 4096 / ci_groups
```

| Layer | ci_groups | co_groups | max_og_per_load | Loads needed |
|-------|-----------|-----------|-----------------|-------------|
| 0 | 1 | 2 | 4096 | 1 |
| 2 | 2 | 4 | 2048 | 1 |
| 4 | 4 | 8 | 1024 | 1 |
| 6 | 8 | 16 | 512 | 1 |
| 8 | 16 | 32 | 256 | 1 |
| 10 | 32 | 64 | 128 | 1 |
| 12 | 64 | 128 | 64 | **2** |

Only layer 12 (Cin=512, Cout=1024) exceeds URAM capacity, requiring 2 weight loads. The CPU splits it into two chunks of 64 output groups each, reloading weights between them via `wt_wr_addr_rst`.

Note: `cfg_wt_base_addr` is relative to the current chunk, not the absolute output group index: `(og - chunk_start) * ci_groups`. The bias_store still uses the absolute `og` since all biases fit in one load (max 128 groups × 2 rows = 256 entries).

### Controller FSM States

```
IDLE ──go──> LOAD_BIAS ──1 cycle──> WAIT_BIAS ──bias_valid──> CONV ──last_pixel──> DRAIN ──pipe flush──> IDLE
                                                                 │                              │
                                                                 │ pixel_valid: drive weights    │
                                                                 │ + conv_3x3 each cycle        done pulse
```

1. **IDLE**: Wait for CPU `go` pulse.
2. **LOAD_BIAS**: Issue `bias_rd_en` with `cfg_output_group` to `bias_store`.
3. **WAIT_BIAS**: Wait 1 cycle for `bias_valid`. Biases latch on `bias_out[0:7]` and stay stable until next read.
4. **CONV**: Main compute state. On each `pixel_valid` from kernel_window:
   - Assert `wt_rd_en` with address `cfg_wt_base_addr + ci_cnt`
   - Generate `valid_raw` and `last_ch_raw` (delayed by `WT_LATENCY` cycles before reaching `conv_3x3`)
   - Increment `ci_cnt` (0 .. ci_groups-1), assert `last_ch_raw` on the last group
   - When `last_pixel` coincides with the final channel group → transition to DRAIN
5. **DRAIN**: Wait `PIPE_DEPTH = WT_LATENCY(3) + CONV_PE_PIPE(3) + 1 = 7` cycles for the full pipeline to flush. Pulse `done`.

### Pixel Re-Streaming

For each output group, the **entire input image** is re-streamed from DDR via the input DMA. The line buffer / kernel_window cannot store the full frame — only 2-3 rows. Each output group needs the same pixels multiplied by different weights (filters).

**Bandwidth cost:** Each layer re-reads the input `co_groups` times.
- Worst case (layer 12): 13×13×512 bytes × 128 groups = ~11 MB, at 1.6 GB/s ≈ 7 ms.
- Total re-stream overhead across all layers is well within DDR4 bandwidth.

### `last_pixel` Signal Contract

The input DMA (or kernel_window) must assert `last_pixel` alongside `pixel_valid` on the **very last beat** of the frame — the last channel group ($ci\_cnt = ci\_groups - 1$) of the last spatial position. This is the DMA's responsibility since it knows the total transfer length.

### Pipeline Synchronization

Weights and pixels must arrive at `conv_pe` inputs on the **same cycle**, because the multiply stage (`products <= pixel * weight`) samples both combinationally. The full latency chain:

```
Cycle 0: controller asserts wt_rd_en, valid_raw, last_ch_raw
         kernel_window outputs pixels
           │
           ├── weight_manager: 3-cycle URAM read pipeline
           │     Cycle 1: rdata_pipe[0] <= memory[raddr]
           │     Cycle 2: rdata_pipe[1] <= rdata_pipe[0]
           │     Cycle 3: rdata_pipe[2] <= rdata_pipe[1]  → weights valid at conv_pe
           │
           ├── conv_controller: 3-cycle delay shift registers
           │     valid_dly[0] → valid_dly[1] → valid_dly[2] = conv_valid_in
           │     last_ch_dly[0] → last_ch_dly[1] → last_ch_dly[2] = conv_last_channel
           │
           └── conv_top: 3-cycle pixel delay (shift register on pixels[0:2][0:2])
                 pixel_d[0] → pixel_d[1] → pixel_d[2]  → pixels valid at conv_pe

Cycle 3: weights, pixels, conv_valid_in, conv_last_channel all arrive at conv_pe simultaneously
           │
           └── conv_pe internal pipeline (3 stages):
                 Cycle 4: products <= pixel * weight
                 Cycle 5: spatial_sum <= reduce(products)
                 Cycle 6: cycle_sum <= reduce(spatial_sum)
                 Cycle 7: acc += cycle_sum (gated by valid_pipe[2] / lastc_pipe[2])
```

**DRAIN depth** = `WT_LATENCY(3) + CONV_PE_PIPE(3) + accumulator(1)` = **7 cycles**.

**conv_top pixel delay requirement:** The `pixels[0:2][0:2]` bus from `kernel_window` output must be delayed by `WT_LATENCY` (3) cycles before reaching `conv_3x3` inputs. This is a simple shift register in `conv_top` wiring — 9 × 64-bit × 3 stages. This ensures pixels and weights arrive at the multiply stage on the same clock edge.

---

## 1x1 Convolution Mode

The architecture supports 1x1 convolution by reusing the existing 3x3 `conv_pe` infrastructure. This eliminates the need for a separate 1x1 datapath, providing identical timing and simpler debugging.

### Concept

A 1x1 convolution is mathematically equivalent to a 3x3 convolution where:
1. Only the **center spatial position** (position 4) has non-zero weights
2. Only the **center pixel** of the 3×3 window contributes to the output

By packing 1x1 weights into the center position of the 576-bit weight format and feeding only the center pixel to `conv_3x3`, the same pipeline computes 1x1 convolutions with zero additional RTL.

### Weight Packing for 1x1

The `conv_pe` extracts weights using:
```systemverilog
weight_byte = weights[(i*64 + j*8) +: 8];  // i = spatial position (0-8), j = input channel (0-7)
```

| Spatial Position | 3×3 Grid Location | Bit Range |
|------------------|-------------------|-----------|
| 0 | [0][0] top-left | [63:0] |
| 1 | [0][1] top-center | [127:64] |
| 2 | [0][2] top-right | [191:128] |
| 3 | [1][0] mid-left | [255:192] |
| **4** | **[1][1] center** | **[319:256]** |
| 5 | [1][2] mid-right | [383:320] |
| 6 | [2][0] bot-left | [447:384] |
| 7 | [2][1] bot-center | [511:448] |
| 8 | [2][2] bot-right | [575:512] |

**For 1x1:** Pack the 8 input channel weights into bits [319:256] (spatial position 4). All other bits must be zero.

**URAM storage format (72 bits per URAM):**
- Each URAM stores 9 spatial positions × 8 bits
- bits [7:0] = spatial 0, bits [15:8] = spatial 1, ..., bits [39:32] = spatial 4, ..., bits [71:64] = spatial 8

**1x1 weight packing:**
```python
# For 1x1: pack weight into spatial position 4 of each URAM
for cig in range(ci_groups):
    for bank in range(8):  # output channel
        for uram in range(8):  # input channel
            ci = cig * 8 + uram
            w_val = int(weights[bank, ci]) & 0xFF
            word = w_val << 32  # bits [39:32] = spatial position 4
            write_to_uram(word)
```

### Pixel Routing for 1x1

In `conv_top`, a `pixel_mux` routes pixels based on `cfg_kernel_1x1`:

```systemverilog
always_comb begin
    if (cfg_kernel_1x1) begin
        // 1x1 mode: only center pixel, all others zero
        for (int r = 0; r < 3; r++)
            for (int c = 0; c < 3; c++)
                pixel_mux[r][c] = (r == 1 && c == 1) ? pixel_1x1_d3 : 64'b0;
    end else begin
        // 3x3 mode: use full kernel window
        pixel_mux = pixel_3x3_d2;
    end
end
```

This ensures that only `pixels[1][1]` (center) is non-zero, which multiplies with the only non-zero weights at position 4.

### Pixel Delay Difference: 4 Cycles for 1x1

**Critical timing difference:** The 1x1 pixel delay must be **4 cycles**, not 3.

The controller's valid delay has two components:
1. `valid_raw` latency: 1 cycle (NBA in controller's always_ff)
2. `valid_dly` shift register: 3 cycles (WT_LATENCY)
3. **Total: 4 cycles**

For 3x3 mode, the kernel_window's `kw_dout_valid` already accounts for its internal latency relative to `kw_window` data, so a 3-cycle pixel delay works.

For 1x1 mode, `pixel_in_valid` is used directly (no kernel_window), so the pixel delay must match the full 4-cycle valid delay:

```systemverilog
// 1x1 pixel delay: 4 stages (matches 1 + WT_LATENCY = 4 cycle valid delay)
logic [63:0] pixel_1x1_d0, pixel_1x1_d1, pixel_1x1_d2, pixel_1x1_d3;

always_ff @(posedge clk) begin
    pixel_1x1_d0 <= pixel_in;
    pixel_1x1_d1 <= pixel_1x1_d0;
    pixel_1x1_d2 <= pixel_1x1_d1;
    pixel_1x1_d3 <= pixel_1x1_d2;
end
```

### Configuration Differences

| Parameter | 3x3 Mode | 1x1 Mode |
|-----------|----------|----------|
| `cfg_kernel_1x1` | 0 | 1 |
| `pixel_valid_mux` source | `kw_dout_valid` | `pixel_in_valid` |
| Pixel delay stages | 3 (`pixel_3x3_d2`) | 4 (`pixel_1x1_d3`) |
| Weight spatial positions used | All 9 | Only position 4 |
| Kernel window | Active (priming delay) | Bypassed |
| MaxPool `img_width` | `cfg_img_width - 2` | `cfg_img_width` |

### Benefits of Unified 1x1/3x3 Pipeline

1. **Single timing path** — No separate 1x1 pipeline to debug
2. **Identical latency** — Both modes use the same `conv_3x3` → quantizer → maxpool chain
3. **Reduced RTL** — No `conv_1x1` or `conv_1x1_pe` modules needed
4. **Proven correctness** — Reuses the already-verified 3x3 pipeline

---

## Upsampling (CPU-Side Operation)

YOLOv3-tiny uses 2× nearest-neighbor upsampling to increase spatial resolution (13×13 → 26×26) before the second detection head.

### Why CPU, Not FPGA

| Factor | FPGA | CPU |
|--------|------|-----|
| Compute complexity | Zero (just pixel duplication) | Zero |
| FPGA resource cost | State machine, address gen, buffers | None |
| Implementation time | Hours of RTL | 10 lines of C |
| Performance | ~169 cycles | <1ms on ARM Cortex-A53 |

**Upsampling is memory-bound, not compute-bound.** The FPGA's parallel MACs provide zero benefit for simple pixel copying.

### Implementation

```c
// Nearest-neighbor 2x upsample: H×W×C → 2H×2W×C
void upsample_2x(int8_t *src, int8_t *dst, int H, int W, int C) {
    for (int h = 0; h < H; h++) {
        for (int w = 0; w < W; w++) {
            for (int c = 0; c < C; c++) {
                int8_t val = src[(h*W + w)*C + c];
                dst[((2*h  )*(2*W) + (2*w  ))*C + c] = val;
                dst[((2*h  )*(2*W) + (2*w+1))*C + c] = val;
                dst[((2*h+1)*(2*W) + (2*w  ))*C + c] = val;
                dst[((2*h+1)*(2*W) + (2*w+1))*C + c] = val;
            }
        }
    }
}
```

---

## Concatenation (Zero-Cost DMA Operation)

YOLOv3-tiny concatenates upsampled deep features (26×26×256) with shallow features (26×26×128) along the channel dimension, producing a 26×26×384 tensor.

### Key Insight: Avoid Physical Concatenation

**Concatenation requires zero computation and zero data movement** with smart DMA programming. Instead of copying both tensors into an interleaved buffer, stream them sequentially to the conv hardware.

### Sequential Streaming Approach

The conv accumulator doesn't care that channels came from different memory regions. For each spatial position, stream channels from both sources:

```
Pixel (h,w): A[0:7], A[8:15], ..., A[248:255], B[0:7], B[8:15], ..., B[120:127]
             └──── 32 ci_groups from A ────┘  └──── 16 ci_groups from B ────┘
```

The conv hardware sees 48 continuous ci_groups, unaware they originate from two separate buffers.

### CPU Driver Implementation

```c
void run_conv_after_concat(void *feature_a, int ca,    // 26×26×256
                           void *feature_b, int cb) {  // 26×26×128

    int total_ci_groups = (ca + cb) / 8;  // 48 groups

    for (int og = 0; og < co_groups; og++) {
        load_weights(og, total_ci_groups);  // Weights for all 384 input channels
        configure_conv(total_ci_groups, og);

        // DMA streams A's channels, then B's channels per pixel
        start_dma_concat_stream(feature_a, ca, feature_b, cb, H, W);

        pulse_go();
        wait_done();
    }
}
```

### DMA Scatter-Gather Pattern

For NHWC layout, the DMA must interleave reads from both buffers:

```
For each row h:
    For each column w:
        Transfer A[h,w,0:ca-1]    // ca/8 beats from buffer A
        Transfer B[h,w,0:cb-1]    // cb/8 beats from buffer B
```

This can be achieved with:
1. **Scatter-gather DMA** with a descriptor list alternating between A and B
2. **CPU-managed streaming** that switches source buffers
3. **Two DMA channels** with coordinated handoff

### Comparison

| Approach | Memory Bandwidth | FPGA Resources | Latency |
|----------|------------------|----------------|---------|
| Physical copy (CPU) | 2× (read + write both) | None | ~2ms |
| FPGA concat unit | 2× | State machine, buffers | ~1ms |
| **Sequential DMA** | **1× (read only)** | **None** | **Zero overhead** |

**Recommendation:** Implement concatenation as a DMA addressing pattern, not a data transformation.

---

## YOLOv3-tiny Layer Execution Summary

| Layer | Operation | Executor | Notes |
|-------|-----------|----------|-------|
| 0-5 | Conv + MaxPool | FPGA | Standard 3×3 conv |
| 6 | Conv | FPGA | No pooling |
| 7 | Conv 1×1 | FPGA | Uses center-position weight packing |
| 8 | Conv | FPGA | Detection head 1 output |
| 9 | Route | CPU | Just pointer selection |
| 10 | Conv 1×1 | FPGA | |
| 11 | Upsample 2× | CPU | Nearest-neighbor pixel duplication |
| 12 | Route (concat) | DMA | Sequential streaming from 2 buffers |
| 13 | Conv | FPGA | |
| 14 | Conv 1×1 | FPGA | Detection head 2 output |

**FPGA handles:** Convolution (3×3 and 1×1), quantization, maxpool
**CPU handles:** Upsampling, route/concat addressing, layer sequencing, DMA setup

---

## AXI Integration Architecture

The design uses the Xilinx RTL Kernel Wizard to generate AXI infrastructure, providing a standard interface for Vitis integration on the Kria KV260.

### File Structure

```
hdl/
├── TinyYOLOV3_HW.v                    # Top-level AXI kernel
├── TinyYOLOV3_HW_control_s_axi.v      # AXI-Lite register interface (generated)
├── TinyYOLOV3_HW_conv_wrapper.sv      # Wire↔logic adapter wrapper
├── axi_conv_integration.sv            # AXI-Stream ↔ conv_top bridge + FSM
│
├── conv_top.sv                        # Convolution datapath top
├── conv_controller.sv                 # Convolution FSM
├── conv_3x3.sv                        # 8 parallel conv PEs
├── conv_pe.sv                         # Single processing element
├── weight_manager.sv                  # URAM-based weight storage
├── bias_store.sv                      # BRAM-based bias storage
├── kernelWindow.sv                    # 3×3 sliding window generator
├── quantizer.sv                       # INT32→INT8 scaling + ReLU
├── maxPool.sv                         # 2×2 max pooling
├── lineBuffer.sv                      # Line buffer for kernel window
└── delayLine.sv                       # Configurable delay line
```

### Module Hierarchy

```
TinyYOLOV3_HW                              # Top-level RTL kernel
├── TinyYOLOV3_HW_control_s_axi            # AXI-Lite slave (11 cfg registers + control)
└── TinyYOLOV3_HW_conv_wrapper             # Interface adapter
    └── axi_conv_integration               # AXI-Stream bridge + loading FSM
        └── conv_top                       # Convolution datapath
            ├── bias_store                 # 128-bit×256 BRAM, dual-port
            ├── weight_manager             # 8 banks × 8 URAMs
            ├── conv_controller            # IDLE→LOAD_BIAS→CONV→DRAIN FSM
            ├── kernelWindow               # 3×3 sliding window
            ├── conv_3x3                   # 8 parallel output channels
            │   └── conv_pe [×8]           # 72 MACs each
            ├── quantizer [×8]             # Per-channel quantization
            └── maxPool                    # Optional 2×2 pooling
```

### AXI Interfaces

| Interface | Type | Width | Direction | Purpose |
|-----------|------|-------|-----------|---------|
| `s_axi_control` | AXI4-Lite Slave | 32-bit | CPU→FPGA | Configuration registers |
| `s_axis_weights` | AXI4-Stream Slave | 128-bit | DMA→FPGA | Weight loading |
| `s_axis_bias` | AXI4-Stream Slave | 128-bit | DMA→FPGA | Bias loading |
| `s_axis_pixels` | AXI4-Stream Slave | 64-bit | DMA→FPGA | Input pixel stream |
| `m_axis_output` | AXI4-Stream Master | 64-bit | FPGA→DMA | Output pixel stream |

### Signal Flow Diagram

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           TinyYOLOV3_HW (Top)                               │
│                                                                             │
│   ┌─────────────────────────┐         ┌───────────────────────────────────┐ │
│   │  TinyYOLOV3_HW_control  │         │     TinyYOLOV3_HW_conv_wrapper    │ │
│   │      _s_axi             │         │                                   │ │
│   │                         │  cfg_*  │  ┌─────────────────────────────┐  │ │
│   │  AXI-Lite ◄────────────────────────►│     axi_conv_integration     │  │ │
│   │  Registers              │         │  │                             │  │ │
│   │                         │ap_start │  │  ┌────────────────────────┐ │  │ │
│   │  0x00: AP_CTRL ─────────┼─────────┼──┼─►│       conv_top         │ │  │ │
│   │  0x10: cfg_ci_groups    │         │  │  │                        │ │  │ │
│   │  0x18: cfg_output_group │ ap_done │  │  │  bias_store            │ │  │ │
│   │  0x20: cfg_wt_base_addr │◄────────┼──┼──│  weight_manager        │ │  │ │
│   │  0x28: cfg_in_channels  │         │  │  │  conv_3x3              │ │  │ │
│   │  0x30: cfg_img_width    │         │  │  │  quantizer             │ │  │ │
│   │  0x38: cfg_use_maxpool  │         │  │  │  maxPool               │ │  │ │
│   │  0x40: cfg_stride_2     │         │  │  └────────────────────────┘ │  │ │
│   │  0x48: cfg_quant_m      │         │  │             ▲               │  │ │
│   │  0x50: cfg_quant_n      │         │  │   wt_wr_*   │  bias_wr_*   │  │ │
│   │  0x58: cfg_use_relu     │         │  │      ▲      │      ▲       │  │ │
│   │  0x60: cfg_kernel_1x1   │         │  │      │      │      │       │  │ │
│   └─────────────────────────┘         │  │  ┌──┴──────┴──────┴────┐   │  │ │
│                                       │  │  │  Weight/Bias FSMs   │   │  │ │
│                                       │  │  │  (addr_rst, wr_en)  │   │  │ │
│   s_axis_weights ─────────────────────┼──┼──►                     │   │  │ │
│   (128-bit)        [71:0] used        │  │  │  Pixel passthrough  │   │  │ │
│                                       │  │  │  (when busy)        │   │  │ │
│   s_axis_bias ────────────────────────┼──┼──►                     │   │  │ │
│   (128-bit)                           │  │  │                     │   │  │ │
│                                       │  │  │  Output forwarding  │   │  │ │
│   s_axis_pixels ──────────────────────┼──┼──►  (data_out_valid)   │   │  │ │
│   (64-bit)                            │  │  └──────────┬──────────┘   │  │ │
│                                       │  │             │              │  │ │
│   m_axis_output ◄─────────────────────┼──┼─────────────┘              │  │ │
│   (64-bit)                            │  └─────────────────────────────┘  │ │
│                                       └───────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## AXI-Lite Register Map

The `TinyYOLOV3_HW_control_s_axi` module implements the standard Vitis `ap_ctrl_hs` protocol plus 11 configuration registers.

### Control Register (0x00)

| Bit | Name | Access | Description |
|-----|------|--------|-------------|
| 0 | `ap_start` | R/W | Start kernel execution (auto-clears on `ap_ready`) |
| 1 | `ap_done` | R/COR | Kernel completed (clear on read) |
| 2 | `ap_idle` | R | Kernel is idle |
| 3 | `ap_ready` | R/COR | Kernel ready for next input |
| 7 | `auto_restart` | R/W | Enable continuous mode |
| 9 | `interrupt` | R | Interrupt status |

### Configuration Registers

| Address | Name | Width | Description |
|---------|------|-------|-------------|
| 0x10 | `cfg_ci_groups` | 32 | Input channel groups ($C_{in}/8$) |
| 0x18 | `cfg_output_group` | 32 | Current output group index |
| 0x20 | `cfg_wt_base_addr` | 32 | Weight base address in URAM |
| 0x28 | `cfg_in_channels` | 32 | Total input channels |
| 0x30 | `cfg_img_width` | 32 | Image width (padded for 3×3) |
| 0x38 | `cfg_use_maxpool` | 32 | Enable 2×2 max pooling |
| 0x40 | `cfg_stride_2` | 32 | MaxPool stride=2 mode |
| 0x48 | `cfg_quant_m` | 32 | Quantization multiplier M |
| 0x50 | `cfg_quant_n` | 32 | Quantization shift N |
| 0x58 | `cfg_use_relu` | 32 | Enable ReLU activation |
| 0x60 | `cfg_kernel_1x1` | 32 | 1×1 convolution mode |

---

## CPU Execution Flow

The CPU controls all layer sequencing. The FPGA processes one output group at a time.

### Integration FSM States

The `axi_conv_integration` module manages the loading sequence:

```
ST_IDLE ──(wt_done && bias_done)──► ST_READY ──(ap_start)──► ST_GO ──► ST_RUNNING ──(conv_done)──► ST_DONE
   │                                                                        ▲                         │
   │                                                                        │                         │
   └── Accept weight/bias streams                                    Accept pixels            Signal ap_done
       (parallel FSMs)                                               Output results           (!ap_start)→IDLE
```

**Weight Loading FSM:**
```
WT_IDLE ──(tvalid)──► WT_FIRST ──► WT_LOAD ──(tlast)──► WT_DONE
              │                                              │
              └── Reset wt_wr_addr                           └── Block tready
```

**Bias Loading FSM:** (identical structure)

### CPU Driver Sequence (Per Output Group)

```c
// ═══════════════════════════════════════════════════════════════════
// Phase 0: Pre-layer setup (once per layer)
// ═══════════════════════════════════════════════════════════════════

// Load biases for all output groups (fits in single DMA transfer)
dma_transfer(BIAS_CHANNEL, bias_buffer, bias_size);
wait_dma_complete(BIAS_CHANNEL);

// ═══════════════════════════════════════════════════════════════════
// Phase 1: Per-chunk weight loading
// ═══════════════════════════════════════════════════════════════════

// Load weights for this chunk of output groups
dma_transfer(WEIGHTS_CHANNEL, weight_buffer, weight_size);
wait_dma_complete(WEIGHTS_CHANNEL);

// ═══════════════════════════════════════════════════════════════════
// Phase 2: Per-output-group processing
// ═══════════════════════════════════════════════════════════════════

for (int og = chunk_start; og < chunk_end; og++) {

    // Step 1: Configure registers
    write_reg(CFG_CI_GROUPS,    ci_groups);
    write_reg(CFG_OUTPUT_GROUP, og);
    write_reg(CFG_WT_BASE_ADDR, (og - chunk_start) * ci_groups);
    write_reg(CFG_IN_CHANNELS,  in_channels);
    write_reg(CFG_IMG_WIDTH,    img_width);
    write_reg(CFG_USE_MAXPOOL,  use_maxpool);
    write_reg(CFG_STRIDE_2,     stride_2);
    write_reg(CFG_QUANT_M,      quant_m);
    write_reg(CFG_QUANT_N,      quant_n);
    write_reg(CFG_USE_RELU,     use_relu);
    write_reg(CFG_KERNEL_1X1,   kernel_1x1);

    // Step 2: Start output DMA (prepare to receive)
    dma_start_receive(OUTPUT_CHANNEL, output_buffer + og * output_size, output_size);

    // Step 3: Trigger kernel
    write_reg(AP_CTRL, 0x01);  // Set ap_start

    // Step 4: Start pixel DMA (stream input)
    dma_start_send(PIXELS_CHANNEL, input_buffer, input_size);

    // Step 5: Wait for completion
    while (!(read_reg(AP_CTRL) & 0x02));  // Poll ap_done
    // Or use interrupt-driven wait

    // Step 6: Wait for output DMA
    wait_dma_complete(OUTPUT_CHANNEL);
}
```

### Timing Diagram

```
                    Weight DMA    Bias DMA     ap_start    Pixel DMA    Output DMA
                    ─────────     ────────     ────────    ─────────    ──────────
Time ──────────────────────────────────────────────────────────────────────────────►

Layer setup:        ╔════════╗    ╔═══════╗
                    ║ stream ║    ║stream ║
                    ╚════════╝    ╚═══════╝
                              wt_done  bias_done
                                   │      │
                                   ▼      ▼
Output group 0:                         ╔═╗   ╔═════════════╗   ╔═════════════╗
                                        ║1║   ║ stream in   ║   ║ stream out  ║
                                        ╚═╝   ╚═════════════╝   ╚═════════════╝
                                         │                               │
                                         │          conv_busy            │ ap_done
                                         └───────────────────────────────┘

Output group 1:                         ╔═╗   ╔═════════════╗   ╔═════════════╗
                                        ║1║   ║ stream in   ║   ║ stream out  ║
                                        ╚═╝   ╚═════════════╝   ╚═════════════╝
                                         ...
```

### AXI-Stream TREADY Behavior

| Stream | TREADY Condition | Notes |
|--------|------------------|-------|
| `s_axis_weights` | `wt_state != WT_DONE` | Accept until tlast received |
| `s_axis_bias` | `bias_state != BIAS_DONE` | Accept until tlast received |
| `s_axis_pixels` | `conv_busy` | Accept only during RUNNING state |
| `m_axis_output` | Downstream DMA ready | No internal backpressure handling |

### Important Notes

1. **Weight Format:** The 128-bit AXI-Stream carries 72-bit weight words in the lower bits. Upper 56 bits are ignored.

2. **Load Before Start:** Weights and biases must be fully loaded (DMAs complete) before asserting `ap_start`. The integration FSM enforces this by requiring both `wt_done` and `bias_done` to transition to `ST_READY`.

3. **No Output Backpressure:** The conv pipeline does not stall if `m_axis_output_tready` goes low. Ensure the output DMA is started before `ap_start` and can sustain the output rate.

4. **Pixel Streaming Rate:** Once `ap_start` is asserted and pixels begin streaming, they should flow continuously. The kernel window expects uninterrupted pixel delivery to maintain proper 3×3 window generation.

5. **TLAST Signals:**
   - `s_axis_weights_tlast`: Marks end of weight transfer
   - `s_axis_bias_tlast`: Marks end of bias transfer
   - `s_axis_pixels_tlast`: Marks last pixel of frame
   - `m_axis_output_tlast`: Asserted with final output (on `conv_done`)

---

## Complete System Block Diagram

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                              Kria KV260 Platform                                │
│                                                                                 │
│   ┌─────────────────────┐                      ┌──────────────────────────────┐ │
│   │   ARM Cortex-A53    │                      │     Programmable Logic       │ │
│   │                     │                      │                              │ │
│   │  ┌───────────────┐  │     AXI-Lite         │  ┌────────────────────────┐  │ │
│   │  │  CPU Driver   │──┼──────────────────────┼──│  TinyYOLOV3_HW kernel  │  │ │
│   │  │               │  │  (cfg_*, ap_ctrl)    │  │                        │  │ │
│   │  │  - Layer loop │  │                      │  │  ┌──────────────────┐  │  │ │
│   │  │  - DMA setup  │  │                      │  │  │ control_s_axi    │  │  │ │
│   │  │  - Config     │  │                      │  │  └──────────────────┘  │  │ │
│   │  └───────────────┘  │                      │  │                        │  │ │
│   │         │           │                      │  │  ┌──────────────────┐  │  │ │
│   │         ▼           │                      │  │  │ conv_wrapper     │  │  │ │
│   │  ┌───────────────┐  │                      │  │  │                  │  │  │ │
│   │  │   DMA Engine  │  │     AXI-Stream       │  │  │  axi_conv_integ  │  │  │ │
│   │  │               │──┼──────────────────────┼──│  │                  │  │  │ │
│   │  │  - Weights    │  │  s_axis_weights      │  │  │  ┌────────────┐  │  │  │ │
│   │  │  - Biases     │  │  s_axis_bias         │  │  │  │  conv_top  │  │  │  │ │
│   │  │  - Pixels     │  │  s_axis_pixels       │  │  │  │            │  │  │  │ │
│   │  │  - Output     │◄─┼──────────────────────┼──│  │  └────────────┘  │  │  │ │
│   │  │               │  │  m_axis_output       │  │  └──────────────────┘  │  │ │
│   │  └───────────────┘  │                      │  └────────────────────────┘  │ │
│   │         │           │                      │                              │ │
│   └─────────┼───────────┘                      └──────────────────────────────┘ │
│             │                                                                   │
│             ▼                                                                   │
│   ┌─────────────────────────────────────────────────────────────────────────┐   │
│   │                              DDR4 Memory                                │   │
│   │                                                                         │   │
│   │   ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐               │   │
│   │   │ Weights  │  │  Biases  │  │  Input   │  │  Output  │               │   │
│   │   │ (layer)  │  │  (all)   │  │  Buffer  │  │  Buffer  │               │   │
│   │   └──────────┘  └──────────┘  └──────────┘  └──────────┘               │   │
│   └─────────────────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────────────────┘
```

---

## Calibrated Quantization Parameters (CRITICAL)

**IMPORTANT:** The hardware MUST use calibrated quantization parameters from `sim/hardware-ai/quantized_params.npz` for accurate inference. Using uncalibrated/computed parameters will result in severe accuracy loss due to saturation.

### Why Calibrated Parameters?

The `hardware_sim.py` model achieves high INT8 accuracy by:
1. Running calibration on representative data (e.g., COCO subset)
2. Computing optimal per-layer output scales (`o_scale`) based on actual activation distributions
3. Pre-computing M values that properly scale outputs to INT8 range

**Key insight:** The output scale (`o_scale`) varies significantly across layers based on activation statistics:

| Layer | o_scale | M (hex) | Notes |
|-------|---------|---------|-------|
| 0 | 2.2175 | 0xC0 | Very low scale due to early activations |
| 1 | 3.8 | 0x6E | |
| 2 | 5.1 | 0x52 | |
| ... | ... | ... | |
| 6 | 20.1 | 0x15 | High scale for deeper layers |

### Calibrated vs Uncalibrated Comparison

| Parameter | Uncalibrated | Calibrated | Impact |
|-----------|--------------|------------|--------|
| Layer 0 M | 0x2AF9 (11001) | 0xC0 (192) | **57× smaller** |
| Output range | [-128, 127] (saturated) | [-12, 76] (precise) | Severe accuracy loss without calibration |
| Biases | Computed on-the-fly | Pre-scaled in NPZ | Exact match with hardware_sim.py |

### Required Files

- **`sim/hardware-ai/quantized_params.npz`** — Contains all calibrated parameters:
  - `l{N}_M` — Quantization multiplier for layer N
  - `l{N}_n` — Shift amount for layer N (typically 8)
  - `l{N}_o_scale` — Output scale for layer N
  - `l{N}_q_weights` — Pre-quantized INT8 weights
  - `l{N}_q_biases` — Pre-scaled INT32 biases
  - `input_scale` — Scale for input normalization

### How to Use Calibrated Parameters

1. **For stimulus generation:** Use `scripts/gen_stimulus_from_calibrated.py`
   ```bash
   python3 scripts/gen_stimulus_from_calibrated.py --layer 0
   ```

2. **For testbench configuration:** Set `cfg_quant_m` to calibrated value
   ```systemverilog
   // CORRECT: Use calibrated M from quantized_params.npz
   write_register(32'h048, 32'h000000C0);  // Layer 0: M = 0xC0

   // WRONG: Using computed M will cause saturation
   // write_register(32'h048, 32'h00002AF9);  // DO NOT USE
   ```

3. **For C++ host code:** Load parameters from NPZ or pre-generated JSON
   ```cpp
   // Per-layer M values (calibrated)
   const uint32_t quant_m[NUM_LAYERS] = {
       0xC0,   // Layer 0
       0x6E,   // Layer 1
       // ... (values from quantized_params.npz)
   };
   ```

### Regenerating Calibrated Parameters

If model weights or architecture change, re-run calibration:

```bash
cd sim/hardware-ai
python3 hardware_sim.py --calibrate --num_images 100
```

This updates `quantized_params.npz` with new optimal scales.

---

## Future Optimizations

### 1. BRAM-Based Pixel Cache

**Problem:** The current architecture is memory-bound due to pixel re-streaming. For each output group, the entire input feature map is re-read from DDR, wasting bandwidth.

**Current Resource Usage (Post-Implementation):**

| Resource | Used | Available | Free | Util% |
|----------|------|-----------|------|-------|
| BRAM Tiles | 41 | 144 | **103** | 28.5% |
| URAM | 64 | 64 | 0 | 100% |
| DSP48E2 | 756 | 1248 | 492 | 60.6% |
| LUT | 51,951 | 117,120 | 65,169 | 44.4% |

**BRAM Breakdown:**

| Component | BRAMs | Size | Purpose |
|-----------|-------|------|---------|
| Line buffers (×3) | ~21 | 96 KB | kernel_window (×2) + maxpool (×1) |
| bias_store | ~4 | 16 KB | 256×128-bit |
| AXI infrastructure | ~16 | 72 KB | Read/write master FIFOs, interconnect |
| **Total Used** | 41 | 185 KB | |
| **Free** | 103 | **463 KB** | Available for pixel cache |

**Solution:** Add a BRAM-based pixel cache that stores the input feature map once, then replays it for each output group without DDR re-reads.

**Layer Cacheability:**

| Layer | Input Size | Fits in 463KB? | Output Groups | Cache Benefit |
|-------|------------|----------------|---------------|---------------|
| 0 | 418×418×8 = 1.4 MB | No | 2 | — |
| 1 | 210×210×16 = 706 KB | No | 4 | — |
| 2 | 106×106×32 = 360 KB | **Yes** | 8 | **8× fewer DDR reads** |
| 3 | 54×54×64 = 187 KB | **Yes** | 16 | **16× fewer DDR reads** |
| 4 | 28×28×128 = 100 KB | **Yes** | 32 | **32× fewer DDR reads** |
| 5 | 14×14×256 = 50 KB | **Yes** | 64 | **64× fewer DDR reads** |
| 6+ | Smaller | **Yes** | 64+ | **64× fewer DDR reads** |

**Proposed Architecture:**

```
                           ┌─────────────────────────────┐
                           │      Pixel Cache (BRAM)     │
                           │  ~450KB, 57K × 64-bit       │
                           │  ~100 RAMB36E2              │
                           └──────────┬──────────────────┘
                                      │
    DDR ──────► AXI Read ────►  Cache Fill    ────► conv_top
                Master         Controller           │
                                  ▲                 │
                                  │                 │
                              Cache Replay ◄────────┘
                              (for OG 1,2,3...)
```

**Control Flow Change:**

```
CURRENT (memory-bound):
  for og in range(num_output_groups):
      load_weights(og)           # DDR read
      stream_pixels_from_ddr()   # DDR read (REPEATED!)
      process()
      write_output()             # DDR write

OPTIMIZED (compute-bound for layers 2+):
  cache_pixels_to_bram()         # DDR read (ONCE!)
  for og in range(num_output_groups):
      load_weights(og)           # DDR read
      stream_pixels_from_bram()  # BRAM read (FAST!)
      process()
      write_output()             # DDR write
```

**Performance Impact:**

| Layer | Output Groups | Current DDR Reads | With Cache | Speedup |
|-------|---------------|-------------------|------------|---------|
| 0 | 2 | 2× | 2× (no cache) | 1× |
| 1 | 4 | 4× | 4× (no cache) | 1× |
| 2 | 8 | 8× | **1×** | **8×** |
| 3 | 16 | 16× | **1×** | **16×** |
| 4 | 32 | 32× | **1×** | **32×** |
| 5 | 64 | 64× | **1×** | **64×** |

**Estimated FPS Improvement:**

| Metric | Current | With Pixel Cache |
|--------|---------|------------------|
| Layer 0-1 time | ~15 ms | ~15 ms (unchanged) |
| Layer 2-5 time | ~25 ms | ~3 ms |
| **Total inference** | ~40 ms | **~18 ms** |
| **FPS** | ~23 FPS | **~55 FPS** |

**Implementation Requirements:**

1. New module: `pixel_cache.sv` (~100 BRAMs, simple dual-port)
2. New config register: `cfg_use_cache` (CPU decides per-layer)
3. Modified FSM: FILL_CACHE state before PROCESS for cacheable layers
4. Cache read port: Same interface as pixel AXI stream

---

### 2. Increased Output Parallelism ($P_{out}=16$)

**Current:** $P_{out}=8$ uses 576 DSPs (46% of available 1,248)

**Potential:** $P_{out}=16$ would use 1,152 DSPs (92%), doubling throughput for compute-bound layers.

**Trade-offs:**
- Weight bandwidth: Need 2× weight reads per cycle (may require dual-port URAM or interleaved banks)
- Routing congestion: Higher fanout from kernel_window to 16 filter clusters
- URAM capacity: Same depth, but need 128 URAMs (not available) unless weights are time-multiplexed

**Recommendation:** Pursue pixel cache first (simpler, higher impact for memory-bound layers).

---

### 3. Strip Caching for Layers 0-1

For layers too large to fully cache, implement horizontal strip caching:

- Cache 64 rows at a time (~214 KB for layer 0)
- Process all output groups for the strip
- Advance to next strip

This reduces DDR reads by the output group count even for large layers.

---

### 4. Clock Domain Crossing for Higher Memory Bandwidth

Current limitation: AXI HP ports max out at ~250 MHz, limiting memory bandwidth.

**Potential optimization:**
- Run conv datapath at 200 MHz (proven timing)
- Run AXI interfaces at 300 MHz with async FIFOs
- Gain ~50% more memory bandwidth

**Complexity:** Requires careful CDC handling and deeper FIFOs.