#!/usr/bin/env python3
"""
Generate stride-1 maxpool test stimulus for RTL verification.
Uses hardware_sim.py quantization as the GOLDEN STANDARD.

For stride-1 maxpool with backward-looking RTL (skipping row 0 and col 0):
- To get HxW final output, maxpool needs (H+1)x(W+1) input
- For 3x3 conv to produce (H+1)x(W+1), conv needs (H+3)x(W+3) padded input

Test case: 4x4 final output
- Maxpool input: 5x5
- Conv output: 5x5
- Conv input (padded): 7x7

Output: scripts/stimulus_l5/*.hex files
"""

import numpy as np
import os
import sys

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_ROOT = os.path.dirname(SCRIPT_DIR)
sys.path.insert(0, os.path.join(PROJECT_ROOT, 'sim', 'hardware-ai'))

from hardware_sim import load_quant_params

# Test configuration for stride-1 maxpool
FINAL_OUT_H, FINAL_OUT_W = 4, 4  # Desired final output after maxpool
CONV_OUT_H, CONV_OUT_W = 5, 5    # Conv output = maxpool input
IMG_H, IMG_W = CONV_OUT_H, CONV_OUT_W  # Core image (before padding)
PADDED_H, PADDED_W = IMG_H + 2, IMG_W + 2  # 1-pixel border for 3x3 conv = 7x7

# Channel configuration (use Layer 5: 256->512 but with small test)
# For simpler test, use Layer 0 params: 3->16
CIN = 3
CIN_PAD = 8
COUT = 16
POUT = 8
CI_GROUPS = CIN_PAD // 8  # 1
CO_GROUPS = COUT // 8     # 2

def int8_to_hex(val):
    """Convert signed int8 to 2-char hex."""
    return f"{val & 0xFF:02x}"

def int32_to_hex(val):
    """Convert signed int32 to 8-char hex."""
    return f"{int(val) & 0xFFFFFFFF:08x}"

def pack_pixel_word(pixels_8ch):
    """Pack 8 int8 channels into 64-bit word (little-endian)."""
    val = 0
    for i, p in enumerate(pixels_8ch):
        val |= (int(p) & 0xFF) << (i * 8)
    return val

def pack_weight_word(weights_9spatial):
    """Pack 9 spatial weights into 72-bit word."""
    val = 0
    for i, w in enumerate(weights_9spatial):
        val |= (int(w) & 0xFF) << (i * 8)
    return val

