#!/usr/bin/env python3
"""
Generate small 8x8 test stimulus for local RTL simulation.
Uses hardware_sim.py quantization as the GOLDEN STANDARD.

Output: scripts/stimulus/*.hex files for tb_conv_top_e2e.sv
"""

import numpy as np
import os
import sys

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_ROOT = os.path.dirname(SCRIPT_DIR)
sys.path.insert(0, os.path.join(PROJECT_ROOT, 'sim', 'hardware-ai'))

from hardware_sim import load_quant_params

# Test configuration
IMG_H, IMG_W = 8, 8
PADDED_H, PADDED_W = 10, 10  # 1-pixel border
CIN = 3
CIN_PAD = 8  # Pad to multiple of 8
COUT = 16
POUT = 8
CI_GROUPS = CIN_PAD // 8  # 1
CO_GROUPS = COUT // 8      # 2

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
    Quantize accumulator output matching hardware_sim.py:
    1. Add bias
    2. Apply leaky ReLU
    3. Multiply by M
    4. Right-shift by n
    5. Clamp to [-128, 127]
    """
    with_bias = acc + bias
    after_relu = leaky_relu(with_bias)
    scaled = (after_relu * M) >> n
    clamped = np.clip(scaled, -128, 127)
    return clamped.astype(np.int8)

def maxpool_2x2_stride2(data):
    """2x2 maxpool with stride 2."""
    h, w, c = data.shape
    out_h, out_w = h // 2, w // 2
    out = np.zeros((out_h, out_w, c), dtype=np.int8)
    for y in range(out_h):
        for x in range(out_w):
            window = data[y*2:y*2+2, x*2:x*2+2, :]
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
    out_dir = os.path.join(SCRIPT_DIR, 'stimulus')
    os.makedirs(out_dir, exist_ok=True)

    # Load real quantization parameters from hardware_sim.py
    quant_path = os.path.join(PROJECT_ROOT, 'sim/hardware-ai/quantized_params.npz')
    print(f"Loading quant params from {quant_path}")
    q_params = load_quant_params(quant_path)

    p = q_params[0]  # Layer 0
    weights = p['q_weights']  # (16, 3, 3, 3) = (cout, cin, kh, kw)
    biases = p['q_biases']    # (16,)
    M = int(p['M'])
    n = int(p['n'])

    print(f"Layer 0: weights={weights.shape}, biases={biases.shape}")
    print(f"M=0x{M:04X}, n={n}")

    # Generate synthetic 8x8 input image (3 channels)
    np.random.seed(42)
    input_img = np.random.randint(-50, 50, (IMG_H, IMG_W, CIN), dtype=np.int8)

    # Pad channels to 8
    input_padded_ch = np.zeros((IMG_H, IMG_W, CIN_PAD), dtype=np.int8)
    input_padded_ch[:, :, :CIN] = input_img

    # Add spatial padding (1-pixel border)
    input_padded = np.zeros((PADDED_H, PADDED_W, CIN_PAD), dtype=np.int8)
    input_padded[1:-1, 1:-1, :] = input_padded_ch

    print(f"Input shape: {input_padded.shape}")

    # Compute expected output using golden model
    # Pad weights to CIN_PAD channels
    weights_padded = np.zeros((COUT, CIN_PAD, 3, 3), dtype=np.int8)
    weights_padded[:, :CIN, :, :] = weights

    # Run convolution
    conv_out = conv3x3(input_padded, weights_padded, biases, M, n)
    print(f"Conv output shape: {conv_out.shape}")

    # Run maxpool
    maxpool_out = maxpool_2x2_stride2(conv_out)
    print(f"Maxpool output shape: {maxpool_out.shape}")

    # ========== Generate hex files ==========

    # 1. Pixels (same for both OGs since input is shared)
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
            # Weight streaming order: addr (ci_groups), bank (8 filters), uram (8 channels)
            for addr in range(CI_GROUPS):
                for bank in range(8):
                    filter_idx = og * POUT + bank
                    for uram in range(8):
                        ch = addr * 8 + uram
                        # Pack 9 spatial weights
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

    # 4. All biases packed (128-bit words, 4 biases each)
    with open(os.path.join(out_dir, 'biases_all.hex'), 'w') as f:
        for i in range(0, COUT, 4):
            # Pack 4 biases into 128-bit word
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
                    # Pack 8 channels for this output group
                    word = pack_pixel_word(maxpool_out[y, x, og*8:(og+1)*8])
                    f.write(f"{word:016x}\n")
        print(f"Written expected_og{og}.hex ({out_h * out_w} words)")

    # 6. Quant params (for reference)
    with open(os.path.join(out_dir, 'quant_params.txt'), 'w') as f:
        f.write(f"# Layer 0 quantization params from hardware_sim.py\n")
        f.write(f"M=0x{M:08X}\n")
        f.write(f"n={n}\n")
    print(f"Written quant_params.txt")

    print(f"\nDone! Stimulus written to {out_dir}/")
    print(f"Expected output range: [{maxpool_out.min()}, {maxpool_out.max()}]")

    # Print some sample values for verification
    print(f"\nSample expected values (OG0, first 4 positions):")
    for i in range(4):
        y, x = i // 2, (i % 2) * 2  # Assuming 4x4 output
        vals = maxpool_out[y, x, :8]
        print(f"  [{y},{x}]: {list(vals)}")

if __name__ == "__main__":
    main()
