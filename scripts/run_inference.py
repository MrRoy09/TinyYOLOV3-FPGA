#!/usr/bin/env python3
"""
TinyYOLOv3 Full Inference Orchestrator

Coordinates layer-by-layer execution on FPGA with CPU-handled operations
(upsampling, concatenation, route).

This script:
1. Prepares input image
2. Runs each conv layer on FPGA via C++ runner
3. Handles CPU operations (upsample, concat, route)
4. Verifies against Python reference
5. Post-processes detection outputs

Usage:
    python run_inference.py <image> [--xclbin <path>] [--verify]

Example:
    python run_inference.py scripts/test_image.jpg --xclbin TinyYOLOV3.xclbin --verify
"""

import argparse
import json
import os
import subprocess
import sys
import tempfile
import time
from pathlib import Path

import cv2
import numpy as np

# Add project paths
SCRIPT_DIR = Path(__file__).parent.absolute()
PROJECT_ROOT = SCRIPT_DIR.parent
sys.path.insert(0, str(SCRIPT_DIR))
sys.path.insert(0, str(PROJECT_ROOT / 'sim' / 'hardware-ai'))

from tinyyolo_reference import TinyYOLOv3Reference, compare_outputs, print_comparison

# Hardware parameters
PIN = 8
POUT = 8

# Layer execution order (Darknet indices)
# Conv layers executed on FPGA
FPGA_LAYERS = [0, 2, 4, 6, 8, 10, 12, 13, 14, 15, 18, 21, 22]

# CPU-only layers
CPU_LAYERS = {
    9:  'maxpool',  # Separate maxpool for layer 8 (needed because route 20 refs layer 8)
    16: 'yolo',     # Detection output 1
    17: 'route',    # Takes layer 13
    19: 'upsample', # 2x upsample
    20: 'route',    # Concat layer 19 + layer 8 (128+256=384)
    23: 'yolo',     # Detection output 2
}

# Layer configuration
# IMPORTANT: Layer 8 has NO fused maxpool - route 20 needs its 26x26 output
# Layer 9 is a separate CPU maxpool operation
LAYER_CONFIG = {
    # layer_idx: (cin, cout, kernel, fused_maxpool_stride)
    0:  {'cin': 3,    'cout': 16,   'kernel': 3, 'mp_stride': 2, 'activation': 'leaky'},
    2:  {'cin': 16,   'cout': 32,   'kernel': 3, 'mp_stride': 2, 'activation': 'leaky'},
    4:  {'cin': 32,   'cout': 64,   'kernel': 3, 'mp_stride': 2, 'activation': 'leaky'},
    6:  {'cin': 64,   'cout': 128,  'kernel': 3, 'mp_stride': 2, 'activation': 'leaky'},
    8:  {'cin': 128,  'cout': 256,  'kernel': 3, 'mp_stride': 0, 'activation': 'leaky'},  # NO fused maxpool
    10: {'cin': 256,  'cout': 512,  'kernel': 3, 'mp_stride': 1, 'activation': 'leaky'},
    12: {'cin': 512,  'cout': 1024, 'kernel': 3, 'mp_stride': 0, 'activation': 'leaky'},
    13: {'cin': 1024, 'cout': 256,  'kernel': 1, 'mp_stride': 0, 'activation': 'leaky'},
    14: {'cin': 256,  'cout': 512,  'kernel': 3, 'mp_stride': 0, 'activation': 'leaky'},
    15: {'cin': 512,  'cout': 255,  'kernel': 1, 'mp_stride': 0, 'activation': 'linear'},
    18: {'cin': 256,  'cout': 128,  'kernel': 1, 'mp_stride': 0, 'activation': 'leaky'},
    21: {'cin': 384,  'cout': 256,  'kernel': 3, 'mp_stride': 0, 'activation': 'leaky'},
    22: {'cin': 256,  'cout': 255,  'kernel': 1, 'mp_stride': 0, 'activation': 'linear'},
}


def ceil_div(a, b):
    return (a + b - 1) // b


