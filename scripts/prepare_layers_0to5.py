#!/usr/bin/env python3
"""
Prepare stimulus for Layers 0-5 (full downsampling path).

Uses hardware_sim.py as the GOLDEN STANDARD for all layer outputs.

Hardware Layer → NPZ Layer:
- HW Layer 0 → NPZ 0 (3→16, maxpool stride-2): 416→208
- HW Layer 1 → NPZ 2 (16→32, maxpool stride-2): 208→104
- HW Layer 2 → NPZ 4 (32→64, maxpool stride-2): 104→52
- HW Layer 3 → NPZ 6 (64→128, maxpool stride-2): 52→26
- HW Layer 4 → NPZ 8 (128→256, maxpool stride-2): 26→13
- HW Layer 5 → NPZ 10 (256→512, maxpool stride-1): 13→13

Usage:
    python prepare_layers_0to5.py [image_path] [--output-dir stimulus_chain]
"""

import argparse
import os
import sys
import numpy as np

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_ROOT = os.path.dirname(SCRIPT_DIR)
sys.path.insert(0, os.path.join(PROJECT_ROOT, 'sim', 'hardware-ai'))

from hardware_sim import load_quant_params, TinyYoloINT8

# Hardware parameters
PIN = 8
POUT = 8

# Layer configurations: (npz_idx, cin, cout, spatial_in, maxpool_stride)
# After maxpool: spatial_out = spatial_in // maxpool_stride
LAYER_CONFIGS = [
    # (hw_layer, npz_idx, cin, cout, spatial_in, maxpool_stride)
    (0, 0, 3, 16, 416, 2),    # 416→208
    (1, 2, 16, 32, 208, 2),   # 208→104
    (2, 4, 32, 64, 104, 2),   # 104→52
    (3, 6, 64, 128, 52, 2),   # 52→26
    (4, 8, 128, 256, 26, 2),  # 26→13
    (5, 10, 256, 512, 13, 1), # 13→13 (stride-1 maxpool)
]


def pad_channels(data, target_channels):
    """Pad channels from current to target (multiple of 8)."""
    if data.shape[-1] >= target_channels:
        return data
    pad_width = [(0, 0)] * (len(data.shape) - 1) + [(0, target_channels - data.shape[-1])]
    return np.pad(data, pad_width, mode='constant', constant_values=0)


def pad_spatial(data, pad=1):
    """Add spatial padding (1-pixel border for 3x3 conv)."""
    h, w, c = data.shape
    padded = np.zeros((h + 2*pad, w + 2*pad, c), dtype=data.dtype)
    padded[pad:pad+h, pad:pad+w, :] = data
    return padded


def pack_weights_binary(weights, og, ci_groups):
    """
    Pack weights for one output group in hardware format.
    72-bit words padded to 128-bit (16 bytes).
    """
    cout, cin, kh, kw = weights.shape
    cin_pad = ci_groups * 8

    # Pad weights to cin_pad channels
    weights_padded = np.zeros((cout, cin_pad, kh, kw), dtype=np.int8)
    weights_padded[:, :cin, :, :] = weights

    data = bytearray()

    # Streaming order: for addr in ci_groups: for bank in 8: for uram in 8
    for addr in range(ci_groups):
        for bank in range(8):
            filter_idx = og * POUT + bank
            for uram in range(8):
                ch = addr * 8 + uram

                # Pack 9 spatial weights into 72-bit word
                val = 0
                for spatial_idx in range(9):
                    ky = spatial_idx // 3
                    kx = spatial_idx % 3
                    w_byte = int(weights_padded[filter_idx, ch, ky, kx])
                    if w_byte < 0:
                        w_byte = w_byte & 0xFF
                    val |= w_byte << (spatial_idx * 8)

                # Pad to 128-bit (16 bytes)
                data.extend(val.to_bytes(16, byteorder='little'))

    return bytes(data)


