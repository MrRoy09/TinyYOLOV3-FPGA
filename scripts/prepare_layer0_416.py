#!/usr/bin/env python3
"""
Prepare Layer 0 stimulus for 416x416 real image.

Uses hardware_sim.py as the GOLDEN STANDARD for quantization since
it produces correct detections.

This script:
1. Loads a real image and converts to INT8 (matching hardware_sim.py)
2. Pads channels (3->8) and spatial (416->418)
3. Uses quantization parameters from hardware_sim.py
4. Generates expected output using hardware_sim.py's INT8 convolution
5. Outputs binary files for C++ host code

Usage:
    python prepare_layer0_416.py [image_path] [--output-dir stimulus_416]
"""

import argparse
import os
import sys
import numpy as np
import cv2

# Add paths
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_ROOT = os.path.dirname(SCRIPT_DIR)
sys.path.insert(0, SCRIPT_DIR)
sys.path.insert(0, os.path.join(PROJECT_ROOT, 'sim', 'hardware-ai'))

from hardware_sim import load_quant_params, TinyYoloINT8

# Hardware parameters
PIN = 8
POUT = 8
IMG_SIZE = 416
PADDED_SIZE = 418  # 416 + 2 (1-pixel border for 3x3 conv)
CIN = 3
CIN_PAD = 8
COUT = 16
CI_GROUPS = 1
CO_GROUPS = 2

# Output dimensions after conv (no padding in output) + maxpool stride-2
OUT_H = (PADDED_SIZE - 2) // 2  # (418-2)/2 = 208
OUT_W = (PADDED_SIZE - 2) // 2  # 208


def load_and_preprocess_image(image_path, input_scale=127.0):
    """
    Load image and convert to INT8 NHWC format with padding.
    Matches hardware_sim.py preprocessing.
    """
    img = cv2.imread(image_path)
    if img is None:
        raise ValueError(f"Cannot load image: {image_path}")

    # Resize to 416x416
    img = cv2.resize(img, (IMG_SIZE, IMG_SIZE))
    img = cv2.cvtColor(img, cv2.COLOR_BGR2RGB)

    # Normalize and quantize to INT8 (same as hardware_sim.py)
    img_float = img.astype(np.float32) / 255.0
    img_int8 = np.round(img_float * input_scale).astype(np.int8)

    print(f"Image INT8 range: [{img_int8.min()}, {img_int8.max()}]")

    # Pad channels 3 -> 8 (NHWC format)
    img_ch_padded = np.zeros((IMG_SIZE, IMG_SIZE, CIN_PAD), dtype=np.int8)
    img_ch_padded[:, :, :CIN] = img_int8

    # Pad spatial 416 -> 418 (1-pixel zero border for 3x3 conv)
    img_full = np.zeros((PADDED_SIZE, PADDED_SIZE, CIN_PAD), dtype=np.int8)
    img_full[1:1+IMG_SIZE, 1:1+IMG_SIZE, :] = img_ch_padded

    return img_full, img_int8


def reference_conv_layer0(img_nhwc, q_params):
    """
    Compute layer 0 conv using hardware_sim.py's INT8 arithmetic.

    This matches the golden standard that produces correct detections.
    """
    # Get quantized weights and biases from hardware_sim.py
    p = q_params[0]  # Layer 0
    weights = p['q_weights']  # (16, 3, 3, 3) - OIHW format
    biases = p['q_biases']    # (16,)
    M = int(p['M'])
    n = int(p['n'])
    activation = p['activation']

    print(f"Using hardware_sim.py quantization:")
    print(f"  Weights shape: {weights.shape}, range: [{weights.min()}, {weights.max()}]")
    print(f"  Biases range: [{biases.min()}, {biases.max()}]")
    print(f"  M=0x{M:08x} ({M}), n={n}")
    print(f"  Activation: {activation}")

    # Pad weights to CIN_PAD channels
    weights_padded = np.zeros((COUT, CIN_PAD, 3, 3), dtype=np.int8)
    weights_padded[:, :CIN, :, :] = weights

    # Output before maxpool: (416, 416, 16)
    conv_h = PADDED_SIZE - 2  # 416
    conv_w = PADDED_SIZE - 2  # 416

    # Convolution with INT32 accumulator
    print(f"\nComputing convolution ({conv_h}x{conv_w}x{COUT})...")
    conv_out = np.zeros((conv_h, conv_w, COUT), dtype=np.int32)

    for f in range(COUT):
        if f % 4 == 0:
            print(f"  Filter {f}/{COUT}...", end='\r')
        for c in range(CIN_PAD):
            for ky in range(3):
                for kx in range(3):
                    w = int(weights_padded[f, c, ky, kx])
                    if w == 0:
                        continue
                    # Sliding window
                    for y in range(conv_h):
                        for x in range(conv_w):
                            p = int(img_nhwc[y + ky, x + kx, c])
                            conv_out[y, x, f] += p * w

        # Add bias
        conv_out[:, :, f] += int(biases[f])

    print(f"  Conv output range (pre-quantization): [{conv_out.min()}, {conv_out.max()}]")

    # Hardware order (from quantizer.sv):
    # 1. Multiply by M
    # 2. Shift right by n
    # 3. Leaky ReLU (>>3 for negative)
    # 4. Clamp to INT8

    # Step 1-2: Quantization: (acc * M) >> n
    conv_out = (conv_out.astype(np.int64) * M) >> n
    print(f"  After quantization: [{conv_out.min()}, {conv_out.max()}]")

    # Step 3: Leaky ReLU AFTER quantization (matching hardware)
    if activation == 'leaky':
        conv_out = np.where(conv_out >= 0, conv_out, conv_out >> 3)
        print(f"  After leaky ReLU: [{conv_out.min()}, {conv_out.max()}]")

    # Step 4: Clamp to INT8
    conv_out = np.clip(conv_out, -128, 127).astype(np.int8)
    print(f"  After clamp: [{conv_out.min()}, {conv_out.max()}]")

    # Maxpool 2x2 stride-2
    print(f"\nComputing maxpool ({OUT_H}x{OUT_W}x{COUT})...")
    mp_out = np.zeros((OUT_H, OUT_W, COUT), dtype=np.int8)
    for y in range(OUT_H):
        for x in range(OUT_W):
            for f in range(COUT):
                window = conv_out[y*2:y*2+2, x*2:x*2+2, f]
                mp_out[y, x, f] = np.max(window)

    print(f"  Maxpool output range: [{mp_out.min()}, {mp_out.max()}]")

    return mp_out, conv_out


