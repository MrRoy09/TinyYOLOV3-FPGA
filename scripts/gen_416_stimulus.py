#!/usr/bin/env python3
"""
Generate stimulus files for full 416x416 TinyYOLOv3 inference using
hardware-accurate quantization (per-output-group, leaky after quantize).

This matches the quantization in gen_layer0_stimulus.py which is verified
against the RTL testbench.

Layer 0: 3->16 channels, 3x3 conv, leaky ReLU, maxpool stride-2
  - Input:  416x416x3 (padded to 418x418x8)
  - Output: 208x208x16

Layer 1: 16->32 channels, 3x3 conv, leaky ReLU, maxpool stride-2
  - Input:  208x208x16 (padded to 210x210x16)
  - Output: 104x104x32

Usage:
  python3 gen_416_stimulus.py [--image path/to/image.jpg]
"""

import numpy as np
import struct
import os
import argparse
import time

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
WEIGHTS_PATH = os.path.join(SCRIPT_DIR, "yolov3-tiny.weights")

# Layer byte offsets in weights file (after 20-byte header)
# Layer N: biases[n], scales[n], means[n], vars[n], weights[n*c*3*3]
LAYER_OFFSETS = {
    0: 0,  # Start of layer 0
    1: 16*4 + 16*3*3*3,  # After layer 0: 16 BN params + 16*3*9 weights = 496 floats
}


def load_weights(path, layer_idx, n_filters, n_cin):
    """Load and return folded weights/biases for a layer."""
    with open(path, "rb") as f:
        # Skip header (20 bytes)
        f.read(20)

        # Skip to layer
        if layer_idx > 0:
            skip_floats = 0
            # Layer 0: 16 filters, 3 cin
            skip_floats += 16 * 4 + 16 * 3 * 3 * 3  # 496
            if layer_idx > 1:
                # Layer 1: 32 filters, 16 cin
                skip_floats += 32 * 4 + 32 * 16 * 3 * 3  # 4736
            if layer_idx > 2:
                # Would need more layers...
                raise ValueError(f"Layer {layer_idx} offset not implemented")
            f.read(4 * skip_floats)

        biases = np.array(struct.unpack(f"{n_filters}f", f.read(4 * n_filters)))
        scales = np.array(struct.unpack(f"{n_filters}f", f.read(4 * n_filters)))
        means = np.array(struct.unpack(f"{n_filters}f", f.read(4 * n_filters)))
        variances = np.array(struct.unpack(f"{n_filters}f", f.read(4 * n_filters)))
        n_weights = n_filters * n_cin * 3 * 3
        weights = np.array(struct.unpack(f"{n_weights}f", f.read(4 * n_weights)))
        weights = weights.reshape(n_filters, n_cin, 3, 3)  # OIHW

    # Fold batch normalization
    eps = 1e-5
    scale_factor = scales / np.sqrt(variances + eps)
    w_folded = weights * scale_factor[:, None, None, None]
    b_folded = (biases - means) * scale_factor

    return w_folded, b_folded


def quantize_per_og(w_folded, b_folded, cout, pout=8):
    """Quantize weights/biases per output group (hardware-accurate approach)."""
    co_groups = cout // pout
    cin_pad = w_folded.shape[1]

    w_int8 = np.zeros((cout, cin_pad, 3, 3), dtype=np.int8)
    b_int32 = np.zeros(cout, dtype=np.int32)
    quant_m = np.zeros(co_groups, dtype=np.uint32)
    quant_n = np.zeros(co_groups, dtype=np.int32)

    for og in range(co_groups):
        fs, fe = og * pout, (og + 1) * pout
        w_og = w_folded[fs:fe]
        w_max = np.max(np.abs(w_og))
        w_scale = 127.0 / w_max if w_max > 0 else 1.0

        w_int8[fs:fe] = np.clip(np.round(w_og * w_scale), -128, 127).astype(np.int8)
        b_int32[fs:fe] = np.round(b_folded[fs:fe] * w_scale).astype(np.int32)

        # M and n: output = (acc * M) >> n, where M ≈ 2^n / w_scale
        n = 16
        m_val = round(2**n / w_scale)
        while m_val > 0xFFFFFFFF:
            n -= 1
            m_val = round(2**n / w_scale)
        quant_m[og] = m_val
        quant_n[og] = n

    return w_int8, b_int32, quant_m, quant_n


