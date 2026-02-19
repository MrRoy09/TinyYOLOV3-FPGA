#!/usr/bin/env python3
"""
TinyYOLOv3 Reference Implementation for Hardware Verification

This module provides INT8 reference inference that exactly matches the hardware
arithmetic for layer-by-layer verification against FPGA outputs.

Key features:
- Per-output-group quantization matching hardware weight_manager
- Leaky ReLU as >>3 (matching quantizer.sv)
- Layer-by-layer execution with intermediate outputs
- NHWC format conversion for hardware comparison

Layer Map (Darknet index -> Hardware operation):
  0: Conv 3x3, 3->16, leaky   (ci_groups=1, co_groups=2)
  1: MaxPool 2x2 stride-2
  2: Conv 3x3, 16->32, leaky  (ci_groups=2, co_groups=4)
  3: MaxPool 2x2 stride-2
  4: Conv 3x3, 32->64, leaky  (ci_groups=4, co_groups=8)
  5: MaxPool 2x2 stride-2
  6: Conv 3x3, 64->128, leaky (ci_groups=8, co_groups=16)
  7: MaxPool 2x2 stride-2
  8: Conv 3x3, 128->256, leaky (ci_groups=16, co_groups=32)
  9: MaxPool 2x2 stride-2
  10: Conv 3x3, 256->512, leaky (ci_groups=32, co_groups=64)
  11: MaxPool 2x2 stride-1  (special zero-pad)
  12: Conv 3x3, 512->1024, leaky (ci_groups=64, co_groups=128, 2 weight loads)
  13: Conv 1x1, 1024->256, leaky (ci_groups=128, co_groups=32)
  14: Conv 3x3, 256->512, leaky (ci_groups=32, co_groups=64)
  15: Conv 1x1, 512->255, linear (ci_groups=64, co_groups=32) -> Detection Head 1
  16: YOLO output
  17: Route (takes layer 13 output)
  18: Conv 1x1, 256->128, leaky (ci_groups=32, co_groups=16)
  19: Upsample 2x
  20: Route (concat layer 19 + layer 8) -> 128+256=384 channels
  21: Conv 3x3, 384->256, leaky (ci_groups=48, co_groups=32)
  22: Conv 1x1, 256->255, linear (ci_groups=32, co_groups=32) -> Detection Head 2
  23: YOLO output

Usage:
    from tinyyolo_reference import TinyYOLOv3Reference

    ref = TinyYOLOv3Reference()
    ref.load_image("test.jpg")
    outputs = ref.run_all_layers()
    layer_0_out = ref.get_layer_output(0)
"""

import numpy as np
import cv2
import os
import sys

# Add sim/hardware-ai to path for loading quantized params
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'sim', 'hardware-ai'))

# Hardware parameters
PIN = 8
POUT = 8