def pad_channels(tensor, target_ch):
    """Pad channels to multiple of 8."""
    h, w, c = tensor.shape
    if c >= target_ch:
        return tensor
    padded = np.zeros((h, w, target_ch), dtype=tensor.dtype)
    padded[:, :, :c] = tensor
    return padded


def pad_spatial(tensor, kernel_size=3):
    """Add spatial padding for convolution."""
    if kernel_size == 1:
        return tensor
    h, w, c = tensor.shape
    pad = kernel_size // 2
    padded = np.zeros((h + 2*pad, w + 2*pad, c), dtype=tensor.dtype)
    padded[pad:pad+h, pad:pad+w, :] = tensor
    return padded


def tensor_to_binary(tensor, path):
    """Save NHWC tensor as binary file."""
    tensor.astype(np.int8).tofile(path)


def binary_to_tensor(path, shape):
    """Load binary file as NHWC tensor."""
    data = np.fromfile(path, dtype=np.int8)
    return data.reshape(shape)


def upsample_2x(tensor):
    """Nearest-neighbor 2x upsampling in NHWC format."""
    h, w, c = tensor.shape
    out = np.zeros((h*2, w*2, c), dtype=tensor.dtype)
    for y in range(h):
        for x in range(w):
            out[y*2:y*2+2, x*2:x*2+2, :] = tensor[y, x, :]
    return out


def maxpool_2x2(tensor, stride=2):
    """2x2 max pooling in NHWC format."""
    h, w, c = tensor.shape
    out_h = h // stride
    out_w = w // stride
    out = np.zeros((out_h, out_w, c), dtype=tensor.dtype)
    for y in range(out_h):
        for x in range(out_w):
            y_start = y * stride
            x_start = x * stride
            # 2x2 window max
            window = tensor[y_start:y_start+2, x_start:x_start+2, :]
            out[y, x, :] = np.max(window, axis=(0, 1))
    return out