def reference_conv(img, w_int8, b_int32, og, pout=8):
    """Hardware-accurate convolution for one output group (vectorized)."""
    padded_h, padded_w, cin_pad = img.shape
    out_h = padded_h - 2
    out_w = padded_w - 2
    fstart = og * pout

    # Get weights for this output group: (pout, cin_pad, 3, 3)
    w_og = w_int8[fstart:fstart+pout].astype(np.int64)

    # Use stride tricks for efficient windowing
    from numpy.lib.stride_tricks import as_strided

    # Create sliding window view of input: (out_h, out_w, 3, 3, cin_pad)
    img_int64 = img.astype(np.int64)
    shape = (out_h, out_w, 3, 3, cin_pad)
    strides = (img_int64.strides[0], img_int64.strides[1],
               img_int64.strides[0], img_int64.strides[1], img_int64.strides[2])
    windows = as_strided(img_int64, shape=shape, strides=strides)

    # Compute convolution: einsum over spatial and channel dimensions
    # windows: (out_h, out_w, ky, kx, cin)
    # w_og: (pout, cin, ky, kx) -> transpose to (pout, ky, kx, cin)
    w_transposed = w_og.transpose(0, 2, 3, 1)  # (pout, ky, kx, cin)

    # Result: (out_h, out_w, pout)
    result = np.einsum('hwijk,fijk->hwf', windows, w_transposed, dtype=np.int64)

    # Add bias
    result += b_int32[fstart:fstart+pout].astype(np.int64)

    return result.astype(np.int32)


def reference_quantize(conv_out, M, n, use_relu=True):
    """Hardware-accurate quantization: (acc * M) >> n, then leaky ReLU (vectorized)."""
    # Multiply and shift
    mult = conv_out.astype(np.int64) * int(M)
    shifted = mult >> int(n)

    # Leaky ReLU AFTER quantization (hardware order)
    if use_relu:
        shifted = np.where(shifted >= 0, shifted, shifted >> 3)

    # Clamp to int8
    result = np.clip(shifted, -128, 127).astype(np.int8)
    return result


def reference_maxpool(quant_out, stride=2):
    """Hardware-accurate 2x2 maxpool (vectorized)."""
    H, W, F = quant_out.shape

    if stride == 1:
        # stride-1: pad right and bottom by 1, output same size
        padded = np.full((H+1, W+1, F), -128, dtype=np.int8)
        padded[:H, :W, :] = quant_out
        oh, ow = H, W
        # Get 4 shifted views
        v00 = padded[0:oh, 0:ow, :]
        v01 = padded[0:oh, 1:ow+1, :]
        v10 = padded[1:oh+1, 0:ow, :]
        v11 = padded[1:oh+1, 1:ow+1, :]
    else:
        oh, ow = H // 2, W // 2
        # Reshape for stride-2 pooling
        v00 = quant_out[0::2, 0::2, :]
        v01 = quant_out[0::2, 1::2, :]
        v10 = quant_out[1::2, 0::2, :]
        v11 = quant_out[1::2, 1::2, :]

    # Stack and take max (signed comparison)
    stacked = np.stack([v00.astype(np.int16), v01.astype(np.int16),
                        v10.astype(np.int16), v11.astype(np.int16)], axis=0)
    result = np.max(stacked, axis=0).astype(np.int8)
    return result


def pack_pixel_stream_bin(img):
    """Pack HWC uint8 image to binary (64-bit words, 8 channels per word)."""
    H, W, C = img.shape
    ci_groups = C // 8
    data = bytearray()
    for r in range(H):
        for c in range(W):
            for cig in range(ci_groups):
                for ch in range(8):
                    data.append(img[r, c, cig * 8 + ch])
    return bytes(data)


