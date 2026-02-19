#!/usr/bin/env python3
"""
Generate stimulus files for tb_conv_top_e2e using quantized_params.npz.

This uses the EXACT same weights, biases, and quantization parameters
as hardware_sim.py to ensure RTL matches the golden model.

Layer 0: 3->16 channels, 3x3 conv, leaky ReLU, maxpool stride-2
Hardware: Pin=8 (pad Cin=3 to 8), Pout=8, ci_groups=1, co_groups=2

Output: scripts/stimulus/*.hex files for $readmemh in tb_conv_top_e2e.sv
"""

import numpy as np
import os

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
NPZ_FILE = os.path.join(SCRIPT_DIR, "..", "sim", "hardware-ai", "quantized_params.npz")
OUT_DIR = os.path.join(SCRIPT_DIR, "stimulus")

# Test image config (small for fast simulation)
IMG_H, IMG_W = 8, 8
PAD = 1
PADDED_H = IMG_H + 2 * PAD  # 10
PADDED_W = IMG_W + 2 * PAD  # 10
CIN = 3
CIN_PAD = 8
COUT = 16
CO_GROUPS = 2
POUT = 8
SEED = 42


def load_npz():
    """Load quantized parameters from hardware_sim.py's NPZ file."""
    data = np.load(NPZ_FILE, allow_pickle=True)

    q_weights = data['l0_q_weights']  # (16, 3, 3, 3) int8
    q_biases = data['l0_q_biases']    # (16,) int32
    M = int(data['l0_M'])
    n = int(data['l0_n'])
    input_scale = float(data['input_scale'])

    print(f"Loaded from quantized_params.npz:")
    print(f"  Weights: {q_weights.shape}, dtype={q_weights.dtype}")
    print(f"  Biases: {q_biases.shape}, dtype={q_biases.dtype}")
    print(f"  M=0x{M:X} ({M}), n={n}")
    print(f"  input_scale={input_scale}")

    return q_weights, q_biases, M, n, input_scale


def pad_weights(q_weights):
    """Pad weights from Cin=3 to Cin_pad=8."""
    w_padded = np.zeros((COUT, CIN_PAD, 3, 3), dtype=np.int8)
    w_padded[:, :CIN, :, :] = q_weights
    return w_padded


def generate_image(input_scale):
    """Generate 8x8 test image scaled to signed int8."""
    rng = np.random.RandomState(SEED)

    # Generate uint8 [0, 255] image
    img_uint8 = rng.randint(0, 256, size=(IMG_H, IMG_W, CIN), dtype=np.uint8)

    # Scale to signed int8 matching hardware_sim.py:
    # blob = cv2.dnn.blobFromImage(img, 1/255.0, ...) gives [0, 1]
    # current_data = np.round(blob * input_scale).astype(np.int8) gives [0, input_scale]
    img_scaled = np.round(img_uint8.astype(np.float64) / 255.0 * input_scale).astype(np.int8)

    # Pad channels from 3 to 8
    img_padded_ch = np.zeros((IMG_H, IMG_W, CIN_PAD), dtype=np.int8)
    img_padded_ch[:, :, :CIN] = img_scaled

    # Spatial padding for conv (1 pixel zero border)
    img_full = np.zeros((PADDED_H, PADDED_W, CIN_PAD), dtype=np.int8)
    img_full[PAD:PAD+IMG_H, PAD:PAD+IMG_W, :] = img_padded_ch

    return img_full  # (10, 10, 8) int8


def reference_conv(img, w_int8, b_int32, og):
    """Compute convolution for one output group."""
    out_h = PADDED_H - 2  # 8
    out_w = PADDED_W - 2  # 8
    fstart = og * POUT
    result = np.zeros((out_h, out_w, POUT), dtype=np.int64)

    for r in range(out_h):
        for c in range(out_w):
            for f in range(POUT):
                acc = np.int64(0)
                for ky in range(3):
                    for kx in range(3):
                        for ch in range(CIN_PAD):
                            pixel = np.int64(np.int8(img[r + ky, c + kx, ch]))
                            weight = np.int64(np.int8(w_int8[fstart + f, ch, ky, kx]))
                            acc += pixel * weight
                acc += np.int64(b_int32[fstart + f])
                result[r, c, f] = acc

    return result.astype(np.int32)


def reference_quantize(conv_out, M, n, use_relu=True):
    """
    Apply leaky ReLU and quantization matching hardware_sim.py:
    1. Leaky ReLU: if negative, divide by 8 (arithmetic shift right by 3)
    2. Quantize: (val * M) >> n
    3. Clamp to int8 [-128, 127]
    """
    result = conv_out.astype(np.int64)

    if use_relu:
        # Leaky ReLU: negative values divided by 8
        result = np.where(result >= 0, result, result >> 3)

    # Quantize
    result = (result * M) >> n

    # Clamp to int8
    result = np.clip(result, -128, 127).astype(np.int8)

    return result


def reference_maxpool(quant_out):
    """2x2 max pooling with stride 2."""
    h, w, c = quant_out.shape
    out_h, out_w = h // 2, w // 2
    result = np.zeros((out_h, out_w, c), dtype=np.int8)

    for r in range(out_h):
        for c_idx in range(out_w):
            for ch in range(c):
                vals = [
                    quant_out[r*2, c_idx*2, ch],
                    quant_out[r*2, c_idx*2+1, ch],
                    quant_out[r*2+1, c_idx*2, ch],
                    quant_out[r*2+1, c_idx*2+1, ch]
                ]
                result[r, c_idx, ch] = max(vals)

    return result


