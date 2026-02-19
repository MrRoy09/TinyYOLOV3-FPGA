import numpy as np
import cv2
import os

def sigmoid(x):
    return 1 / (1 + np.exp(-x))

class TinyYoloFP32:
    def __init__(self, weights_path):
        print(f"Loading weights from {weights_path}...")
        self.data = np.load(weights_path, allow_pickle=True)
        # Parse layer names to find sorted indices
        self.layer_indices = sorted([int(k.split('_')[1]) for k in self.data.files])
        self.activation_stats = {} # To store max values for calibration
        
        # Cache for layer outputs (needed for route/shortcut layers)
        self.layer_outputs = {}

    def convolution(self, input_data, layer_idx):
        layer_name = f"layer_{layer_idx}"
        params = self.data[layer_name].item()
        
        weights = params['weights'] # (out, in, h, w)
        biases = params['biases']   # (out,)
        activation = params['activation']
        stride = params['stride']
        pad = params['pad']
        
        n_filters, n_channels, k_h, k_w = weights.shape
        batch, in_ch, h, w = input_data.shape
        
        # Padding
        pad_h = k_h // 2 if pad else 0
        pad_w = k_w // 2 if pad else 0
        padded_input = np.pad(input_data, ((0,0), (0,0), (pad_h, pad_h), (pad_w, pad_w)), mode='constant') if pad else input_data
            
        # Output dimensions
        out_h = (h + 2*pad_h - k_h) // stride + 1
        out_w = (w + 2*pad_w - k_w) // stride + 1
        
        output = np.zeros((batch, n_filters, out_h, out_w), dtype=np.float32)
        
        for f in range(n_filters):
            for c in range(n_channels):
                kernel = weights[f, c]
                img_slice = padded_input[0, c]
                
                from numpy.lib.stride_tricks import as_strided
                shape = (out_h, out_w, k_h, k_w)
                strides = (stride * img_slice.strides[0], stride * img_slice.strides[1], img_slice.strides[0], img_slice.strides[1])
                windows = as_strided(img_slice, shape=shape, strides=strides)
                
                output[0, f] += np.einsum('ij,klij->kl', kernel, windows)
            
            output[0, f] += biases[f]
            
        if activation == 'leaky':
            output = np.where(output > 0, output, output * 0.1)
            
        return output

    def maxpool(self, input_data, layer_idx):
        layer_name = f"layer_{layer_idx}"
        params = self.data[layer_name].item()
        size = params['size']
        stride = params['stride']
        
        batch, c, h, w = input_data.shape
        if stride == 1 and size == 2:
             input_data = np.pad(input_data, ((0,0), (0,0), (0,1), (0,1)), mode='constant', constant_values=-float('inf'))
             batch, c, h, w = input_data.shape
        
        out_h = (h - size) // stride + 1
        out_w = (w - size) // stride + 1
        
        if h % size == 0 and w % size == 0 and stride == size:
             reshaped = input_data.reshape(batch, c, out_h, size, out_w, size)
             return reshaped.max(axis=(3, 5))
        
        output = np.zeros((batch, c, out_h, out_w), dtype=np.float32)
        for i in range(out_h):
            for j in range(out_w):
                h_start, w_start = i * stride, j * stride
                output[:, :, i, j] = np.max(input_data[:, :, h_start:h_start+size, w_start:w_start+size], axis=(2, 3))
        return output

    def upsample(self, input_data, layer_idx):
        params = self.data[f"layer_{layer_idx}"].item()
        return input_data.repeat(params['stride'], axis=2).repeat(params['stride'], axis=3)

    def route(self, layer_idx):
        params = self.data[f"layer_{layer_idx}"].item()
        tensors = [self.layer_outputs[layer_idx + l if l < 0 else l] for l in params['layers']]
        return np.concatenate(tensors, axis=1)

    def run_forward(self, image_path):
        img = cv2.imread(image_path)
        if img is None: return None
        blob = cv2.dnn.blobFromImage(img, 1/255.0, (416, 416), swapRB=True, crop=False)
        current_data = blob
        
        for idx in self.layer_indices:
            params = self.data[f"layer_{idx}"].item()
            l_type = params['type']
            
            if l_type == 'convolutional': current_data = self.convolution(current_data, idx)
            elif l_type == 'maxpool': current_data = self.maxpool(current_data, idx)
            elif l_type == 'upsample': current_data = self.upsample(current_data, idx)
            elif l_type == 'route': current_data = self.route(idx)
            
            self.layer_outputs[idx] = current_data
            max_val = np.max(np.abs(current_data))
            if idx not in self.activation_stats: self.activation_stats[idx] = []
            self.activation_stats[idx].append(max_val)

        return self.layer_outputs

