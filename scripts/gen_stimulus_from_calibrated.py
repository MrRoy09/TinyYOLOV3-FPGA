#!/usr/bin/env python3
"""
Generate stimulus files using CALIBRATED quantization parameters from
hardware_sim.py's quantized_params.npz.

This ensures exact match with hardware_sim.py's proven INT8 accuracy.

Usage:
  python3 gen_stimulus_from_calibrated.py --layer 0
  python3 gen_stimulus_from_calibrated.py --layer 1
"""

import numpy as np
import struct
import os
import argparse

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
CALIB_FILE = os.path.join(SCRIPT_DIR, "..", "sim", "hardware-ai", "quantized_params.npz")
WEIGHTS_PATH = os.path.join(SCRIPT_DIR, "yolov3-tiny.weights")

# Hardware constants
PIN = 8
POUT = 8


def load_calibrated_params(layer_idx):
    """Load calibrated quantization parameters for a layer."""
    data = np.load(CALIB_FILE, allow_pickle=True)

    params = {
        'input_scale': float(data['input_scale']),
        'M': int(data[f'l{layer_idx}_M']),
        'n': int(data[f'l{layer_idx}_n']),
        'o_scale': float(data[f'l{layer_idx}_o_scale']),
        'q_weights': data[f'l{layer_idx}_q_weights'],
        'q_biases': data[f'l{layer_idx}_q_biases'],
        'activation': str(data[f'l{layer_idx}_activation']),
        'stride': int(data[f'l{layer_idx}_stride']),
        'pad': int(data[f'l{layer_idx}_pad']),
    }

    return params, data


def get_prev_scale(data, layer_idx):
    """Get the output scale of the previous layer (which is input scale for this layer)."""
    if layer_idx == 0:
        return float(data['input_scale'])

    # Walk backwards to find previous conv/maxpool/route layer
    for i in range(layer_idx - 1, -1, -1):
        if f'l{i}_o_scale' in data.files:
            return float(data[f'l{i}_o_scale'])

    return float(data['input_scale'])


