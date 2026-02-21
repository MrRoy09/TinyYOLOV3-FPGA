#!/usr/bin/env python3
"""
Configure AXI testbench for a specific layer.
Updates both stimulus files and testbench configuration.

Usage: ./configure_axi_tb.py <layer_num>
"""

import os
import sys
import shutil

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_DIR = os.path.join(SCRIPT_DIR, "..", "TinyYOLOV3_HW_Complete_ex")
IMPORTS_DIR = os.path.join(PROJECT_DIR, "imports")
TB_FILE = os.path.join(IMPORTS_DIR, "TinyYOLOV3_HW_Complete_tb.sv")

# Layer configurations: (ci_groups, co_groups, img_w_padded, cin, M, out_h, out_w, use_stride2)
LAYER_CONFIGS = {
    0: {
        'ci_groups': 1, 'co_groups': 2,
        'cin_pad': 8, 'img_w': 10,  # 8x8 + pad
        'quant_m': 0xC0, 'quant_n': 16,
        'out_h': 4, 'out_w': 4,  # After stride-2 maxpool
        'use_stride2': 1,
        'stim_dir': 'stimulus',
        'desc': '3->16, 8x8->4x4'
    },
    1: {
        'ci_groups': 2, 'co_groups': 4,
        'cin_pad': 16, 'img_w': 6,  # 4x4 + pad
        'quant_m': 0x1BB, 'quant_n': 16,
        'out_h': 2, 'out_w': 2,
        'use_stride2': 1,
        'stim_dir': 'stimulus_l1',
        'desc': '16->32, 4x4->2x2'
    },
    2: {
        'ci_groups': 4, 'co_groups': 8,
        'cin_pad': 32, 'img_w': 6,  # 4x4 + pad
        'quant_m': 0x3CA, 'quant_n': 16,
        'out_h': 2, 'out_w': 2,
        'use_stride2': 1,
        'stim_dir': 'stimulus_l2',
        'desc': '32->64, 4x4->2x2'
    },
    3: {
        'ci_groups': 8, 'co_groups': 16,
        'cin_pad': 64, 'img_w': 6,  # 4x4 + pad
        'quant_m': 0x22B, 'quant_n': 16,
        'out_h': 2, 'out_w': 2,
        'use_stride2': 1,
        'stim_dir': 'stimulus_l3',
        'desc': '64->128, 4x4->2x2'
    },
    # Layer 5: stride-1 maxpool test using Layer 0 params
    # For stride-1 with backward-looking RTL (skip row 0/col 0):
    # - 7x7 padded input -> 5x5 conv output -> 4x4 maxpool output
    5: {
        'ci_groups': 1, 'co_groups': 2,
        'cin_pad': 8, 'img_w': 7,  # 5x5 + 2 padding = 7x7
        'quant_m': 0xC0, 'quant_n': 16,
        'out_h': 4, 'out_w': 4,  # stride-1 maxpool: 5x5 -> 4x4
        'use_stride2': 0,  # STRIDE-1 MAXPOOL
        'stim_dir': 'stimulus_l5',
        'desc': '3->16, stride-1 maxpool test'
    },
}


def convert_weights_72_to_128(input_file, output_file):
    """Convert 72-bit weight hex to 128-bit zero-padded format."""
    count = 0
    with open(input_file, 'r') as fin:
        with open(output_file, 'w') as fout:
            for line in fin:
                line = line.strip()
                if not line:
                    continue
                val_128bit = line.zfill(32)
                fout.write(val_128bit + '\n')
                count += 1
    return count