def calculate_quant_params(fp32_model):
    q_params = {}
    input_scale = 127.0
    q_params['input_scale'] = input_scale
    prev_scale = input_scale
    
    for idx in fp32_model.layer_indices:
        params = fp32_model.data[f"layer_{idx}"].item()
        l_type = params['type']
        q_params[idx] = {'type': l_type}
        
        if l_type == 'convolutional':
            w_max = np.max(np.abs(params['weights']))
            w_scale = 127.0 / (w_max if w_max != 0 else 1.0)
            a_max = np.percentile(fp32_model.activation_stats[idx], 90) if idx in fp32_model.activation_stats else 1.0
            o_scale = 127.0 / (a_max if a_max != 0 else 1.0)
            
            effective_scale = o_scale / (prev_scale * w_scale)
            n = 16 
            M = int(round(effective_scale * (1 << n)))
            
            q_params[idx].update({
                'q_weights': np.round(params['weights'] * w_scale).astype(np.int8),
                'q_biases': np.round(params['biases'] * (prev_scale * w_scale)).astype(np.int32),
                'M': M, 'n': n, 'o_scale': o_scale,
                'activation': params['activation'], 'stride': params.get('stride', 1), 'pad': params.get('pad', 0)
            })
            prev_scale = o_scale
        elif l_type in ['maxpool', 'upsample']:
            q_params[idx].update({'stride': params.get('stride', 1), 'size': params.get('size', 1), 'o_scale': prev_scale})
        elif l_type == 'route':
            q_params[idx]['o_scale'] = prev_scale
            q_params[idx]['layers'] = params['layers']
        elif l_type == 'yolo':
            q_params[idx]['o_scale'] = prev_scale
    return q_params

