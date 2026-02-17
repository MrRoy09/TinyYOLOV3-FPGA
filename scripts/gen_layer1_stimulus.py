#!/usr/bin/env python3
"""
Generate stimulus files for end-to-end conv_top verification using
YOLOv3-tiny layer 1 weights on a small 4x4 synthetic image.

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


def quantize_weights_biases(w_folded, b_folded):
    w_int8 = np.zeros((COUT, CIN_PAD, 3, 3), dtype=np.int8)
    b_int32 = np.zeros(COUT, dtype=np.int32)
    quant_m = np.zeros(CO_GROUPS, dtype=np.uint64)
    quant_n = np.zeros(CO_GROUPS, dtype=np.int32)
    w_scales = np.zeros(CO_GROUPS, dtype=np.float64)

    for og in range(CO_GROUPS):
        fs, fe = og * POUT, (og + 1) * POUT
        w_og = w_folded[fs:fe]
        w_max = np.max(np.abs(w_og))
        w_scale = 127.0 / w_max if w_max > 0 else 1.0
        w_scales[og] = w_scale

        w_int8[fs:fe] = np.clip(np.round(w_og * w_scale), -128, 127).astype(np.int8)
        b_int32[fs:fe] = np.round(b_folded[fs:fe] * w_scale).astype(np.int32)

        n = 16
        m_val = round(2**n / w_scale)
        while m_val > 0xFFFFFFFF:
            n -= 1
            m_val = round(2**n / w_scale)
        quant_m[og] = m_val
        quant_n[og] = n

    print(f"Weight scales: {w_scales}")
    print(f"Quant M: {quant_m}")
    print(f"Quant n: {quant_n}")
    for og in range(CO_GROUPS):
        print(f"  OG{og}: M={quant_m[og]}, n={quant_n[og]}, effective_scale={quant_m[og]/2**quant_n[og]:.6f}, ideal={1/w_scales[og]:.6f}")

    return w_int8, b_int32, quant_m, quant_n, w_scales


def generate_image():
    rng = np.random.RandomState(SEED)
    img = rng.randint(0, 256, size=(IMG_H, IMG_W, CIN), dtype=np.uint8)
    # No channel padding needed (CIN == CIN_PAD)
    img_full = np.zeros((PADDED_H, PADDED_W, CIN_PAD), dtype=np.uint8)
    img_full[PAD:PAD+IMG_H, PAD:PAD+IMG_W, :] = img
    return img_full  # (6, 6, 16) uint8


def reference_conv(img, w_int8, b_int32, og):
    """Compute conv for one output group matching RTL conv_pe arithmetic."""
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
                            pixel = np.int64(img[r + ky, c + kx, ch])
                            weight = np.int64(np.int8(w_int8[fstart + f, ch, ky, kx]))
                            acc += pixel * weight
                acc += np.int64(b_int32[fstart + f])
                result[r, c, f] = acc

    return result.astype(np.int32)


def reference_quantize(conv_out, M, n, use_relu=True):
    """Match RTL quantizer.sv arithmetic."""
    H, W, F = conv_out.shape
    result = np.zeros((H, W, F), dtype=np.int8)

    for r in range(H):
        for c in range(W):
            for f in range(F):
                val = int(conv_out[r, c, f])
                mult = val * int(M)
                shifted = mult >> int(n)
                if use_relu and shifted < 0:
                    shifted = shifted >> 3
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
    """
    Pack (6,6,16) uint8 → list of 64-bit words.
    16 channels = 2 ci_groups of 8 channels each.
    For each spatial position: 2 words (ch0-7, ch8-15).
    Total: 6×6×2 = 72 words per OG.
    """
    words = []
    for r in range(PADDED_H):
        for c in range(PADDED_W):
            for cig in range(CI_GROUPS):
                val = 0
                for ch in range(8):
                    val |= int(img[r, c, cig * 8 + ch]) << (ch * 8)
                words.append(val)
    return words


def pack_weight_stream(w_int8, og):
    """
    Pack weights for one output group in addr→bank→uram order (72-bit words).

    Streaming order (matching weight_manager wr_cnt):
      for addr in range(ci_groups):       # wr_cnt[ADDR_WIDTH+5:6]
        for bank in range(8):             # wr_cnt[5:3] — which filter in og
          for uram in range(8):           # wr_cnt[2:0] — which input channel
            stream 72-bit word

    Each 72-bit word = 9 spatial weights for filter (og*8+bank), channel (uram):
      word = {w[2][2], w[2][1], w[2][0], w[1][2], w[1][1], w[1][0], w[0][2], w[0][1], w[0][0]}
      w[0][0] at bits[7:0] (LSB), w[2][2] at bits[71:64] (MSB)
    """
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
    """
    Pack all 32 biases as 128-bit words for bias_store DMA.
    bias_store expects 128-bit words, 4 biases per word.
    For 32 biases: 8 words.
    """
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
    """Pack (2,2,8) int8 maxpool output as 64-bit words. ch0 at bits[7:0]."""
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
    """Pack (4,4,8) int8 quant output as 64-bit words. ch0 at bits[7:0]."""
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

    print("\n=== Quantizing ===")
    w_int8, b_int32, quant_m, quant_n, w_scales = quantize_weights_biases(w_folded, b_folded)
    print(f"W_int8 range: [{w_int8.min()}, {w_int8.max()}]")
    print(f"B_int32 range: [{b_int32.min()}, {b_int32.max()}]")

    print("\n=== Generating image ===")
    img = generate_image()
    print(f"Image shape: {img.shape}")

    print("\n=== Computing references ===")
    for og in range(CO_GROUPS):
        print(f"\n--- Output Group {og} ---")
        conv_out = reference_conv(img, w_int8, b_int32, og)
        print(f"Conv out range: [{conv_out.min()}, {conv_out.max()}]")

        quant_out = reference_quantize(conv_out, quant_m[og], quant_n[og], use_relu=True)
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
        for og in range(CO_GROUPS):
            f.write(f"og{og}: M=0x{quant_m[og]:08x} n={quant_n[og]}\n")

    print(f"\n=== Files written to {OUT_DIR} ===")
    for fn in sorted(os.listdir(OUT_DIR)):
        fp = os.path.join(OUT_DIR, fn)
        print(f"  {fn}: {os.path.getsize(fp)} bytes")