def copy_stimulus_files(layer_num, cfg):
    """Copy and convert stimulus files for the layer."""
    stim_dir = os.path.join(SCRIPT_DIR, cfg['stim_dir'])

    if not os.path.exists(stim_dir):
        print(f"ERROR: Stimulus directory not found: {stim_dir}")
        print(f"Run gen_layer{layer_num}_stimulus.py first!")
        return False

    # Weights
    weights_src = os.path.join(stim_dir, "weights_og0.hex")
    if os.path.exists(weights_src):
        wt_count = convert_weights_72_to_128(weights_src, os.path.join(IMPORTS_DIR, "weights_axi.hex"))
        print(f"  Converted {wt_count} weight entries")

    # Biases - check for biases_all.hex (L1+) or biases_og0.hex (L0)
    biases_src = os.path.join(stim_dir, "biases_all.hex")
    if not os.path.exists(biases_src):
        biases_src = os.path.join(stim_dir, "biases_og0.hex")

    if os.path.exists(biases_src):
        # Check if it's 128-bit or 32-bit format
        with open(biases_src, 'r') as f:
            first_line = f.readline().strip()

        if len(first_line) == 32:  # Already 128-bit
            shutil.copy(biases_src, os.path.join(IMPORTS_DIR, "biases_axi.hex"))
            print(f"  Copied 128-bit biases")
        else:  # 32-bit, need to pack
            # Pack 4 biases per 128-bit word
            biases = []
            with open(biases_src, 'r') as f:
                for line in f:
                    line = line.strip()
                    if line:
                        biases.append(int(line, 16))

            with open(os.path.join(IMPORTS_DIR, "biases_axi.hex"), 'w') as f:
                for i in range(0, len(biases), 4):
                    word = 0
                    for j in range(4):
                        if i + j < len(biases):
                            word |= (biases[i + j] & 0xFFFFFFFF) << (j * 32)
                    f.write(f"{word:032x}\n")
            print(f"  Packed {len(biases)} biases into {(len(biases)+3)//4} words")

    # Pixels and expected for all OGs
    for fname in ["pixels_og0.hex", "expected_og0.hex", "expected_og1.hex", "expected_og2.hex", "expected_og3.hex"]:
        src = os.path.join(stim_dir, fname)
        if os.path.exists(src):
            shutil.copy(src, os.path.join(IMPORTS_DIR, fname))
            print(f"  Copied {fname}")

    # OG1/2/3 weights for batch test
    for og in [1, 2, 3]:
        weights_src = os.path.join(stim_dir, f"weights_og{og}.hex")
        if os.path.exists(weights_src):
            wt_count = convert_weights_72_to_128(weights_src, os.path.join(IMPORTS_DIR, f"weights_og{og}_axi.hex"))
            print(f"  Converted {wt_count} OG{og} weight entries")

    # OG1/2/3 biases for batch test
    for og in [1, 2, 3]:
        biases_src = os.path.join(stim_dir, f"biases_og{og}.hex")
        if os.path.exists(biases_src):
            # Convert 32-bit biases to 128-bit format
            biases = []
            with open(biases_src, 'r') as f:
                for line in f:
                    line = line.strip()
                    if line:
                        biases.append(int(line, 16))

            with open(os.path.join(IMPORTS_DIR, f"biases_og{og}_axi.hex"), 'w') as f:
                for i in range(0, len(biases), 4):
                    word = 0
                    for j in range(4):
                        if i + j < len(biases):
                            word |= (biases[i + j] & 0xFFFFFFFF) << (j * 32)
                    f.write(f"{word:032x}\n")
            print(f"  Packed {len(biases)} OG{og} biases into {(len(biases)+3)//4} words")

    return True