class TinyYoloINT8:
    def __init__(self, q_params):
        self.params = q_params
        self.layer_indices = sorted([k for k in q_params.keys() if isinstance(k, int)])
        self.layer_outputs = {}

    def convolution(self, input_data, layer_idx):
        p = self.params[layer_idx]
        weights, biases, M, n, stride, pad, activation = p['q_weights'], p['q_biases'], p['M'], p['n'], p['stride'], p['pad'], p['activation']
        n_filters, n_channels, k_h, k_w = weights.shape
        batch, in_ch, h, w = input_data.shape
        
        pad_h, pad_w = (k_h // 2, k_w // 2) if pad else (0, 0)
        padded_input = np.pad(input_data, ((0,0), (0,0), (pad_h, pad_h), (pad_w, pad_w)), mode='constant', constant_values=0) if pad else input_data
        out_h, out_w = (h + 2*pad_h - k_h) // stride + 1, (w + 2*pad_w - k_w) // stride + 1
        output = np.zeros((batch, n_filters, out_h, out_w), dtype=np.int32)
        
        for f in range(n_filters):
            for c in range(n_channels):
                kernel, img_slice = weights[f, c], padded_input[0, c]
                from numpy.lib.stride_tricks import as_strided
                shape = (out_h, out_w, k_h, k_w)
                strides = (stride * img_slice.strides[0], stride * img_slice.strides[1], img_slice.strides[0], img_slice.strides[1])
                windows = as_strided(img_slice, shape=shape, strides=strides)
                output[0, f] += np.einsum('ij,klij->kl', kernel, windows, dtype=np.int32)
            output[0, f] += biases[f]
        
        if activation == 'leaky': output = np.where(output > 0, output, output >> 3)
        output = (output.astype(np.int64) * M) >> n
        return np.clip(output, -128, 127).astype(np.int8)

    def maxpool(self, input_data, layer_idx):
        p = self.params[layer_idx]
        size, stride = p['size'], p['stride']
        batch, c, h, w = input_data.shape
        if stride == 1 and size == 2:
             input_data = np.pad(input_data, ((0,0), (0,0), (0,1), (0,1)), mode='constant', constant_values=-128)
             batch, c, h, w = input_data.shape
        out_h, out_w = (h - size) // stride + 1, (w - size) // stride + 1
        if h % size == 0 and w % size == 0 and stride == size:
             return input_data.reshape(batch, c, out_h, size, out_w, size).max(axis=(3, 5))
        output = np.full((batch, c, out_h, out_w), -128, dtype=np.int8)
        for i in range(out_h):
            for j in range(out_w):
                h_s, w_s = i * stride, j * stride
                output[:, :, i, j] = np.max(input_data[:, :, h_s:h_s+size, w_s:w_s+size], axis=(2, 3))
        return output
        
    def upsample(self, input_data, layer_idx):
        return input_data.repeat(self.params[layer_idx]['stride'], axis=2).repeat(self.params[layer_idx]['stride'], axis=3)

    def route(self, layer_idx):
        p = self.params[layer_idx]
        tensors = [self.layer_outputs[layer_idx + l if l < 0 else l] for l in p['layers']]
        return np.concatenate(tensors, axis=1)

    def run_forward(self, image_path):
        img = cv2.imread(image_path)
        blob = cv2.dnn.blobFromImage(img, 1/255.0, (416, 416), swapRB=True, crop=False)
        current_data = np.round(blob * self.params['input_scale']).astype(np.int8)
        for idx in self.layer_indices:
            l_type = self.params[idx]['type']
            if l_type == 'convolutional': current_data = self.convolution(current_data, idx)
            elif l_type == 'maxpool': current_data = self.maxpool(current_data, idx)
            elif l_type == 'upsample': current_data = self.upsample(current_data, idx)
            elif l_type == 'route': current_data = self.route(idx)
            self.layer_outputs[idx] = current_data
        return self.layer_outputs

def decode_yolo(output, anchors, num_classes=80, conf_thresh=0.3):
    batch, channels, h, w = output.shape
    output = output.reshape(batch, 3, 5 + num_classes, h, w).transpose(0, 1, 3, 4, 2)
    output[..., 0:2], output[..., 4:] = sigmoid(output[..., 0:2]), sigmoid(output[..., 4:])
    grid_x, grid_y = np.tile(np.arange(w), (h, 1)), np.tile(np.arange(h), (w, 1)).T
    boxes = []
    for a in range(3):
        anchor_w, anchor_h = anchors[a]
        pred_x, pred_y = (output[0, a, :, :, 0] + grid_x) / w, (output[0, a, :, :, 1] + grid_y) / h
        pred_w, pred_h = (np.exp(output[0, a, :, :, 2]) * anchor_w) / 416.0, (np.exp(output[0, a, :, :, 3]) * anchor_h) / 416.0
        conf, probs = output[0, a, :, :, 4], output[0, a, :, :, 5:]
        mask = conf > conf_thresh
        if np.any(mask):
            for i, row in enumerate(np.where(mask)[0]):
                col = np.where(mask)[1][i]
                class_id = np.argmax(probs[row, col])
                if (conf[row, col] * probs[row, col, class_id]) > conf_thresh:
                    boxes.append([pred_x[row, col], pred_y[row, col], pred_w[row, col], pred_h[row, col], float(conf[row, col] * probs[row, col, class_id]), class_id])
    return boxes

def get_final_detections(outputs, q_params=None):
    all_anchors = [(10,14), (23,27), (37,58), (81,82), (135,169), (344,319)]
    masks = {16: [3, 4, 5], 23: [0, 1, 2]}
    all_boxes = []
    for idx in [16, 23]:
        raw = outputs[idx].astype(np.float32) / q_params[idx]['o_scale'] if q_params else outputs[idx]
        all_boxes.extend(decode_yolo(raw, [all_anchors[i] for i in masks[idx]]))
    return all_boxes

def save_quant_params(q_params, path):

    """Saves nested q_params dict to a flat .npz file."""

    flat_params = {}

    for layer_idx, data in q_params.items():

        if isinstance(layer_idx, int):

            for key, val in data.items():

                flat_params[f"l{layer_idx}_{key}"] = val

        else:

            flat_params[layer_idx] = data

    np.savez(path, **flat_params)

    print(f"Quantization parameters frozen to {path}")



def load_quant_params(path):

    """Loads flat .npz file back into nested q_params dict."""

    raw = np.load(path, allow_pickle=True)

    q_params = {}

    for k in raw.files:

        if k.startswith('l') and '_' in k:

            parts = k[1:].split('_')

            idx = int(parts[0])

            key = '_'.join(parts[1:])

            if idx not in q_params: q_params[idx] = {}

            q_params[idx][key] = raw[k]

            # Handle scalars saved as 0-d arrays

            if q_params[idx][key].ndim == 0:

                q_params[idx][key] = q_params[idx][key].item()

        else:

            q_params[k] = raw[k].item() if raw[k].ndim == 0 else raw[k]

    return q_params



if __name__ == "__main__":

    weights_file = "./folded_weights.npz"

    frozen_file = "./quantized_params.npz"

    test_images = ["scripts/test_image.jpg", "scripts/person.jpg", "scripts/horses.jpg", 

                   "scripts/kite.jpg", "scripts/eagle.jpg", "scripts/giraffe.jpg"]

    

    if not os.path.exists(frozen_file):

        print("Frozen parameters not found. Starting Calibration...")

        fp32_model = TinyYoloFP32(weights_file)

        for img_p in test_images:

            if os.path.exists(img_p): fp32_model.run_forward(img_p)

        q_params = calculate_quant_params(fp32_model)

        save_quant_params(q_params, frozen_file)

    else:

        print(f"Loading frozen parameters from {frozen_file}...")

        q_params = load_quant_params(frozen_file)



        print("\n--- Batch Testing: FP32 vs INT8 Model ---")



        fp32_model = TinyYoloFP32(weights_file)



        int8_model = TinyYoloINT8(q_params)



        



        for img_p in test_images:



            if not os.path.exists(img_p): continue



            print(f"\nTesting {img_p}...")



            



            # FP32 Results



            fp32_results = fp32_model.run_forward(img_p)



            fp32_boxes = get_final_detections(fp32_results)



            



            # INT8 Results



            int8_results = int8_model.run_forward(img_p)



            int8_boxes = get_final_detections(int8_results, q_params)



            



            def print_top(boxes, title):



                sorted_boxes = sorted(boxes, key=lambda x: x[4], reverse=True)



                print(f"  {title}: ", end="")



                if not sorted_boxes:



                    print("No detections.")



                else:



                    top = sorted_boxes[0]



                    print(f"Class {top[5]} ({top[4]:.3f}) at [{top[0]:.2f}, {top[1]:.2f}, {top[2]:.2f}, {top[3]:.2f}]")



    



            print_top(fp32_boxes, "FP32 Top")



            print_top(int8_boxes, "INT8 Top")



    