def pack_pixels_binary(img):
    """Pack NHWC image as binary file (row-major, 8 bytes per pixel)."""
    return img.astype(np.int8).tobytes()


def pack_weights_binary(q_params, og):
    """
    Pack weights for one output group in hardware format.
    Returns bytes for 72-bit words padded to 128-bit.

    Uses weights from hardware_sim.py (the golden standard).
    """
    p = q_params[0]
    weights = p['q_weights']  # (16, 3, 3, 3)

    # Pad to CIN_PAD channels
    weights_padded = np.zeros((COUT, CIN_PAD, 3, 3), dtype=np.int8)
    weights_padded[:, :CIN, :, :] = weights

    data = bytearray()

    # Streaming order: for addr in ci_groups: for bank in 8: for uram in 8
    for addr in range(CI_GROUPS):
        for bank in range(8):
            filter_idx = og * POUT + bank
            for uram in range(8):
                ch = addr * 8 + uram

                # Pack 9 spatial weights into 72-bit word
                # w[0][0] at bits[7:0], w[2][2] at bits[71:64]
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


def pack_biases_binary(q_params, og):
    """
    Pack biases for one output group as 128-bit words.
    4 biases per 128-bit word.

    Uses biases from hardware_sim.py (the golden standard).
    """
    p = q_params[0]
    biases = p['q_biases']  # (16,)

    data = bytearray()

    # Pack 8 biases for this output group (2 x 128-bit words, 4 biases each)
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


def pack_output_binary(output):
    """Pack NHWC output as binary file."""
    return output.astype(np.int8).tobytes()


def verify_with_hardware_sim(image_path, q_params):
    """
    Run hardware_sim.py's TinyYoloINT8 and extract layer 0+1 output.
    This is the absolute golden reference.

    In hardware_sim.py:
    - Layer 0: Conv 3x3 (416x416x16)
    - Layer 1: MaxPool 2x2 stride-2 (208x208x16)
    """
    print("\nRunning hardware_sim.py TinyYoloINT8 for verification...")
    int8_model = TinyYoloINT8(q_params)
    int8_model.run_forward(image_path)

    # Layer 0 is conv (pre-maxpool), Layer 1 is maxpool
    # We want output after maxpool (layer 1)
    layer1_out = int8_model.layer_outputs[1]  # (1, 16, 208, 208) NCHW
    layer1_out_nhwc = np.transpose(layer1_out[0], (1, 2, 0))  # (208, 208, 16) HWC

    print(f"  hardware_sim layer 1 (post-maxpool) shape: {layer1_out_nhwc.shape}")
    print(f"  hardware_sim layer 1 output range: [{layer1_out_nhwc.min()}, {layer1_out_nhwc.max()}]")

    # Also show layer 0 (pre-maxpool) for debugging
    layer0_out = int8_model.layer_outputs[0]
    print(f"  hardware_sim layer 0 (pre-maxpool) shape: {layer0_out.shape}")
    print(f"  hardware_sim layer 0 output range: [{layer0_out.min()}, {layer0_out.max()}]")

    return layer1_out_nhwc


