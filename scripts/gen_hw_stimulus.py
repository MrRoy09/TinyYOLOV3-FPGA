#!/usr/bin/env python3
"""
Generate hardware stimulus from quantized_params.npz.

Extracts pre-quantized weights/biases directly from hardware_sim.py's NPZ.
Only computes a few expected outputs for spot-checking.

Usage:
  python3 gen_hw_stimulus.py --layer 0 --img_h 416 --img_w 416
  python3 gen_hw_stimulus.py --layer 2 --img_h 208 --img_w 208
"""

import numpy as np
import os
import argparse

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
NPZ_FILE = os.path.join(SCRIPT_DIR, "..", "sim", "hardware-ai", "quantized_params.npz")

# Hardware constants
PIN = 8
POUT = 8


def load_npz():
    """Load the pre-quantized parameters."""
    return np.load(NPZ_FILE, allow_pickle=True)


def pack_weights_to_bin(w_int8, co_groups, ci_groups, out_dir):
    """
    Pack weights in hardware format.

    Hardware write counter maps: uram_sel = wr_cnt[2:0], bank_sel = wr_cnt[5:3]
    So data arrives as: entry N -> uram = N%8, bank = (N/8)%8, addr = N/64

    This means we must send data in order: uram varies fastest, then bank, then addr.
    i.e., loop order: for addr: for bank: for uram

    Each 72-bit word = 9 spatial weights for one (filter, input_channel) pair
    """
    cout, cin, kh, kw = w_int8.shape

    for og in range(co_groups):
        weight_bytes = bytearray()

        # Hardware expects: uram cycles fastest, then bank, then addr
        # entry N -> written to bank=(N/8)%8, uram=N%8, addr=N/64
        # So we generate entries 0,1,2,... and they get routed correctly
        for addr in range(ci_groups):
            for bank in range(8):  # 8 filters per output group
                filt = og * POUT + bank
                for uram in range(8):  # 8 input channels per ci_group
                    ch = addr * 8 + uram
                    if ch < cin:
                        # Pack 9 spatial weights into 72 bits
                        val = 0
                        for s in range(9):
                            ky, kx = s // 3, s % 3
                            w = int(w_int8[filt, ch, ky, kx]) & 0xFF
                            val |= w << (s * 8)
                    else:
                        val = 0  # Zero-pad if cin < ci_groups * 8

                    # Pack as 16 bytes (128-bit aligned, lower 9 bytes used)
                    weight_bytes.extend(val.to_bytes(16, 'little'))

        with open(os.path.join(out_dir, f"weights_og{og}.bin"), "wb") as f:
            f.write(weight_bytes)

        print(f"  weights_og{og}.bin: {len(weight_bytes)} bytes")


def pack_biases_to_bin(b_int32, co_groups, out_dir):
    """
    Pack biases in hardware format.

    4 biases per 128-bit word.
    """
    for og in range(co_groups):
        bias_bytes = bytearray()
        fstart = og * POUT

        for i in range(0, POUT, 4):
            word_128 = 0
            for j in range(4):
                if fstart + i + j < len(b_int32):
                    b = int(b_int32[fstart + i + j]) & 0xFFFFFFFF
                    word_128 |= b << (j * 32)
            bias_bytes.extend(word_128.to_bytes(16, 'little'))

        with open(os.path.join(out_dir, f"biases_og{og}.bin"), "wb") as f:
            f.write(bias_bytes)

        print(f"  biases_og{og}.bin: {len(bias_bytes)} bytes")


def generate_pixels(img_h, img_w, cin, cin_pad, input_scale, seed=42):
    """Generate test input pixels."""
    rng = np.random.RandomState(seed)

    # Random image [0, 255] -> scale to [0, input_scale] as int8
    img_uint8 = rng.randint(0, 256, size=(img_h, img_w, cin), dtype=np.uint8)
    img_scaled = np.round(img_uint8.astype(np.float64) / 255.0 * input_scale).astype(np.int8)

    # Pad channels if needed
    if cin < cin_pad:
        img_padded = np.zeros((img_h, img_w, cin_pad), dtype=np.int8)
        img_padded[:, :, :cin] = img_scaled
    else:
        img_padded = img_scaled

    # Spatial padding for 3x3 conv (1 pixel border)
    padded_h, padded_w = img_h + 2, img_w + 2
    img = np.zeros((padded_h, padded_w, cin_pad), dtype=np.int8)
    img[1:1+img_h, 1:1+img_w, :] = img_padded

    return img


