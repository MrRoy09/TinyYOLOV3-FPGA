#!/usr/bin/env python3
"""
Prepare TinyYOLOv3 Weights for FPGA Inference

This script extracts, folds, and quantizes all convolutional layer weights
for FPGA execution. It generates binary files for each output group that
can be directly loaded by the C++ host code.

Output structure:
    data/weights/
        layer_00/
            og_00_weights.bin    # 72-bit weights padded to 128-bit
            og_00_biases.bin     # 32-bit biases packed to 128-bit
            og_01_weights.bin
            og_01_biases.bin
            ...
        layer_02/
            ...
        layer_config.json        # All layer configurations

Usage:
    python prepare_weights.py [--output-dir data/weights]
"""

import numpy as np
import struct
import json
import os
import sys
from pathlib import Path

# Hardware parameters
PIN = 8
POUT = 8

# Layer configuration (same as tinyyolo_reference.py)
# Maps Darknet layer index to hardware parameters
# IMPORTANT: Layer 8 does NOT have fused maxpool because route layer 20
# needs its pre-maxpool output (26x26x256). Layer 9 is a separate maxpool.
CONV_LAYERS = {
    # layer_idx: (cin, cout, kernel_size, has_fused_maxpool, maxpool_stride)
    0:  (3,    16,   3, True,  2),   # 416->208
    2:  (16,   32,   3, True,  2),   # 208->104
    4:  (32,   64,   3, True,  2),   # 104->52
    6:  (64,   128,  3, True,  2),   # 52->26
    8:  (128,  256,  3, False, 0),   # 26->26 (NO fused maxpool - needed by route 20)
    10: (256,  512,  3, True,  1),   # 13->13 (stride-1 maxpool)
    12: (512,  1024, 3, False, 0),   # 13->13
    13: (1024, 256,  1, False, 0),   # 13->13 (1x1 conv)
    14: (256,  512,  3, False, 0),   # 13->13
    15: (512,  255,  1, False, 0),   # 13->13 (1x1 conv, linear activation)
    18: (256,  128,  1, False, 0),   # 13->13 (1x1 conv)
    21: (384,  256,  3, False, 0),   # 26->26 (after concat)
    22: (256,  255,  1, False, 0),   # 26->26 (1x1 conv, linear activation)
}


def load_folded_weights(path):
    """Load pre-folded weights from .npz file."""
    return np.load(path, allow_pickle=True)


def load_quant_params(path):
    """Load quantization parameters from .npz file."""
    raw = np.load(path, allow_pickle=True)
    q_params = {}
    for k in raw.files:
        if k.startswith('l') and '_' in k:
            parts = k[1:].split('_')
            idx = int(parts[0])
            key = '_'.join(parts[1:])
            if idx not in q_params:
                q_params[idx] = {}
            q_params[idx][key] = raw[k]
            if q_params[idx][key].ndim == 0:
                q_params[idx][key] = q_params[idx][key].item()
        else:
            q_params[k] = raw[k].item() if raw[k].ndim == 0 else raw[k]
    return q_params


def ceil_div(a, b):
    """Ceiling division."""
    return (a + b - 1) // b


def pack_weights_for_og(weights_int8, og_idx, ci_groups, kernel_size=3):
    """
    Pack weights for one output group in hardware format.

    Hardware weight format (72-bit words):
    - Streaming order: for addr in ci_groups: for bank in 8: for uram in 8
    - Each word: 9 spatial weights (3x3) for one filter/channel pair
    - w[0][0] at bits[7:0], w[2][2] at bits[71:64]

    For 1x1 conv: Only center position (spatial_idx=4) is non-zero.

    Args:
        weights_int8: INT8 weights (Cout, Cin_padded, Kh, Kw)
        og_idx: Output group index
        ci_groups: Number of input channel groups
        kernel_size: 1 or 3

    Returns:
        List of 72-bit integers
    """
    cout, cin_pad, kh, kw = weights_int8.shape

    words = []
    for addr in range(ci_groups):
        for bank in range(8):
            filter_idx = og_idx * POUT + bank
            if filter_idx >= cout:
                # Pad with zeros if output channels don't fill the group
                for _ in range(8):
                    words.append(0)
                continue

            for uram in range(8):
                ch = addr * 8 + uram
                if ch >= cin_pad:
                    words.append(0)
                    continue

                val = 0
                if kernel_size == 1:
                    # 1x1 conv: weight at center position (index 4)
                    w_byte = int(weights_int8[filter_idx, ch, 0, 0])
                    if w_byte < 0:
                        w_byte = w_byte & 0xFF
                    val = w_byte << (4 * 8)  # Position 4 = center
                else:
                    # 3x3 conv: 9 spatial positions
                    for spatial_idx in range(9):
                        ky = spatial_idx // 3
                        kx = spatial_idx % 3
                        w_byte = int(weights_int8[filter_idx, ch, ky, kx])
                        if w_byte < 0:
                            w_byte = w_byte & 0xFF
                        val |= w_byte << (spatial_idx * 8)
                words.append(val)

    return words


