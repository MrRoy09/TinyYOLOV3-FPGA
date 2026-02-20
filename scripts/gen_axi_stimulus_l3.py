#!/usr/bin/env python3
"""
Generate AXI-compatible stimulus for Layer 3 (ci_groups=8) testbench.
Uses stimulus from gen_layer3_stimulus.py.
"""

import os
import numpy as np

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
STIM_DIR = os.path.join(SCRIPT_DIR, "stimulus_l3")
OUT_DIR = os.path.join(SCRIPT_DIR, "..", "TinyYOLOV3_HW_Complete_ex", "imports")

# Layer 3 config
CI_GROUPS = 8
CO_GROUPS = 16


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


def convert_biases_to_128(input_file, output_file):
    """Copy biases_all.hex (already 128-bit packed)."""
    print(f"Copying biases: {input_file} -> {output_file}")
    import shutil
    shutil.copy(input_file, output_file)


def copy_file(src, dst):
    """Copy a file."""
    import shutil
    print(f"Copying: {src} -> {dst}")
    shutil.copy(src, dst)


def main():
    os.makedirs(OUT_DIR, exist_ok=True)

    print("=" * 60)
    print("Generating AXI stimulus for Layer 3 (ci_groups=8)")
    print("=" * 60)

    # For single OG test, use OG0
    og = 0

    # Weights: convert 72-bit hex to 128-bit
    weights_src = os.path.join(STIM_DIR, f"weights_og{og}.hex")
    weights_dst = os.path.join(OUT_DIR, "weights_axi.hex")
    convert_weights_72_to_128(weights_src, weights_dst)

    # Biases: use all biases (for proper addressing)
    biases_src = os.path.join(STIM_DIR, "biases_all.hex")
    biases_dst = os.path.join(OUT_DIR, "biases_axi.hex")
    convert_biases_to_128(biases_src, biases_dst)

    # Pixels: copy directly (already 64-bit format)
    pixels_src = os.path.join(STIM_DIR, f"pixels_og{og}.hex")
    pixels_dst = os.path.join(OUT_DIR, "pixels_og0.hex")
    copy_file(pixels_src, pixels_dst)

    # Expected: copy directly
    expected_src = os.path.join(STIM_DIR, f"expected_og{og}.hex")
    expected_dst = os.path.join(OUT_DIR, "expected_og0.hex")
    copy_file(expected_src, expected_dst)

    # Write config file for testbench
    config_path = os.path.join(OUT_DIR, "layer3_config.txt")
    with open(config_path, 'w') as f:
        f.write(f"# Layer 3 AXI testbench config\n")
        f.write(f"ci_groups=8\n")
        f.write(f"co_groups=16\n")
        f.write(f"img_width=6\n")
        f.write(f"in_channels=64\n")
        f.write(f"quant_m=0x022b\n")
        f.write(f"quant_n=16\n")

    print()
    print("Files written:")
    for f in ["weights_axi.hex", "biases_axi.hex", "pixels_og0.hex", "expected_og0.hex"]:
        path = os.path.join(OUT_DIR, f)
        if os.path.exists(path):
            with open(path, 'r') as fp:
                lines = len(fp.readlines())
            print(f"  {f}: {lines} lines")

    print()
    print("Now update testbench configuration in TinyYOLOV3_HW_Complete_tb.sv:")
    print("  cfg_ci_groups = 8")
    print("  cfg_in_channels = 64")
    print("  cfg_img_width = 6")
    print("  cfg_quant_m = 0x022b")


if __name__ == "__main__":
    main()
