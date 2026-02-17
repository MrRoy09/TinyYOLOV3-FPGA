#!/bin/bash
# Run a testbench using Vivado in batch mode
# Usage: ./run_tb.sh <testbench_name>
# Example: ./run_tb.sh tb_line_buffer

set -e

TB_NAME="${1:-tb_line_buffer}"
PROJECT_DIR="/media/ubuntu/T7/projects/arm-bharat/TinyYOLOV3-HW"
PROJECT_FILE="$PROJECT_DIR/TinyYOLOV3-HW.xpr"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TB_DIR="/media/ubuntu/T7/projects/arm-bharat/hdl/testbenches"
TB_FILE="$TB_DIR/${TB_NAME}.sv"

# Source Vivado
source /media/ubuntu/T7/Xilinx-tools/settings64.sh

# Create TCL script for this run
TCL_SCRIPT=$(mktemp /tmp/run_sim_XXXXXX.tcl)

cat > "$TCL_SCRIPT" << 'EOF'
# Open project in quiet mode
open_project PROJECT_FILE_PLACEHOLDER

# Add testbench file to project if not already present
set tb_file "TB_FILE_PLACEHOLDER"
if {[file exists $tb_file]} {
    # Check if file is already in project
    set existing [get_files -quiet -of_objects [get_filesets sim_1] $tb_file]
    if {$existing eq ""} {
        puts "Adding $tb_file to simulation fileset..."
        add_files -fileset sim_1 -norecurse $tb_file
    }
}

# Set the top module for simulation
set_property top TB_NAME_PLACEHOLDER [get_filesets sim_1]
set_property top_lib xil_defaultlib [get_filesets sim_1]

# Update compile order
update_compile_order -fileset sim_1

# Launch simulation without GUI
puts "Launching simulation..."
if {[catch {launch_simulation -mode behavioral} errmsg]} {
    puts "ERROR: Failed to launch simulation: $errmsg"
    close_project
    quit
}

# Run simulation to completion (xsim command)
puts "Running simulation..."
run all

# Close simulation and project
close_sim
close_project

quit
EOF

# Replace placeholders
sed -i "s|PROJECT_FILE_PLACEHOLDER|$PROJECT_FILE|g" "$TCL_SCRIPT"
sed -i "s|TB_NAME_PLACEHOLDER|$TB_NAME|g" "$TCL_SCRIPT"
sed -i "s|TB_FILE_PLACEHOLDER|$TB_FILE|g" "$TCL_SCRIPT"

# Verify testbench file exists
if [[ ! -f "$TB_FILE" ]]; then
    echo "ERROR: Testbench file not found: $TB_FILE"
    exit 1
fi

echo "========================================"
echo "Running testbench: $TB_NAME"
echo "Testbench file: $TB_FILE"
echo "========================================"

# Run Vivado in batch mode (timeout 60 seconds)
cd "$PROJECT_DIR"
timeout 60 vivado -mode batch -source "$TCL_SCRIPT" -nojournal -nolog 2>&1 | grep -v "^$" | tail -200

# Cleanup
rm -f "$TCL_SCRIPT"

echo "========================================"
echo "Testbench $TB_NAME complete"
echo "========================================"
