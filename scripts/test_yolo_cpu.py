import cv2
import numpy as np
import os
import time

def main():
    # Paths
    weights_path = "scripts/yolov3-tiny.weights"
    config_path = "scripts/yolov3-tiny.cfg"
    names_path = "scripts/coco.names"
    image_path = "scripts/test_image.jpg"

    # Verify files exist
    for p in [weights_path, config_path, names_path, image_path]:
        if not os.path.exists(p):
            print(f"Error: {p} not found.")
            return

    # Load class names
    with open(names_path, "r") as f:
        classes = [line.strip() for line in f.readlines()]

    # Load model
    print("Loading model...")
    net = cv2.dnn.readNet(weights_path, config_path)
    
    # Try to use OpenCL if available for a bit of speedup, 
    # though we are targeting CPU for this test.
    net.setPreferableBackend(cv2.dnn.DNN_BACKEND_OPENCV)
    net.setPreferableTarget(cv2.dnn.DNN_TARGET_CPU)

    # Load image
    image = cv2.imread(image_path)
    if image is None:
        print(f"Error: Could not read image {image_path}")
        return
    
    height, width = image.shape[:2]

    # Create blob from image
    # YOLOv3-tiny uses 416x416
    blob = cv2.dnn.blobFromImage(image, 1/255.0, (416, 416), swapRB=True, crop=False)
    net.setInput(blob)

    # Get output layers
    layer_names = net.getLayerNames()
    output_layers = [layer_names[i - 1] for i in net.getUnconnectedOutLayers()]

    # Run forward pass
    print("Running inference...")
    start_time = time.time()
    outputs = net.forward(output_layers)
    end_time = time.time()
    print(f"Inference took: {end_time - start_time:.4f} seconds")

    # Processing detections
    class_ids = []
    confidences = []
    boxes = []
    
    for out in outputs:
        for detection in out:
            scores = detection[5:]
            class_id = np.argmax(scores)
            confidence = scores[class_id]
            if confidence > 0.3:
                # Object detected
                center_x = int(detection[0] * width)
                center_y = int(detection[1] * height)
                w = int(detection[2] * width)
                h = int(detection[3] * height)

                # Rectangle coordinates
                x = int(center_x - w / 2)
                y = int(center_y - h / 2)

                boxes.append([x, y, w, h])
                confidences.append(float(confidence))
                class_ids.append(class_id)

    # Apply Non-Maximum Suppression to remove overlapping boxes
    indices = cv2.dnn.NMSBoxes(boxes, confidences, 0.3, 0.4)

    if len(indices) > 0:
        print(f"Found {len(indices)} objects:")
        for i in indices.flatten():
            label = str(classes[class_ids[i]])
            conf = confidences[i]
            box = boxes[i]
            print(f" - {label}: {conf:.2f} at {box}")
            
            # Draw bounding box
            x, y, w, h = box
            cv2.rectangle(image, (x, y), (x + w, y + h), (0, 255, 0), 2)
            cv2.putText(image, f"{label} {conf:.2f}", (x, y - 10), cv2.FONT_HERSHEY_SIMPLEX, 0.5, (0, 255, 0), 2)
    else:
        print("No objects detected.")

    # Save output image
    output_image_path = "scripts/detection_result.jpg"
    cv2.imwrite(output_image_path, image)
    print(f"Result saved to {output_image_path}")

if __name__ == "__main__":
    main()
