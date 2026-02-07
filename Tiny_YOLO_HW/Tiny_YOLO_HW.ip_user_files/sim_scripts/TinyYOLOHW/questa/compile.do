vlib questa_lib/work
vlib questa_lib/msim

vlib questa_lib/msim/xil_defaultlib

vmap xil_defaultlib questa_lib/msim/xil_defaultlib

vlog -work xil_defaultlib -64 -incr -mfcu  "+incdir+../../../../../../../Xilinx-tools/2025.1/data/rsb/busdef" \
"/media/ubuntu/T7/projects/arm-bharat/Tiny_YOLO_HW/Tiny_YOLO_HW.gen/sources_1/ip/TinyYOLOHW/TinyYOLOHW_sim_netlist.v" \


vlog -work xil_defaultlib \
"glbl.v"

