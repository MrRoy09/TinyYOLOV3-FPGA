#!/usr/bin/env python3
"""
Generate AXI-compatible stimulus files for TinyYOLOV3_HW_Complete testbench.

Converts existing stimulus files to AXI VIP format:
- 72-bit weights → 128-bit zero-padded
- Copies 64-bit pixels and expected outputs as-is
- Converts 32-bit biases to 128-bit packed format

Output files go to TinyYOLOV3_HW_Complete_ex/imports/ for simulation.
"""

import os
import shutil

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
STIM_DIR = os.path.join(SCRIPT_DIR, "stimulus")
OUT_DIR = os.path.join(SCRIPT_DIR, "..", "TinyYOLOV3_HW_Complete_ex", "imports")
# Also copy to xsim working directory where $readmemh looks for files
XSIM_DIR = os.path.join(SCRIPT_DIR, "..", "TinyYOLOV3_HW_Complete_ex",
                        "TinyYOLOV3_HW_Complete_ex.sim", "sim_1", "behav", "xsim")


def convert_weights_72_to_128(input_file, output_file):
    """Convert 72-bit weight hex to 128-bit zero-padded format."""
    print(f"Converting weights: {input_file} -> {output_file}")

    with open(input_file, 'r') as fin:
        with open(output_file, 'w') as fout:
            for line_num, line in enumerate(fin):
                line = line.strip()
                if not line:
                    continue

                # 72-bit value in hex = 18 hex chars
                # Pad to 128-bit = 32 hex chars (zero-extend on the left)
                val_128bit = line.zfill(32)
                fout.write(val_128bit + '\n')

    print(f"  Converted {line_num + 1} weight entries")


def convert_biases_32_to_128(input_file, output_file):
    """Convert 32-bit bias hex to 128-bit packed format (4 biases per word)."""
    print(f"Converting biases: {input_file} -> {output_file}")

    biases = []
    with open(input_file, 'r') as fin:
        for line in fin:
            line = line.strip()
            if line:
                # 32-bit signed value
                val = int(line, 16)
                biases.append(val)

    print(f"  Read {len(biases)} biases")

    # Pack 4 biases per 128-bit word (little-endian: bias[0] in bits [31:0])
    with open(output_file, 'w') as fout:
        for i in range(0, len(biases), 4):
            word_128 = 0
            for j in range(4):
                if i + j < len(biases):
                    # Convert to unsigned 32-bit representation
                    val = biases[i + j] & 0xFFFFFFFF
                    word_128 |= val << (j * 32)

            fout.write(f"{word_128:032x}\n")

    print(f"  Output {(len(biases) + 3) // 4} 128-bit words")


def copy_file(src, dst):
    """Copy a file and report."""
    print(f"Copying: {src} -> {dst}")
    shutil.copy(src, dst)


def main():
    os.makedirs(OUT_DIR, exist_ok=True)

    print("=" * 60)
    print("Generating AXI-compatible stimulus for testbench")
    print("=" * 60)
    print()

    # Convert weights (72-bit -> 128-bit)
    convert_weights_72_to_128(
        os.path.join(STIM_DIR, "weights_og0.hex"),
        os.path.join(OUT_DIR, "weights_axi.hex")
    )
    print()

    # Convert biases (use biases_all.hex which has all 16 biases)
    # Or convert from biases_og0.hex (8 biases)
    convert_biases_32_to_128(
        os.path.join(STIM_DIR, "biases_og0.hex"),
        os.path.join(OUT_DIR, "biases_axi.hex")
    )
    print()

    # Copy pixel and expected files (already 64-bit)
    copy_file(
        os.path.join(STIM_DIR, "pixels_og0.hex"),
        os.path.join(OUT_DIR, "pixels_og0.hex")
    )

    copy_file(
        os.path.join(STIM_DIR, "expected_og0.hex"),
        os.path.join(OUT_DIR, "expected_og0.hex")
    )

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

    print()
    print("=" * 60)
    print("Done! Files written to:")
    print(f"  {OUT_DIR}")
    if os.path.isdir(XSIM_DIR):
        print(f"  {XSIM_DIR}")
    print()
    print("Next: Run Vivado simulation with modified testbench")
    print("  ./scripts/run_axi_tb.sh")
    print("=" * 60)


if __name__ == "__main__":
    main()
