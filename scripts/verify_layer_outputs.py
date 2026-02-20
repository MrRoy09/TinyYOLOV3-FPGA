#!/usr/bin/env python3
"""
Verify layer outputs against hardware_sim.py golden model.

This script:
1. Loads the actual HW outputs from a binary file
2. Runs hardware_sim.py to get expected outputs
3. Compares them channel by channel

Usage: python verify_layer_outputs.py <hw_output_file> <layer_idx> <image_path>
"""

import os
import sys
import numpy as np

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_ROOT = os.path.dirname(SCRIPT_DIR)
sys.path.insert(0, os.path.join(PROJECT_ROOT, 'sim', 'hardware-ai'))

from hardware_sim import load_quant_params, TinyYoloINT8

# Layer configurations: (hw_layer, npz_conv_idx, npz_output_idx, out_h, out_w, cout)
LAYER_INFO = {
    0: (0, 1, 208, 208, 16),    # NPZ conv=0, output=1 (after maxpool)
    1: (2, 3, 104, 104, 32),
    2: (4, 5, 52, 52, 64),
    3: (6, 7, 26, 26, 128),
    4: (8, 9, 13, 13, 256),
    5: (10, 11, 13, 13, 512),   # stride-1 maxpool
    6: (12, 12, 13, 13, 1024),  # no maxpool
    7: (13, 13, 13, 13, 256),   # 1x1 conv
    8: (14, 14, 13, 13, 512),   # 3x3 conv
    9: (15, 15, 13, 13, 255),   # 1x1 conv, linear
}


def load_hw_output(path, h, w, c):
    """Load HW output binary file as NHWC array."""
    data = np.fromfile(path, dtype=np.int8)
    expected_size = h * w * c
    if len(data) != expected_size:
        print(f"WARNING: File size {len(data)} != expected {expected_size}")
        # Pad or truncate
        if len(data) < expected_size:
            data = np.pad(data, (0, expected_size - len(data)))
        else:
            data = data[:expected_size]
    return data.reshape(h, w, c)


def compare_outputs(hw_output, golden_output, layer_idx, tolerance=3):
    """Compare HW output with golden model output."""
    # golden_output is NCHW, convert to NHWC for comparison
    if len(golden_output.shape) == 4:
        golden_nhwc = np.transpose(golden_output[0], (1, 2, 0))
    else:
        golden_nhwc = golden_output

    h, w, c = hw_output.shape

    print(f"\nLayer {layer_idx} comparison ({h}x{w}x{c}):")

    # Overall stats
    diff = hw_output.astype(np.int16) - golden_nhwc.astype(np.int16)
    exact_match = np.sum(diff == 0)
    within_tol = np.sum(np.abs(diff) <= tolerance)
    total = diff.size

    print(f"  Exact match: {exact_match}/{total} ({100*exact_match/total:.2f}%)")
    print(f"  Within ±{tolerance}: {within_tol}/{total} ({100*within_tol/total:.2f}%)")
    print(f"  Max diff: {np.max(np.abs(diff))}")

    # Per-OG stats
    num_ogs = (c + 7) // 8
    og_stats = []
    for og in range(num_ogs):
        ch_start = og * 8
        ch_end = min(ch_start + 8, c)
        og_diff = diff[:, :, ch_start:ch_end]
        og_exact = np.sum(og_diff == 0)
        og_total = og_diff.size
        og_pct = 100 * og_exact / og_total
        og_stats.append((og, og_pct, np.max(np.abs(og_diff))))

    print(f"\n  Per-OG accuracy:")
    for og, pct, max_d in og_stats:
        status = "OK" if pct > 99.0 else "WARN" if pct > 95.0 else "FAIL"
        print(f"    OG{og:2d}: {pct:6.2f}% exact, max_diff={max_d:3d} [{status}]")

    # Show first few mismatches
    mismatch_indices = np.where(np.abs(diff) > tolerance)
    if len(mismatch_indices[0]) > 0:
        print(f"\n  First 10 mismatches (outside ±{tolerance}):")
        for i in range(min(10, len(mismatch_indices[0]))):
            y, x, ch = mismatch_indices[0][i], mismatch_indices[1][i], mismatch_indices[2][i]
            hw_val = hw_output[y, x, ch]
            gold_val = golden_nhwc[y, x, ch]
            print(f"    [{y:3d},{x:3d},{ch:3d}]: HW={hw_val:4d}, golden={gold_val:4d}, diff={hw_val-gold_val:4d}")

    return exact_match == total


def main():
    if len(sys.argv) < 2:
        print("Usage: python verify_layer_outputs.py <hw_output_file> [layer_idx] [image_path]")
        print("   or: python verify_layer_outputs.py --run-all <image_path>")
        sys.exit(1)

    # Load quantization params
    quant_path = os.path.join(PROJECT_ROOT, 'sim/hardware-ai/quantized_params.npz')
    print(f"Loading quant params from {quant_path}")
    q_params = load_quant_params(quant_path)

    if sys.argv[1] == '--run-all':
        # Run full inference and save intermediate outputs for comparison
        image_path = sys.argv[2] if len(sys.argv) > 2 else 'scripts/test_image.jpg'

        print(f"\nRunning hardware_sim.py on {image_path}...")
        model = TinyYoloINT8(q_params)
        outputs = model.run_forward(image_path)

        # Save each layer's expected output
        for hw_layer, (npz_conv, npz_out, out_h, out_w, cout) in LAYER_INFO.items():
            if npz_out in outputs:
                output_nchw = outputs[npz_out]
                output_nhwc = np.transpose(output_nchw[0], (1, 2, 0))

                out_path = os.path.join(SCRIPT_DIR, f'golden_layer{hw_layer}.bin')
                output_nhwc.astype(np.int8).tofile(out_path)
                print(f"  Saved Layer {hw_layer}: {output_nhwc.shape} to {out_path}")
    else:
        hw_output_file = sys.argv[1]
        layer_idx = int(sys.argv[2]) if len(sys.argv) > 2 else 0
        image_path = sys.argv[3] if len(sys.argv) > 3 else 'scripts/test_image.jpg'

        # Get layer info
        if layer_idx not in LAYER_INFO:
            print(f"ERROR: Unknown layer {layer_idx}")
            sys.exit(1)

        npz_conv, npz_out, out_h, out_w, cout = LAYER_INFO[layer_idx]

        # Load HW output
        print(f"Loading HW output from {hw_output_file}")
        hw_output = load_hw_output(hw_output_file, out_h, out_w, cout)

        # Run golden model
        print(f"Running hardware_sim.py on {image_path}...")
        model = TinyYoloINT8(q_params)
        outputs = model.run_forward(image_path)

        # Compare
        golden_output = outputs[npz_out]
        compare_outputs(hw_output, golden_output, layer_idx)


if __name__ == "__main__":
    main()
