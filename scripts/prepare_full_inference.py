#!/usr/bin/env python3
"""
Prepare stimulus for full TinyYOLOv3 inference (all layers).

NPZ Layer → HW Layer mapping:
- NPZ 0,1:   HW 0  (Conv 3→16 + MaxPool stride-2)
- NPZ 2,3:   HW 1  (Conv 16→32 + MaxPool stride-2)
- NPZ 4,5:   HW 2  (Conv 32→64 + MaxPool stride-2)
- NPZ 6,7:   HW 3  (Conv 64→128 + MaxPool stride-2)
- NPZ 8,9:   HW 4  (Conv 128→256 + MaxPool stride-2)
- NPZ 10,11: HW 5  (Conv 256→512 + MaxPool stride-1)
- NPZ 12:    HW 6  (Conv 512→1024, no maxpool)
- NPZ 13:    HW 7  (Conv1x1 1024→256)
- NPZ 14:    HW 8  (Conv 256→512)
- NPZ 15:    HW 9  (Conv1x1 512→255, detection head 1)
- NPZ 17:    Route (take HW 7 output)
- NPZ 18:    HW 10 (Conv1x1 256→128)
- NPZ 19:    Upsample 2x (CPU)
- NPZ 20:    Route+Concat (HW 10 upsample + HW 4 output)
- NPZ 21:    HW 11 (Conv 384→256)
- NPZ 22:    HW 12 (Conv1x1 256→255, detection head 2)

Usage: python prepare_full_inference.py [image_path] [--output-dir stimulus_full]
"""

import argparse
import os
import sys
import numpy as np

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_ROOT = os.path.dirname(SCRIPT_DIR)
sys.path.insert(0, os.path.join(PROJECT_ROOT, 'sim', 'hardware-ai'))

from hardware_sim import load_quant_params, TinyYoloINT8

PIN = 8
POUT = 8

# Full layer configurations
# (hw_layer, npz_idx, cin, cout, spatial_in, spatial_out, maxpool_stride, kernel_size, use_relu)
LAYER_CONFIGS = [
    # Downsampling path (already done)
    (0, 0, 3, 16, 416, 208, 2, 3, True),
    (1, 2, 16, 32, 208, 104, 2, 3, True),
    (2, 4, 32, 64, 104, 52, 2, 3, True),
    (3, 6, 64, 128, 52, 26, 2, 3, True),
    (4, 8, 128, 256, 26, 13, 2, 3, True),
    (5, 10, 256, 512, 13, 13, 1, 3, True),  # stride-1 maxpool

    # Detection path
    (6, 12, 512, 1024, 13, 13, 0, 3, True),   # no maxpool
    (7, 13, 1024, 256, 13, 13, 0, 1, True),   # 1x1 conv
    (8, 14, 256, 512, 13, 13, 0, 3, True),    # 3x3 conv
    (9, 15, 512, 255, 13, 13, 0, 1, False),   # 1x1 conv, linear (detection head 1)

    # Second detection head
    (10, 18, 256, 128, 13, 13, 0, 1, True),   # 1x1 conv (input from route/layer 7)
    # Upsample 13→26 (CPU)
    # Concat with layer 4 output (256 channels) → 384 channels
    (11, 21, 384, 256, 26, 26, 0, 3, True),   # 3x3 conv
    (12, 22, 256, 255, 26, 26, 0, 1, False),  # 1x1 conv, linear (detection head 2)
]


def pad_channels(data, target_channels):
    """Pad channels to target (multiple of 8)."""
    if data.shape[-1] >= target_channels:
        return data
    pad_width = [(0, 0)] * (len(data.shape) - 1) + [(0, target_channels - data.shape[-1])]
    return np.pad(data, pad_width, mode='constant', constant_values=0)


def pad_spatial(data, pad=1):
    """Add spatial padding for 3x3 conv."""
    h, w, c = data.shape
    padded = np.zeros((h + 2*pad, w + 2*pad, c), dtype=data.dtype)
    padded[pad:pad+h, pad:pad+w, :] = data
    return padded