def compute_sample_outputs(img, w_int8, b_int32, M, n, co_groups, ci_groups, num_samples=4):
    """
    Compute a few expected outputs for spot-checking.

    Computes both pre-maxpool and post-maxpool values.
    """
    padded_h, padded_w, cin_pad = img.shape
    out_h, out_w = padded_h - 2, padded_w - 2
    mp_h, mp_w = out_h // 2, out_w // 2

    pre_maxpool = []
    post_maxpool = []

    for og in range(min(co_groups, 2)):  # Just first 2 OGs
        fstart = og * POUT

        # Compute pre-maxpool for first few positions
        og_pre = []
        for idx in range(min(num_samples, out_h * out_w)):
            r = idx // out_w
            c = idx % out_w

            pixel_out = []
            for f in range(POUT):
                acc = np.int64(0)
                for ky in range(3):
                    for kx in range(3):
                        for ch in range(cin_pad):
                            pixel = np.int64(np.int8(img[r+ky, c+kx, ch]))
                            weight = np.int64(np.int8(w_int8[fstart+f, ch, ky, kx]))
                            acc += pixel * weight
                acc += np.int64(b_int32[fstart + f])

                val = int(acc)
                if val < 0:
                    val = val >> 3
                val = (val * M) >> n
                val = max(-128, min(127, val))
                pixel_out.append(val)

            og_pre.append((r, c, pixel_out))
        pre_maxpool.append(og_pre)

        # Compute post-maxpool (2x2 max, stride 2)
        og_post = []
        for idx in range(min(num_samples, mp_h * mp_w)):
            mr = idx // mp_w
            mc = idx % mp_w

            mp_out = []
            for f in range(POUT):
                vals_2x2 = []
                for dy in range(2):
                    for dx in range(2):
                        r, c = mr * 2 + dy, mc * 2 + dx
                        acc = np.int64(0)
                        for ky in range(3):
                            for kx in range(3):
                                for ch in range(cin_pad):
                                    pixel = np.int64(np.int8(img[r+ky, c+kx, ch]))
                                    weight = np.int64(np.int8(w_int8[fstart+f, ch, ky, kx]))
                                    acc += pixel * weight
                        acc += np.int64(b_int32[fstart + f])

                        val = int(acc)
                        if val < 0:
                            val = val >> 3
                        val = (val * M) >> n
                        val = max(-128, min(127, val))
                        vals_2x2.append(val)
                mp_out.append(max(vals_2x2))

            og_post.append((mr, mc, mp_out))
        post_maxpool.append(og_post)

    return pre_maxpool, post_maxpool


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--layer", type=int, required=True, help="Layer index (0, 2, 4, ...)")
    parser.add_argument("--img_h", type=int, default=416, help="Image height")
    parser.add_argument("--img_w", type=int, default=416, help="Image width")
    parser.add_argument("--seed", type=int, default=42, help="Random seed")
    parser.add_argument("--samples", type=int, default=8, help="Number of sample outputs to compute")
    args = parser.parse_args()

    data = load_npz()
    layer = args.layer

    # Get layer params from NPZ
    q_weights = data[f'l{layer}_q_weights']
    q_biases = data[f'l{layer}_q_biases']
    M = int(data[f'l{layer}_M'])
    n = int(data[f'l{layer}_n'])
    input_scale = float(data['input_scale'])

    cout, cin, kh, kw = q_weights.shape
    cin_pad = ((cin + 7) // 8) * 8  # Round up to multiple of 8
    co_groups = cout // POUT
    ci_groups = cin_pad // PIN

    out_dir = os.path.join(SCRIPT_DIR, f"stimulus_l{layer}_hw")
    os.makedirs(out_dir, exist_ok=True)

    print("=" * 60)
    print(f"LAYER {layer} STIMULUS (from quantized_params.npz)")
    print("=" * 60)
    print(f"Input: {args.img_h}x{args.img_w}x{cin} (padded to {cin_pad})")
    print(f"Output: {cout} channels, {co_groups} output groups")
    print(f"M = 0x{M:X} ({M}), n = {n}")
    print(f"Weights: {q_weights.shape}, Biases: {q_biases.shape}")
    print()

    # Pad weights if cin < cin_pad
    if cin < cin_pad:
        w_padded = np.zeros((cout, cin_pad, 3, 3), dtype=np.int8)
        w_padded[:, :cin, :, :] = q_weights
        q_weights = w_padded

    # Pack weights and biases
    print("Packing weights...")
    pack_weights_to_bin(q_weights, co_groups, ci_groups, out_dir)

    print("\nPacking biases...")
    pack_biases_to_bin(q_biases, co_groups, out_dir)

    # Generate pixels
    print(f"\nGenerating {args.img_h}x{args.img_w} test image...")
    img = generate_pixels(args.img_h, args.img_w, cin, cin_pad, input_scale, args.seed)

    # Save pixels
    pixel_bytes = img.flatten().astype(np.int8).tobytes()
    with open(os.path.join(out_dir, "pixels.bin"), "wb") as f:
        f.write(pixel_bytes)
    print(f"  pixels.bin: {len(pixel_bytes)} bytes ({img.shape})")

    # Compute sample outputs
    print(f"\nComputing {args.samples} sample outputs for verification...")
    pre_mp, post_mp = compute_sample_outputs(img, q_weights, q_biases, M, n,
                                              co_groups, ci_groups, args.samples)

    # Save sample outputs
    with open(os.path.join(out_dir, "expected_samples.txt"), "w") as f:
        f.write(f"# Layer {layer} expected outputs\n")
        f.write(f"# M=0x{M:X}, n={n}\n\n")

        f.write("# PRE-MAXPOOL (conv output before 2x2 max):\n")
        for og, og_samples in enumerate(pre_mp):
            for r, c, vals in og_samples:
                line = f"og{og} [{r:3d},{c:3d}]: " + " ".join(f"{v:4d}" for v in vals)
                f.write(line + "\n")

        f.write("\n# POST-MAXPOOL (hardware output - compare against this!):\n")
        for og, og_samples in enumerate(post_mp):
            for r, c, vals in og_samples:
                line = f"og{og} [{r:3d},{c:3d}]: " + " ".join(f"{v:4d}" for v in vals)
                f.write(line + "\n")
                print(f"  {line}")

    # Write quant params
    with open(os.path.join(out_dir, "quant_params.txt"), "w") as f:
        f.write(f"# Layer {layer} quantization (from quantized_params.npz)\n")
        for og in range(co_groups):
            f.write(f"og{og}: M=0x{M:08x} n={n}\n")

    # Write layer config for host
    with open(os.path.join(out_dir, "layer_config.txt"), "w") as f:
        f.write(f"layer={layer}\n")
        f.write(f"img_h={args.img_h}\n")
        f.write(f"img_w={args.img_w}\n")
        f.write(f"padded_h={args.img_h + 2}\n")
        f.write(f"padded_w={args.img_w + 2}\n")
        f.write(f"cin={cin}\n")
        f.write(f"cin_pad={cin_pad}\n")
        f.write(f"cout={cout}\n")
        f.write(f"ci_groups={ci_groups}\n")
        f.write(f"co_groups={co_groups}\n")
        f.write(f"M=0x{M:08x}\n")
        f.write(f"n={n}\n")

    print(f"\nFiles written to: {out_dir}")
    print("\nNext: Copy to KV260 and run hardware test")


if __name__ == "__main__":
    main()
