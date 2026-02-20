#!/usr/bin/env python3
"""
export_weights_for_cpu.py - Export quantized weights for ARM CPU inference

Converts quantized_params.npz to binary files optimized for C++ loading.
Creates a directory structure with all layer parameters.

Usage:
    python3 export_weights_for_cpu.py [npz_path] [output_dir]

Defaults:
    npz_path: ../sim/hardware-ai/quantized_params.npz
    output_dir: ./weights_cpu
"""

import numpy as np
import os
import sys
import struct

# Layer configuration: (npz_idx, cin, cout, kernel_size, stride, pad, activation, maxpool_stride)
# npz_idx maps to the layer index in the NPZ file
LAYER_CONFIG = [
    # hw_layer, npz_idx, cin, cout, k, stride, pad, activation, maxpool_stride
    (0,  0,    3,   16, 3, 1, 1, 'leaky', 2),
    (1,  2,   16,   32, 3, 1, 1, 'leaky', 2),
    (2,  4,   32,   64, 3, 1, 1, 'leaky', 2),
    (3,  6,   64,  128, 3, 1, 1, 'leaky', 2),
    (4,  8,  128,  256, 3, 1, 1, 'leaky', 2),  # CPU does maxpool to save pre-pool output
    (5, 10,  256,  512, 3, 1, 1, 'leaky', 1),
    (6, 12,  512, 1024, 3, 1, 1, 'leaky', 0),
    (7, 13, 1024,  256, 1, 1, 0, 'leaky', 0),
    (8, 14,  256,  512, 3, 1, 1, 'leaky', 0),
    (9, 15,  512,  255, 1, 1, 0, 'linear', 0),  # Detection head 1
    (10, 18, 256,  128, 1, 1, 0, 'leaky', 0),
    (11, 21, 384,  256, 3, 1, 1, 'leaky', 0),
    (12, 22, 256,  255, 1, 1, 0, 'linear', 0),  # Detection head 2
]

def load_quant_params(npz_path):
    """Load quantized parameters from NPZ file."""
    raw = np.load(npz_path, allow_pickle=True)
    q_params = {}

    for k in raw.files:
        if k.startswith('l') and '_' in k:
            parts = k[1:].split('_')
            idx = int(parts[0])
            key = '_'.join(parts[1:])
            if idx not in q_params:
                q_params[idx] = {}
            q_params[idx][key] = raw[k]
            # Handle scalars saved as 0-d arrays
            if q_params[idx][key].ndim == 0:
                q_params[idx][key] = q_params[idx][key].item()
        else:
            q_params[k] = raw[k].item() if raw[k].ndim == 0 else raw[k]

    return q_params

def export_layer(q_params, hw_layer, npz_idx, output_dir):
    """Export a single layer's parameters to binary files."""
    layer_dir = os.path.join(output_dir, f"layer{hw_layer}")
    os.makedirs(layer_dir, exist_ok=True)

    p = q_params[npz_idx]

    # Weights: INT8, shape [cout, cin, kh, kw] in NCHW format
    weights = p['q_weights'].astype(np.int8)
    weights_path = os.path.join(layer_dir, "weights.bin")
    weights.tofile(weights_path)
    print(f"  Layer {hw_layer}: weights {weights.shape} -> {weights_path}")

    # Biases: INT32, shape [cout]
    biases = p['q_biases'].astype(np.int32)
    biases_path = os.path.join(layer_dir, "biases.bin")
    biases.tofile(biases_path)
    print(f"  Layer {hw_layer}: biases {biases.shape} -> {biases_path}")

    # Quantization params: M (int32), n (int32), o_scale (float32)
    M = int(p['M'])
    n = int(p['n'])
    o_scale = float(p['o_scale'])
    activation = p['activation'] if isinstance(p['activation'], str) else p['activation'].item()

    # Write config as binary: M(4), n(4), o_scale(4), activation(1), pad(1), stride(1), kernel_size(1)
    config_path = os.path.join(layer_dir, "config.bin")
    with open(config_path, 'wb') as f:
        f.write(struct.pack('<I', M))           # uint32
        f.write(struct.pack('<I', n))           # uint32
        f.write(struct.pack('<f', o_scale))     # float32
        f.write(struct.pack('<B', 1 if activation == 'leaky' else 0))  # uint8
        f.write(struct.pack('<B', p.get('pad', 1)))     # uint8
        f.write(struct.pack('<B', p.get('stride', 1)))  # uint8
        # Kernel size inferred from weights
        k = weights.shape[2]
        f.write(struct.pack('<B', k))           # uint8

    return weights.shape

def main():
    # Default paths
    script_dir = os.path.dirname(os.path.abspath(__file__))
    default_npz = os.path.join(script_dir, "../sim/hardware-ai/quantized_params.npz")
    default_output = os.path.join(script_dir, "weights_cpu")

    npz_path = sys.argv[1] if len(sys.argv) > 1 else default_npz
    output_dir = sys.argv[2] if len(sys.argv) > 2 else default_output

    print(f"Loading quantized parameters from: {npz_path}")
    q_params = load_quant_params(npz_path)

    print(f"\nExporting to: {output_dir}")
    os.makedirs(output_dir, exist_ok=True)

    # Export each layer
    total_weight_bytes = 0
    total_bias_bytes = 0

    for hw_layer, npz_idx, cin, cout, k, stride, pad, activation, mp_stride in LAYER_CONFIG:
        shape = export_layer(q_params, hw_layer, npz_idx, output_dir)
        total_weight_bytes += np.prod(shape)
        total_bias_bytes += cout * 4  # INT32

    # Export global config
    global_config_path = os.path.join(output_dir, "model_config.txt")
    with open(global_config_path, 'w') as f:
        f.write("# TinyYOLOv3 Model Configuration\n")
        f.write(f"input_scale: {q_params['input_scale']}\n")
        f.write(f"num_layers: {len(LAYER_CONFIG)}\n\n")
        f.write("# Layer configs: hw_layer, npz_idx, cin, cout, k, stride, pad, activation, maxpool_stride\n")
        for cfg in LAYER_CONFIG:
            f.write(f"{cfg}\n")

    print(f"\nExport complete!")
    print(f"  Total weights: {total_weight_bytes / 1024 / 1024:.2f} MB")
    print(f"  Total biases: {total_bias_bytes / 1024:.2f} KB")
    print(f"  Config saved to: {global_config_path}")

    # Also export dequantization scales for detection heads
    dequant_path = os.path.join(output_dir, "dequant_scales.bin")
    with open(dequant_path, 'wb') as f:
        # Layer 9 (13x13 head) o_scale
        f.write(struct.pack('<f', float(q_params[15]['o_scale'])))
        # Layer 12 (26x26 head) o_scale
        f.write(struct.pack('<f', float(q_params[22]['o_scale'])))
    print(f"  Dequant scales: {dequant_path}")

if __name__ == "__main__":
    main()
