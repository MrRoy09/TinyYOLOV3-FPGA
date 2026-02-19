#!/usr/bin/env python3
"""
Generate stimulus files for end-to-end conv_top verification using
YOLOv3-tiny layer 1 weights on a small 4x4 synthetic image.

This script matches hardware_sim.py quantization:
- Signed int8 pixels
- Leaky ReLU applied BEFORE quantization (on accumulator)
- Per-layer quantization (same M for all output groups)
- Biases scaled by (input_scale * w_scale)

Layer 1: 16->32 channels, 3x3 conv, batch_norm, leaky ReLU, maxpool stride-2
Hardware: Pin=8 (Cin=16, no padding needed), Pout=8, ci_groups=2, co_groups=4

Output: scripts/stimulus_l1/*.hex files for $readmemh in tb_conv_top_e2e_l1.sv
"""

import numpy as np
import struct
import os

# ──────────────────────────────────────────────────────────
#  Config
# ──────────────────────────────────────────────────────────
IMG_H, IMG_W = 4, 4
PAD = 1
PADDED_H = IMG_H + 2 * PAD   # 6
PADDED_W = IMG_W + 2 * PAD   # 6
CIN = 16
CIN_PAD = 16  # no padding needed
CI_GROUPS = 2
COUT = 32
CO_GROUPS = 4
POUT = 8
SEED = 42

# Input scale for layer 1 (output scale from layer 0)
# For simplicity, assume layer 0 output is already in a good int8 range
INPUT_SCALE = 1.0  # Layer 1 input is already quantized int8

WEIGHTS_PATH = os.path.join(os.path.dirname(os.path.abspath(__file__)), "yolov3-tiny.weights")
OUT_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "stimulus_l1")

# Layer 0 size: 16 biases + 16 scales + 16 means + 16 vars + 16*3*3*3 weights
# = 64 + 432 = 496 floats = 1984 bytes
LAYER0_FLOATS = 16 * 4 + 16 * 3 * 3 * 3  # 496


def load_layer1_weights(path):
    with open(path, "rb") as f:
        major, minor, revision = struct.unpack("3i", f.read(12))
        images_seen = struct.unpack("q", f.read(8))[0]
        print(f"Weights header: v{major}.{minor}.{revision}, images_seen={images_seen}")

        # Skip layer 0 data
        f.read(4 * LAYER0_FLOATS)

        # Read layer 1
        n_filters, n_cin = 32, 16
        biases = np.array(struct.unpack(f"{n_filters}f", f.read(4 * n_filters)))
        scales = np.array(struct.unpack(f"{n_filters}f", f.read(4 * n_filters)))
        means  = np.array(struct.unpack(f"{n_filters}f", f.read(4 * n_filters)))
        variances = np.array(struct.unpack(f"{n_filters}f", f.read(4 * n_filters)))
        n_weights = n_filters * n_cin * 3 * 3
        weights = np.array(struct.unpack(f"{n_weights}f", f.read(4 * n_weights)))
        weights = weights.reshape(n_filters, n_cin, 3, 3)  # OIHW

    return biases, scales, means, variances, weights


def fold_bn(weights, biases, scales, means, variances, eps=1e-5):
    scale_factor = scales / np.sqrt(variances + eps)
    w_folded = weights * scale_factor[:, None, None, None]
    b_folded = (biases - means) * scale_factor
    return w_folded, b_folded


def quantize_weights_biases_hwsim(w_folded, b_folded, prev_scale=1.0):
    """
    Quantize weights and biases matching hardware_sim.py approach.
    """
    # Per-layer weight scale (all filters use same scale)
    w_max = np.max(np.abs(w_folded))
    w_scale = 127.0 / w_max if w_max > 0 else 1.0

    # Quantize weights
    w_int8 = np.clip(np.round(w_folded * w_scale), -128, 127).astype(np.int8)

    # Quantize biases: scaled by (prev_scale * w_scale)
    b_int32 = np.round(b_folded * (prev_scale * w_scale)).astype(np.int32)

    # Compute M and n for quantization
    n = 16
    m_val = round(2**n / w_scale)
    while m_val > 0xFFFFFFFF:
        n -= 1
        m_val = round(2**n / w_scale)

    quant_m = m_val
    quant_n = n

    print(f"Per-layer weight scale: {w_scale:.6f}")
    print(f"Per-layer M=0x{quant_m:08x} ({quant_m}), n={quant_n}")
    print(f"Effective scale: {quant_m / 2**quant_n:.6f}, ideal: {1/w_scale:.6f}")

    return w_int8, b_int32, quant_m, quant_n, w_scale


