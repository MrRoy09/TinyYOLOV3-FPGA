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