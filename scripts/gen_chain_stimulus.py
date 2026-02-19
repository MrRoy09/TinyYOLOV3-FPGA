#!/usr/bin/env python3
"""
Generate calibrated stimulus for Layer 0 + Layer 2 chain test.

Uses quantized_params.npz from hardware_sim.py for exact INT8 accuracy.

Layer mapping:
- NPZ Layer 0: Conv 3->16 + MaxPool (produces 208x208x16)
- NPZ Layer 1: MaxPool (fused with conv in hardware)
- NPZ Layer 2: Conv 16->32 + MaxPool (produces 104x104x32)
- NPZ Layer 3: MaxPool (fused with conv in hardware)

Output directories:
- stimulus_l0_calib/  (for hardware layer 0)
- stimulus_l2_calib/  (for hardware layer 1 - which is NPZ layer 2)
"""

import numpy as np
import os
import struct

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
CALIB_FILE = os.path.join(SCRIPT_DIR, "..", "sim", "hardware-ai", "quantized_params.npz")

# Hardware constants
PIN = 8
POUT = 8


def load_calibrated_params(layer_idx):
    """Load calibrated parameters from NPZ."""
    data = np.load(CALIB_FILE, allow_pickle=True)

    params = {
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


def generate_layer0_stimulus(img_h=8, img_w=8, seed=42):
    """
    Generate Layer 0 stimulus (Conv 3->16 + MaxPool).

    Uses small image by default for quick testing.
    Set img_h=416, img_w=416 for full inference.
    """
    params, data = load_calibrated_params(0)
    input_scale = float(data['input_scale'])

    OUT_DIR = os.path.join(SCRIPT_DIR, "stimulus_l0_calib")
    os.makedirs(OUT_DIR, exist_ok=True)

    print("=" * 60)
    print("LAYER 0 CALIBRATED STIMULUS")
    print("=" * 60)
    print(f"Input: {img_h}x{img_w}x3")
    print(f"Output: {img_h//2}x{img_w//2}x16 (after maxpool)")
    print(f"M = 0x{params['M']:X} ({params['M']})")
    print(f"n = {params['n']}")
    print(f"o_scale = {params['o_scale']:.4f}")
    print(f"input_scale = {input_scale}")
    print()

    # Config
    PAD = 1
    PADDED_H, PADDED_W = img_h + 2*PAD, img_w + 2*PAD
    CIN, CIN_PAD = 3, 8
    COUT = 16
    CO_GROUPS = COUT // POUT  # 2

    # Get quantized weights (16, 3, 3, 3) -> pad to (16, 8, 3, 3)
    w_orig = params['q_weights']  # OIHW format
    w_int8 = np.zeros((COUT, CIN_PAD, 3, 3), dtype=np.int8)
    w_int8[:, :CIN, :, :] = w_orig

    # Get quantized biases
    b_int32 = params['q_biases'].astype(np.int32)

    print(f"Weights shape: {w_int8.shape}, range: [{w_int8.min()}, {w_int8.max()}]")
    print(f"Biases: {b_int32}")

    # Generate random image and scale to int8 [0, input_scale]
    rng = np.random.RandomState(seed)
    img_uint8 = rng.randint(0, 256, size=(img_h, img_w, CIN), dtype=np.uint8)
    # Scale to [0, input_scale] as signed int8
    img_scaled = np.round(img_uint8.astype(np.float64) / 255.0 * input_scale).astype(np.int8)

    # Pad channels (3 -> 8)
    img_padded_ch = np.zeros((img_h, img_w, CIN_PAD), dtype=np.int8)
    img_padded_ch[:, :, :CIN] = img_scaled

    # Spatial padding for conv
    img = np.zeros((PADDED_H, PADDED_W, CIN_PAD), dtype=np.int8)
    img[PAD:PAD+img_h, PAD:PAD+img_w, :] = img_padded_ch

    print(f"Padded image: {img.shape}, range: [{img.min()}, {img.max()}]")

    # Get quantization params
    M = params['M']
    n = params['n']

    # Compute reference for each output group
    all_mp_outputs = []

    for og in range(CO_GROUPS):
        print(f"\n--- Output Group {og} ---")

        # Reference conv
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
                        val = val >> 3  # Leaky ReLU (arithmetic shift)
                    val = (val * M) >> n
                    val = max(-128, min(127, val))
                    quant_out[r, c, f] = np.int8(val)

        print(f"Quant range: [{quant_out.min()}, {quant_out.max()}]")

        # MaxPool stride-2
        oh, ow = out_h // 2, out_w // 2
        mp_out = np.zeros((oh, ow, POUT), dtype=np.int8)
        for r in range(oh):
            for c in range(ow):
                for f in range(POUT):
                    vals = [int(quant_out[2*r+dy, 2*c+dx, f]) for dy in range(2) for dx in range(2)]
                    mp_out[r, c, f] = np.int8(max(vals))

        print(f"MaxPool shape: {mp_out.shape}, range: [{mp_out.min()}, {mp_out.max()}]")
        all_mp_outputs.append(mp_out)

        # ====== Write stimulus files ======

        # Pixels (64-bit words, 8 channels packed)
        with open(os.path.join(OUT_DIR, f"pixels_og{og}.hex"), "w") as fh:
            for r in range(PADDED_H):
                for c in range(PADDED_W):
                    val = 0
                    for ch in range(8):
                        b = int(np.int8(img[r, c, ch])) & 0xFF
                        val |= b << (ch * 8)
                    fh.write(f"{val:016x}\n")

        # Binary pixels
        pixel_bytes = img.flatten().astype(np.int8).tobytes()
        with open(os.path.join(OUT_DIR, "pixels.bin"), "wb") as fb:
            fb.write(pixel_bytes)

        # Weights (72-bit per URAM entry: 9 spatial × 8-bit)
        with open(os.path.join(OUT_DIR, f"weights_og{og}.hex"), "w") as fh:
            for bank in range(8):
                filt = og * POUT + bank
                for uram in range(8):
                    ch = uram
                    val = 0
                    for s in range(9):
                        ky, kx = s // 3, s % 3
                        w = int(w_int8[filt, ch, ky, kx]) & 0xFF
                        val |= w << (s * 8)
                    fh.write(f"{val:018x}\n")

        # Binary weights (for AXI - 128-bit aligned, only lower 72 bits used)
        weight_bytes = bytearray()
        for bank in range(8):
            filt = og * POUT + bank
            for uram in range(8):
                ch = uram
                val = 0
                for s in range(9):
                    ky, kx = s // 3, s % 3
                    w = int(w_int8[filt, ch, ky, kx]) & 0xFF
                    val |= w << (s * 8)
                # Pack as 16 bytes (128-bit), lower 9 bytes are weights
                weight_bytes.extend(val.to_bytes(16, 'little'))
        with open(os.path.join(OUT_DIR, f"weights_og{og}.bin"), "wb") as fb:
            fb.write(weight_bytes)

        # Biases (32-bit each, packed to 128-bit for AXI)
        with open(os.path.join(OUT_DIR, f"biases_og{og}.hex"), "w") as fh:
            for i in range(POUT):
                b = int(b_int32[fstart + i])
                if b < 0:
                    b = b & 0xFFFFFFFF
                fh.write(f"{b:08x}\n")

        # Binary biases (packed 4 per 128-bit word)
        bias_bytes = bytearray()
        for i in range(0, POUT, 4):
            word_128 = 0
            for j in range(4):
                if i + j < POUT:
                    b = int(b_int32[fstart + i + j]) & 0xFFFFFFFF
                    word_128 |= b << (j * 32)
            bias_bytes.extend(word_128.to_bytes(16, 'little'))
        with open(os.path.join(OUT_DIR, f"biases_og{og}.bin"), "wb") as fb:
            fb.write(bias_bytes)

        # Expected output (64-bit words)
        with open(os.path.join(OUT_DIR, f"expected_og{og}.hex"), "w") as fh:
            for r in range(oh):
                for c in range(ow):
                    val = 0
                    for ch in range(POUT):
                        b = int(np.int8(mp_out[r, c, ch])) & 0xFF
                        val |= b << (ch * 8)
                    fh.write(f"{val:016x}\n")

        # Binary expected
        exp_bytes = mp_out.flatten().astype(np.int8).tobytes()
        with open(os.path.join(OUT_DIR, f"expected_og{og}.bin"), "wb") as fb:
            fb.write(exp_bytes)

    # Write quant params (SAME M for all output groups - per-layer quantization)
    with open(os.path.join(OUT_DIR, "quant_params.txt"), "w") as f:
        f.write(f"# Layer 0 CALIBRATED quantization (same M for all OGs)\n")
        for og in range(CO_GROUPS):
            f.write(f"og{og}: M=0x{M:08x} n={n}\n")

    # Combine all OG outputs into full layer output
    full_output = np.concatenate(all_mp_outputs, axis=2)  # (oh, ow, 16)
    print(f"\nFull layer 0 output: {full_output.shape}")

    # Save for layer 2 input
    np.save(os.path.join(OUT_DIR, "layer0_output.npy"), full_output)

    print(f"\nFiles written to: {OUT_DIR}")
    return full_output, params['o_scale']


def generate_layer2_stimulus(layer0_output, prev_scale, img_h=4, img_w=4):
    """
    Generate Layer 2 stimulus (Conv 16->32 + MaxPool).

    Uses layer 0 output as input.
    """
    params, data = load_calibrated_params(2)

    OUT_DIR = os.path.join(SCRIPT_DIR, "stimulus_l2_calib")
    os.makedirs(OUT_DIR, exist_ok=True)

    print("\n" + "=" * 60)
    print("LAYER 2 CALIBRATED STIMULUS")
    print("=" * 60)
    print(f"Input: {img_h}x{img_w}x16 (from layer 0 output)")
    print(f"Output: {img_h//2}x{img_w//2}x32 (after maxpool)")
    print(f"M = 0x{params['M']:X} ({params['M']})")
    print(f"n = {params['n']}")
    print(f"o_scale = {params['o_scale']:.4f}")
    print(f"prev_scale (layer 0 o_scale) = {prev_scale:.4f}")
    print()

    # Config
    PAD = 1
    PADDED_H, PADDED_W = img_h + 2*PAD, img_w + 2*PAD
    CIN = 16
    CIN_PAD = 16  # No padding needed
    CI_GROUPS = CIN_PAD // PIN  # 2
    COUT = 32
    CO_GROUPS = COUT // POUT  # 4

    # Get quantized weights (32, 16, 3, 3)
    w_int8 = params['q_weights'].astype(np.int8)

    # Get quantized biases
    b_int32 = params['q_biases'].astype(np.int32)

    print(f"Weights shape: {w_int8.shape}, range: [{w_int8.min()}, {w_int8.max()}]")
    print(f"Biases shape: {b_int32.shape}, range: [{b_int32.min()}, {b_int32.max()}]")

    # Use layer 0 output (already int8)
    img_input = layer0_output[:img_h, :img_w, :].astype(np.int8)

    # Spatial padding for conv
    img = np.zeros((PADDED_H, PADDED_W, CIN_PAD), dtype=np.int8)
    img[PAD:PAD+img_h, PAD:PAD+img_w, :] = img_input

    print(f"Padded image: {img.shape}, range: [{img.min()}, {img.max()}]")

    # Get quantization params
    M = params['M']
    n = params['n']

    # Compute reference for each output group
    all_mp_outputs = []

    for og in range(CO_GROUPS):
        print(f"\n--- Output Group {og} ---")

        # Reference conv
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

        # MaxPool stride-2
        oh, ow = out_h // 2, out_w // 2
        mp_out = np.zeros((oh, ow, POUT), dtype=np.int8)
        for r in range(oh):
            for c in range(ow):
                for f in range(POUT):
                    vals = [int(quant_out[2*r+dy, 2*c+dx, f]) for dy in range(2) for dx in range(2)]
                    mp_out[r, c, f] = np.int8(max(vals))

        print(f"MaxPool shape: {mp_out.shape}, range: [{mp_out.min()}, {mp_out.max()}]")
        all_mp_outputs.append(mp_out)

        # ====== Write stimulus files ======

        # Pixels - need to handle CI_GROUPS (2 groups of 8 channels)
        with open(os.path.join(OUT_DIR, f"pixels_og{og}.hex"), "w") as fh:
            for r in range(PADDED_H):
                for c in range(PADDED_W):
                    for cig in range(CI_GROUPS):
                        val = 0
                        for ch in range(8):
                            b = int(np.int8(img[r, c, cig*8 + ch])) & 0xFF
                            val |= b << (ch * 8)
                        fh.write(f"{val:016x}\n")

        # Binary pixels (for all OGs - same input)
        pixel_bytes = img.flatten().astype(np.int8).tobytes()
        with open(os.path.join(OUT_DIR, "pixels.bin"), "wb") as fb:
            fb.write(pixel_bytes)

        # Weights (72-bit per URAM entry) - for CI_GROUPS addresses
        with open(os.path.join(OUT_DIR, f"weights_og{og}.hex"), "w") as fh:
            for addr in range(CI_GROUPS):
                for bank in range(8):
                    filt = og * POUT + bank
                    for uram in range(8):
                        ch = addr * 8 + uram
                        val = 0
                        for s in range(9):
                            ky, kx = s // 3, s % 3
                            w = int(w_int8[filt, ch, ky, kx]) & 0xFF
                            val |= w << (s * 8)
                        fh.write(f"{val:018x}\n")

        # Binary weights
        weight_bytes = bytearray()
        for addr in range(CI_GROUPS):
            for bank in range(8):
                filt = og * POUT + bank
                for uram in range(8):
                    ch = addr * 8 + uram
                    val = 0
                    for s in range(9):
                        ky, kx = s // 3, s % 3
                        w = int(w_int8[filt, ch, ky, kx]) & 0xFF
                        val |= w << (s * 8)
                    weight_bytes.extend(val.to_bytes(16, 'little'))
        with open(os.path.join(OUT_DIR, f"weights_og{og}.bin"), "wb") as fb:
            fb.write(weight_bytes)

        # Biases
        with open(os.path.join(OUT_DIR, f"biases_og{og}.hex"), "w") as fh:
            for i in range(POUT):
                b = int(b_int32[fstart + i])
                if b < 0:
                    b = b & 0xFFFFFFFF
                fh.write(f"{b:08x}\n")

        # Binary biases
        bias_bytes = bytearray()
        for i in range(0, POUT, 4):
            word_128 = 0
            for j in range(4):
                if i + j < POUT:
                    b = int(b_int32[fstart + i + j]) & 0xFFFFFFFF
                    word_128 |= b << (j * 32)
            bias_bytes.extend(word_128.to_bytes(16, 'little'))
        with open(os.path.join(OUT_DIR, f"biases_og{og}.bin"), "wb") as fb:
            fb.write(bias_bytes)

        # Expected output
        with open(os.path.join(OUT_DIR, f"expected_og{og}.hex"), "w") as fh:
            for r in range(oh):
                for c in range(ow):
                    val = 0
                    for ch in range(POUT):
                        b = int(np.int8(mp_out[r, c, ch])) & 0xFF
                        val |= b << (ch * 8)
                    fh.write(f"{val:016x}\n")

        # Binary expected
        exp_bytes = mp_out.flatten().astype(np.int8).tobytes()
        with open(os.path.join(OUT_DIR, f"expected_og{og}.bin"), "wb") as fb:
            fb.write(exp_bytes)

    # Write quant params
    with open(os.path.join(OUT_DIR, "quant_params.txt"), "w") as f:
        f.write(f"# Layer 2 CALIBRATED quantization (same M for all OGs)\n")
        for og in range(CO_GROUPS):
            f.write(f"og{og}: M=0x{M:08x} n={n}\n")

    # Combine outputs
    full_output = np.concatenate(all_mp_outputs, axis=2)
    print(f"\nFull layer 2 output: {full_output.shape}")

    np.save(os.path.join(OUT_DIR, "layer2_output.npy"), full_output)

    print(f"\nFiles written to: {OUT_DIR}")
    return full_output


def main():
    import argparse
    parser = argparse.ArgumentParser(description="Generate calibrated stimulus for layer chain")
    parser.add_argument("--img_h", type=int, default=8, help="Image height (default: 8, use 416 for full)")
    parser.add_argument("--img_w", type=int, default=8, help="Image width (default: 8, use 416 for full)")
    parser.add_argument("--seed", type=int, default=42, help="Random seed")
    args = parser.parse_args()

    print("Generating calibrated stimulus for Layer 0 + Layer 2 chain\n")

    # Generate Layer 0 stimulus
    l0_output, l0_o_scale = generate_layer0_stimulus(args.img_h, args.img_w, args.seed)

    # Generate Layer 2 stimulus using Layer 0 output
    l2_img_h = args.img_h // 2  # After maxpool
    l2_img_w = args.img_w // 2
    generate_layer2_stimulus(l0_output, l0_o_scale, l2_img_h, l2_img_w)

    print("\n" + "=" * 60)
    print("DONE! Generated calibrated stimulus for chain test.")
    print("=" * 60)
    print("\nNext steps:")
    print("1. Copy stimulus_l0_calib/ and stimulus_l2_calib/ to KV260")
    print("2. Run: ./test_layer01_chain <xclbin> stimulus_l0_calib stimulus_l2_calib")


if __name__ == "__main__":
    main()
