# Makefile for TinyYOLOv3 host programs
#
# Usage:
#   make arm              - Build ARM-native inference (no FPGA required)
#   make fpga             - Build FPGA host programs (requires XRT)
#   make all              - Build everything (requires XRT)
#   make yolo_arm_native  - Build just ARM-native inference
#
# For benchmarking ARM vs FPGA:
#   1. Build ARM version:  make arm
#   2. Export weights:     python3 export_weights_for_cpu.py
#   3. Run ARM inference:  ./yolo_arm_native weights_cpu test.jpg --benchmark 100
#   4. Compare with FPGA:  ./yolo_inference <xclbin> <weights> test.jpg

CXX := g++
CXXFLAGS := -std=c++17 -O2 -g -Wall

# XRT paths (only used for FPGA targets)
ifdef XILINX_XRT
    XRT_INCLUDES := -I$(XILINX_XRT)/include
    XRT_LDFLAGS := -L$(XILINX_XRT)/lib
    XRT_LDLIBS := -lxrt_coreutil -luuid -lpthread
else
    XRT_INCLUDES :=
    XRT_LDFLAGS :=
    XRT_LDLIBS :=
endif

# OpenCV flags
OPENCV_CFLAGS := $(shell pkg-config --cflags opencv4 2>/dev/null || echo "")
OPENCV_LIBS := $(shell pkg-config --libs opencv4 2>/dev/null || echo "-lopencv_core -lopencv_imgcodecs -lopencv_imgproc")

# Target lists
FPGA_TARGETS := test_layer0_416 test_layer0_full test_layer01_chain test_layers_chain test_inference yolo_inference yolo_camera
ARM_TARGETS := yolo_arm_native

.PHONY: all arm fpga clean help

# Default: build ARM (no XRT required)
all: arm
	@echo ""
	@echo "ARM-native targets built. For FPGA targets, run: make fpga"

# Build ARM-native targets (no FPGA/XRT required)
arm: $(ARM_TARGETS)
	@echo ""
	@echo "ARM-native inference built successfully!"
	@echo "Usage: ./yolo_arm_native <weights_dir> <image.jpg>"
	@echo ""
	@echo "First export weights:"
	@echo "  python3 export_weights_for_cpu.py ../sim/hardware-ai/quantized_params.npz ./weights_cpu"

# Build FPGA targets (requires XRT)
fpga: check_xrt $(FPGA_TARGETS)

check_xrt:
ifndef XILINX_XRT
	$(error XILINX_XRT is not set. Source XRT setup script: source /opt/xilinx/xrt/setup.sh)
endif

# ============================================================================
# ARM-Native Targets (no XRT dependency)
# ============================================================================

# ARM-native inference - optimized for Cortex-A53/A72
yolo_arm_native: yolo_arm_native.cpp yolo_postprocess.hpp
	$(CXX) -std=c++17 -O3 -march=native -ffast-math -funroll-loops -g -Wall \
		$(OPENCV_CFLAGS) \
		-o $@ $< \
		$(OPENCV_LIBS) -lpthread
	@echo "Built: $@"

# Cross-compile for ARM (when building on x86 host for Kria target)
yolo_arm_native_cross: yolo_arm_native.cpp yolo_postprocess.hpp
	aarch64-linux-gnu-g++ -std=c++17 -O3 -march=armv8-a+simd -mtune=cortex-a53 \
		-ffast-math -funroll-loops -g -Wall \
		$(OPENCV_CFLAGS) \
		-o $@ $< \
		$(OPENCV_LIBS) -lpthread

# ============================================================================
# FPGA Targets (require XRT)
# ============================================================================

test_layer0_416: test_layer0_416.cpp
	$(CXX) $(CXXFLAGS) $(XRT_INCLUDES) -o $@ $< $(XRT_LDFLAGS) $(XRT_LDLIBS)

test_layer0_full: test_layer0_full.cpp
	$(CXX) $(CXXFLAGS) $(XRT_INCLUDES) -o $@ $< $(XRT_LDFLAGS) $(XRT_LDLIBS)

test_layer01_chain: test_layer01_chain.cpp
	$(CXX) $(CXXFLAGS) $(XRT_INCLUDES) -o $@ $< $(XRT_LDFLAGS) $(XRT_LDLIBS)

test_layers_chain: test_layers_chain.cpp
	$(CXX) $(CXXFLAGS) $(XRT_INCLUDES) -o $@ $< $(XRT_LDFLAGS) $(XRT_LDLIBS)

test_inference: test_inference.cpp
	$(CXX) $(CXXFLAGS) $(XRT_INCLUDES) -o $@ $< $(XRT_LDFLAGS) $(XRT_LDLIBS)

yolo_inference: yolo_inference.cpp stb_image.h yolo_postprocess.hpp
	$(CXX) $(CXXFLAGS) $(XRT_INCLUDES) $(OPENCV_CFLAGS) -o $@ $< $(XRT_LDFLAGS) $(XRT_LDLIBS) $(OPENCV_LIBS)

yolo_camera: yolo_camera.cpp yolo_postprocess.hpp
	$(CXX) $(CXXFLAGS) $(XRT_INCLUDES) $(OPENCV_CFLAGS) -o $@ $< $(XRT_LDFLAGS) $(XRT_LDLIBS) $(OPENCV_LIBS) -lpthread

# ============================================================================
# Utility
# ============================================================================

clean:
	rm -f $(FPGA_TARGETS) $(ARM_TARGETS) yolo_arm_native_cross

help:
	@echo "TinyYOLOv3 Host Programs Makefile"
	@echo ""
	@echo "Targets:"
	@echo "  make arm          - Build ARM-native inference (no FPGA required)"
	@echo "  make fpga         - Build FPGA host programs (requires XRT)"
	@echo "  make all          - Same as 'make arm'"
	@echo "  make clean        - Remove built binaries"
	@echo ""
	@echo "ARM-native benchmarking:"
	@echo "  1. make arm"
	@echo "  2. python3 export_weights_for_cpu.py"
	@echo "  3. ./yolo_arm_native weights_cpu test.jpg --benchmark 100"
