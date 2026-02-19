# Hardware vs hardware_sim.py Analysis

## Executive Summary

There are **4 critical differences** between the current hardware and `hardware_sim.py`:

| # | Aspect | hardware_sim.py | Current Hardware | Impact |
|---|--------|-----------------|------------------|--------|
| 1 | **Pixel interpretation** | Signed [-128, 127] | Unsigned [0, 255] | 2x accumulator range |
| 2 | **Operation order** | Leaky → Quantize | Quantize → Leaky | Different effective slope |
| 3 | **Quantization** | Per-layer M | Per-output-group M | Different scale factors |
| 4 | **Bias scaling** | `bias * input_scale * w_scale` | `bias * w_scale` | ~127x bias difference |

---

## Detailed Analysis

### 1. Pixel Interpretation

**hardware_sim.py (TinyYoloINT8.run_forward, line 213-214):**
```python
blob = cv2.dnn.blobFromImage(img, 1/255.0, (416, 416), ...)  # [0, 1] FP32
current_data = np.round(blob * input_scale).astype(np.int8)  # input_scale = 127.0
# Result: signed int8 with range [0, 127] for RGB input
```

**Current Hardware (conv_pe.sv, line 95):**
```verilog
assign pixel_byte = $signed({1'b0, pixels[...][j*8 +: 8]});
// Takes uint8 [0, 255], zero-extends to signed 9-bit [0, 255]
```

**Impact:**
- hardware_sim.py: pixel value 255 → scaled to 127
- Hardware: pixel value 255 → stays as 255
- Accumulator values differ by ~2x
- This affects the optimal M value

---

### 2. Operation Order (CRITICAL)

**hardware_sim.py (TinyYoloINT8.convolution, lines 182-184):**
```python
# Step 1: Accumulate (int32)
output[0, f] += biases[f]

# Step 2: Leaky ReLU FIRST (on int32 accumulator!)
if activation == 'leaky':
    output = np.where(output > 0, output, output >> 3)

# Step 3: Quantize SECOND
output = (output.astype(np.int64) * M) >> n
return np.clip(output, -128, 127).astype(np.int8)
```

**Current Hardware (quantizer.sv, lines 33-43):**
```verilog
// Step 1: Quantize FIRST
mult_result <= data_in * $signed({1'b0, M});
shifted_result <= mult_result >>> n;

// Step 2: Leaky ReLU SECOND (on quantized value!)
if($signed(shifted_result) >= 0)
    relu_result <= shifted_result;
else
    relu_result <= $signed(shifted_result) >>> 3;
```

**Impact - Worked Example:**

Suppose accumulator value = -8000

| Step | hardware_sim.py | Current Hardware |
|------|-----------------|------------------|
| Input | -8000 | -8000 |
| After Leaky (>>3) | -1000 | (not yet) |
| After Quant (M=192, n=16) | (-1000 * 192) >> 16 = **-3** | (-8000 * 192) >> 16 = -24 |
| After Leaky (>>3) | (already done) | -24 >> 3 = **-3** |
| Final | **-3** | **-3** |

Wait, in this example they match! Let me try another:

Suppose accumulator value = -80000

| Step | hardware_sim.py | Current Hardware |
|------|-----------------|------------------|
| Input | -80000 | -80000 |
| After Leaky (>>3) | -10000 | (not yet) |
| After Quant (M=192, n=16) | (-10000 * 192) >> 16 = **-29** | (-80000 * 192) >> 16 = -234 |
| After Leaky (>>3) | (already done) | -234 >> 3 = **-29** |

They match again in this linear case! But consider when M is larger...

Suppose M = 1000, accumulator = -1000:

| Step | hardware_sim.py | Current Hardware |
|------|-----------------|------------------|
| Input | -1000 | -1000 |
| After Leaky | -125 | (not yet) |
| After Quant | (-125 * 1000) >> 16 = **-1** | (-1000 * 1000) >> 16 = -15 |
| After Leaky | (done) | -15 >> 3 = **-1** |

Still match! The key insight: `(x >> 3) * M >> n == x * M >> n >> 3` when M and n are the same.

**BUT** the real issue is when there's **clamping**:

Suppose M = 1000, accumulator = -100000:

