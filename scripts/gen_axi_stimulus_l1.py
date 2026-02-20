#!/usr/bin/env python3
"""
Generate AXI-compatible stimulus files for TinyYOLOV3_HW_Complete testbench.
Layer 1 configuration: ci_groups=2 (16->32 channels)

Converts stimulus from scripts/stimulus_l1/:
- 72-bit weights -> 128-bit zero-padded
- 32-bit biases -> 128-bit packed (4 per word)
- Copies 64-bit pixels and expected outputs as-is
"""

import os
import shutil

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
STIM_DIR = os.path.join(SCRIPT_DIR, "stimulus_l1")
OUT_DIR = os.path.join(SCRIPT_DIR, "..", "TinyYOLOV3_HW_Complete_ex", "imports")
XSIM_DIR = os.path.join(SCRIPT_DIR, "..", "TinyYOLOV3_HW_Complete_ex",
                        "TinyYOLOV3_HW_Complete_ex.sim", "sim_1", "behav", "xsim")


def convert_weights_72_to_128(input_file, output_file):
    """Convert 72-bit weight hex to 128-bit zero-padded format."""
    print(f"Converting weights: {input_file} -> {output_file}")

    count = 0
    with open(input_file, 'r') as fin:
        with open(output_file, 'w') as fout:
            for line in fin:
                line = line.strip()
                if not line:
                    continue
                # 72-bit value in hex = 18 hex chars
                # Pad to 128-bit = 32 hex chars (zero-extend on the left)
                val_128bit = line.zfill(32)
                fout.write(val_128bit + '\n')
                count += 1

    print(f"  Converted {count} weight entries")
    return count


def convert_biases_128_to_128(input_file, output_file):
    """Copy 128-bit bias hex directly (already packed from gen_layer1_stimulus.py)."""
    print(f"Copying biases: {input_file} -> {output_file}")

    count = 0
    with open(input_file, 'r') as fin:
        with open(output_file, 'w') as fout:
            for line in fin:
                line = line.strip()
                if line:
                    fout.write(line + '\n')
                    count += 1

    print(f"  Copied {count} bias entries (128-bit)")
    return count


def copy_file(src, dst):
    """Copy a file and report."""
    print(f"Copying: {src} -> {dst}")
    shutil.copy(src, dst)


def main():
    os.makedirs(OUT_DIR, exist_ok=True)

    print("=" * 60)
    print("Generating AXI-compatible stimulus for Layer 1 (ci_groups=2)")
    print("=" * 60)
    print()

    # Check source files exist
    weights_src = os.path.join(STIM_DIR, "weights_og0.hex")
    biases_src = os.path.join(STIM_DIR, "biases_all.hex")
    pixels_src = os.path.join(STIM_DIR, "pixels_og0.hex")
    expected_src = os.path.join(STIM_DIR, "expected_og0.hex")

    for f in [weights_src, biases_src, pixels_src, expected_src]:
        if not os.path.exists(f):
            print(f"ERROR: Source file not found: {f}")
            print("Run gen_layer1_stimulus.py first!")
            return

    # Show quant params
    with open(os.path.join(STIM_DIR, "quant_params.txt")) as f:
        print("Quant params:")
        print(f.read())

    # Convert weights (72-bit -> 128-bit)
    wt_count = convert_weights_72_to_128(weights_src, os.path.join(OUT_DIR, "weights_axi.hex"))
    print()

    # Copy biases (already 128-bit packed)
    bias_count = convert_biases_128_to_128(biases_src, os.path.join(OUT_DIR, "biases_axi.hex"))
    print()

    # Copy pixel and expected files (already 64-bit)
    copy_file(pixels_src, os.path.join(OUT_DIR, "pixels_og0.hex"))
    copy_file(expected_src, os.path.join(OUT_DIR, "expected_og0.hex"))

    # Also copy to xsim directory if it exists
    if os.path.isdir(XSIM_DIR):
        print()
        print("Copying to xsim working directory...")
        for hexfile in ["weights_axi.hex", "biases_axi.hex", "pixels_og0.hex", "expected_og0.hex"]:
            src = os.path.join(OUT_DIR, hexfile)
            dst = os.path.join(XSIM_DIR, hexfile)
            if os.path.exists(src):
                shutil.copy(src, dst)
                print(f"  {hexfile} -> xsim/")
    else:
        print(f"\nNote: xsim dir doesn't exist yet: {XSIM_DIR}")
        print("Files will be copied when simulation runs.")

    print()
    print("=" * 60)
    print("Layer 1 parameters for testbench:")
    print(f"  num_weights = {wt_count * 16} bytes ({wt_count} entries)")
    print(f"  num_bias = {bias_count * 16} bytes ({bias_count} entries)")
    print(f"  num_pixels = 72 * 8 = 576 bytes (6x6 x 2 ci_groups)")
    print(f"  num_outputs = 4 * 8 = 32 bytes (2x2 maxpool)")
    print(f"  cfg_ci_groups = 2")
    print(f"  cfg_in_channels = 16")
    print(f"  cfg_img_width = 6")
    print(f"  cfg_quant_m = 0x1bb (443)")
    print(f"  cfg_quant_n = 16")
    print()
    print(f"Files written to: {OUT_DIR}")
    print("=" * 60)


if __name__ == "__main__":
    main()