def generate_layer0_stimulus():
    """Generate Layer 0 stimulus using calibrated parameters."""
    params, data = load_calibrated_params(0)
    prev_scale = get_prev_scale(data, 0)

    print("="*60)
    print("LAYER 0 CALIBRATED PARAMETERS")
    print("="*60)
    print(f"prev_scale (input_scale): {prev_scale}")
    print(f"o_scale: {params['o_scale']}")
    print(f"M: 0x{params['M']:08x} ({params['M']})")
    print(f"n: {params['n']}")
    print(f"q_weights shape: {params['q_weights'].shape}")
    print(f"q_weights range: [{params['q_weights'].min()}, {params['q_weights'].max()}]")
    print(f"q_biases range: [{params['q_biases'].min()}, {params['q_biases'].max()}]")
    print()

    # Config
    IMG_H, IMG_W = 8, 8
    PAD = 1
    PADDED_H, PADDED_W = IMG_H + 2*PAD, IMG_W + 2*PAD
    CIN, CIN_PAD = 3, 8
    COUT = 16
    CO_GROUPS = 2
    SEED = 42

    OUT_DIR = os.path.join(SCRIPT_DIR, "stimulus_calibrated")
    os.makedirs(OUT_DIR, exist_ok=True)

    # Pad weights from (16, 3, 3, 3) to (16, 8, 3, 3)
    w_orig = params['q_weights']  # Shape: (16, 3, 3, 3) in OIHW
    w_int8 = np.zeros((COUT, CIN_PAD, 3, 3), dtype=np.int8)
    w_int8[:, :CIN, :, :] = w_orig

    # Biases already quantized
    b_int32 = params['q_biases']

    # Generate image scaled to int8 [0, 127]
    rng = np.random.RandomState(SEED)
    img_uint8 = rng.randint(0, 256, size=(IMG_H, IMG_W, CIN), dtype=np.uint8)
    img_scaled = np.round(img_uint8.astype(np.float64) / 255.0 * prev_scale).astype(np.int8)

    # Pad channels and spatial
    img_padded_ch = np.zeros((IMG_H, IMG_W, CIN_PAD), dtype=np.int8)
    img_padded_ch[:, :, :CIN] = img_scaled
    img = np.zeros((PADDED_H, PADDED_W, CIN_PAD), dtype=np.int8)
    img[PAD:PAD+IMG_H, PAD:PAD+IMG_W, :] = img_padded_ch

    print(f"Image shape: {img.shape}, range: [{img.min()}, {img.max()}]")

    # Compute reference for each output group
    M = params['M']
    n = params['n']

    for og in range(CO_GROUPS):
        print(f"\n--- Output Group {og} ---")

        # Reference conv (signed pixels, signed weights)
        out_h, out_w = PADDED_H - 2, PADDED_W - 2
        fstart = og * POUT
        conv_out = np.zeros((out_h, out_w, POUT), dtype=np.int64)

        for r in range(out_h):
            for c in range(out_w):
                for f in range(POUT):
                    acc = np.int64(0)
                    for ky in range(3):
                        for kx in range(3):
                            for ch in range(CIN_PAD):
                                pixel = np.int64(np.int8(img[r+ky, c+kx, ch]))
                                weight = np.int64(np.int8(w_int8[fstart+f, ch, ky, kx]))
                                acc += pixel * weight
                    acc += np.int64(b_int32[fstart + f])
                    conv_out[r, c, f] = acc

        print(f"Conv range: [{conv_out.min()}, {conv_out.max()}]")

        # Quantize: leaky FIRST, then multiply, then shift
        quant_out = np.zeros((out_h, out_w, POUT), dtype=np.int8)
        for r in range(out_h):
            for c in range(out_w):
                for f in range(POUT):
                    val = int(conv_out[r, c, f])
                    if val < 0:
                        val = val >> 3  # Leaky ReLU
                    val = (val * M) >> n
                    val = max(-128, min(127, val))
                    quant_out[r, c, f] = np.int8(val)

        print(f"Quant range: [{quant_out.min()}, {quant_out.max()}]")

        # Maxpool stride-2
        oh, ow = out_h // 2, out_w // 2
        mp_out = np.zeros((oh, ow, POUT), dtype=np.int8)
        for r in range(oh):
            for c in range(ow):
                for f in range(POUT):
                    vals = [int(quant_out[2*r+dy, 2*c+dx, f]) for dy in range(2) for dx in range(2)]
                    mp_out[r, c, f] = np.int8(max(vals))

        print(f"Maxpool shape: {mp_out.shape}, range: [{mp_out.min()}, {mp_out.max()}]")

        # Write hex files
        # Pixels
        with open(os.path.join(OUT_DIR, f"pixels_og{og}.hex"), "w") as f:
            for r in range(PADDED_H):
                for c in range(PADDED_W):
                    val = 0
                    for ch in range(8):
                        b = int(np.int8(img[r, c, ch])) & 0xFF
                        val |= b << (ch * 8)
                    f.write(f"{val:016x}\n")

        # Weights (72-bit)
        with open(os.path.join(OUT_DIR, f"weights_og{og}.hex"), "w") as f:
            for bank in range(8):
                filt = og * POUT + bank
                for uram in range(8):
                    ch = uram
                    val = 0
                    for s in range(9):
                        ky, kx = s // 3, s % 3
                        w = int(w_int8[filt, ch, ky, kx]) & 0xFF
                        val |= w << (s * 8)
                    f.write(f"{val:018x}\n")

        # Biases
        with open(os.path.join(OUT_DIR, f"biases_og{og}.hex"), "w") as f:
            for i in range(POUT):
                b = int(b_int32[fstart + i])
                if b < 0:
                    b = b & 0xFFFFFFFF
                f.write(f"{b:08x}\n")

        # Expected output
        with open(os.path.join(OUT_DIR, f"expected_og{og}.hex"), "w") as f:
            for r in range(oh):
                for c in range(ow):
                    val = 0
                    for ch in range(POUT):
                        b = int(np.int8(mp_out[r, c, ch])) & 0xFF
                        val |= b << (ch * 8)
                    f.write(f"{val:016x}\n")

    # Write quant params
    with open(os.path.join(OUT_DIR, "quant_params.txt"), "w") as f:
        f.write(f"# Layer 0 CALIBRATED quantization parameters\n")
        f.write(f"M=0x{M:08x}\n")
        f.write(f"n={n}\n")
        f.write(f"o_scale={params['o_scale']}\n")
        f.write(f"prev_scale={prev_scale}\n")

    print(f"\nFiles written to: {OUT_DIR}")
    return OUT_DIR


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--layer", type=int, default=0, help="Layer index")
    args = parser.parse_args()

    if args.layer == 0:
        generate_layer0_stimulus()
    else:
        print(f"Layer {args.layer} not yet implemented")