def pack_weights_binary(weights, og, ci_groups, kernel_size=3):
    """Pack weights for one output group."""
    cout, cin, kh, kw = weights.shape
    cin_pad = ci_groups * 8
    cout_pad = ((cout + 7) // 8) * 8  # Pad output channels to multiple of 8

    # Pad both input and output channels
    weights_padded = np.zeros((cout_pad, cin_pad, kh, kw), dtype=np.int8)
    weights_padded[:cout, :cin, :, :] = weights

    data = bytearray()

    if kernel_size == 1:
        # 1x1 conv: only center weight, pack as 72 bits (9 bytes with 8 zeros)
        for addr in range(ci_groups):
            for bank in range(8):
                filter_idx = og * POUT + bank
                for uram in range(8):
                    ch = addr * 8 + uram
                    # Only center pixel (position 4 of 9)
                    val = 0
                    for spatial_idx in range(9):
                        if spatial_idx == 4:  # center
                            w_byte = int(weights_padded[filter_idx, ch, 0, 0])
                            if w_byte < 0:
                                w_byte = w_byte & 0xFF
                            val |= w_byte << (spatial_idx * 8)
                    data.extend(val.to_bytes(16, byteorder='little'))
    else:
        # 3x3 conv
        for addr in range(ci_groups):
            for bank in range(8):
                filter_idx = og * POUT + bank
                for uram in range(8):
                    ch = addr * 8 + uram
                    val = 0
                    for spatial_idx in range(9):
                        ky = spatial_idx // 3
                        kx = spatial_idx % 3
                        w_byte = int(weights_padded[filter_idx, ch, ky, kx])
                        if w_byte < 0:
                            w_byte = w_byte & 0xFF
                        val |= w_byte << (spatial_idx * 8)
                    data.extend(val.to_bytes(16, byteorder='little'))

    return bytes(data)


def pack_biases_binary(biases, og):
    """Pack 8 biases for one output group."""
    data = bytearray()
    for i in range(0, POUT, 4):
        val = 0
        for j in range(4):
            bias_idx = og * POUT + i + j
            if bias_idx < len(biases):
                b = int(biases[bias_idx])
                if b < 0:
                    b = b & 0xFFFFFFFF
                val |= b << (j * 32)
        data.extend(val.to_bytes(16, byteorder='little'))
    return bytes(data)


def main():
    parser = argparse.ArgumentParser(description='Prepare full inference stimulus')
    parser.add_argument('image', nargs='?', default='scripts/test_image.jpg')
    parser.add_argument('--output-dir', default='scripts/stimulus_full')
    args = parser.parse_args()

    os.makedirs(args.output_dir, exist_ok=True)

    # Load quantization parameters
    quant_path = os.path.join(PROJECT_ROOT, 'sim/hardware-ai/quantized_params.npz')
    print(f"Loading quant params from {quant_path}")
    q_params = load_quant_params(quant_path)
    input_scale = q_params.get('input_scale', 127.0)

    # Run full inference to get all layer outputs
    print(f"\nRunning hardware_sim.py on {args.image}...")
    model = TinyYoloINT8(q_params)
    model.run_forward(args.image)

    print(f"\n{'='*70}")
    print("Generating stimulus for all layers")
    print(f"{'='*70}\n")

    # Also save special outputs needed for routing
    route_outputs = {}

    for hw_layer, npz_idx, cin, cout, spatial_in, spatial_out, mp_stride, kernel_size, use_relu in LAYER_CONFIGS:
        print(f"\n--- HW Layer {hw_layer} (NPZ {npz_idx}): {cin}→{cout}, {spatial_in}→{spatial_out}, k={kernel_size}x{kernel_size} ---")

        layer_dir = os.path.join(args.output_dir, f"layer{hw_layer}")
        os.makedirs(layer_dir, exist_ok=True)

        # Get layer parameters
        p = q_params[npz_idx]
        weights = p['q_weights']
        biases = p['q_biases']
        M = int(p['M'])
        n = int(p['n'])

        cin_pad = ((cin + 7) // 8) * 8
        ci_groups = cin_pad // 8
        co_groups = cout // 8 if cout >= 8 else 1

        # Handle 255 output channels (detection heads)
        if cout == 255:
            co_groups = 32  # 32 groups, last one has only 7 valid channels

        padded_in = spatial_in + 2 if kernel_size == 3 else spatial_in

        print(f"  Weights: {weights.shape}, Biases: {biases.shape}")
        print(f"  M=0x{M:04X}, n={n}, use_relu={use_relu}")
        print(f"  ci_groups={ci_groups}, co_groups={co_groups}")

        # Determine input source
        if hw_layer == 0:
            # Layer 0: use quantized input image
            import cv2
            img = cv2.imread(args.image)
            img = cv2.resize(img, (416, 416))
            img = cv2.cvtColor(img, cv2.COLOR_BGR2RGB)
            img_float = img.astype(np.float32) / 255.0
            input_nhwc = np.round(img_float * input_scale).astype(np.int8)
        elif hw_layer == 10:
            # Layer 10: input from route (layer 7 output = NPZ 13)
            input_nchw = model.layer_outputs[13]  # HW layer 7 output
            input_nhwc = np.transpose(input_nchw[0], (1, 2, 0))
        elif hw_layer == 11:
            # Layer 11: input from concat (upsample(layer 10) + layer 4)
            # This needs CPU preprocessing - save the components
            layer10_out = model.layer_outputs[18]  # HW layer 10 output = NPZ 18 (13x13x128)
            layer4_out = model.layer_outputs[8]    # Conv output BEFORE maxpool = NPZ 8 (26x26x256)

            # Upsample layer 10 output: 13x13x128 -> 26x26x128
            upsampled = layer10_out.repeat(2, axis=2).repeat(2, axis=3)

            # Concat: 26x26x128 + 26x26x256 = 26x26x384
            concat_out = np.concatenate([upsampled, layer4_out], axis=1)
            input_nhwc = np.transpose(concat_out[0], (1, 2, 0))
        else:
            # Use previous layer's output
            # For stride-2 and stride-1 maxpool layers, input is previous layer's maxpool output
            # NPZ layout: conv at N, maxpool at N+1, so previous maxpool is at npz_idx - 1
            if mp_stride >= 1:
                prev_npz_idx = npz_idx - 1  # Previous layer's maxpool output
            else:
                prev_npz_idx = npz_idx - 1  # Previous conv (no maxpool)

            # Special cases for detection path
            if hw_layer == 6:
                prev_npz_idx = 11  # After stride-1 maxpool
            elif hw_layer == 7:
                prev_npz_idx = 12  # After layer 6 conv
            elif hw_layer == 8:
                prev_npz_idx = 13  # After layer 7 conv
            elif hw_layer == 9:
                prev_npz_idx = 14  # After layer 8 conv
            elif hw_layer == 12:
                prev_npz_idx = 21  # After layer 11 conv

            prev_output = model.layer_outputs[prev_npz_idx]
            input_nhwc = np.transpose(prev_output[0], (1, 2, 0))

        # Pad channels and spatial
        input_padded = pad_channels(input_nhwc, cin_pad)
        if kernel_size == 3:
            input_padded = pad_spatial(input_padded, pad=1)

        print(f"  Input shape: {input_padded.shape}")

        # Save pixels
        pixels_path = os.path.join(layer_dir, 'pixels.bin')
        with open(pixels_path, 'wb') as f:
            f.write(input_padded.astype(np.int8).tobytes())
        print(f"  Pixels: {os.path.getsize(pixels_path):,} bytes")

        # Get expected output
        if mp_stride == 2:
            expected_npz_idx = npz_idx + 1
        elif mp_stride == 1:
            expected_npz_idx = npz_idx + 1  # Maxpool output for stride-1
        else:
            expected_npz_idx = npz_idx  # No maxpool, use conv output directly

        expected_nchw = model.layer_outputs[expected_npz_idx]
        expected_nhwc = np.transpose(expected_nchw[0], (1, 2, 0))

        print(f"  Expected output: {expected_nhwc.shape}")

        # Save expected output
        expected_path = os.path.join(layer_dir, 'expected.bin')
        with open(expected_path, 'wb') as f:
            f.write(expected_nhwc.astype(np.int8).tobytes())

        # Save per-output-group data
        for og in range(co_groups):
            weights_path = os.path.join(layer_dir, f'weights_og{og}.bin')
            with open(weights_path, 'wb') as f:
                f.write(pack_weights_binary(weights, og, ci_groups, kernel_size))

            biases_path = os.path.join(layer_dir, f'biases_og{og}.bin')
            with open(biases_path, 'wb') as f:
                f.write(pack_biases_binary(biases, og))

            # Expected per OG
            og_channels = min(8, cout - og * 8)
            og_expected = expected_nhwc[:, :, og*POUT:og*POUT+og_channels]
            # Pad to 8 channels if needed
            if og_channels < 8:
                og_expected = np.pad(og_expected, [(0,0), (0,0), (0, 8-og_channels)])
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
            f.write(f"kernel_size={kernel_size}\n")
            f.write(f"use_relu={1 if use_relu else 0}\n")
            f.write(f"quant_m=0x{M:08x}\n")
            f.write(f"quant_n={n}\n")

    print(f"\n{'='*70}")
    print("Done! Stimulus written to:")
    for hw_layer, npz_idx, cin, cout, spatial_in, spatial_out, _, ks, _ in LAYER_CONFIGS:
        print(f"  layer{hw_layer}/  ({cin}→{cout}, {spatial_in}→{spatial_out}, {ks}x{ks})")
    print(f"{'='*70}\n")


if __name__ == "__main__":
    main()
