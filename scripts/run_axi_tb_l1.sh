#!/bin/bash
# Run the TinyYOLOV3_HW_Complete AXI testbench with Layer 1 (ci_groups=2)
# Usage: ./run_axi_tb_l1.sh

set -e

PROJECT_DIR="/media/ubuntu/T7/projects/arm-bharat/TinyYOLOV3_HW_Complete_ex"
PROJECT_FILE="$PROJECT_DIR/TinyYOLOV3_HW_Complete_ex.xpr"
SIM_DIR="$PROJECT_DIR/TinyYOLOV3_HW_Complete_ex.sim/sim_1/behav/xsim"
IMPORTS_DIR="$PROJECT_DIR/imports"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Source Vivado
source /media/ubuntu/T7/Xilinx-tools/settings64.sh

echo "========================================"
echo "TinyYOLOV3 AXI Testbench - Layer 1 (ci_groups=2)"
echo "========================================"

# Step 1: Generate Layer 1 stimulus
echo "Step 1: Generating Layer 1 stimulus..."
python3 "$SCRIPT_DIR/gen_axi_stimulus_l1.py"

# Step 2: Copy hex files to xsim directory
echo "Step 2: Copying hex files to simulation directory..."
mkdir -p "$SIM_DIR"
cp "$IMPORTS_DIR"/*.hex "$SIM_DIR/"
echo "  Copied hex files"

# Step 3: Run simulation
echo "Step 3: Running Vivado simulation..."

TCL_SCRIPT=$(mktemp /tmp/run_axi_sim_l1_XXXXXX.tcl)

cat > "$TCL_SCRIPT" << 'EOF'
# Open project
open_project PROJECT_FILE_PLACEHOLDER

# Set testbench as top
set_property top TinyYOLOV3_HW_Complete_tb [get_filesets sim_1]
set_property top_lib xil_defaultlib [get_filesets sim_1]

# Update compile order
update_compile_order -fileset sim_1

# Launch simulation
puts "Launching behavioral simulation for Layer 1 (ci_groups=2)..."
launch_simulation -mode behavioral

# Run simulation (shorter than L3, ci_groups=2)
puts "Running simulation (timeout: 2ms)..."
run 2ms

puts ""
puts "========================================"
puts "Layer 1 (ci_groups=2) Simulation complete"
puts "========================================"

close_sim
close_project
quit
EOF

sed -i "s|PROJECT_FILE_PLACEHOLDER|$PROJECT_FILE|g" "$TCL_SCRIPT"

cd "$PROJECT_DIR"
vivado -mode batch -source "$TCL_SCRIPT" -nojournal -nolog 2>&1 | tee /tmp/axi_tb_l1_output.log | tail -200

rm -f "$TCL_SCRIPT"

echo ""
echo "========================================"
echo "Full log saved to: /tmp/axi_tb_l1_output.log"
echo "========================================"
