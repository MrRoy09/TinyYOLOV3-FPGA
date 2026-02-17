#!/usr/bin/env python3
"""
Generate stimulus for conv_1x1 mode testing.
Simple 4x4 image with 16 input channels -> 8 output channels.
No kernel window, no padding needed for 1x1 conv.
"""

import numpy as np
import os

np.random.seed(42)

# Configuration
IMG_W = 4
IMG_H = 4
IN_CHANNELS = 16  # ci_groups = 2
OUT_CHANNELS = 8  # 1 output group
CI_GROUPS = IN_CHANNELS // 8

# Quantization params - use values that produce visible variation
# M and n chosen so outputs are in reasonable range
QUANT_M = 0x00004000  # 16384
QUANT_N = 8           # Shift by 8 bits

# Output directory
OUTPUT_DIR = os.path.join(os.path.dirname(__file__), "stimulus_1x1")
os.makedirs(OUTPUT_DIR, exist_ok=True)

# Generate random input image [H, W, C] in NHWC format
# Values 0-255 (uint8)
input_image = np.random.randint(0, 256, size=(IMG_H, IMG_W, IN_CHANNELS), dtype=np.uint8)

# Generate random weights [OUT_CHANNELS, IN_CHANNELS]
# Values -128 to 127 (int8)
weights = np.random.randint(-64, 64, size=(OUT_CHANNELS, IN_CHANNELS), dtype=np.int8)

# Generate random biases [OUT_CHANNELS]
# Values -1000 to 1000 (int32)
biases = np.random.randint(-500, 500, size=(OUT_CHANNELS,), dtype=np.int32)

# Compute expected output using numpy
# 1x1 conv is essentially a matrix multiply per spatial position
# output[h,w,co] = sum over ci: input[h,w,ci] * weight[co,ci] + bias[co]
output_raw = np.zeros((IMG_H, IMG_W, OUT_CHANNELS), dtype=np.int32)
for h in range(IMG_H):
    for w in range(IMG_W):
        for co in range(OUT_CHANNELS):
            acc = int(biases[co])
            for ci in range(IN_CHANNELS):
                # Pixel is unsigned, weight is signed
                acc += int(input_image[h, w, ci]) * int(weights[co, ci])
            output_raw[h, w, co] = acc

print(f"Input shape: {input_image.shape}")
print(f"Weights shape: {weights.shape}")
print(f"Output shape: {output_raw.shape}")
print(f"Sample input [0,0]: {input_image[0,0,:]}")
print(f"Sample weights[0]: {weights[0,:]}")
print(f"Sample bias[0]: {biases[0]}")
print(f"Sample raw output [0,0]: {output_raw[0,0,:]}")

# Apply quantization matching hardware quantizer.sv:
# 1. mult_result = data_in * M (64-bit signed)
# 2. shifted_result = mult_result >>> n (arithmetic right shift)
# 3. If use_relu and shifted < 0: relu_result = shifted >>> 3 (leaky, divide by 8)
# 4. Clamp to [-128, 127]
# 5. Output as signed 8-bit (but stored as uint8 0-255 in testbench)
def quantize_leaky(acc, M, n, use_relu=True):
    # Step 1: multiply (64-bit signed)
    mult = acc * M

    # Step 2: arithmetic right shift by n
    shifted = mult >> n  # Python >> is arithmetic for negative numbers

    # Step 3: leaky ReLU (divide by 8 for negative values)
    if use_relu:
        if shifted < 0:
            relu = shifted >> 3
        else:
            relu = shifted
    else:
        relu = shifted

    # Step 4: clamp to [-128, 127]
    clamped = max(-128, min(127, relu))

    # Step 5: convert to unsigned 8-bit for storage
    return clamped & 0xFF

output_quant = np.zeros((IMG_H, IMG_W, OUT_CHANNELS), dtype=np.uint8)
for h in range(IMG_H):
    for w in range(IMG_W):
        for co in range(OUT_CHANNELS):
            output_quant[h, w, co] = quantize_leaky(output_raw[h, w, co], QUANT_M, QUANT_N)