# Layer configuration table (Darknet layer index -> hardware config)
# IMPORTANT: Route layer 20 references layer 8 BEFORE maxpool, so layer 8
# must NOT have fused_maxpool. Layer 9 is a separate maxpool layer.
LAYER_CONFIG = {
    # Conv layers: (cin, cout, kernel, stride, pad, activation, maxpool_stride)
    # maxpool_stride: 0=none, 1=stride-1, 2=stride-2
    0:  {'type': 'conv', 'cin': 3,   'cout': 16,   'kernel': 3, 'stride': 1, 'pad': 1, 'activation': 'leaky', 'fused_maxpool': 2},
    1:  {'type': 'maxpool', 'size': 2, 'stride': 2},  # Handled by fused_maxpool in layer 0
    2:  {'type': 'conv', 'cin': 16,  'cout': 32,   'kernel': 3, 'stride': 1, 'pad': 1, 'activation': 'leaky', 'fused_maxpool': 2},
    3:  {'type': 'maxpool', 'size': 2, 'stride': 2},
    4:  {'type': 'conv', 'cin': 32,  'cout': 64,   'kernel': 3, 'stride': 1, 'pad': 1, 'activation': 'leaky', 'fused_maxpool': 2},
    5:  {'type': 'maxpool', 'size': 2, 'stride': 2},
    6:  {'type': 'conv', 'cin': 64,  'cout': 128,  'kernel': 3, 'stride': 1, 'pad': 1, 'activation': 'leaky', 'fused_maxpool': 2},
    7:  {'type': 'maxpool', 'size': 2, 'stride': 2},
    # Layer 8: NO fused maxpool - route layer 20 needs the 26x26 output
    8:  {'type': 'conv', 'cin': 128, 'cout': 256,  'kernel': 3, 'stride': 1, 'pad': 1, 'activation': 'leaky', 'fused_maxpool': 0},
    9:  {'type': 'maxpool', 'size': 2, 'stride': 2},  # Separate maxpool for layer 8
    10: {'type': 'conv', 'cin': 256, 'cout': 512,  'kernel': 3, 'stride': 1, 'pad': 1, 'activation': 'leaky', 'fused_maxpool': 1},  # stride-1 maxpool
    11: {'type': 'maxpool', 'size': 2, 'stride': 1},  # Handled by fused_maxpool in layer 10
    12: {'type': 'conv', 'cin': 512, 'cout': 1024, 'kernel': 3, 'stride': 1, 'pad': 1, 'activation': 'leaky', 'fused_maxpool': 0},
    13: {'type': 'conv', 'cin': 1024,'cout': 256,  'kernel': 1, 'stride': 1, 'pad': 0, 'activation': 'leaky', 'fused_maxpool': 0},
    14: {'type': 'conv', 'cin': 256, 'cout': 512,  'kernel': 3, 'stride': 1, 'pad': 1, 'activation': 'leaky', 'fused_maxpool': 0},
    15: {'type': 'conv', 'cin': 512, 'cout': 255,  'kernel': 1, 'stride': 1, 'pad': 0, 'activation': 'linear', 'fused_maxpool': 0},
    16: {'type': 'yolo'},
    17: {'type': 'route', 'layers': [-4]},  # Takes layer 13 output
    18: {'type': 'conv', 'cin': 256, 'cout': 128,  'kernel': 1, 'stride': 1, 'pad': 0, 'activation': 'leaky', 'fused_maxpool': 0},
    19: {'type': 'upsample', 'stride': 2},
    20: {'type': 'route', 'layers': [-1, 8]},  # Concat layer 19 + layer 8 (128+256=384)
    21: {'type': 'conv', 'cin': 384, 'cout': 256,  'kernel': 3, 'stride': 1, 'pad': 1, 'activation': 'leaky', 'fused_maxpool': 0},
    22: {'type': 'conv', 'cin': 256, 'cout': 255,  'kernel': 1, 'stride': 1, 'pad': 0, 'activation': 'linear', 'fused_maxpool': 0},
    23: {'type': 'yolo'},
}


def load_quant_params(path):
    """Load quantization parameters from .npz file."""
    raw = np.load(path, allow_pickle=True)
    q_params = {}
    for k in raw.files:
        if k.startswith('l') and '_' in k:
            parts = k[1:].split('_')
            idx = int(parts[0])
            key = '_'.join(parts[1:])
            if idx not in q_params:
                q_params[idx] = {}
            q_params[idx][key] = raw[k]
            if q_params[idx][key].ndim == 0:
                q_params[idx][key] = q_params[idx][key].item()
        else:
            q_params[k] = raw[k].item() if raw[k].ndim == 0 else raw[k]
    return q_params


