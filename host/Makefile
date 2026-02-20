# Makefile for TinyYOLOv3 host test programs
#
# Usage:
#   make test_layer0_416     - Build layer 0 test
#   make test_layer0_full    - Build layer 0 full test
#   make test_layer01_chain  - Build layer 0+1 chain test
#   make all                 - Build all tests

ifndef XILINX_XRT
$(error XILINX_XRT is not set. Source XRT setup script first: source /opt/xilinx/xrt/setup.sh)
endif

CXX := g++
CXXFLAGS := -std=c++17 -O2 -g -Wall
INCLUDES := -I$(XILINX_XRT)/include
LDFLAGS := -L$(XILINX_XRT)/lib
LDLIBS := -lxrt_coreutil -luuid -lpthread

# Targets
TARGETS := test_layer0_416 test_layer0_full test_layer01_chain test_layers_chain test_inference

.PHONY: all clean

all: $(TARGETS)

test_layer0_416: test_layer0_416.cpp
	$(CXX) $(CXXFLAGS) $(INCLUDES) -o $@ $< $(LDFLAGS) $(LDLIBS)

test_layer0_full: test_layer0_full.cpp
	$(CXX) $(CXXFLAGS) $(INCLUDES) -o $@ $< $(LDFLAGS) $(LDLIBS)

test_layer01_chain: test_layer01_chain.cpp
	$(CXX) $(CXXFLAGS) $(INCLUDES) -o $@ $< $(LDFLAGS) $(LDLIBS)

test_layers_chain: test_layers_chain.cpp
	$(CXX) $(CXXFLAGS) $(INCLUDES) -o $@ $< $(LDFLAGS) $(LDLIBS)

test_inference: test_inference.cpp
	$(CXX) $(CXXFLAGS) $(INCLUDES) -o $@ $< $(LDFLAGS) $(LDLIBS)

clean:
	rm -f $(TARGETS)
