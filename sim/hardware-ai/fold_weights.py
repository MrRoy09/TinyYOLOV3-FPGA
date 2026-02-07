import numpy as np
import os
import struct

def parse_cfg(cfg_path):
    """
    Parses the Darknet .cfg file to understand layer structure.
    Returns a list of blocks (dicts).
    """
    with open(cfg_path, 'r') as f:
        lines = f.read().split('\n')
    
    blocks = []
    block = {}
    
    for line in lines:
        line = line.strip()
        if not line or line.startswith('#'):
            continue
        
        if line.startswith('['):
            if block:
                blocks.append(block)
                block = {}
            block['type'] = line[1:-1].strip()
        else:
            key, value = line.split('=')
            block[key.strip()] = value.strip()
            
    if block:
        blocks.append(block)
        
    return blocks

def load_weights(weights_path):
    """
    Loads the raw binary weights file.
    Returns the weights as a numpy array and the header.
    """
    with open(weights_path, 'rb') as f:
        # The first 5 values are header information
        # 1. Major version number
        # 2. Minor version number
        # 3. Subversion number
        # 4, 5. Images seen by the network (during training)
        header = np.fromfile(f, dtype=np.int32, count=5)
        weights = np.fromfile(f, dtype=np.float32)
        
    return header, weights

def fold_batch_norm(blocks, weights):
    """
    Iterates through the layers, folds BN into Conv, and returns
    a list of layers with 'weights' and 'bias' keys.
    """
    ptr = 0
    layers = []
    
    for i, block in enumerate(blocks):
        if block['type'] == 'convolutional':
            # Get layer parameters
            batch_normalize = int(block.get('batch_normalize', 0))
            filters = int(block['filters'])
            size = int(block['size'])
            stride = int(block['stride'])
            pad = int(block['pad'])
            activation = block['activation']
            
            # Check previous layer for input channels
            if i == 0:
                input_channels = 3 # RGB image
            else:
                prev_layer = blocks[i-1]
                if prev_layer['type'] == 'convolutional':
                    input_channels = int(prev_layer['filters'])
                elif prev_layer['type'] == 'maxpool':
                    # Find the convolution before the maxpool
                    # In TinyYOLOv3, maxpool doesn't change channels
                    # This is a simplification; a robust parser tracks channels properly
                    # For TinyYOLOv3 structure, this holds.
                    # We need to look back to find the last filter count.
                    # A better way is to track output_shapes.
                    pass 
                # For this specific script on TinyYOLOv3 structure, we need to be careful.
                # Let's dynamically track channels in the main loop instead.
            
            # --- Better Channel Tracking Strategy needed for robust parsing ---
            # But for now, we just consume weights based on the formula:
            # Conv weights count: filters * input_channels * size * size
            # But wait! We don't know input_channels easily just from previous block text.
            # We must calculate it.
            pass

    return []

