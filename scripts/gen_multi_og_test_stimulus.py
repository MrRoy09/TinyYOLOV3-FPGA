#!/usr/bin/env python3
"""
Generate stimulus for multi-OG batching test.

This creates synthetic but UNIQUE data for each OG so we can verify
that the RTL correctly processes each OG independently.

Layer config: 8x8 input, ci_groups=1, co_groups=4 (32 output channels)
This matches the AXI testbench's NUM_OGS=4 setting.
"""

import numpy as np
import os
import sys

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_ROOT = os.path.dirname(SCRIPT_DIR)

# Test configuration - 4 output groups for batch testing
IMG_H, IMG_W = 8, 8
PADDED_H, PADDED_W = 10, 10  # 1-pixel border
CIN = 3
CIN_PAD = 8  # Pad to multiple of 8
COUT = 32    # 4 output groups of 8 channels each
POUT = 8
CI_GROUPS = CIN_PAD // 8  # 1
CO_GROUPS = COUT // 8     # 4

def int8_to_hex(val):
    return f"{val & 0xFF:02x}"

def int32_to_hex(val):
    return f"{int(val) & 0xFFFFFFFF:08x}"

def pack_pixel_word(pixels_8ch):
    val = 0
    for i, p in enumerate(pixels_8ch):
        val |= (int(p) & 0xFF) << (i * 8)
    return val

def pack_weight_word(weights_9spatial):
    val = 0
    for i, w in enumerate(weights_9spatial):
        val |= (int(w) & 0xFF) << (i * 8)
    return val

