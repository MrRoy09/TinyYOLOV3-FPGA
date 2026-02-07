vlib modelsim_lib/work
vlib modelsim_lib/msim

vlib modelsim_lib/msim/xil_defaultlib

vmap xil_defaultlib modelsim_lib/msim/xil_defaultlib

vlog -work xil_defaultlib -64 -incr -mfcu  "+incdir+../../../../../../../Xilinx-tools/2025.1/data/rsb/busdef" \
"/media/ubuntu/T7/projects/arm-bharat/Tiny_YOLO_HW/Tiny_YOLO_HW.gen/sources_1/ip/TinyYOLOHW/TinyYOLOHW_sim_netlist.v" \


vlog -work xil_defaultlib \
"glbl.v"

