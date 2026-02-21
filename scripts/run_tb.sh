#!/bin/bash
# Run a testbench using the Makefile in hdl/testbenches/
# Usage: ./run_tb.sh <testbench_name> [SIM=vivado|iverilog]
#
# Examples:
#   ./run_tb.sh tb_conv_pe
#   ./run_tb.sh tb_axi_conv_wrapper SIM=iverilog

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TB_DIR="$SCRIPT_DIR/../hdl/testbenches"

# Source Vivado if available
if [ -f /media/ubuntu/T7/Xilinx-tools/settings64.sh ]; then
    source /media/ubuntu/T7/Xilinx-tools/settings64.sh
fi

# Default testbench
TB_NAME="${1:-tb_conv_pe}"

# Pass through any additional args (like SIM=iverilog)
shift 2>/dev/null || true

cd "$TB_DIR"
make "$TB_NAME" "$@"