def generate_image():
    """Generate synthetic image as signed int8."""
    rng = np.random.RandomState(SEED)
    # Generate random int8 values to simulate layer 0 output
    img = rng.randint(-128, 128, size=(IMG_H, IMG_W, CIN), dtype=np.int8)

    # Spatial padding for conv (1 pixel zero border)
    img_full = np.zeros((PADDED_H, PADDED_W, CIN_PAD), dtype=np.int8)
    img_full[PAD:PAD+IMG_H, PAD:PAD+IMG_W, :] = img

    return img_full  # (6, 6, 16) int8


def reference_conv(img, w_int8, b_int32, og):
    """Compute conv for one output group with signed int8 pixels."""
    out_h = PADDED_H - 2
    out_w = PADDED_W - 2
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
    """Match new RTL quantizer.sv: leaky FIRST, then quantize."""
    H, W, F = conv_out.shape
    result = np.zeros((H, W, F), dtype=np.int8)

    for r in range(H):
        for c in range(W):
            for f in range(F):
                val = int(conv_out[r, c, f])

                # Stage 1: Leaky ReLU FIRST (on accumulator)
                if use_relu and val < 0:
                    val = val >> 3

                # Stage 2: Multiply by M
                mult = val * int(M)

                # Stage 3: Shift by n
                shifted = mult >> int(n)

                # Stage 4: Clamp to INT8
                shifted = max(-128, min(127, shifted))
                result[r, c, f] = np.int8(shifted)

    return result


def reference_maxpool(quant_out):
    """Match RTL maxPool.sv: 2x2 stride-2, signed INT8 comparison."""
    H, W, F = quant_out.shape
    oh, ow = H // 2, W // 2
    result = np.zeros((oh, ow, F), dtype=np.int8)

    for r in range(oh):
        for c in range(ow):
            for f in range(F):
                vals = [
                    int(np.int8(quant_out[2*r,   2*c,   f])),
                    int(np.int8(quant_out[2*r,   2*c+1, f])),
                    int(np.int8(quant_out[2*r+1, 2*c,   f])),
                    int(np.int8(quant_out[2*r+1, 2*c+1, f])),
                ]
                result[r, c, f] = np.int8(max(vals))

    return result


# ──────────────────────────────────────────────────────────
#  Hex file generation
# ──────────────────────────────────────────────────────────
def write_hex(path, words, width_bits):
    hex_w = (width_bits + 3) // 4
    with open(path, "w") as f:
        for w in words:
            if w < 0:
                w = w & ((1 << width_bits) - 1)
            f.write(f"{w:0{hex_w}x}\n")


def pack_pixel_stream(img):
    """Pack (6,6,16) int8 → list of 64-bit words (2 per spatial position)."""
    words = []
    for r in range(PADDED_H):
        for c in range(PADDED_W):
            for cig in range(CI_GROUPS):
                val = 0
                for ch in range(8):
                    b = int(np.int8(img[r, c, cig * 8 + ch]))
                    if b < 0:
                        b = b & 0xFF
                    val |= b << (ch * 8)
                words.append(val)
    return words


def pack_weight_stream(w_int8, og):
    """Pack weights for one output group in addr→bank→uram order (72-bit words)."""
    words = []
    for addr in range(CI_GROUPS):
        for bank in range(8):
            f = og * POUT + bank
            for uram in range(8):
                ch = addr * 8 + uram
                val = 0
                for spatial_idx in range(9):
                    ky = spatial_idx // 3
                    kx = spatial_idx % 3
                    w_byte = int(w_int8[f, ch, ky, kx])
                    if w_byte < 0:
                        w_byte = w_byte & 0xFF
                    val |= w_byte << (spatial_idx * 8)
                words.append(val)
    return words


def pack_all_biases(b_int32):
    """Pack all 32 biases as 128-bit words for bias_store DMA."""
    words = []
    for i in range(0, COUT, 4):
        val = 0
        for j in range(4):
            b = int(b_int32[i + j])
            if b < 0:
                b = b & 0xFFFFFFFF
            val |= b << (j * 32)
        words.append(val)
    return words