def pack_biases_for_og(biases_int32, og_idx):
    """
    Pack biases for one output group as 32-bit values.

    Args:
        biases_int32: INT32 biases (Cout,)
        og_idx: Output group index

    Returns:
        List of 32-bit integers
    """
    cout = len(biases_int32)
    biases = []
    for i in range(8):
        filter_idx = og_idx * POUT + i
        if filter_idx < cout:
            biases.append(int(biases_int32[filter_idx]))
        else:
            biases.append(0)
    return biases


def write_weights_bin(path, words_72bit):
    """
    Write 72-bit weight words as 128-bit padded binary (16 bytes each).

    The AXI interface reads 128-bit words, with weight data in lower 72 bits.
    """
    with open(path, 'wb') as f:
        for w in words_72bit:
            # Pack as 16 bytes: lower 9 bytes are weight, upper 7 are zero padding
            data = w.to_bytes(16, byteorder='little', signed=False)
            f.write(data)


def write_biases_bin(path, biases_32bit):
    """
    Write 32-bit biases packed as 128-bit words (4 biases per word).
    """
    with open(path, 'wb') as f:
        # Pack 4 biases at a time into 128-bit (16 byte) words
        for i in range(0, len(biases_32bit), 4):
            val = 0
            for j in range(4):
                if i + j < len(biases_32bit):
                    b = biases_32bit[i + j]
                    if b < 0:
                        b = b & 0xFFFFFFFF
                    val |= b << (j * 32)
            data = val.to_bytes(16, byteorder='little', signed=False)
            f.write(data)


def prepare_layer_weights(layer_idx, q_params, output_dir):
    """
    Prepare all output group weights for one layer.

    Args:
        layer_idx: Darknet layer index
        q_params: Quantization parameters dict
        output_dir: Base output directory

    Returns:
        Layer config dict
    """
    if layer_idx not in CONV_LAYERS:
        return None

    cin, cout, kernel_size, has_maxpool, mp_stride = CONV_LAYERS[layer_idx]
    cin_pad = ceil_div(cin, PIN) * PIN
    ci_groups = ceil_div(cin, PIN)
    co_groups = ceil_div(cout, POUT)

    # Get quantized weights and biases
    p = q_params[layer_idx]
    weights = p['q_weights']  # (Cout, Cin, Kh, Kw)
    biases = p['q_biases']    # (Cout,)
    M = int(p['M'])
    n = int(p['n'])
    activation = p['activation']

    # Pad input channels to multiple of PIN
    if weights.shape[1] < cin_pad:
        pad_amount = cin_pad - weights.shape[1]
        weights = np.pad(weights, ((0, 0), (0, pad_amount), (0, 0), (0, 0)),
                        mode='constant', constant_values=0)

    # Create layer directory
    layer_dir = os.path.join(output_dir, f"layer_{layer_idx:02d}")
    os.makedirs(layer_dir, exist_ok=True)

    # Process each output group
    og_configs = []
    for og in range(co_groups):
        # Pack weights
        wt_words = pack_weights_for_og(weights, og, ci_groups, kernel_size)
        wt_path = os.path.join(layer_dir, f"og_{og:02d}_weights.bin")
        write_weights_bin(wt_path, wt_words)

        # Pack biases
        bias_words = pack_biases_for_og(biases, og)
        bias_path = os.path.join(layer_dir, f"og_{og:02d}_biases.bin")
        write_biases_bin(bias_path, bias_words)

        og_configs.append({
            'og_idx': og,
            'weights_file': f"og_{og:02d}_weights.bin",
            'biases_file': f"og_{og:02d}_biases.bin",
            'num_weights': len(wt_words),
            'num_biases': len(bias_words),
            'quant_m': M,
            'quant_n': n,
        })

        print(f"  OG {og:2d}: {len(wt_words)} weight words, {len(bias_words)} biases, M=0x{M:08x}, n={n}")

    # Layer config
    layer_config = {
        'layer_idx': layer_idx,
        'cin': cin,
        'cout': cout,
        'cin_padded': cin_pad,
        'ci_groups': ci_groups,
        'co_groups': co_groups,
        'kernel_size': kernel_size,
        'use_maxpool': has_maxpool,
        'maxpool_stride': mp_stride,
        'use_relu': activation == 'leaky',
        'kernel_1x1': kernel_size == 1,
        'output_groups': og_configs,
    }

    # Save layer config
    config_path = os.path.join(layer_dir, "config.json")
    with open(config_path, 'w') as f:
        json.dump(layer_config, f, indent=2)

    return layer_config


def prepare_all_weights(q_params, output_dir):
    """
    Prepare weights for all convolutional layers.

    Args:
        q_params: Quantization parameters dict
        output_dir: Base output directory

    Returns:
        Complete configuration dict
    """
    os.makedirs(output_dir, exist_ok=True)

    all_configs = {}
    for layer_idx in sorted(CONV_LAYERS.keys()):
        print(f"\nLayer {layer_idx}: {CONV_LAYERS[layer_idx]}")
        config = prepare_layer_weights(layer_idx, q_params, output_dir)
        if config:
            all_configs[f"layer_{layer_idx}"] = config

    # Save master config
    master_config_path = os.path.join(output_dir, "layer_config.json")
    with open(master_config_path, 'w') as f:
        json.dump(all_configs, f, indent=2)

    print(f"\n\nMaster config written to {master_config_path}")
    return all_configs