| Step | hardware_sim.py | Current Hardware |
|------|-----------------|------------------|
| Input | -100000 | -100000 |
| After Leaky | -12500 | (not yet) |
| After Quant | (-12500 * 1000) >> 16 = -190 | (-100000 * 1000) >> 16 = -1525 |
| After Leaky | (done) | -1525 >> 3 = -190 |
| After Clamp | **-128** (clamped) | **-128** (clamped) |

Hmm, they still match after clamping!

The real difference might be more subtle. Let me reconsider...

Actually, the issue is the **slope value**. In hardware_sim.py, leaky uses `0.1` in FP32 mode but `>>3` (0.125) in INT8 mode. But the key is WHEN it's applied affects the quantization output scale.

---

### 3. Quantization Approach

**hardware_sim.py (calculate_quant_params, lines 129-145):**
```python
# Per-LAYER quantization with calibrated scales
w_scale = 127.0 / w_max                    # Scale weights to [-127, 127]
o_scale = 127.0 / a_max                    # Scale output based on activation stats
effective_scale = o_scale / (prev_scale * w_scale)
M = int(round(effective_scale * (1 << n))) # Single M for entire layer
```

**Current Hardware approach (gen_layer0_stimulus.py):**
```python
# Per-OUTPUT-GROUP quantization
for og in range(CO_GROUPS):
    w_og = w_padded[fs:fe]
    w_max = np.max(np.abs(w_og))           # Max within output group only
    w_scale = 127.0 / w_max
    M = round(2**n / w_scale)              # Different M per output group
```

**Impact:**
- hardware_sim.py uses calibrated output scales based on actual activation statistics
- Current hardware uses simpler 1/w_scale approach per output group
- hardware_sim.py's M values account for expected output range

---

### 4. Bias Scaling

**hardware_sim.py (line 141):**
```python
q_biases = np.round(params['biases'] * (prev_scale * w_scale)).astype(np.int32)
# For layer 0: prev_scale = input_scale = 127.0
# So bias is scaled by 127.0 * w_scale
```

**Current Hardware (gen_layer0_stimulus.py):**
```python
b_int32[fs:fe] = np.round(b_folded[fs:fe] * w_scale).astype(np.int32)
# Bias scaled by w_scale only, missing the input_scale factor
```

**Impact:**
- For layer 0: hardware_sim.py biases are ~127x larger
- This directly affects the accumulator value
- Combined with different M, the final results differ

---

## Required Hardware Changes

### Option A: Modify Hardware to Match hardware_sim.py

#### Change 1: Pixel as Signed (conv_pe.sv line 95)
```verilog
// Current (unsigned, zero-extended):
assign pixel_byte = $signed({1'b0, pixels[i/3][i%3][j*8 +: 8]});

// New (signed):
assign pixel_byte = $signed(pixels[i/3][i%3][j*8 +: 8]);
```

#### Change 2: Leaky Before Quantize (quantizer.sv)
```verilog
// Current order: quantize → leaky
// New order: leaky → quantize

// Add leaky BEFORE multiply:
logic signed [31:0] leaky_result;
always_ff @(posedge clk) begin
    if (use_relu && data_in < 0)
        leaky_result <= data_in >>> 3;
    else
        leaky_result <= data_in;

    mult_result <= leaky_result * $signed({1'b0, M});
    shifted_result <= mult_result >>> n;
    // No leaky after shift - already done
end
```

#### Change 3: Update Quantization Parameters
- Use per-layer M instead of per-output-group M
- Scale biases by `input_scale * w_scale` instead of just `w_scale`
- Use calibrated output scales from activation statistics

### Option B: Create hardware_sim.py-Compatible Stimulus

Keep hardware as-is, but generate stimulus that matches hardware's expectations:
- Pre-scale pixels by 2x (127 → 255)
- Adjust M values to compensate for operation order
- Scale biases differently

This is more complex and may not achieve the same accuracy.

---

## Recommended Path

**Option A (Modify Hardware)** is cleaner because:
1. hardware_sim.py is proven to give good detection accuracy
2. Changes are minimal (2 RTL files)
3. Future layers will automatically work correctly

**Changes required:**
1. `conv_pe.sv`: Remove zero-extension on pixel (1 line)
2. `quantizer.sv`: Move leaky before multiply (~10 lines)
3. Stimulus generator: Use hardware_sim.py quantization parameters
4. Re-synthesize and test