def pack_weights_bin(w_int8, og, ci_groups, pout=8):
    """Pack weights for one OG to binary (72-bit data in 128-bit AXI words).

    Hardware extracts wt_wr_data = wb_axis_tdata[71:0], so each 72-bit weight
    must be in the lower 9 bytes of a 16-byte (128-bit) AXI word.
    """
    data = bytearray()
    for addr in range(ci_groups):
        for bank in range(8):
            f = og * pout + bank
            for uram in range(8):
                ch = addr * 8 + uram
                # Pack 9 spatial weights into lower 9 bytes of 16-byte word
                word = bytearray(16)  # 128-bit word, initialized to 0
                for spatial_idx in range(9):
                    ky = spatial_idx // 3
                    kx = spatial_idx % 3
                    w_byte = int(w_int8[f, ch, ky, kx])
                    if w_byte < 0:
                        w_byte = w_byte & 0xFF
                    word[spatial_idx] = w_byte
                # Upper 7 bytes remain 0 (padding)
                data.extend(word)
    return bytes(data)


def pack_biases_bin(b_int32, og, pout=8):
    """Pack 8 biases for one OG as 128-bit words (2 words = 32 bytes)."""
    fs = og * pout
    data = bytearray()
    for i in range(2):  # 2 words of 4 biases each
        for j in range(4):
            b = int(b_int32[fs + i*4 + j])
            # Pack as little-endian int32
            data.extend(b.to_bytes(4, 'little', signed=True))
    return bytes(data)


def pack_output_bin(out):
    """Pack HWC int8 output to binary (64-bit words, 8 channels per word)."""
    H, W, C = out.shape
    data = bytearray()
    for r in range(H):
        for c in range(W):
            for ch in range(C):
                b = int(out[r, c, ch])
                if b < 0:
                    b = b & 0xFF
                data.append(b)
    return bytes(data)


def process_layer0(img_uint8, out_dir):
    """Process layer 0 and return output for layer 1."""
    print("\n" + "="*60)
    print("LAYER 0: 3->16 channels, 416x416 -> 208x208")
    print("="*60)

    # Load and fold weights
    w_folded, b_folded = load_weights(WEIGHTS_PATH, 0, n_filters=16, n_cin=3)
    print(f"W_folded range: [{w_folded.min():.4f}, {w_folded.max():.4f}]")
    print(f"B_folded range: [{b_folded.min():.4f}, {b_folded.max():.4f}]")

    # Pad channels: 3 -> 8
    cin_pad = 8
    w_padded = np.zeros((16, cin_pad, 3, 3), dtype=np.float64)
    w_padded[:, :3, :, :] = w_folded

    # Quantize per output group
    w_int8, b_int32, quant_m, quant_n = quantize_per_og(w_padded, b_folded, cout=16)
    print(f"W_int8 range: [{w_int8.min()}, {w_int8.max()}]")
    print(f"B_int32 range: [{b_int32.min()}, {b_int32.max()}]")
    for og in range(2):
        print(f"  OG{og}: M=0x{quant_m[og]:08x}, n={quant_n[og]}")

    # Pad image: spatial (416->418) and channels (3->8)
    H, W, _ = img_uint8.shape
    img_padded = np.zeros((H + 2, W + 2, cin_pad), dtype=np.uint8)
    img_padded[1:H+1, 1:W+1, :3] = img_uint8
    print(f"Input shape: {img_padded.shape}")

    # Save pixel data
    pixel_data = pack_pixel_stream_bin(img_padded)
    with open(os.path.join(out_dir, "pixels.bin"), "wb") as f:
        f.write(pixel_data)
    print(f"Pixels: {len(pixel_data)} bytes")

    # Process each output group
    co_groups = 2
    all_outputs = []

    for og in range(co_groups):
        print(f"\n--- Output Group {og} ---")

        # Save weights and biases
        wt_data = pack_weights_bin(w_int8, og, ci_groups=1)
        with open(os.path.join(out_dir, f"weights_og{og}.bin"), "wb") as f:
            f.write(wt_data)
        print(f"  Weights: {len(wt_data)} bytes")

        bias_data = pack_biases_bin(b_int32, og)
        with open(os.path.join(out_dir, f"biases_og{og}.bin"), "wb") as f:
            f.write(bias_data)
        print(f"  Biases: {len(bias_data)} bytes")

        # Compute reference
        print(f"  Computing convolution...", end=" ", flush=True)
        t0 = time.time()
        conv_out = reference_conv(img_padded, w_int8, b_int32, og)
        print(f"done ({time.time()-t0:.1f}s)")
        print(f"  Conv range: [{conv_out.min()}, {conv_out.max()}]")

        quant_out = reference_quantize(conv_out, quant_m[og], quant_n[og])
        print(f"  Quant range: [{quant_out.min()}, {quant_out.max()}]")

        mp_out = reference_maxpool(quant_out, stride=2)
        print(f"  Maxpool shape: {mp_out.shape}, range: [{mp_out.min()}, {mp_out.max()}]")

        # Save expected output
        exp_data = pack_output_bin(mp_out)
        with open(os.path.join(out_dir, f"expected_og{og}.bin"), "wb") as f:
            f.write(exp_data)
        print(f"  Expected: {len(exp_data)} bytes")

        all_outputs.append(mp_out)

    # Combine output groups: (208, 208, 8) + (208, 208, 8) -> (208, 208, 16)
    combined = np.concatenate(all_outputs, axis=2)
    print(f"\nLayer 0 output shape: {combined.shape}")

    # Save quant params
    with open(os.path.join(out_dir, "quant_params.txt"), "w") as f:
        f.write("# Layer 0 quantization parameters (per output group)\n")
        for og in range(co_groups):
            f.write(f"og{og}: M=0x{quant_m[og]:08x} n={quant_n[og]}\n")

    return combined