def pack_biases_binary(biases, og):
    """Pack 8 biases for one output group as 128-bit words."""
    data = bytearray()

    for i in range(0, POUT, 4):
        val = 0
        for j in range(4):
            bias_idx = og * POUT + i + j
            b = int(biases[bias_idx])
            if b < 0:
                b = b & 0xFFFFFFFF
            val |= b << (j * 32)
        data.extend(val.to_bytes(16, byteorder='little'))

    return bytes(data)


def main():
    parser = argparse.ArgumentParser(description='Prepare Layers 0-5 stimulus')
    parser.add_argument('image', nargs='?', default='scripts/test_image.jpg',
                       help='Input image path')
    parser.add_argument('--output-dir', default='scripts/stimulus_chain',
                       help='Output directory')
    args = parser.parse_args()

    os.makedirs(args.output_dir, exist_ok=True)

    # Load quantization parameters
    quant_path = os.path.join(PROJECT_ROOT, 'sim/hardware-ai/quantized_params.npz')
    print(f"Loading quant params from {quant_path}")
    q_params = load_quant_params(quant_path)
    input_scale = q_params.get('input_scale', 127.0)

    # Run hardware_sim.py to get all layer outputs
    print(f"\nRunning hardware_sim.py on {args.image}...")
    model = TinyYoloINT8(q_params)
    model.run_forward(args.image)

    print(f"\n{'='*70}")
    print("Generating stimulus for Layers 0-5")
    print(f"{'='*70}\n")

    for hw_layer, npz_idx, cin, cout, spatial_in, mp_stride in LAYER_CONFIGS:
        print(f"\n--- HW Layer {hw_layer} (NPZ {npz_idx}): {cin}→{cout}, {spatial_in}→{spatial_in//mp_stride} ---")

        layer_dir = os.path.join(args.output_dir, f"layer{hw_layer}")
        os.makedirs(layer_dir, exist_ok=True)

        # Get layer parameters
        p = q_params[npz_idx]
        weights = p['q_weights']  # (cout, cin, 3, 3)
        biases = p['q_biases']    # (cout,)
        M = int(p['M'])
        n = int(p['n'])

        cin_pad = ((cin + 7) // 8) * 8
        ci_groups = cin_pad // 8
        co_groups = cout // 8
        spatial_out = spatial_in // mp_stride  # stride-1 maintains size, stride-2 halves
        padded_in = spatial_in + 2  # 1-pixel border

        print(f"  Weights: {weights.shape}, Biases: {biases.shape}")
        print(f"  M=0x{M:04X}, n={n}")
        print(f"  ci_groups={ci_groups}, co_groups={co_groups}")
        print(f"  Padded input: {padded_in}x{padded_in}x{cin_pad}")
        print(f"  Output: {spatial_out}x{spatial_out}x{cout}")

        # Get input from previous layer output (or image for layer 0)
        if hw_layer == 0:
            # Layer 0: use quantized input image
            # model.layer_outputs doesn't have the input, so we reconstruct it
            import cv2
            img = cv2.imread(args.image)
            img = cv2.resize(img, (416, 416))
            img = cv2.cvtColor(img, cv2.COLOR_BGR2RGB)
            img_float = img.astype(np.float32) / 255.0
            input_nhwc = np.round(img_float * input_scale).astype(np.int8)
        else:
            # Get output from previous conv layer (before maxpool for that layer)
            # hardware_sim stores outputs after each layer
            # NPZ indices: conv at 0, maxpool at 1, conv at 2, maxpool at 3, etc.
            prev_npz_idx = npz_idx - 2 + 1  # Previous maxpool layer
            prev_output = model.layer_outputs[prev_npz_idx]  # (1, C, H, W) NCHW
            input_nhwc = np.transpose(prev_output[0], (1, 2, 0))  # (H, W, C) HWC

        # Pad channels and spatial
        input_padded = pad_channels(input_nhwc, cin_pad)
        input_padded = pad_spatial(input_padded, pad=1)

        print(f"  Input data shape: {input_padded.shape}")

        # Save pixels
        pixels_path = os.path.join(layer_dir, 'pixels.bin')
        with open(pixels_path, 'wb') as f:
            f.write(input_padded.astype(np.int8).tobytes())
        print(f"  Pixels: {os.path.getsize(pixels_path):,} bytes")

        # Get expected output (after maxpool)
        # NPZ index for maxpool is npz_idx + 1
        if mp_stride == 2:
            expected_npz_idx = npz_idx + 1  # Maxpool layer
        else:
            # stride-1 maxpool - use conv output directly
            expected_npz_idx = npz_idx

        expected_nchw = model.layer_outputs[expected_npz_idx]  # (1, C, H, W)
        expected_nhwc = np.transpose(expected_nchw[0], (1, 2, 0))  # (H, W, C)

        # For stride-1 maxpool (Layer 5), we need to apply it manually
        if mp_stride == 1 and npz_idx == 10:
            # Layer 10 is conv, layer 11 is maxpool stride-1
            expected_nchw = model.layer_outputs[11]
            expected_nhwc = np.transpose(expected_nchw[0], (1, 2, 0))

        print(f"  Expected output: {expected_nhwc.shape}, range: [{expected_nhwc.min()}, {expected_nhwc.max()}]")

        # Save expected output (full)
        expected_path = os.path.join(layer_dir, 'expected.bin')
        with open(expected_path, 'wb') as f:
            f.write(expected_nhwc.astype(np.int8).tobytes())
        print(f"  Expected: {os.path.getsize(expected_path):,} bytes")

        # Save per-output-group data
        for og in range(co_groups):
            # Weights
            weights_path = os.path.join(layer_dir, f'weights_og{og}.bin')
            with open(weights_path, 'wb') as f:
                f.write(pack_weights_binary(weights, og, ci_groups))

            # Biases
            biases_path = os.path.join(layer_dir, f'biases_og{og}.bin')
            with open(biases_path, 'wb') as f:
                f.write(pack_biases_binary(biases, og))

            # Expected per OG
            og_expected = expected_nhwc[:, :, og*POUT:(og+1)*POUT]
            expected_og_path = os.path.join(layer_dir, f'expected_og{og}.bin')
            with open(expected_og_path, 'wb') as f:
                f.write(og_expected.astype(np.int8).tobytes())

        print(f"  Saved {co_groups} output groups")

        # Save config
        config_path = os.path.join(layer_dir, 'config.txt')
        with open(config_path, 'w') as f:
            f.write(f"hw_layer={hw_layer}\n")
            f.write(f"npz_idx={npz_idx}\n")
            f.write(f"cin={cin}\n")
            f.write(f"cout={cout}\n")
            f.write(f"cin_pad={cin_pad}\n")
            f.write(f"ci_groups={ci_groups}\n")
            f.write(f"co_groups={co_groups}\n")
            f.write(f"spatial_in={spatial_in}\n")
            f.write(f"spatial_out={spatial_out}\n")
            f.write(f"padded_in={padded_in}\n")
            f.write(f"maxpool_stride={mp_stride}\n")
            f.write(f"quant_m=0x{M:08x}\n")
            f.write(f"quant_n={n}\n")

    print(f"\n{'='*70}")
    print("Done! Files written to:")
    print(f"  {args.output_dir}/layer0/  (416→208, 3→16)")
    print(f"  {args.output_dir}/layer1/  (208→104, 16→32)")
    print(f"  {args.output_dir}/layer2/  (104→52, 32→64)")
    print(f"  {args.output_dir}/layer3/  (52→26, 64→128)")
    print(f"  {args.output_dir}/layer4/  (26→13, 128→256)")
    print(f"  {args.output_dir}/layer5/  (13→13, 256→512)")
    print(f"{'='*70}\n")


if __name__ == "__main__":
    main()