class InferenceRunner:
    """Orchestrates TinyYOLOv3 inference on FPGA."""

    def __init__(self, xclbin_path, weights_dir, run_layer_bin):
        self.xclbin_path = xclbin_path
        self.weights_dir = Path(weights_dir)
        self.run_layer_bin = run_layer_bin

        # Load layer configs
        config_path = self.weights_dir / 'layer_config.json'
        if config_path.exists():
            with open(config_path) as f:
                self.layer_configs = json.load(f)
        else:
            self.layer_configs = {}

        # Layer output cache
        self.layer_outputs = {}

        # Timing stats
        self.timing = {}

    def prepare_input(self, image_path, input_scale=127.0):
        """
        Load and preprocess image for layer 0.

        Returns:
            NHWC INT8 tensor (418, 418, 8) - padded for 3x3 conv
        """
        img = cv2.imread(str(image_path))
        if img is None:
            raise ValueError(f"Cannot load image: {image_path}")

        # Resize to 416x416
        img = cv2.resize(img, (416, 416))
        img = cv2.cvtColor(img, cv2.COLOR_BGR2RGB)

        # Normalize and quantize to INT8
        img_float = img.astype(np.float32) / 255.0
        img_int8 = np.round(img_float * input_scale).astype(np.int8)

        # Pad channels 3 -> 8
        img_padded = pad_channels(img_int8, 8)

        # Pad spatial 416 -> 418
        img_full = pad_spatial(img_padded, kernel_size=3)

        return img_full

    def run_fpga_layer(self, layer_idx, input_tensor, tmp_dir):
        """
        Execute a convolution layer on FPGA.

        Args:
            layer_idx: Darknet layer index
            input_tensor: NHWC INT8 input tensor
            tmp_dir: Temporary directory for files

        Returns:
            NHWC INT8 output tensor
        """
        cfg = LAYER_CONFIG[layer_idx]
        cin, cout = cfg['cin'], cfg['cout']
        kernel = cfg['kernel']

        ci_groups = ceil_div(cin, PIN)
        co_groups = ceil_div(cout, POUT)

        # Calculate output dimensions
        h, w, c = input_tensor.shape
        out_h = h - (2 if kernel == 3 else 0)
        out_w = w - (2 if kernel == 3 else 0)

        if cfg['mp_stride'] == 2:
            out_h //= 2
            out_w //= 2
        # stride-1 maxpool keeps size (hardware handles padding)

        # Prepare input file
        input_path = os.path.join(tmp_dir, f"layer{layer_idx}_input.bin")
        tensor_to_binary(input_tensor, input_path)

        # Collect outputs from all output groups
        outputs = []

        layer_dir = self.weights_dir / f"layer_{layer_idx:02d}"

        for og in range(co_groups):
            # Get quant params from config
            og_config = None
            if f"layer_{layer_idx}" in self.layer_configs:
                for og_cfg in self.layer_configs[f"layer_{layer_idx}"]['output_groups']:
                    if og_cfg['og_idx'] == og:
                        og_config = og_cfg
                        break

            if og_config is None:
                raise ValueError(f"Missing config for layer {layer_idx} OG {og}")

            weights_path = layer_dir / og_config['weights_file']
            biases_path = layer_dir / og_config['biases_file']
            output_path = os.path.join(tmp_dir, f"layer{layer_idx}_og{og}_output.bin")

            quant_m = og_config['quant_m']
            quant_n = og_config['quant_n']

            # Run FPGA kernel
            cmd = [
                self.run_layer_bin,
                self.xclbin_path,
                str(layer_idx),
                str(og),
                str(weights_path),
                str(biases_path),
                input_path,
                output_path,
                f"0x{quant_m:08x}",
                str(quant_n),
            ]

            start = time.time()
            result = subprocess.run(cmd, capture_output=True, text=True)
            elapsed = time.time() - start

            if result.returncode != 0:
                print(f"ERROR running layer {layer_idx} OG {og}:")
                print(result.stdout)
                print(result.stderr)
                raise RuntimeError(f"FPGA execution failed for layer {layer_idx} OG {og}")

            # Record timing
            key = f"layer_{layer_idx}_og_{og}"
            self.timing[key] = elapsed

            # Load output
            # Output is (out_h * out_w) 64-bit words = (out_h, out_w, 8) bytes
            og_out = binary_to_tensor(output_path, (out_h, out_w, 8))
            outputs.append(og_out)

        # Concatenate output groups along channel dimension
        full_output = np.concatenate(outputs, axis=2)

        # Trim to actual cout (e.g., 255 instead of 256)
        full_output = full_output[:, :, :cout]

        return full_output

    def run_cpu_layer(self, layer_idx):
        """Execute CPU-only layers (maxpool, route, upsample, yolo)."""
        layer_type = CPU_LAYERS.get(layer_idx)

        if layer_type == 'maxpool':
            if layer_idx == 9:
                # Maxpool for layer 8 output: 26x26 -> 13x13
                return maxpool_2x2(self.layer_outputs[8], stride=2)

        elif layer_type == 'route':
            if layer_idx == 17:
                # Route takes layer 13 output
                return self.layer_outputs[13].copy()
            elif layer_idx == 20:
                # Route concatenates layer 19 + layer 8
                l19 = self.layer_outputs[19]
                l8 = self.layer_outputs[8]
                return np.concatenate([l19, l8], axis=2)

        elif layer_type == 'upsample':
            # Layer 19: 2x upsample of layer 18 output
            return upsample_2x(self.layer_outputs[18])

        elif layer_type == 'yolo':
            # YOLO layers don't transform data
            if layer_idx == 16:
                return self.layer_outputs[15].copy()
            elif layer_idx == 23:
                return self.layer_outputs[22].copy()

        raise ValueError(f"Unknown CPU layer: {layer_idx}")

    def run_inference(self, image_path, verify=False, reference=None):
        """
        Run complete TinyYOLOv3 inference.

        Args:
            image_path: Input image path
            verify: If True, verify each layer against reference
            reference: TinyYOLOv3Reference instance for verification

        Returns:
            Dict with detection outputs and timing stats
        """
        self.layer_outputs = {}
        self.timing = {}

        with tempfile.TemporaryDirectory() as tmp_dir:
            # Prepare input
            print(f"\nPreparing input image: {image_path}")
            current_input = self.prepare_input(image_path)
            print(f"  Input shape: {current_input.shape}")

            # If verifying, run reference model first
            if verify and reference is not None:
                print("\nRunning reference model...")
                reference.load_image(str(image_path))
                ref_outputs = reference.run_all_layers()

            # Execute layers in order
            layer_order = []
            for layer_idx in range(24):
                if layer_idx in FPGA_LAYERS:
                    layer_order.append(('fpga', layer_idx))
                elif layer_idx in CPU_LAYERS:
                    layer_order.append(('cpu', layer_idx))
                # Skip standalone maxpool layers (fused into conv)

            for exec_type, layer_idx in layer_order:
                cfg = LAYER_CONFIG.get(layer_idx, {})
                print(f"\nLayer {layer_idx:2d} ({exec_type.upper()}): ", end="")

                if exec_type == 'fpga':
                    # Determine input tensor
                    if layer_idx == 0:
                        layer_input = current_input
                    elif layer_idx == 21:
                        # Layer 21 takes concatenated input from route layer 20
                        l20_out = self.layer_outputs[20]
                        # Pad channels to multiple of 8 (384 -> 384, already good)
                        cin_pad = ceil_div(384, PIN) * PIN
                        layer_input = pad_channels(l20_out, cin_pad)
                        # Pad spatial for 3x3 conv
                        layer_input = pad_spatial(layer_input, kernel_size=3)
                    else:
                        # Get previous layer output
                        prev_idx = layer_idx - 1
                        while prev_idx >= 0 and prev_idx not in self.layer_outputs:
                            prev_idx -= 1

                        prev_out = self.layer_outputs[prev_idx]

                        # Pad channels if needed
                        cin = cfg['cin']
                        cin_pad = ceil_div(cin, PIN) * PIN
                        layer_input = pad_channels(prev_out, cin_pad)

                        # Pad spatial for 3x3 conv
                        if cfg['kernel'] == 3:
                            layer_input = pad_spatial(layer_input, kernel_size=3)

                    print(f"input={layer_input.shape}, ", end="", flush=True)

                    start = time.time()
                    output = self.run_fpga_layer(layer_idx, layer_input, tmp_dir)
                    elapsed = time.time() - start

                    print(f"output={output.shape}, time={elapsed*1000:.1f}ms")
                    self.layer_outputs[layer_idx] = output

                else:  # CPU layer
                    output = self.run_cpu_layer(layer_idx)
                    self.layer_outputs[layer_idx] = output
                    print(f"output={output.shape}")

                # Verify against reference
                if verify and reference is not None and layer_idx in ref_outputs:
                    ref_out = reference.get_layer_output_nhwc(layer_idx)
                    if ref_out is not None and output.shape == ref_out.shape:
                        stats = compare_outputs(ref_out, output, tolerance=3,
                                               name=f"Layer {layer_idx}")
                        if not stats['match']:
                            print(f"  WARNING: Verification failed!")
                            print_comparison(stats)

            # Collect results
            results = {
                'detection_head_1': self.layer_outputs.get(16),
                'detection_head_2': self.layer_outputs.get(23),
                'timing': self.timing,
                'all_outputs': self.layer_outputs,
            }

            return results


