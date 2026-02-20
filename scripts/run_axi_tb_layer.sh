#!/bin/bash
# Run AXI testbench for a specific layer
# Usage: ./run_axi_tb_layer.sh <layer_num>

set -e

if [ -z "$1" ]; then
    echo "Usage: ./run_axi_tb_layer.sh <layer_num>"
    echo "  layer_num: 0, 1, 2, or 3"
    exit 1
fi

LAYER=$1
PROJECT_DIR="/media/ubuntu/T7/projects/arm-bharat/TinyYOLOV3_HW_Complete_ex"
PROJECT_FILE="$PROJECT_DIR/TinyYOLOV3_HW_Complete_ex.xpr"
SIM_DIR="$PROJECT_DIR/TinyYOLOV3_HW_Complete_ex.sim/sim_1/behav/xsim"
IMPORTS_DIR="$PROJECT_DIR/imports"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Source Vivado
source /media/ubuntu/T7/Xilinx-tools/settings64.sh

echo "========================================"
echo "TinyYOLOV3 AXI Testbench - Layer $LAYER"
echo "========================================"

# Step 1: Configure for the layer
echo "Step 1: Configuring for Layer $LAYER..."
python3 "$SCRIPT_DIR/configure_axi_tb.py" "$LAYER"

# Step 2: Copy hex files to xsim directory
echo ""
echo "Step 2: Copying hex files to simulation directory..."
mkdir -p "$SIM_DIR"
cp "$IMPORTS_DIR"/*.hex "$SIM_DIR/"
echo "  Copied hex files"

# Step 3: Run simulation
echo ""
echo "Step 3: Running Vivado simulation..."

TCL_SCRIPT=$(mktemp /tmp/run_axi_sim_l${LAYER}_XXXXXX.tcl)

cat > "$TCL_SCRIPT" << EOF
# Open project
open_project $PROJECT_FILE

# Set testbench as top
set_property top TinyYOLOV3_HW_Complete_tb [get_filesets sim_1]
set_property top_lib xil_defaultlib [get_filesets sim_1]

# Update compile order
update_compile_order -fileset sim_1

# Launch simulation
puts "Launching behavioral simulation for Layer $LAYER..."
launch_simulation -mode behavioral

# Adjust timeout based on layer (higher ci_groups = more data)
set timeout_ms [expr {1 + $LAYER * 2}]
puts "Running simulation (timeout: \${timeout_ms}ms)..."
run \${timeout_ms}ms

puts ""
puts "========================================"
puts "Layer $LAYER Simulation complete"
puts "========================================"

close_sim
close_project
quit
EOF

cd "$PROJECT_DIR"
vivado -mode batch -source "$TCL_SCRIPT" -nojournal -nolog 2>&1 | tee /tmp/axi_tb_l${LAYER}_output.log | tail -150

rm -f "$TCL_SCRIPT"

echo ""
echo "========================================"
echo "Full log saved to: /tmp/axi_tb_l${LAYER}_output.log"
echo "========================================"
