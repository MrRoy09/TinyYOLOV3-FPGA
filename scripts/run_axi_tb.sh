#!/bin/bash
# Run the AXI conv wrapper testbench
# Usage: ./run_axi_tb.sh [SIM=vivado|iverilog]
#
# Prerequisites:
#   - Run configure_axi_tb.py <layer> first to generate stimulus files

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TB_DIR="$SCRIPT_DIR/../hdl/testbenches"
STIMULUS_DIR="$SCRIPT_DIR/stimulus"

# Source Vivado if available
if [ -f /media/ubuntu/T7/Xilinx-tools/settings64.sh ]; then
    source /media/ubuntu/T7/Xilinx-tools/settings64.sh
fi

# Verify stimulus files exist
if [ ! -f "$STIMULUS_DIR/pixels_og0.hex" ]; then
    echo "ERROR: Stimulus files not found in $STIMULUS_DIR"
    echo "Run: python3 scripts/configure_axi_tb.py <layer_num> first"
    exit 1
fi

# Copy stimulus to testbench work directory
mkdir -p "$TB_DIR/work"
cp "$STIMULUS_DIR"/*.hex "$TB_DIR/work/" 2>/dev/null || true

cd "$TB_DIR"
make tb_axi_conv_wrapper "$@"