class TinyYOLOv3Reference:
    """
    INT8 reference implementation matching hardware arithmetic.
    """

    def __init__(self, quant_params_path=None):
        """
        Initialize with pre-computed quantization parameters.

        Args:
            quant_params_path: Path to quantized_params.npz. If None, uses default location.
        """
        if quant_params_path is None:
            quant_params_path = os.path.join(
                os.path.dirname(__file__), '..', 'sim', 'hardware-ai', 'quantized_params.npz'
            )

        if not os.path.exists(quant_params_path):
            raise FileNotFoundError(f"Quantization parameters not found: {quant_params_path}")

        print(f"Loading quantization parameters from {quant_params_path}")
        self.q_params = load_quant_params(quant_params_path)
        self.layer_outputs = {}
        self.input_tensor = None

    def load_image(self, image_path, input_size=416):
        """
        Load and preprocess image to INT8.

        Args:
            image_path: Path to input image
            input_size: Network input size (default 416)

        Returns:
            INT8 tensor in NCHW format (1, 3, H, W)
        """
        img = cv2.imread(image_path)
        if img is None:
            raise ValueError(f"Cannot load image: {image_path}")

        # Resize and normalize
        img = cv2.resize(img, (input_size, input_size))
        img = cv2.cvtColor(img, cv2.COLOR_BGR2RGB)

        # Convert to float [0, 1] then scale to INT8
        img_float = img.astype(np.float32) / 255.0
        input_scale = self.q_params.get('input_scale', 127.0)
        img_int8 = np.round(img_float * input_scale).astype(np.int8)

        # NHWC -> NCHW
        self.input_tensor = np.transpose(img_int8, (2, 0, 1))[np.newaxis, ...]
        return self.input_tensor

    def load_tensor(self, tensor):
        """
        Load pre-processed INT8 tensor directly.

        Args:
            tensor: INT8 tensor in NCHW format (1, C, H, W)
        """
        self.input_tensor = tensor.astype(np.int8)
        return self.input_tensor

    def conv_int8(self, input_data, layer_idx):
        """
        INT8 convolution matching hardware arithmetic.

        Args:
            input_data: INT8 input tensor (1, Cin, H, W)
            layer_idx: Darknet layer index

        Returns:
            INT8 output tensor (1, Cout, H', W')
        """
        p = self.q_params[layer_idx]
        weights = p['q_weights']  # (Cout, Cin, Kh, Kw)
        biases = p['q_biases']    # (Cout,)
        M = int(p['M'])
        n = int(p['n'])
        activation = p['activation']
        stride = int(p.get('stride', 1))
        pad = int(p.get('pad', 0))

        cout, cin, kh, kw = weights.shape
        batch, in_ch, h, w = input_data.shape

        # Padding
        if pad:
            pad_h, pad_w = kh // 2, kw // 2
            padded = np.pad(input_data, ((0, 0), (0, 0), (pad_h, pad_h), (pad_w, pad_w)),
                           mode='constant', constant_values=0)
        else:
            padded = input_data
            pad_h, pad_w = 0, 0

        # Output dimensions
        out_h = (h + 2 * pad_h - kh) // stride + 1
        out_w = (w + 2 * pad_w - kw) // stride + 1

        # INT32 accumulator
        output = np.zeros((batch, cout, out_h, out_w), dtype=np.int32)

        # Convolution
        for f in range(cout):
            for c in range(cin):
                kernel = weights[f, c]
                img_slice = padded[0, c]

                from numpy.lib.stride_tricks import as_strided
                shape = (out_h, out_w, kh, kw)
                strides_tuple = (stride * img_slice.strides[0], stride * img_slice.strides[1],
                                img_slice.strides[0], img_slice.strides[1])
                windows = as_strided(img_slice, shape=shape, strides=strides_tuple)
                output[0, f] += np.einsum('ij,klij->kl', kernel, windows, dtype=np.int32)

            output[0, f] += biases[f]

        # Leaky ReLU (>>3 for negative, matching hardware)
        if activation == 'leaky':
            output = np.where(output > 0, output, output >> 3)

        # Quantization: (acc * M) >> n
        output = (output.astype(np.int64) * M) >> n

        # Clamp to INT8
        return np.clip(output, -128, 127).astype(np.int8)

    def maxpool_int8(self, input_data, size=2, stride=2):
        """
        INT8 max pooling matching hardware.

        Args:
            input_data: INT8 input tensor (1, C, H, W)
            size: Pool size
            stride: Pool stride

        Returns:
            INT8 output tensor
        """
        batch, c, h, w = input_data.shape

        # Special case: stride-1 with size-2 needs zero-padding
        if stride == 1 and size == 2:
            input_data = np.pad(input_data, ((0, 0), (0, 0), (0, 1), (0, 1)),
                               mode='constant', constant_values=-128)
            _, _, h, w = input_data.shape

        out_h = (h - size) // stride + 1
        out_w = (w - size) // stride + 1

        # Optimized path for stride==size
        if h % size == 0 and w % size == 0 and stride == size:
            return input_data.reshape(batch, c, out_h, size, out_w, size).max(axis=(3, 5))

        # General case
        output = np.full((batch, c, out_h, out_w), -128, dtype=np.int8)
        for i in range(out_h):
            for j in range(out_w):
                h_start, w_start = i * stride, j * stride
                output[:, :, i, j] = np.max(
                    input_data[:, :, h_start:h_start+size, w_start:w_start+size],
                    axis=(2, 3)
                )
        return output

    def upsample_int8(self, input_data, stride=2):
        """
        Nearest-neighbor upsampling.

        Args:
            input_data: INT8 input tensor (1, C, H, W)
            stride: Upsample factor

        Returns:
            INT8 output tensor (1, C, H*stride, W*stride)
        """
        return input_data.repeat(stride, axis=2).repeat(stride, axis=3)

    def route(self, layer_idx):
        """
        Route layer: select or concatenate previous layer outputs.

        Args:
            layer_idx: Current layer index

        Returns:
            Concatenated or selected tensor
        """
        cfg = LAYER_CONFIG[layer_idx]
        layers = cfg['layers']

        tensors = []
        for l in layers:
            if l < 0:
                src_idx = layer_idx + l
            else:
                src_idx = l
            tensors.append(self.layer_outputs[src_idx])

        return np.concatenate(tensors, axis=1)

    def run_layer(self, layer_idx, input_data=None):
        """
        Execute a single layer.

        Args:
            layer_idx: Darknet layer index
            input_data: Optional input tensor. If None, uses previous layer output.

        Returns:
            Layer output tensor
        """
        cfg = LAYER_CONFIG[layer_idx]
        layer_type = cfg['type']

        # Determine input
        if input_data is not None:
            x = input_data
        elif layer_idx == 0:
            x = self.input_tensor
        else:
            # Find previous layer that has output
            prev_idx = layer_idx - 1
            while prev_idx >= 0 and prev_idx not in self.layer_outputs:
                prev_idx -= 1
            x = self.layer_outputs[prev_idx] if prev_idx >= 0 else self.input_tensor

        # Execute layer
        if layer_type == 'conv':
            output = self.conv_int8(x, layer_idx)

            # Fused maxpool
            fused_mp = cfg.get('fused_maxpool', 0)
            if fused_mp > 0:
                output = self.maxpool_int8(output, size=2, stride=fused_mp)

        elif layer_type == 'maxpool':
            # Standalone maxpool (usually fused, but kept for completeness)
            output = self.maxpool_int8(x, size=cfg['size'], stride=cfg['stride'])

        elif layer_type == 'upsample':
            output = self.upsample_int8(x, stride=cfg['stride'])

        elif layer_type == 'route':
            output = self.route(layer_idx)

        elif layer_type == 'yolo':
            # YOLO layer doesn't transform, just marks output
            output = x

        else:
            raise ValueError(f"Unknown layer type: {layer_type}")

        self.layer_outputs[layer_idx] = output
        return output

    def run_all_layers(self):
        """
        Run full inference through all layers.

        Returns:
            Dict of all layer outputs
        """
        if self.input_tensor is None:
            raise ValueError("No input tensor loaded. Call load_image() or load_tensor() first.")

        self.layer_outputs = {}

        for layer_idx in sorted(LAYER_CONFIG.keys()):
            cfg = LAYER_CONFIG[layer_idx]

            # Skip standalone maxpool layers that are fused into previous conv
            # Exception: layer 9 is NOT fused (layer 8 needs unfused output for route)
            if cfg['type'] == 'maxpool':
                prev_idx = layer_idx - 1
                if prev_idx in LAYER_CONFIG and LAYER_CONFIG[prev_idx]['type'] == 'conv':
                    if LAYER_CONFIG[prev_idx].get('fused_maxpool', 0) > 0:
                        continue
                # Layer 9 is standalone maxpool, don't skip

            output = self.run_layer(layer_idx)
            print(f"Layer {layer_idx:2d} ({cfg['type']:>10s}): output shape {output.shape}, "
                  f"range [{output.min():4d}, {output.max():4d}]")

        return self.layer_outputs

    def get_layer_output(self, layer_idx):
        """Get output of a specific layer."""
        return self.layer_outputs.get(layer_idx)

    def get_layer_output_nhwc(self, layer_idx):
        """Get output of a specific layer in NHWC format for hardware comparison."""
        out = self.layer_outputs.get(layer_idx)
        if out is not None:
            # NCHW -> NHWC
            return np.transpose(out[0], (1, 2, 0))
        return None

    def get_detection_outputs(self):
        """Get the two detection head outputs (layers 15 and 22)."""
        return {
            'head1': self.layer_outputs.get(15),  # 13x13x255
            'head2': self.layer_outputs.get(22),  # 26x26x255
        }