print(f"Sample quant output [0,0]: {output_quant[0,0,:]}")
print(f"Sample quant output [0,0] hex: {[hex(x) for x in output_quant[0,0,:]]}")

# Verify one manually
acc = output_raw[0, 0, 0]
mult = acc * QUANT_M
shifted = mult >> QUANT_N
if shifted < 0:
    relu = shifted >> 3
else:
    relu = shifted
clamped = max(-128, min(127, relu))
print(f"\nManual verification for [0,0,0]:")
print(f"  acc = {acc}")
print(f"  mult = acc * M = {mult}")
print(f"  shifted = mult >> {QUANT_N} = {shifted}")
print(f"  relu = {relu}")
print(f"  clamped = {clamped}")
print(f"  output = {clamped & 0xFF}")

# Write pixel hex file
# For 1x1, pixels stream as [H, W, CI_GROUP] with 8 channels packed per 64-bit word
with open(os.path.join(OUTPUT_DIR, "pixels.hex"), "w") as f:
    for h in range(IMG_H):
        for w in range(IMG_W):
            for cig in range(CI_GROUPS):
                word = 0
                for c in range(8):
                    word |= int(input_image[h, w, cig*8 + c]) << (c * 8)
                f.write(f"{word:016x}\n")

print(f"\nWritten {IMG_H * IMG_W * CI_GROUPS} pixel words")

# Write weight hex file
# For 1x1: weights stored in weight_manager format (72-bit URAM words)
# weight_manager expects: for each address, 8 banks x 8 URAMs
# Write order follows wr_cnt: uram_sel[2:0], bank_sel[5:3], addr[...]
# So order is: uram0-7 for bank0, uram0-7 for bank1, ..., then next address
#
# Key insight from conv_pe.sv weight mapping:
#   weight_byte = weights[(i*64 + j*8) +: 8] where i=spatial(0-8), j=channel(0-7)
#   So spatial position 4 (center [1][1]) is at bits [4*64 : 4*64+64] = [319:256]
#
# URAM storage format (72 bits per URAM):
#   bits [7:0] = spatial 0, bits [15:8] = spatial 1, ...,
#   bits [39:32] = spatial 4 (center), ..., bits [71:64] = spatial 8
#
# For 1x1: put weight at bits [39:32] (spatial position 4 = center)
with open(os.path.join(OUTPUT_DIR, "weights.hex"), "w") as f:
    for cig in range(CI_GROUPS):
        for bank in range(8):  # output channel
            for uram in range(8):  # input channel within this ci_group
                ci = cig * 8 + uram  # absolute input channel
                w_val = int(weights[bank, ci]) & 0xFF
                # Put weight at bits [39:32] (spatial position 4 = center)
                word = w_val << 32
                f.write(f"{word:018x}\n")

print(f"Written {CI_GROUPS * 8 * 8} weight words")

# Write bias hex file (128-bit words, 4 biases per word)
with open(os.path.join(OUTPUT_DIR, "biases.hex"), "w") as f:
    for word_idx in range(2):
        word = 0
        for b in range(4):
            bias_idx = word_idx * 4 + b
            b_val = int(biases[bias_idx]) & 0xFFFFFFFF
            word |= b_val << (b * 32)
        f.write(f"{word:032x}\n")

print(f"Written 2 bias words")

# Write expected output hex file
# Output streams as [H, W] with 8 channels packed per 64-bit word
with open(os.path.join(OUTPUT_DIR, "expected.hex"), "w") as f:
    for h in range(IMG_H):
        for w in range(IMG_W):
            word = 0
            for c in range(8):
                word |= int(output_quant[h, w, c]) << (c * 8)
            f.write(f"{word:016x}\n")

print(f"Written {IMG_H * IMG_W} expected words")

# Write quant params
with open(os.path.join(OUTPUT_DIR, "quant_params.txt"), "w") as f:
    f.write(f"QUANT_M = 0x{QUANT_M:08x} ({QUANT_M})\n")
    f.write(f"QUANT_N = {QUANT_N}\n")

print(f"\nStimulus files written to {OUTPUT_DIR}")