# Let's rewrite the main logic to track 'prev_filters'
def process_network(cfg_path, weights_path, output_path):
    blocks = parse_cfg(cfg_path)
    header, all_weights = load_weights(weights_path)
    
    ptr = 0
    prev_filters = 3 # Start with RGB input
    
    folded_layers = {}
    
    # TinyYOLOv3 specific: we need to handle the 'route' and 'yolo' layers to track channels correctly
    # Only Convolutional layers have weights.
    
    output_filters = [] # Track output filters of each layer by index
    
    print(f"Total weights in file: {len(all_weights)}")
    
    for i, block in enumerate(blocks):
        layer_type = block['type']
        
        if layer_type == 'net':
            continue
            
        elif layer_type == 'convolutional':
            batch_normalize = int(block.get('batch_normalize', 0))
            filters = int(block['filters'])
            kernel_size = int(block['size'])
            stride = int(block['stride'])
            pad = int(block['pad'])
            activation = block['activation']
            
            # Calculate input channels
            # Usually it's the output of the previous layer
            if i == 0:
                in_ch = 3 # 'net' is usually block 0, but parse_cfg might split differently.
                          # In darknet cfg, [net] is the first block.
                          # Our parse_cfg returns [net] as blocks[0].
                          # So the first conv is blocks[1].
                pass
            
            # Let's find the real input channels based on the 'output_filters' list
            # The input to this layer is the output of the previous layer (i-1)
            # Adjust index because blocks[0] is [net]
            if len(output_filters) == 0:
                in_ch = 3
            else:
                # The previous layer's output channels
                # We need to handle 'route' layers or 'shortcut' if they exist, 
                # but TinyYOLOv3 mainly has conv and maxpool.
                # Let's look at the previous block logic.
                pass
                
            # Actually, let's just trace the graph linearly for now, 
            # as TinyYOLOv3 is mostly linear except for the route/upsample near the end.
            
            # To do this robustly without a full graph engine:
            # We will just maintain 'current_channels'.
            
            pass 
            
    # --- SIMPLIFIED IMPLEMENTATION FOR TINY-YOLO V3 STRUCTURE ---
    # We will trace the 'current_channels' variable.
    
    current_channels = 3
    # We need to store output channels of every layer to handle 'route'
    layer_output_channels = {} 
    
    block_idx = 0 # Logical index of layer in the network (excluding [net])
    
    for block in blocks:
        if block['type'] == 'net':
            continue
            
        if block['type'] == 'convolutional':
            batch_normalize = int(block.get('batch_normalize', 0))
            filters = int(block['filters'])
            size = int(block['size'])
            stride = int(block['stride'])
            pad = int(block.get('pad', 0))
            
            # Number of weights
            # Shape: (out_channels, in_channels, k, k)
            num_weights = filters * current_channels * size * size
            
            bn_biases = None
            bn_weights = None
            bn_means = None
            bn_vars = None
            conv_biases = None
            conv_weights = None
            
            if batch_normalize:
                # Order in file: BN Biases, BN Weights, BN Means, BN Vars
                bn_biases = all_weights[ptr : ptr + filters]
                ptr += filters
                
                bn_weights = all_weights[ptr : ptr + filters]
                ptr += filters
                
                bn_means = all_weights[ptr : ptr + filters]
                ptr += filters
                
                bn_vars = all_weights[ptr : ptr + filters]
                ptr += filters
                
                # Conv weights follow BN params
                conv_weights = all_weights[ptr : ptr + num_weights]
                ptr += num_weights
                
                # FOLDING LOGIC
                # W_new = W_old * (gamma / sqrt(var + epsilon))
                # B_new = beta - (mean * gamma / sqrt(var + epsilon))
                epsilon = 0.000001
                scale = bn_weights / np.sqrt(bn_vars + epsilon)
                
                # Reshape scale for broadcasting: (filters, 1, 1, 1)
                scale_reshaped = scale.reshape(filters, 1, 1, 1)
                
                # Reshape conv weights: (filters, in_channels, size, size)
                w_reshaped = conv_weights.reshape(filters, current_channels, size, size)
                
                folded_w = w_reshaped * scale_reshaped
                folded_b = bn_biases - (bn_means * scale)
                
            else:
                # If no BN, order is: Biases, Weights
                conv_biases = all_weights[ptr : ptr + filters]
                ptr += filters
                
                conv_weights = all_weights[ptr : ptr + num_weights]
                ptr += num_weights
                
                folded_w = conv_weights.reshape(filters, current_channels, size, size)
                folded_b = conv_biases
                
            # Store processed weights
            folded_layers[f"layer_{block_idx}"] = {
                "type": "convolutional",
                "weights": folded_w,
                "biases": folded_b,
                "activation": block['activation'],
                "stride": stride,
                "pad": pad
            }
            
            current_channels = filters
            layer_output_channels[block_idx] = filters
            
        elif block['type'] == 'maxpool':
            # Maxpool doesn't change channels
            folded_layers[f"layer_{block_idx}"] = {
                "type": "maxpool",
                "size": int(block['size']),
                "stride": int(block['stride'])
            }
            layer_output_channels[block_idx] = current_channels
            
        elif block['type'] == 'upsample':
            stride = int(block['stride'])
            # Channels stay same, spatial dim increases
            folded_layers[f"layer_{block_idx}"] = {
                "type": "upsample",
                "stride": stride
            }
            layer_output_channels[block_idx] = current_channels
            
        elif block['type'] == 'route':
            # Route layers can be "-4" or "-1, 8"
            layers_attr = block['layers'].split(',')
            layers_attr = [int(x.strip()) for x in layers_attr]
            
            total_filters = 0
            for l_idx in layers_attr:
                if l_idx < 0:
                    src_layer_idx = block_idx + l_idx
                else:
                    src_layer_idx = l_idx
                
                total_filters += layer_output_channels[src_layer_idx]
            
            current_channels = total_filters
            folded_layers[f"layer_{block_idx}"] = {
                "type": "route",
                "layers": layers_attr
            }
            layer_output_channels[block_idx] = current_channels
            
        elif block['type'] == 'yolo':
             folded_layers[f"layer_{block_idx}"] = {
                "type": "yolo"
            }
             layer_output_channels[block_idx] = current_channels
        
        block_idx += 1
        
    print(f"Processed {block_idx} layers.")
    print(f"Saving folded parameters to {output_path}...")
    np.savez(output_path, **folded_layers)
    print("Done.")

if __name__ == "__main__":
    cfg = "scripts/yolov3-tiny.cfg"
    wgt = "scripts/yolov3-tiny.weights"
    out = "sim/hardware-ai/folded_weights.npz"
    
    if os.path.exists(cfg) and os.path.exists(wgt):
        process_network(cfg, wgt, out)
    else:
        print("Error: Config or Weights file not found in scripts/")
