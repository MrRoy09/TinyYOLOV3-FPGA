transcript off
onbreak {quit -force}
onerror {quit -force}
transcript on

vlib work
vlib riviera/xil_defaultlib

vmap xil_defaultlib riviera/xil_defaultlib

vlog -work xil_defaultlib  -incr -v2k5 "+incdir+../../../../../../../Xilinx-tools/2025.1/data/rsb/busdef" -l xil_defaultlib \
"/media/ubuntu/T7/projects/arm-bharat/Tiny_YOLO_HW/Tiny_YOLO_HW.gen/sources_1/ip/TinyYOLOHW/TinyYOLOHW_sim_netlist.v" \


vlog -work xil_defaultlib \
"glbl.v"