def leaky_relu(x):
    """Leaky ReLU with slope ~0.125 (x/8 for negative)."""
    return np.where(x >= 0, x, x // 8)

def quantize_output(acc, bias, M, n):
    """
    Quantize accumulator output matching hardware_sim.py.
    """
    with_bias = acc + bias
    after_relu = leaky_relu(with_bias)
    scaled = (after_relu * M) >> n
    clamped = np.clip(scaled, -128, 127)
    return clamped.astype(np.int8)

def maxpool_2x2_stride1_backward_with_padding(data):
    """
    2x2 maxpool with stride 1, using BACKWARD-LOOKING algorithm WITH -128 padding.
    This matches the RTL implementation which:
    1. Replaces the last row and last column of input with -128
    2. Uses backward-looking with row 0/col 0 skip

    For input HxW, output is (H-1)x(W-1).
    Output[r][c] = max(modified_input[r:r+2, c:c+2]) where:
    - modified_input[*, W-1] = -128  (padding column)
    - modified_input[H-1, *] = -128  (padding row)
    """
    h, w, c = data.shape
    out_h, out_w = h - 1, w - 1
    out = np.zeros((out_h, out_w, c), dtype=np.int8)

    # Create modified input with -128 at padding positions
    # RTL: is_padding_col = (col_cnt == img_width_r - 1)
    #      is_padding_row = (row_cnt == img_width_r - 1)
    data_eff = data.copy()
    data_eff[h-1, :, :] = -128  # Last row
    data_eff[:, w-1, :] = -128  # Last column

    # Backward-looking: output[r][c] uses modified_input[r:r+2, c:c+2]
    for y in range(out_h):
        for x in range(out_w):
            window = data_eff[y:y+2, x:x+2, :]
            out[y, x, :] = np.max(window, axis=(0, 1))
    return out

def conv3x3(input_padded, weights, biases, M, n):
    """
    3x3 convolution matching hardware_sim.py.
    Input: (H+2, W+2, cin_pad) - already padded
    Weights: (cout, cin, 3, 3)
    Returns: (H, W, cout) int8
    """
    h_out = input_padded.shape[0] - 2
    w_out = input_padded.shape[1] - 2
    cin = weights.shape[1]
    cout = weights.shape[0]

    output = np.zeros((h_out, w_out, cout), dtype=np.int8)

    for y in range(h_out):
        for x in range(w_out):
            window = input_padded[y:y+3, x:x+3, :cin]  # (3, 3, cin)
            for f in range(cout):
                # Dot product
                acc = np.sum(window.astype(np.int32) * weights[f].transpose(1, 2, 0).astype(np.int32))
                # Quantize
                output[y, x, f] = quantize_output(acc, biases[f], M, n)

    return output

def main():
    # Output directory
    out_dir = os.path.join(SCRIPT_DIR, 'stimulus_l5')
    os.makedirs(out_dir, exist_ok=True)

    # Load real quantization parameters
    quant_path = os.path.join(PROJECT_ROOT, 'sim/hardware-ai/quantized_params.npz')
    print(f"Loading quant params from {quant_path}")
    q_params = load_quant_params(quant_path)

    p = q_params[0]  # Use Layer 0 params for simplicity
    weights = p['q_weights']  # (16, 3, 3, 3) = (cout, cin, kh, kw)
    biases = p['q_biases']    # (16,)
    M = int(p['M'])
    n = int(p['n'])

    print(f"Layer 0 params: weights={weights.shape}, biases={biases.shape}")
    print(f"M=0x{M:04X}, n={n}")
    print(f"\nStride-1 maxpool test configuration:")
    print(f"  Final output: {FINAL_OUT_H}x{FINAL_OUT_W}")
    print(f"  Conv/maxpool input: {CONV_OUT_H}x{CONV_OUT_W}")
    print(f"  Padded conv input: {PADDED_H}x{PADDED_W}")

    # Generate synthetic 5x5 input image (3 channels) - will become 5x5 conv output
    np.random.seed(42)
    input_img = np.random.randint(-50, 50, (IMG_H, IMG_W, CIN), dtype=np.int8)

    # Pad channels to 8
    input_padded_ch = np.zeros((IMG_H, IMG_W, CIN_PAD), dtype=np.int8)
    input_padded_ch[:, :, :CIN] = input_img

    # Add spatial padding (1-pixel border) for 3x3 conv -> 7x7
    input_padded = np.zeros((PADDED_H, PADDED_W, CIN_PAD), dtype=np.int8)
    input_padded[1:-1, 1:-1, :] = input_padded_ch

    print(f"Input shape: {input_padded.shape}")

    # Compute expected output using golden model
    # Pad weights to CIN_PAD channels
    weights_padded = np.zeros((COUT, CIN_PAD, 3, 3), dtype=np.int8)
    weights_padded[:, :CIN, :, :] = weights

    # Run convolution -> 5x5 output
    conv_out = conv3x3(input_padded, weights_padded, biases, M, n)
    print(f"Conv output shape: {conv_out.shape}")

    # Run stride-1 maxpool matching hardware_sim.py golden model:
    # 1. 5x5 conv output
    # 2. Replace row 4/col 4 with -128 (this is what RTL does via padding injection)
    # 3. Backward-looking with skip row0/col0 -> 4x4 output
    maxpool_out = maxpool_2x2_stride1_backward_with_padding(conv_out)
    print(f"Maxpool output shape: {maxpool_out.shape}")

    assert maxpool_out.shape[0] == FINAL_OUT_H, f"Expected {FINAL_OUT_H}x{FINAL_OUT_W}, got {maxpool_out.shape}"

    # ========== Generate hex files ==========

    # 1. Pixels (input to conv)
    for og in range(CO_GROUPS):
        with open(os.path.join(out_dir, f'pixels_og{og}.hex'), 'w') as f:
            for y in range(PADDED_H):
                for x in range(PADDED_W):
                    # Pack 8 channels into 64-bit word
                    word = pack_pixel_word(input_padded[y, x, :8])
                    f.write(f"{word:016x}\n")
        print(f"Written pixels_og{og}.hex ({PADDED_H * PADDED_W} words)")

    # 2. Weights per output group
    for og in range(CO_GROUPS):
        with open(os.path.join(out_dir, f'weights_og{og}.hex'), 'w') as f:
            for addr in range(CI_GROUPS):
                for bank in range(8):
                    filter_idx = og * POUT + bank
                    for uram in range(8):
                        ch = addr * 8 + uram
                        spatial_weights = []
                        for ky in range(3):
                            for kx in range(3):
                                if ch < CIN_PAD:
                                    spatial_weights.append(weights_padded[filter_idx, ch, ky, kx])
                                else:
                                    spatial_weights.append(0)
                        word = pack_weight_word(spatial_weights)
                        f.write(f"{word:018x}\n")
        print(f"Written weights_og{og}.hex ({CI_GROUPS * 64} words)")

    # 3. Biases per output group
    for og in range(CO_GROUPS):
        with open(os.path.join(out_dir, f'biases_og{og}.hex'), 'w') as f:
            for i in range(8):
                bias_idx = og * 8 + i
                f.write(f"{int32_to_hex(biases[bias_idx])}\n")
        print(f"Written biases_og{og}.hex (8 words)")

    # 4. All biases packed
    with open(os.path.join(out_dir, 'biases_all.hex'), 'w') as f:
        for i in range(0, COUT, 4):
            word = 0
            for j in range(4):
                b = int(biases[i + j])
                if b < 0:
                    b = b & 0xFFFFFFFF
                word |= b << (j * 32)
            f.write(f"{word:032x}\n")
    print(f"Written biases_all.hex (4 words)")

    # 5. Expected output per output group
    for og in range(CO_GROUPS):
        with open(os.path.join(out_dir, f'expected_og{og}.hex'), 'w') as f:
            out_h, out_w = maxpool_out.shape[0], maxpool_out.shape[1]
            for y in range(out_h):
                for x in range(out_w):
                    word = pack_pixel_word(maxpool_out[y, x, og*8:(og+1)*8])
                    f.write(f"{word:016x}\n")
        print(f"Written expected_og{og}.hex ({out_h * out_w} words)")

    # 6. Quant params
    with open(os.path.join(out_dir, 'quant_params.txt'), 'w') as f:
        f.write(f"# Stride-1 maxpool test using Layer 0 params\n")
        f.write(f"M=0x{M:08X}\n")
        f.write(f"n={n}\n")
        f.write(f"# Test: {PADDED_H}x{PADDED_W} padded input -> {CONV_OUT_H}x{CONV_OUT_W} conv -> {FINAL_OUT_H}x{FINAL_OUT_W} maxpool\n")
    print(f"Written quant_params.txt")

    print(f"\nDone! Stimulus written to {out_dir}/")
    print(f"Expected output range: [{maxpool_out.min()}, {maxpool_out.max()}]")

    # Print sample values
    print(f"\nSample expected values (OG0, all 4x4 positions):")
    for y in range(4):
        row_vals = []
        for x in range(4):
            row_vals.append(maxpool_out[y, x, 0])
        print(f"  row {y}: {row_vals}")

if __name__ == "__main__":
    main()