def prepare_input_image(image_path, output_path, input_scale=127.0, input_size=416):
    """
    Prepare input image as binary file for hardware.

    Converts image to INT8 NHWC format with channel padding.

    Args:
        image_path: Input image path
        output_path: Output binary file path
        input_scale: Quantization scale for input
        input_size: Network input size

    Returns:
        Dict with image metadata
    """
    import cv2

    img = cv2.imread(image_path)
    if img is None:
        raise ValueError(f"Cannot load image: {image_path}")

    # Resize and convert to RGB
    img = cv2.resize(img, (input_size, input_size))
    img = cv2.cvtColor(img, cv2.COLOR_BGR2RGB)

    # Normalize to INT8
    img_float = img.astype(np.float32) / 255.0
    img_int8 = np.round(img_float * input_scale).astype(np.int8)

    # For layer 0: pad channels 3 -> 8
    h, w, c = img_int8.shape
    cin_pad = 8
    img_padded = np.zeros((h, w, cin_pad), dtype=np.int8)
    img_padded[:, :, :c] = img_int8

    # Add spatial padding for 3x3 conv (1 pixel border)
    pad = 1
    img_full = np.zeros((h + 2*pad, w + 2*pad, cin_pad), dtype=np.int8)
    img_full[pad:pad+h, pad:pad+w, :] = img_padded

    # Write as binary (row-major NHWC)
    img_full.tofile(output_path)

    return {
        'original_shape': (h, w, c),
        'padded_shape': img_full.shape,
        'input_scale': input_scale,
        'output_path': output_path,
        'bytes': img_full.size,
    }


def main():
    import argparse

    parser = argparse.ArgumentParser(description='Prepare TinyYOLOv3 weights for FPGA')
    parser.add_argument('--quant-params', default='sim/hardware-ai/quantized_params.npz',
                       help='Path to quantized parameters')
    parser.add_argument('--output-dir', default='data/weights',
                       help='Output directory for weight files')
    parser.add_argument('--image', default=None,
                       help='Optional: prepare input image')
    parser.add_argument('--image-output', default='data/input_416.bin',
                       help='Output path for prepared image')
    args = parser.parse_args()

    # Find paths relative to script location
    script_dir = os.path.dirname(os.path.abspath(__file__))
    project_root = os.path.dirname(script_dir)

    quant_path = os.path.join(project_root, args.quant_params)
    output_dir = os.path.join(project_root, args.output_dir)

    print(f"Loading quantization parameters from: {quant_path}")
    q_params = load_quant_params(quant_path)

    print(f"\nPreparing weights in: {output_dir}")
    configs = prepare_all_weights(q_params, output_dir)

    # Summary
    print("\n" + "=" * 60)
    print("SUMMARY")
    print("=" * 60)

    total_weight_bytes = 0
    total_bias_bytes = 0

    for layer_name, cfg in configs.items():
        layer_idx = cfg['layer_idx']
        cin, cout = cfg['cin'], cfg['cout']
        ci_groups, co_groups = cfg['ci_groups'], cfg['co_groups']
        kernel = '1x1' if cfg['kernel_1x1'] else '3x3'
        maxpool = f"mp-s{cfg['maxpool_stride']}" if cfg['use_maxpool'] else "no-mp"

        # Calculate sizes
        weights_per_og = cfg['output_groups'][0]['num_weights'] * 16  # 16 bytes per 128-bit word
        biases_per_og = ((len(cfg['output_groups'][0]['num_biases']) + 3) // 4) * 16 if isinstance(cfg['output_groups'][0]['num_biases'], list) else 16
        total_weight_bytes += weights_per_og * co_groups
        total_bias_bytes += 16 * co_groups  # 8 biases packed in 2 x 128-bit words

        print(f"  {layer_name}: {cin:4d}->{cout:4d} {kernel} ci={ci_groups:3d} co={co_groups:3d} {maxpool}")

    print(f"\nTotal weight data: {total_weight_bytes / 1024:.1f} KB")
    print(f"Total bias data:   {total_bias_bytes / 1024:.1f} KB")

    # Optionally prepare input image
    if args.image:
        print(f"\nPreparing input image: {args.image}")
        os.makedirs(os.path.dirname(args.image_output), exist_ok=True)
        img_info = prepare_input_image(args.image, args.image_output,
                                       input_scale=q_params.get('input_scale', 127.0))
        print(f"  Original shape: {img_info['original_shape']}")
        print(f"  Padded shape:   {img_info['padded_shape']}")
        print(f"  Output size:    {img_info['bytes']} bytes")
        print(f"  Written to:     {img_info['output_path']}")


if __name__ == "__main__":
    main()