def decode_detections(head1, head2, conf_thresh=0.5, nms_thresh=0.4, o_scale_head1=5.316, o_scale_head2=5.409):
    """
    Decode YOLO detection outputs.

    Args:
        head1: 13x13x255 detection head (large objects)
        head2: 26x26x255 detection head (small objects)
        conf_thresh: Confidence threshold
        nms_thresh: NMS IoU threshold
        o_scale_head1: Output scale for head1 (from quantization calibration)
        o_scale_head2: Output scale for head2 (from quantization calibration)

    Returns:
        List of detections: (class_id, confidence, x, y, w, h)
    """
    anchors = {
        'head1': [(81, 82), (135, 169), (344, 319)],
        'head2': [(10, 14), (23, 27), (37, 58)],
    }

    def sigmoid(x):
        return 1 / (1 + np.exp(-x.astype(np.float32)))

    def decode_head(output, anchors_list, stride, o_scale):
        h, w, _ = output.shape
        # Dequantize using calibrated output scale (NOT 127!)
        output = output.astype(np.float32) / o_scale

        # Reshape to (h, w, 3, 85)
        output = output.reshape(h, w, 3, 85)

        boxes = []
        for a in range(3):
            anchor_w, anchor_h = anchors_list[a]

            for i in range(h):
                for j in range(w):
                    pred = output[i, j, a]

                    # Objectness
                    obj_conf = sigmoid(pred[4])
                    if obj_conf < conf_thresh:
                        continue

                    # Class probabilities
                    class_probs = sigmoid(pred[5:])
                    class_id = np.argmax(class_probs)
                    class_conf = class_probs[class_id]

                    confidence = obj_conf * class_conf
                    if confidence < conf_thresh:
                        continue

                    # Bounding box
                    bx = (sigmoid(pred[0]) + j) / w
                    by = (sigmoid(pred[1]) + i) / h
                    bw = (np.exp(pred[2]) * anchor_w) / 416.0
                    bh = (np.exp(pred[3]) * anchor_h) / 416.0

                    boxes.append([class_id, float(confidence), bx, by, bw, bh])

        return boxes

    all_boxes = []
    if head1 is not None:
        all_boxes.extend(decode_head(head1, anchors['head1'], 32, o_scale_head1))
    if head2 is not None:
        all_boxes.extend(decode_head(head2, anchors['head2'], 16, o_scale_head2))

    # Apply NMS
    if len(all_boxes) == 0:
        return []

    # Sort by confidence
    all_boxes.sort(key=lambda x: x[1], reverse=True)

    # Simple NMS
    keep = []
    while all_boxes:
        best = all_boxes.pop(0)
        keep.append(best)

        remaining = []
        for box in all_boxes:
            if box[0] != best[0]:  # Different class
                remaining.append(box)
                continue

            # Calculate IoU
            x1, y1, w1, h1 = best[2:6]
            x2, y2, w2, h2 = box[2:6]

            xi = max(x1 - w1/2, x2 - w2/2)
            yi = max(y1 - h1/2, y2 - h2/2)
            xa = min(x1 + w1/2, x2 + w2/2)
            ya = min(y1 + h1/2, y2 + h2/2)

            inter = max(0, xa - xi) * max(0, ya - yi)
            union = w1*h1 + w2*h2 - inter
            iou = inter / union if union > 0 else 0

            if iou < nms_thresh:
                remaining.append(box)

        all_boxes = remaining

    return keep


