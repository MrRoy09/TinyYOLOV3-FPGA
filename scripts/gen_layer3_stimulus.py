#!/usr/bin/env python3
"""
Generate stimulus for Layer 3 (ci_groups=8) RTL testbench.
Uses a small 4x4 image for quick simulation.

Layer 3 config:
- cin=64, cout=128
- ci_groups=8, co_groups=16
- 4x4 image padded to 6x6
- Maxpool stride-2 -> 2x2 output
"""

import os
import sys
import numpy as np

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_ROOT = os.path.dirname(SCRIPT_DIR)
sys.path.insert(0, os.path.join(PROJECT_ROOT, 'sim', 'hardware-ai'))

from hardware_sim import load_quant_params

# Layer 3 config
NPZ_IDX = 6  # Conv 64->128
CIN = 64
COUT = 128
CI_GROUPS = 8
CO_GROUPS = 16
IMG_H = 4
IMG_W = 4
PADDED_H = 6
PADDED_W = 6
OUT_H = 2  # After maxpool stride-2
OUT_W = 2

OUT_DIR = os.path.join(SCRIPT_DIR, "stimulus_l3")


def reference_conv(pixels, weights, biases, M, n, img_h, img_w, cout):
    """Compute reference convolution with quantization and leaky ReLU."""
    # pixels: (padded_h, padded_w, cin) int8
    # weights: (cout, cin, 3, 3) int8
    # biases: (cout,) int32

    conv_h = img_h
    conv_w = img_w
    cin = weights.shape[1]

    # Convolution
    conv_out = np.zeros((conv_h, conv_w, cout), dtype=np.int32)
    for f in range(cout):
        for c in range(cin):
            for ky in range(3):
                for kx in range(3):
                    w = int(weights[f, c, ky, kx])
                    if w == 0:
                        continue
                    for y in range(conv_h):
                        for x in range(conv_w):
                            p = int(pixels[y + ky, x + kx, c])
                            conv_out[y, x, f] += p * w
        conv_out[:, :, f] += int(biases[f])

    # Quantize: (acc * M) >> n
    conv_out = (conv_out.astype(np.int64) * M) >> n

    # Leaky ReLU
    conv_out = np.where(conv_out >= 0, conv_out, conv_out >> 3)

    # Clamp to int8
    conv_out = np.clip(conv_out, -128, 127).astype(np.int8)

    # Maxpool 2x2 stride-2
    out_h = conv_h // 2
    out_w = conv_w // 2
    mp_out = np.zeros((out_h, out_w, cout), dtype=np.int8)
    for y in range(out_h):
        for x in range(out_w):
            for f in range(cout):
                window = conv_out[y*2:y*2+2, x*2:x*2+2, f]
                mp_out[y, x, f] = np.max(window)

    return mp_out


def pack_weights_hex(weights, og, ci_groups):
    """Pack weights for one OG as 72-bit hex strings."""
    cout, cin, _, _ = weights.shape
    lines = []

    for addr in range(ci_groups):
        for bank in range(8):
            filter_idx = og * 8 + bank
            for uram in range(8):
                ch = addr * 8 + uram

                # Pack 9 spatial weights
                val = 0
                for spatial_idx in range(9):
                    ky = spatial_idx // 3
                    kx = spatial_idx % 3
                    w_byte = int(weights[filter_idx, ch, ky, kx])
                    if w_byte < 0:
                        w_byte = w_byte & 0xFF
                    val |= w_byte << (spatial_idx * 8)

                lines.append(f"{val:018x}")

    return lines


def pack_biases_hex(biases):
    """Pack all biases as 128-bit hex strings (4 biases per line)."""
    lines = []
    for i in range(0, len(biases), 4):
        val = 0
        for j in range(4):
            if i + j < len(biases):
                b = int(biases[i + j])
                if b < 0:
                    b = b & 0xFFFFFFFF
                val |= b << (j * 32)
        lines.append(f"{val:032x}")
    return lines