def pack_maxpool_output(mp_out):
    """Pack (2,2,8) int8 maxpool output as 64-bit words."""
    words = []
    oh, ow, _ = mp_out.shape
    for r in range(oh):
        for c in range(ow):
            val = 0
            for ch in range(8):
                b = int(np.int8(mp_out[r, c, ch]))
                if b < 0:
                    b = b & 0xFF
                val |= b << (ch * 8)
            words.append(val)
    return words


def pack_quant_output(q_out):
    """Pack (4,4,8) int8 quant output as 64-bit words."""
    words = []
    H, W, _ = q_out.shape
    for r in range(H):
        for c in range(W):
            val = 0
            for ch in range(8):
                b = int(np.int8(q_out[r, c, ch]))
                if b < 0:
                    b = b & 0xFF
                val |= b << (ch * 8)
            words.append(val)
    return words


# ──────────────────────────────────────────────────────────
#  Main
# ──────────────────────────────────────────────────────────
if __name__ == "__main__":
    os.makedirs(OUT_DIR, exist_ok=True)

    print("=== Loading weights ===")
    biases, scales, means, variances, weights = load_layer1_weights(WEIGHTS_PATH)

    print("\n=== Folding BN ===")
    w_folded, b_folded = fold_bn(weights, biases, scales, means, variances)
    print(f"W_folded range: [{w_folded.min():.3f}, {w_folded.max():.3f}]")
    print(f"B_folded range: [{b_folded.min():.3f}, {b_folded.max():.3f}]")

    print("\n=== Quantizing (hardware_sim.py style) ===")
    w_int8, b_int32, quant_m, quant_n, w_scale = quantize_weights_biases_hwsim(w_folded, b_folded)
    print(f"W_int8 range: [{w_int8.min()}, {w_int8.max()}]")
    print(f"B_int32 range: [{b_int32.min()}, {b_int32.max()}]")

    print("\n=== Generating image (int8) ===")
    img = generate_image()
    print(f"Image shape: {img.shape}, dtype: {img.dtype}")
    print(f"Pixel range: [{img.min()}, {img.max()}]")

    print("\n=== Computing references ===")
    for og in range(CO_GROUPS):
        print(f"\n--- Output Group {og} ---")
        conv_out = reference_conv(img, w_int8, b_int32, og)
        print(f"Conv out range: [{conv_out.min()}, {conv_out.max()}]")

        quant_out = reference_quantize(conv_out, quant_m, quant_n, use_relu=True)
        print(f"Quant out range: [{quant_out.min()}, {quant_out.max()}]")

        mp_out = reference_maxpool(quant_out)
        print(f"Maxpool out range: [{mp_out.min()}, {mp_out.max()}]")
        print(f"Maxpool out shape: {mp_out.shape}")

        # Dump intermediate for debugging
        print(f"Conv[0,0,:] = {conv_out[0, 0, :]}")
        print(f"Quant[0,0,:] = {quant_out[0, 0, :]}")
        print(f"Maxpool[0,0,:] = {mp_out[0, 0, :]}")

        # Write files
        pixel_words = pack_pixel_stream(img)
        write_hex(os.path.join(OUT_DIR, f"pixels_og{og}.hex"), pixel_words, 64)

        wt_words = pack_weight_stream(w_int8, og)
        write_hex(os.path.join(OUT_DIR, f"weights_og{og}.hex"), wt_words, 72)

        mp_words = pack_maxpool_output(mp_out)
        write_hex(os.path.join(OUT_DIR, f"expected_og{og}.hex"), mp_words, 64)

        # Also dump quant output (pre-maxpool) for debugging
        q_words = pack_quant_output(quant_out)
        write_hex(os.path.join(OUT_DIR, f"quant_og{og}.hex"), q_words, 64)

    # Write all biases as 128-bit words for bias_store DMA
    all_bias_words = pack_all_biases(b_int32)
    write_hex(os.path.join(OUT_DIR, "biases_all.hex"), all_bias_words, 128)

    # Write quant params
    with open(os.path.join(OUT_DIR, "quant_params.txt"), "w") as f:
        f.write(f"# Per-layer quantization (matching hardware_sim.py)\n")
        f.write(f"M=0x{quant_m:08x}\n")
        f.write(f"n={quant_n}\n")

    print(f"\n=== Files written to {OUT_DIR} ===")
    for fn in sorted(os.listdir(OUT_DIR)):
        fp = os.path.join(OUT_DIR, fn)
        print(f"  {fn}: {os.path.getsize(fp)} bytes")