def draw_detections(image_path, detections, output_path, class_names=None):
    """Draw detection boxes on image."""
    img = cv2.imread(str(image_path))
    h, w = img.shape[:2]

    for det in detections:
        class_id, conf, bx, by, bw, bh = det

        # Convert to pixel coordinates
        x1 = int((bx - bw/2) * w)
        y1 = int((by - bh/2) * h)
        x2 = int((bx + bw/2) * w)
        y2 = int((by + bh/2) * h)

        # Draw box
        color = (0, 255, 0)
        cv2.rectangle(img, (x1, y1), (x2, y2), color, 2)

        # Label
        label = f"{class_id}: {conf:.2f}"
        if class_names and class_id < len(class_names):
            label = f"{class_names[class_id]}: {conf:.2f}"

        cv2.putText(img, label, (x1, y1-5), cv2.FONT_HERSHEY_SIMPLEX,
                   0.5, color, 2)

    cv2.imwrite(str(output_path), img)
    return img


def main():
    parser = argparse.ArgumentParser(description='TinyYOLOv3 Full Inference')
    parser.add_argument('image', help='Input image path')
    parser.add_argument('--xclbin', default='TinyYOLOV3.xclbin',
                       help='FPGA bitstream path')
    parser.add_argument('--weights-dir', default='data/weights',
                       help='Prepared weights directory')
    parser.add_argument('--run-layer', default='host/run_layer',
                       help='Path to run_layer binary')
    parser.add_argument('--verify', action='store_true',
                       help='Verify against Python reference')
    parser.add_argument('--output', default=None,
                       help='Output image with detections')
    parser.add_argument('--conf-thresh', type=float, default=0.5,
                       help='Detection confidence threshold')
    parser.add_argument('--cpu-only', action='store_true',
                       help='Run reference model only (no FPGA)')
    args = parser.parse_args()

    # Find paths
    script_dir = Path(__file__).parent.absolute()
    project_root = script_dir.parent

    xclbin = args.xclbin
    weights_dir = project_root / args.weights_dir
    run_layer_bin = project_root / args.run_layer

    # Load class names
    coco_names_path = script_dir / 'coco.names'
    class_names = None
    if coco_names_path.exists():
        with open(coco_names_path) as f:
            class_names = [line.strip() for line in f.readlines()]

    # CPU-only mode (reference only)
    if args.cpu_only:
        print("Running reference model (CPU only)...")
        ref = TinyYOLOv3Reference()
        ref.load_image(str(args.image))
        outputs = ref.run_all_layers()

        head1 = ref.get_layer_output_nhwc(15)  # 13x13
        head2 = ref.get_layer_output_nhwc(22)  # 26x26

        print(f"\nDetection head 1: {head1.shape}")
        print(f"Detection head 2: {head2.shape}")

        detections = decode_detections(head1, head2, conf_thresh=args.conf_thresh)
        print(f"\nDetections ({len(detections)}):")
        for det in detections:
            class_id, conf, x, y, w, h = det
            name = class_names[class_id] if class_names else f"class_{class_id}"
            print(f"  {name}: {conf:.2f} at ({x:.2f}, {y:.2f}, {w:.2f}, {h:.2f})")

        if args.output:
            draw_detections(args.image, detections, args.output, class_names)
            print(f"\nOutput saved to: {args.output}")

        return

    # Check prerequisites
    if not weights_dir.exists():
        print(f"ERROR: Weights directory not found: {weights_dir}")
        print("Run: python scripts/prepare_weights.py first")
        sys.exit(1)

    if not run_layer_bin.exists():
        print(f"ERROR: run_layer binary not found: {run_layer_bin}")
        print("Build with: cd host && make run_layer")
        sys.exit(1)

    # Initialize
    reference = None
    if args.verify:
        print("Loading reference model for verification...")
        reference = TinyYOLOv3Reference()

    runner = InferenceRunner(xclbin, weights_dir, str(run_layer_bin))

    # Run inference
    print(f"\n{'='*60}")
    print(f"TinyYOLOv3 Full Inference")
    print(f"{'='*60}")

    results = runner.run_inference(args.image, verify=args.verify, reference=reference)

    # Decode detections
    head1 = results['detection_head_1']
    head2 = results['detection_head_2']

    print(f"\n{'='*60}")
    print(f"Detection Results")
    print(f"{'='*60}")

    if head1 is not None and head2 is not None:
        detections = decode_detections(head1, head2, conf_thresh=args.conf_thresh)
        print(f"Found {len(detections)} detections:")
        for det in detections:
            class_id, conf, x, y, w, h = det
            name = class_names[class_id] if class_names else f"class_{class_id}"
            print(f"  {name}: {conf:.2f} at ({x:.2f}, {y:.2f}, {w:.2f}, {h:.2f})")

        if args.output:
            draw_detections(args.image, detections, args.output, class_names)
            print(f"\nOutput saved to: {args.output}")
    else:
        print("Detection heads not available")

    # Timing summary
    print(f"\n{'='*60}")
    print(f"Timing Summary")
    print(f"{'='*60}")
    total_time = sum(results['timing'].values())
    for key, t in sorted(results['timing'].items()):
        print(f"  {key}: {t*1000:.1f} ms")
    print(f"  Total: {total_time*1000:.1f} ms")


if __name__ == "__main__":
    main()