def process_layer1(layer0_out, out_dir):
    """Process layer 1 using layer 0 output."""
    print("\n" + "="*60)
    print("LAYER 1: 16->32 channels, 208x208 -> 104x104")
    print("="*60)

    # Load and fold weights
    w_folded, b_folded = load_weights(WEIGHTS_PATH, 1, n_filters=32, n_cin=16)
    print(f"W_folded range: [{w_folded.min():.4f}, {w_folded.max():.4f}]")
    print(f"B_folded range: [{b_folded.min():.4f}, {b_folded.max():.4f}]")

    # No channel padding needed (16 is already multiple of 8)
    cin_pad = 16

    # Quantize per output group
    w_int8, b_int32, quant_m, quant_n = quantize_per_og(w_folded, b_folded, cout=32)
    print(f"W_int8 range: [{w_int8.min()}, {w_int8.max()}]")
    print(f"B_int32 range: [{b_int32.min()}, {b_int32.max()}]")
    for og in range(4):
        print(f"  OG{og}: M=0x{quant_m[og]:08x}, n={quant_n[og]}")

    # Convert layer 0 output from int8 to uint8 for next layer
    # Hardware sees all pixels as unsigned 0-255
    layer0_uint8 = layer0_out.view(np.uint8)

    # Pad spatial: 208 -> 210
    H, W, C = layer0_uint8.shape
    img_padded = np.zeros((H + 2, W + 2, C), dtype=np.uint8)
    img_padded[1:H+1, 1:W+1, :] = layer0_uint8
    print(f"Input shape: {img_padded.shape}")

    # Save pixel data
    pixel_data = pack_pixel_stream_bin(img_padded)
    with open(os.path.join(out_dir, "pixels.bin"), "wb") as f:
        f.write(pixel_data)
    print(f"Pixels: {len(pixel_data)} bytes")

    # Process each output group
    co_groups = 4
    ci_groups = 2
    all_outputs = []

    for og in range(co_groups):
        print(f"\n--- Output Group {og} ---")

        # Save weights and biases
        wt_data = pack_weights_bin(w_int8, og, ci_groups=ci_groups)
        with open(os.path.join(out_dir, f"weights_og{og}.bin"), "wb") as f:
            f.write(wt_data)
        print(f"  Weights: {len(wt_data)} bytes")

        bias_data = pack_biases_bin(b_int32, og)
        with open(os.path.join(out_dir, f"biases_og{og}.bin"), "wb") as f:
            f.write(bias_data)
        print(f"  Biases: {len(bias_data)} bytes")

        # Compute reference
        print(f"  Computing convolution...", end=" ", flush=True)
        t0 = time.time()
        conv_out = reference_conv(img_padded, w_int8, b_int32, og)
        print(f"done ({time.time()-t0:.1f}s)")
        print(f"  Conv range: [{conv_out.min()}, {conv_out.max()}]")

        quant_out = reference_quantize(conv_out, quant_m[og], quant_n[og])
        print(f"  Quant range: [{quant_out.min()}, {quant_out.max()}]")

        mp_out = reference_maxpool(quant_out, stride=2)
        print(f"  Maxpool shape: {mp_out.shape}, range: [{mp_out.min()}, {mp_out.max()}]")

        # Save expected output
        exp_data = pack_output_bin(mp_out)
        with open(os.path.join(out_dir, f"expected_og{og}.bin"), "wb") as f:
            f.write(exp_data)
        print(f"  Expected: {len(exp_data)} bytes")

        all_outputs.append(mp_out)

    # Combine output groups
    combined = np.concatenate(all_outputs, axis=2)
    print(f"\nLayer 1 output shape: {combined.shape}")

    # Save quant params
    with open(os.path.join(out_dir, "quant_params.txt"), "w") as f:
        f.write("# Layer 1 quantization parameters (per output group)\n")
        for og in range(co_groups):
            f.write(f"og{og}: M=0x{quant_m[og]:08x} n={quant_n[og]}\n")

    return combined