def main():
    parser = argparse.ArgumentParser(description='Prepare Layer 0 416x416 stimulus')
    parser.add_argument('image', nargs='?', default='scripts/test_image.jpg',
                       help='Input image path')
    parser.add_argument('--output-dir', default='scripts/stimulus_416',
                       help='Output directory')
    args = parser.parse_args()

    os.makedirs(args.output_dir, exist_ok=True)

    # Load quantization parameters from hardware_sim.py (golden standard)
    quant_path = os.path.join(PROJECT_ROOT, 'sim/hardware-ai/quantized_params.npz')
    print(f"Loading quant params from {quant_path}")
    q_params = load_quant_params(quant_path)
    input_scale = q_params.get('input_scale', 127.0)
    print(f"Input scale: {input_scale}")

    # Get layer 0 M and n
    M = int(q_params[0]['M'])
    n = int(q_params[0]['n'])

    # Load and preprocess image
    print(f"\nLoading image: {args.image}")
    img_padded, img_orig = load_and_preprocess_image(args.image, input_scale)
    print(f"Padded image shape: {img_padded.shape}")

    # Save pixel data
    pixels_path = os.path.join(args.output_dir, 'pixels.bin')
    with open(pixels_path, 'wb') as f:
        f.write(pack_pixels_binary(img_padded))
    print(f"\nPixels written: {os.path.getsize(pixels_path):,} bytes")

    # Compute expected output using our reference (should match hardware_sim.py)
    print("\n" + "="*60)
    print("Computing reference output...")
    print("="*60)
    expected, conv_pre_mp = reference_conv_layer0(img_padded, q_params)
    print(f"\nExpected output shape: {expected.shape}")

    # Verify against hardware_sim.py
    print("\n" + "="*60)
    print("Verifying against hardware_sim.py...")
    print("="*60)
    hw_sim_out = verify_with_hardware_sim(args.image, q_params)

    # Compare
    diff = np.abs(expected.astype(np.int16) - hw_sim_out.astype(np.int16))
    max_diff = np.max(diff)
    exact_match = np.sum(diff == 0)
    total = diff.size

    print(f"\nComparison with hardware_sim.py:")
    print(f"  Exact matches: {exact_match}/{total} ({100*exact_match/total:.1f}%)")
    print(f"  Max difference: {max_diff}")

    if max_diff > 0:
        print(f"  WARNING: Outputs don't match exactly!")
        # Show first few mismatches
        mismatches = np.where(diff > 0)
        for i in range(min(5, len(mismatches[0]))):
            y, x, c = mismatches[0][i], mismatches[1][i], mismatches[2][i]
            print(f"    [{y},{x},{c}]: expected={expected[y,x,c]}, hw_sim={hw_sim_out[y,x,c]}")

    # Save expected output (use hardware_sim.py output as ground truth)
    expected_path = os.path.join(args.output_dir, 'expected.bin')
    with open(expected_path, 'wb') as f:
        f.write(pack_output_binary(hw_sim_out))
    print(f"\nExpected written: {os.path.getsize(expected_path):,} bytes")

    # Save per-output-group expected
    for og in range(CO_GROUPS):
        og_expected = hw_sim_out[:, :, og*POUT:(og+1)*POUT]
        og_path = os.path.join(args.output_dir, f'expected_og{og}.bin')
        with open(og_path, 'wb') as f:
            f.write(pack_output_binary(og_expected))
        print(f"Expected OG{og} written: {os.path.getsize(og_path):,} bytes")

    # Save weights and biases per output group
    for og in range(CO_GROUPS):
        weights_path = os.path.join(args.output_dir, f'weights_og{og}.bin')
        with open(weights_path, 'wb') as f:
            f.write(pack_weights_binary(q_params, og))
        print(f"Weights OG{og} written: {os.path.getsize(weights_path):,} bytes")

        biases_path = os.path.join(args.output_dir, f'biases_og{og}.bin')
        with open(biases_path, 'wb') as f:
            f.write(pack_biases_binary(q_params, og))
        print(f"Biases OG{og} written: {os.path.getsize(biases_path):,} bytes")

    # Save quant params (using hardware_sim.py's single M,n for all OGs)
    params_path = os.path.join(args.output_dir, 'quant_params.txt')
    with open(params_path, 'w') as f:
        f.write(f"# Layer 0 quantization parameters (from hardware_sim.py)\n")
        f.write(f"# Using SAME M,n for all output groups\n")
        f.write(f"m=0x{M:08x}\n")
        f.write(f"n={n}\n")
        f.write(f"input_scale={input_scale}\n")

    # Summary
    print(f"\n{'='*60}")
    print("SUMMARY")
    print(f"{'='*60}")
    print(f"Input:  {PADDED_SIZE}x{PADDED_SIZE}x{CIN_PAD} = {PADDED_SIZE*PADDED_SIZE*CIN_PAD:,} bytes")
    print(f"Output: {OUT_H}x{OUT_W}x{COUT} = {OUT_H*OUT_W*COUT:,} bytes")
    print(f"Quant:  M=0x{M:08x}, n={n}")
    print(f"Files written to: {args.output_dir}")

    # List files
    print(f"\nFiles:")
    for f in sorted(os.listdir(args.output_dir)):
        fp = os.path.join(args.output_dir, f)
        print(f"  {f}: {os.path.getsize(fp):,} bytes")


if __name__ == "__main__":
    main()
