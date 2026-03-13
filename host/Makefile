# Makefile for TinyYOLOv3 host programs
#
# Usage:
#   make arm              - Build ARM inference programs (no FPGA required)
#   make fpga             - Build FPGA host programs (requires XRT)
#   make all              - Build ARM targets
#
# Benchmarking ARM vs FPGA:
#   1. Export weights:     python3 export_weights_for_cpu.py ../sim/hardware-ai/quantized_params.npz ./weights_cpu
#   2. Naive baseline:     ./yolo_arm_native weights_cpu test.jpg
#   3. Optimized ARM:      ./yolo_arm_optimized weights_cpu test.jpg --benchmark 5
#   4. FPGA:               ./yolo_inference <xclbin> <weights> test.jpg --profile

CXX := g++
CXXFLAGS := -std=c++17 -O3 -march=native -ffast-math -funroll-loops -g -Wall

# XRT paths (only used for FPGA targets)
ifdef XILINX_XRT
    XRT_INCLUDES := -I$(XILINX_XRT)/include
    XRT_LDFLAGS := -L$(XILINX_XRT)/lib
    XRT_LDLIBS := -lxrt_coreutil -luuid -lpthread
else ifneq ($(wildcard /usr/include/xrt/xrt/xrt_bo.h),)
    XRT_INCLUDES := -I/usr/include/xrt
    XRT_LDFLAGS :=
    XRT_LDLIBS := -lxrt_coreutil -luuid -lpthread
    XILINX_XRT := system
else
    XRT_INCLUDES :=
    XRT_LDFLAGS :=
    XRT_LDLIBS :=
endif

# OpenCV flags
OPENCV_CFLAGS := $(shell pkg-config --cflags opencv4 2>/dev/null || echo "-I/usr/include/opencv4")
OPENCV_LIBS := $(shell pkg-config --libs opencv4 2>/dev/null || echo "-lopencv_core -lopencv_imgcodecs -lopencv_imgproc")

# Target lists
FPGA_TARGETS := test_layers_chain test_inference yolo_inference yolo_camera
ARM_TARGETS := yolo_arm_native yolo_arm_optimized

.PHONY: all arm fpga clean help

all: arm
	@echo ""
	@echo "ARM targets built. For FPGA targets: make fpga"

arm: $(ARM_TARGETS)
	@echo ""
	@echo "ARM inference built: yolo_arm_native (naive), yolo_arm_optimized (im2col+NEON+MT)"

fpga: check_xrt $(FPGA_TARGETS)

check_xrt:
ifndef XILINX_XRT
	$(error XRT not found. Set XILINX_XRT or install xrt package.)
endif

# ============================================================================
# ARM Targets (no XRT dependency)
# ============================================================================

yolo_arm_native: yolo_arm_native.cpp yolo_postprocess.hpp
	$(CXX) $(CXXFLAGS) $(OPENCV_CFLAGS) -o $@ $< $(OPENCV_LIBS) -lpthread
	@echo "Built: $@ (naive reference)"

yolo_arm_optimized: yolo_arm_optimized.cpp yolo_postprocess.hpp
	$(CXX) $(CXXFLAGS) $(OPENCV_CFLAGS) -o $@ $< $(OPENCV_LIBS) -lpthread
	@echo "Built: $@ (im2col + NEON + 4-thread)"

# ============================================================================
# FPGA Targets (require XRT)
# ============================================================================

test_layers_chain: test_layers_chain.cpp
	$(CXX) $(CXXFLAGS) $(XRT_INCLUDES) -o $@ $< $(XRT_LDFLAGS) $(XRT_LDLIBS)

test_inference: test_inference.cpp
	$(CXX) $(CXXFLAGS) $(XRT_INCLUDES) -o $@ $< $(XRT_LDFLAGS) $(XRT_LDLIBS)

yolo_inference: yolo_inference.cpp stb_image.h yolo_postprocess.hpp
	$(CXX) $(CXXFLAGS) $(XRT_INCLUDES) $(OPENCV_CFLAGS) -o $@ $< $(XRT_LDFLAGS) $(XRT_LDLIBS) $(OPENCV_LIBS)

yolo_camera: yolo_camera.cpp yolo_postprocess.hpp
	$(CXX) $(CXXFLAGS) $(XRT_INCLUDES) $(OPENCV_CFLAGS) -o $@ $< $(XRT_LDFLAGS) $(XRT_LDLIBS) $(OPENCV_LIBS) -lopencv_highgui -lopencv_videoio -lpthread

# ============================================================================
# Utility
# ============================================================================

clean:
	rm -f $(FPGA_TARGETS) $(ARM_TARGETS)

help:
	@echo "TinyYOLOv3 Host Programs"
	@echo ""
	@echo "Targets:"
	@echo "  make arm     - Build ARM inference (naive + optimized)"
	@echo "  make fpga    - Build FPGA programs (requires XRT)"
	@echo "  make clean   - Remove binaries"
	@echo ""
	@echo "ARM benchmarking:"
	@echo "  1. python3 export_weights_for_cpu.py ../sim/hardware-ai/quantized_params.npz ./weights_cpu"
	@echo "  2. ./yolo_arm_optimized weights_cpu test.jpg --benchmark 5"