def compare_outputs(ref_output, hw_output, tolerance=3, name=""):
    """
    Compare reference output against hardware output.

    Args:
        ref_output: Reference INT8 tensor (H, W, C) in NHWC
        hw_output: Hardware INT8 tensor (H, W, C) in NHWC
        tolerance: Maximum allowed difference per value
        name: Label for reporting

    Returns:
        Dict with comparison statistics
    """
    if ref_output.shape != hw_output.shape:
        return {
            'match': False,
            'error': f"Shape mismatch: ref={ref_output.shape}, hw={hw_output.shape}"
        }

    diff = np.abs(ref_output.astype(np.int16) - hw_output.astype(np.int16))

    exact_match = np.sum(diff == 0)
    within_tolerance = np.sum(diff <= tolerance)
    total = diff.size
    max_diff = np.max(diff)

    stats = {
        'name': name,
        'match': max_diff <= tolerance,
        'exact_match': exact_match,
        'within_tolerance': within_tolerance,
        'total': total,
        'max_diff': int(max_diff),
        'mean_diff': float(np.mean(diff)),
        'exact_pct': 100.0 * exact_match / total,
        'tolerance_pct': 100.0 * within_tolerance / total,
    }

    return stats


def print_comparison(stats):
    """Print comparison statistics."""
    print(f"\n{stats['name']} Comparison:")
    print(f"  Exact matches:     {stats['exact_match']:6d}/{stats['total']:6d} ({stats['exact_pct']:.1f}%)")
    print(f"  Within tolerance:  {stats['within_tolerance']:6d}/{stats['total']:6d} ({stats['tolerance_pct']:.1f}%)")
    print(f"  Max difference:    {stats['max_diff']}")
    print(f"  Mean difference:   {stats['mean_diff']:.3f}")
    print(f"  Result:            {'PASS' if stats['match'] else 'FAIL'}")


if __name__ == "__main__":
    import argparse

    parser = argparse.ArgumentParser(description='TinyYOLOv3 INT8 Reference')
    parser.add_argument('image', nargs='?', default='scripts/test_image.jpg',
                       help='Input image path')
    parser.add_argument('--layer', type=int, default=-1,
                       help='Run specific layer only (-1 for all)')
    args = parser.parse_args()

    # Initialize reference
    ref = TinyYOLOv3Reference()

    # Load image
    print(f"\nLoading image: {args.image}")
    ref.load_image(args.image)
    print(f"Input tensor shape: {ref.input_tensor.shape}")
    print(f"Input range: [{ref.input_tensor.min()}, {ref.input_tensor.max()}]")

    # Run inference
    if args.layer >= 0:
        output = ref.run_layer(args.layer)
        print(f"\nLayer {args.layer} output shape: {output.shape}")
        print(f"Output range: [{output.min()}, {output.max()}]")
    else:
        print("\nRunning full inference:")
        outputs = ref.run_all_layers()

        # Print detection head info
        det = ref.get_detection_outputs()
        print(f"\nDetection Head 1 (13x13): shape={det['head1'].shape}")
        print(f"Detection Head 2 (26x26): shape={det['head2'].shape}")