def pack_weights_hex(w_int8, og):
    """Pack weights for one output group in hardware format (72-bit words)."""
    lines = []
    fstart = og * POUT

    # Hardware expects: for each (filter, channel) pair, pack 9 spatial weights
    # Entry order: bank (filter) varies slower, uram (channel) varies faster
    for bank in range(POUT):  # 8 filters
        filt = fstart + bank
        for uram in range(CIN_PAD):  # 8 channels
            val = 0
            for s in range(9):
                ky, kx = s // 3, s % 3
                w = int(w_int8[filt, uram, ky, kx]) & 0xFF
                val |= w << (s * 8)
            lines.append(f"{val:018x}")

    return lines


def pack_biases_hex(b_int32, og):
    """Pack biases for one output group (32-bit per bias)."""
    lines = []
    fstart = og * POUT
    for f in range(POUT):
        val = int(b_int32[fstart + f]) & 0xFFFFFFFF
        lines.append(f"{val:08x}")
    return lines


def pack_biases_all_hex(b_int32):
    """Pack all 16 biases as 128-bit words (4 biases per word)."""
    lines = []
    for i in range(0, COUT, 4):
        word = 0
        for j in range(4):
            if i + j < COUT:
                val = int(b_int32[i + j]) & 0xFFFFFFFF
                word |= val << (j * 32)
        lines.append(f"{word:032x}")
    return lines


def pack_pixels_hex(img):
    """Pack pixels as 64-bit words (8 channels per word)."""
    lines = []
    for r in range(PADDED_H):
        for c in range(PADDED_W):
            val = 0
            for ch in range(CIN_PAD):
                byte_val = int(img[r, c, ch]) & 0xFF
                val |= byte_val << (ch * 8)
            lines.append(f"{val:016x}")
    return lines


def pack_expected_hex(maxpool_out):
    """Pack expected maxpool output as 64-bit words."""
    lines = []
    h, w, c = maxpool_out.shape
    for r in range(h):
        for c_idx in range(w):
            val = 0
            for ch in range(c):
                byte_val = int(maxpool_out[r, c_idx, ch]) & 0xFF
                val |= byte_val << (ch * 8)
            lines.append(f"{val:016x}")
    return lines


def write_hex(path, lines):
    """Write hex lines to file."""
    with open(path, 'w') as f:
        for line in lines:
            f.write(line + '\n')
    print(f"  {os.path.basename(path)}: {len(lines)} lines")


def main():
    os.makedirs(OUT_DIR, exist_ok=True)

    print("=" * 60)
    print("Generating stimulus from quantized_params.npz")
    print("(Matches hardware_sim.py golden model exactly)")
    print("=" * 60)
    print()

    # Load NPZ parameters
    q_weights, q_biases, M, n, input_scale = load_npz()

    # Pad weights
    w_padded = pad_weights(q_weights)
    print(f"Padded weights: {w_padded.shape}")
    print()

    # Generate test image
    img = generate_image(input_scale)
    print(f"Generated {IMG_H}x{IMG_W} test image (padded to {PADDED_H}x{PADDED_W}x{CIN_PAD})")
    print()

    # Process each output group
    for og in range(CO_GROUPS):
        print(f"--- Output Group {og} ---")

        # Reference computation
        conv_out = reference_conv(img, w_padded, q_biases, og)
        print(f"Conv out range: [{conv_out.min()}, {conv_out.max()}]")

        quant_out = reference_quantize(conv_out, M, n)
        print(f"Quant out range: [{quant_out.min()}, {quant_out.max()}]")

        maxpool_out = reference_maxpool(quant_out)
        print(f"Maxpool out range: [{maxpool_out.min()}, {maxpool_out.max()}]")
        print(f"Maxpool shape: {maxpool_out.shape}")

        # Sample outputs for verification
        print(f"Conv[0,0,:] = {conv_out[0,0,:]}")
        print(f"Quant[0,0,:] = {quant_out[0,0,:]}")
        print(f"Maxpool[0,0,:] = {maxpool_out[0,0,:]}")
        print()

        # Write hex files
        write_hex(os.path.join(OUT_DIR, f"weights_og{og}.hex"), pack_weights_hex(w_padded, og))
        write_hex(os.path.join(OUT_DIR, f"biases_og{og}.hex"), pack_biases_hex(q_biases, og))
        write_hex(os.path.join(OUT_DIR, f"pixels_og{og}.hex"), pack_pixels_hex(img))
        write_hex(os.path.join(OUT_DIR, f"expected_og{og}.hex"), pack_expected_hex(maxpool_out))

        # Also save intermediate values for debugging
        quant_lines = pack_expected_hex(quant_out)
        write_hex(os.path.join(OUT_DIR, f"quant_og{og}.hex"), quant_lines)

    # Write combined biases file
    write_hex(os.path.join(OUT_DIR, "biases_all.hex"), pack_biases_all_hex(q_biases))

    # Write quant params
    with open(os.path.join(OUT_DIR, "quant_params.txt"), 'w') as f:
        f.write(f"# From quantized_params.npz (hardware_sim.py golden)\n")
        f.write(f"M=0x{M:08x}\n")
        f.write(f"n={n}\n")
        f.write(f"input_scale={input_scale}\n")
    print(f"  quant_params.txt")

    print()
    print("=" * 60)
    print(f"Files written to {OUT_DIR}")
    print(f"Using M=0x{M:X}, n={n} (from quantized_params.npz)")
    print("=" * 60)


if __name__ == "__main__":
    main()
