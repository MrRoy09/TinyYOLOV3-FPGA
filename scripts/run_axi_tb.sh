#!/bin/bash
# Run the TinyYOLOV3_HW_Complete AXI testbench
# Usage: ./run_axi_tb.sh

set -e

PROJECT_DIR="/media/ubuntu/T7/projects/arm-bharat/TinyYOLOV3_HW_Complete_ex"
PROJECT_FILE="$PROJECT_DIR/TinyYOLOV3_HW_Complete_ex.xpr"
SIM_DIR="$PROJECT_DIR/TinyYOLOV3_HW_Complete_ex.sim/sim_1/behav/xsim"
IMPORTS_DIR="$PROJECT_DIR/imports"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Source Vivado
source /media/ubuntu/T7/Xilinx-tools/settings64.sh

echo "========================================"
echo "TinyYOLOV3 AXI Testbench Runner"
echo "========================================"

# Step 1: Generate/update stimulus files
echo "Step 1: Generating stimulus files..."
python3 "$SCRIPT_DIR/gen_axi_stimulus.py"

# Step 2: Copy hex files to xsim directory
echo "Step 2: Copying hex files to simulation directory..."
mkdir -p "$SIM_DIR"
cp "$IMPORTS_DIR"/*.hex "$SIM_DIR/"
echo "  Copied: $(ls "$SIM_DIR"/*.hex | wc -l) hex files"

# Step 3: Create TCL script for simulation
echo "Step 3: Creating simulation script..."
TCL_SCRIPT=$(mktemp /tmp/run_axi_sim_XXXXXX.tcl)

cat > "$TCL_SCRIPT" << 'EOF'
# Open project
open_project PROJECT_FILE_PLACEHOLDER

# Set testbench as top
set_property top TinyYOLOV3_HW_Complete_tb [get_filesets sim_1]
set_property top_lib xil_defaultlib [get_filesets sim_1]

# Update compile order
update_compile_order -fileset sim_1

# Launch simulation
puts "Launching behavioral simulation..."
launch_simulation -mode behavioral

# Set timeout (1ms simulation time - should be plenty for debug)
puts "Running simulation (timeout: 1ms)..."
run 1ms

# Print final status
puts ""
puts "========================================"
puts "Simulation complete"
puts "========================================"

# Close
close_sim
close_project
quit
EOF

# Replace placeholder
sed -i "s|PROJECT_FILE_PLACEHOLDER|$PROJECT_FILE|g" "$TCL_SCRIPT"

# Step 4: Run simulation
echo "Step 4: Running Vivado simulation..."
echo ""
cd "$PROJECT_DIR"
vivado -mode batch -source "$TCL_SCRIPT" -nojournal -nolog 2>&1 | tee /tmp/axi_tb_output.log | tail -100

# Cleanup
rm -f "$TCL_SCRIPT"

echo ""
echo "========================================"
echo "Full log saved to: /tmp/axi_tb_output.log"
echo "========================================"