def main():
    parser = argparse.ArgumentParser(description="Generate 416x416 TinyYOLOv3 stimulus")
    parser.add_argument("--image", type=str, help="Path to input image (default: synthetic)")
    parser.add_argument("--seed", type=int, default=42, help="Random seed for synthetic image")
    args = parser.parse_args()

    # Create output directories
    l0_dir = os.path.join(SCRIPT_DIR, "stimulus_416_l0")
    l1_dir = os.path.join(SCRIPT_DIR, "stimulus_416_l1")
    os.makedirs(l0_dir, exist_ok=True)
    os.makedirs(l1_dir, exist_ok=True)

    # Load or generate input image
    if args.image:
        try:
            import cv2
            img = cv2.imread(args.image)
            if img is None:
                raise ValueError(f"Cannot load image: {args.image}")
            img = cv2.resize(img, (416, 416))
            img = cv2.cvtColor(img, cv2.COLOR_BGR2RGB)
            print(f"Loaded image: {args.image} -> {img.shape}")
        except ImportError:
            print("OpenCV not available, using synthetic image")
            args.image = None

    if not args.image:
        # Generate synthetic image
        rng = np.random.RandomState(args.seed)
        img = rng.randint(0, 256, size=(416, 416, 3), dtype=np.uint8)
        print(f"Generated synthetic image: {img.shape}")

    # Process layer 0
    layer0_out = process_layer0(img, l0_dir)

    # Process layer 1
    layer1_out = process_layer1(layer0_out, l1_dir)

    print("\n" + "="*60)
    print("SUMMARY")
    print("="*60)
    print(f"Layer 0 stimulus: {l0_dir}")
    print(f"  - Input:  418x418x8 ({418*418*8} bytes)")
    print(f"  - Output: 208x208x16 ({208*208*16} bytes)")
    print(f"Layer 1 stimulus: {l1_dir}")
    print(f"  - Input:  210x210x16 ({210*210*16} bytes)")
    print(f"  - Output: 104x104x32 ({104*104*32} bytes)")


if __name__ == "__main__":
    main()