def pack_pixels_hex(pixels, ci_groups):
    """Pack pixels as 64-bit hex strings (8 channels per line)."""
    h, w, c = pixels.shape
    lines = []

    for y in range(h):
        for x in range(w):
            for cg in range(ci_groups):
                val = 0
                for ch in range(8):
                    p = int(pixels[y, x, cg * 8 + ch])
                    if p < 0:
                        p = p & 0xFF
                    val |= p << (ch * 8)
                lines.append(f"{val:016x}")

    return lines


def pack_expected_hex(output):
    """Pack expected output as 64-bit hex strings."""
    h, w, c = output.shape
    lines = []

    for y in range(h):
        for x in range(w):
            val = 0
            for ch in range(8):
                p = int(output[y, x, ch])
                if p < 0:
                    p = p & 0xFF
                val |= p << (ch * 8)
            lines.append(f"{val:016x}")

    return lines


def main():
    os.makedirs(OUT_DIR, exist_ok=True)

    # Load quantization parameters
    quant_path = os.path.join(PROJECT_ROOT, 'sim/hardware-ai/quantized_params.npz')
    q_params = load_quant_params(quant_path)

    p = q_params[NPZ_IDX]
    weights = p['q_weights']  # (128, 64, 3, 3)
    biases = p['q_biases']    # (128,)
    M = int(p['M'])
    n = int(p['n'])

    print(f"Layer 3 (NPZ {NPZ_IDX}): {CIN}→{COUT}")
    print(f"  Weights: {weights.shape}")
    print(f"  Biases: {biases.shape}")
    print(f"  M=0x{M:04x}, n={n}")
    print(f"  ci_groups={CI_GROUPS}, co_groups={CO_GROUPS}")
    print()

    # Generate random input pixels
    np.random.seed(42)
    pixels = np.random.randint(-50, 50, (PADDED_H, PADDED_W, CIN), dtype=np.int8)
    # Zero-pad border
    pixels[0, :, :] = 0
    pixels[-1, :, :] = 0
    pixels[:, 0, :] = 0
    pixels[:, -1, :] = 0

    print(f"Input pixels: {pixels.shape}, range [{pixels.min()}, {pixels.max()}]")

    # Compute expected output
    expected_full = reference_conv(pixels, weights, biases, M, n, IMG_H, IMG_W, COUT)
    print(f"Expected output: {expected_full.shape}, range [{expected_full.min()}, {expected_full.max()}]")

    # Save biases (all 128 biases)
    bias_lines = pack_biases_hex(biases)
    with open(os.path.join(OUT_DIR, "biases_all.hex"), 'w') as f:
        f.write('\n'.join(bias_lines) + '\n')
    print(f"Wrote biases_all.hex ({len(bias_lines)} lines)")

    # Save per-OG files
    for og in range(CO_GROUPS):
        # Weights
        wt_lines = pack_weights_hex(weights, og, CI_GROUPS)
        with open(os.path.join(OUT_DIR, f"weights_og{og}.hex"), 'w') as f:
            f.write('\n'.join(wt_lines) + '\n')

        # Pixels (same for all OGs)
        px_lines = pack_pixels_hex(pixels, CI_GROUPS)
        with open(os.path.join(OUT_DIR, f"pixels_og{og}.hex"), 'w') as f:
            f.write('\n'.join(px_lines) + '\n')

        # Expected (8 channels for this OG)
        expected_og = expected_full[:, :, og*8:(og+1)*8]
        exp_lines = pack_expected_hex(expected_og)
        with open(os.path.join(OUT_DIR, f"expected_og{og}.hex"), 'w') as f:
            f.write('\n'.join(exp_lines) + '\n')

        print(f"  OG{og}: weights={len(wt_lines)}, pixels={len(px_lines)}, expected={len(exp_lines)}")

    # Save quant params
    with open(os.path.join(OUT_DIR, "quant_params.txt"), 'w') as f:
        f.write(f"# Layer 3 quantization parameters\n")
        f.write(f"m=0x{M:08x}\n")
        f.write(f"n={n}\n")
        f.write(f"ci_groups={CI_GROUPS}\n")
        f.write(f"co_groups={CO_GROUPS}\n")

    print(f"\nStimulus written to {OUT_DIR}")


if __name__ == "__main__":
    main()