def leaky_relu(x):
    return np.where(x >= 0, x, x // 8)

def quantize_output(acc, bias, M, n):
    with_bias = acc + bias
    after_relu = leaky_relu(with_bias)
    scaled = (after_relu * M) >> n
    clamped = np.clip(scaled, -128, 127)
    return clamped.astype(np.int8)

def maxpool_2x2_stride2(data):
    h, w, c = data.shape
    out_h, out_w = h // 2, w // 2
    out = np.zeros((out_h, out_w, c), dtype=np.int8)
    for y in range(out_h):
        for x in range(out_w):
            window = data[y*2:y*2+2, x*2:x*2+2, :]
            out[y, x, :] = np.max(window, axis=(0, 1))
    return out

def conv3x3(input_padded, weights, biases, M, n):
    h_out = input_padded.shape[0] - 2
    w_out = input_padded.shape[1] - 2
    cin = weights.shape[1]
    cout = weights.shape[0]

    output = np.zeros((h_out, w_out, cout), dtype=np.int8)

    for y in range(h_out):
        for x in range(w_out):
            window = input_padded[y:y+3, x:x+3, :cin]
            for f in range(cout):
                acc = np.sum(window.astype(np.int32) * weights[f].transpose(1, 2, 0).astype(np.int32))
                output[y, x, f] = quantize_output(acc, biases[f], M, n)
    return output

def main():
    out_dir = os.path.join(SCRIPT_DIR, 'stimulus')
    os.makedirs(out_dir, exist_ok=True)

    print("="*60)
    print("Generating Multi-OG Test Stimulus")
    print(f"  {IMG_H}x{IMG_W} input, {CIN}->{COUT} channels, {CO_GROUPS} OGs")
    print("="*60)

    # Use Layer 0 quant params but extend to 32 output channels
    quant_path = os.path.join(PROJECT_ROOT, 'sim/hardware-ai/quantized_params.npz')
    q_params = np.load(quant_path, allow_pickle=True)

    M = int(q_params['l0_M'])
    n = int(q_params['l0_n'])
    print(f"\nUsing M=0x{M:X}, n={n}")

    # Create synthetic weights - DIFFERENT for each OG
    # Use OG index as a seed offset to ensure unique weights per OG
    np.random.seed(42)
    weights_full = np.random.randint(-30, 30, size=(COUT, CIN, 3, 3), dtype=np.int8)

    # Make each OG's weights distinctly different by adding OG-specific offset
    for og in range(CO_GROUPS):
        weights_full[og*8:(og+1)*8, :, :, :] += np.int8(og * 5 - 7)

    # Pad to CIN_PAD
    weights_padded = np.zeros((COUT, CIN_PAD, 3, 3), dtype=np.int8)
    weights_padded[:, :CIN, :, :] = weights_full

    # Create biases - DIFFERENT for each OG
    biases = np.zeros(COUT, dtype=np.int32)
    for og in range(CO_GROUPS):
        for ch in range(8):
            biases[og*8 + ch] = (og * 1000 + ch * 100)  # Distinct per OG

    print(f"Biases per OG: {[biases[og*8] for og in range(CO_GROUPS)]}")

    # Create input
    np.random.seed(123)
    input_raw = np.random.randint(-50, 50, size=(IMG_H, IMG_W, CIN), dtype=np.int8)

    # Pad input
    input_padded = np.zeros((PADDED_H, PADDED_W, CIN_PAD), dtype=np.int8)
    input_padded[1:1+IMG_H, 1:1+IMG_W, :CIN] = input_raw

    print(f"\nInput shape: {input_padded.shape}")
    print(f"Weights shape: {weights_padded.shape}")

    # Compute expected output
    conv_out = conv3x3(input_padded, weights_padded, biases, M, n)
    print(f"Conv output shape: {conv_out.shape}")

    maxpool_out = maxpool_2x2_stride2(conv_out)
    print(f"Maxpool output shape: {maxpool_out.shape}")

    # ========== Generate hex files ==========

    # 1. Pixels (same for all OGs)
    for og in range(CO_GROUPS):
        with open(os.path.join(out_dir, f'pixels_og{og}.hex'), 'w') as f:
            for y in range(PADDED_H):
                for x in range(PADDED_W):
                    word = pack_pixel_word(input_padded[y, x, :8])
                    f.write(f"{word:016x}\n")
        if og == 0:
            print(f"Written pixels_og{og}.hex ({PADDED_H * PADDED_W} words)")

    # 2. Weights per output group - EACH OG HAS UNIQUE WEIGHTS
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

    # 3. Biases per output group - EACH OG HAS UNIQUE BIASES
    for og in range(CO_GROUPS):
        with open(os.path.join(out_dir, f'biases_og{og}.hex'), 'w') as f:
            for i in range(8):
                bias_idx = og * 8 + i
                f.write(f"{int32_to_hex(biases[bias_idx])}\n")
        print(f"Written biases_og{og}.hex (8 words) - first bias: {biases[og*8]}")

    # 4. All biases packed (128-bit words)
    with open(os.path.join(out_dir, 'biases_all.hex'), 'w') as f:
        for i in range(0, COUT, 4):
            word = 0
            for j in range(4):
                b = int(biases[i + j])
                if b < 0:
                    b = b & 0xFFFFFFFF
                word |= b << (j * 32)
            f.write(f"{word:032x}\n")
    print(f"Written biases_all.hex ({COUT // 4} words)")

    # 5. Expected output per output group - UNIQUE FOR EACH OG
    for og in range(CO_GROUPS):
        with open(os.path.join(out_dir, f'expected_og{og}.hex'), 'w') as f:
            out_h, out_w = maxpool_out.shape[0], maxpool_out.shape[1]
            for y in range(out_h):
                for x in range(out_w):
                    word = pack_pixel_word(maxpool_out[y, x, og*8:(og+1)*8])
                    f.write(f"{word:016x}\n")
        print(f"Written expected_og{og}.hex ({out_h * out_w} words)")

    # Verify files are unique
    print("\n" + "="*60)
    print("Verifying uniqueness:")
    import hashlib
    for prefix in ['weights', 'biases', 'expected']:
        hashes = []
        for og in range(CO_GROUPS):
            path = os.path.join(out_dir, f'{prefix}_og{og}.hex')
            with open(path, 'rb') as f:
                h = hashlib.md5(f.read()).hexdigest()[:8]
                hashes.append(h)
        unique = len(set(hashes)) == len(hashes)
        status = "UNIQUE" if unique else "DUPLICATE!"
        print(f"  {prefix}: {hashes} [{status}]")

    print("\n" + "="*60)
    print("Sample expected values per OG (first pixel):")
    for og in range(CO_GROUPS):
        vals = maxpool_out[0, 0, og*8:(og+1)*8]
        print(f"  OG{og}: {list(vals)}")
    print("="*60)

if __name__ == "__main__":
    main()
