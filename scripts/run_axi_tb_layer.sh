#!/bin/bash
# Run AXI testbench for a specific layer
# Usage: ./run_axi_tb_layer.sh <layer_num> [SIM=vivado|iverilog]
#
# Examples:
#   ./run_axi_tb_layer.sh 0
#   ./run_axi_tb_layer.sh 2 SIM=iverilog

set -e

if [ -z "$1" ]; then
    echo "Usage: ./run_axi_tb_layer.sh <layer_num> [SIM=vivado|iverilog]"
    echo "  layer_num: 0, 2, 4, 6, 8, etc."
    exit 1
fi

LAYER=$1
shift

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TB_DIR="$SCRIPT_DIR/../hdl/testbenches"

# Source Vivado if available
if [ -f /media/ubuntu/T7/Xilinx-tools/settings64.sh ]; then
    source /media/ubuntu/T7/Xilinx-tools/settings64.sh
fi

echo "========================================"
echo "Layer $LAYER AXI Testbench"
echo "========================================"

# Step 1: Configure stimulus for this layer
echo "Configuring stimulus for layer $LAYER..."
python3 "$SCRIPT_DIR/configure_axi_tb.py" "$LAYER"

# Step 2: Copy stimulus to testbench work directory
mkdir -p "$TB_DIR/work"
cp "$SCRIPT_DIR/stimulus"/*.hex "$TB_DIR/work/" 2>/dev/null || true

# Step 3: Run testbench
cd "$TB_DIR"
make tb_axi_conv_wrapper "$@"