def update_testbench(layer_num, cfg):
    """Update testbench configuration for the layer."""

    # Calculate sizes
    wt_entries = cfg['ci_groups'] * 8 * 8  # ci_groups * 8 banks * 8 urams
    wt_bytes = wt_entries * 16

    bias_entries = 2  # Per OG: 8 biases / 4 per word = 2 words
    bias_bytes = bias_entries * 16

    pixel_entries = cfg['img_w'] * cfg['img_w'] * cfg['ci_groups']
    pixel_bytes = pixel_entries * 8

    output_entries = cfg['out_h'] * cfg['out_w']
    output_bytes = output_entries * 8

    # Generate new configuration block
    new_config = f'''task automatic set_scalar_registers();
  $display("%t : Setting Scalar Registers for conv_top layer {layer_num} test", $time);

  ///////////////////////////////////////////////////////////////////////////
  // Transfer sizes (in bytes) - Layer {layer_num}: {cfg['desc']}
  ///////////////////////////////////////////////////////////////////////////
  // num_weights: {wt_entries} weights x 16 bytes = {wt_bytes} bytes
  write_register(32'h040, 32'd{wt_bytes});

  // num_bias: {bias_entries} bias words x 16 bytes = {bias_bytes} bytes
  write_register(32'h048, 32'd{bias_bytes});

  // num_pixels: {pixel_entries} pixels x 8 bytes = {pixel_bytes} bytes
  write_register(32'h050, 32'd{pixel_bytes});

  // num_outputs: {output_entries} outputs x 8 bytes = {output_bytes} bytes
  write_register(32'h058, 32'd{output_bytes});

  ///////////////////////////////////////////////////////////////////////////
  // Configuration for Layer {layer_num}: ci_groups={cfg['ci_groups']}, co_groups={cfg['co_groups']}
  ///////////////////////////////////////////////////////////////////////////
  // cfg_ci_groups
  write_register(32'h060, 32'd{cfg['ci_groups']});

  // cfg_co_groups = 0 (output group INDEX for per-OG bias loading)
  write_register(32'h068, 32'd0);

  // cfg_wt_base_addr = 0
  write_register(32'h070, 32'd0);

  // cfg_in_channels
  write_register(32'h078, 32'd{cfg['cin_pad']});

  // cfg_img_width (padded)
  write_register(32'h080, 32'd{cfg['img_w']});

  // cfg_use_maxpool = 1
  write_register(32'h088, 32'd1);

  // cfg_use_stride2 = {cfg['use_stride2']} ({'stride-2' if cfg['use_stride2'] else 'stride-1'} maxpool)
  write_register(32'h090, 32'd{cfg['use_stride2']});

  // cfg_quant_m
  write_register(32'h098, 32'h{cfg['quant_m']:08x});

  // cfg_quant_n
  write_register(32'h0a0, 32'd{cfg['quant_n']});

  // cfg_use_relu = 1 (leaky ReLU)
  write_register(32'h0a8, 32'd1);

  // cfg_kernel_1x1 = 0 (3x3 convolution)
  write_register(32'h0b0, 32'd0);'''

    # Read testbench file
    with open(TB_FILE, 'r') as f:
        content = f.read()

    # Find and replace the set_scalar_registers task
    import re
    pattern = r'task automatic set_scalar_registers\(\);.*?// cfg_kernel_1x1 = 0 \(3x3 convolution.*?\)'

    match = re.search(pattern, content, re.DOTALL)
    if match:
        content = content[:match.start()] + new_config + content[match.end():]

        with open(TB_FILE, 'w') as f:
            f.write(content)
        print(f"  Updated testbench configuration")
        return True
    else:
        print("ERROR: Could not find set_scalar_registers in testbench")
        return False


def main():
    if len(sys.argv) != 2:
        print("Usage: ./configure_axi_tb.py <layer_num>")
        print("  layer_num: 0, 1, 2, 3, or 5")
        sys.exit(1)

    layer_num = int(sys.argv[1])

    if layer_num not in LAYER_CONFIGS:
        print(f"ERROR: Layer {layer_num} not supported. Use 0, 1, 2, 3, or 5.")
        sys.exit(1)

    cfg = LAYER_CONFIGS[layer_num]

    print(f"=" * 60)
    print(f"Configuring AXI testbench for Layer {layer_num}")
    print(f"  {cfg['desc']}")
    print(f"  ci_groups={cfg['ci_groups']}, M=0x{cfg['quant_m']:x}")
    print(f"=" * 60)

    print("\nCopying stimulus files...")
    if not copy_stimulus_files(layer_num, cfg):
        sys.exit(1)

    print("\nUpdating testbench...")
    if not update_testbench(layer_num, cfg):
        sys.exit(1)

    print(f"\n{'=' * 60}")
    print(f"Done! Ready to run: ./scripts/run_axi_tb.sh")
    print(f"{'=' * 60}")


if __name__ == "__main__":
    main()
