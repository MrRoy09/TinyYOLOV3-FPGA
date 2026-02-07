transcript off
onbreak {quit -force}
onerror {quit -force}
transcript on

vlib work
vlib riviera/xilinx_vip
vlib riviera/xpm
vlib riviera/xbip_utils_v3_0_14
vlib riviera/mult_gen_v12_0_23
vlib riviera/xbip_dsp48_wrapper_v3_0_7
vlib riviera/xbip_pipe_v3_0_10
vlib riviera/xbip_multadd_v3_0_22
vlib riviera/xil_defaultlib

vmap xilinx_vip riviera/xilinx_vip
vmap xpm riviera/xpm
vmap xbip_utils_v3_0_14 riviera/xbip_utils_v3_0_14
vmap mult_gen_v12_0_23 riviera/mult_gen_v12_0_23
vmap xbip_dsp48_wrapper_v3_0_7 riviera/xbip_dsp48_wrapper_v3_0_7
vmap xbip_pipe_v3_0_10 riviera/xbip_pipe_v3_0_10
vmap xbip_multadd_v3_0_22 riviera/xbip_multadd_v3_0_22
vmap xil_defaultlib riviera/xil_defaultlib

vlog -work xilinx_vip  -incr -l axi4stream_vip_v1_1_21 -l axi_vip_v1_1_21 "+incdir+/media/ubuntu/T7/Xilinx-tools/2025.1/Vivado/data/xilinx_vip/include" -l xilinx_vip -l xpm -l xbip_utils_v3_0_14 -l mult_gen_v12_0_23 -l xbip_dsp48_wrapper_v3_0_7 -l xbip_pipe_v3_0_10 -l xbip_multadd_v3_0_22 -l xil_defaultlib \
"/media/ubuntu/T7/Xilinx-tools/2025.1/Vivado/data/xilinx_vip/hdl/axi4stream_vip_axi4streampc.sv" \
"/media/ubuntu/T7/Xilinx-tools/2025.1/Vivado/data/xilinx_vip/hdl/axi_vip_axi4pc.sv" \
"/media/ubuntu/T7/Xilinx-tools/2025.1/Vivado/data/xilinx_vip/hdl/xil_common_vip_pkg.sv" \
"/media/ubuntu/T7/Xilinx-tools/2025.1/Vivado/data/xilinx_vip/hdl/axi4stream_vip_pkg.sv" \
"/media/ubuntu/T7/Xilinx-tools/2025.1/Vivado/data/xilinx_vip/hdl/axi_vip_pkg.sv" \
"/media/ubuntu/T7/Xilinx-tools/2025.1/Vivado/data/xilinx_vip/hdl/axi4stream_vip_if.sv" \
"/media/ubuntu/T7/Xilinx-tools/2025.1/Vivado/data/xilinx_vip/hdl/axi_vip_if.sv" \
"/media/ubuntu/T7/Xilinx-tools/2025.1/Vivado/data/xilinx_vip/hdl/clk_vip_if.sv" \
"/media/ubuntu/T7/Xilinx-tools/2025.1/Vivado/data/xilinx_vip/hdl/rst_vip_if.sv" \

vlog -work xpm  -incr -l axi4stream_vip_v1_1_21 -l axi_vip_v1_1_21 "+incdir+../../../../../../../Xilinx-tools/2025.1/data/rsb/busdef" "+incdir+/media/ubuntu/T7/Xilinx-tools/2025.1/Vivado/data/xilinx_vip/include" -l xilinx_vip -l xpm -l xbip_utils_v3_0_14 -l mult_gen_v12_0_23 -l xbip_dsp48_wrapper_v3_0_7 -l xbip_pipe_v3_0_10 -l xbip_multadd_v3_0_22 -l xil_defaultlib \
"/media/ubuntu/T7/Xilinx-tools/2025.1/Vivado/data/ip/xpm/xpm_memory/hdl/xpm_memory.sv" \
"/media/ubuntu/T7/Xilinx-tools/2025.1/Vivado/data/ip/xpm/xpm_cdc/hdl/xpm_cdc.sv" \
"/media/ubuntu/T7/Xilinx-tools/2025.1/Vivado/data/ip/xpm/xpm_fifo/hdl/xpm_fifo.sv" \

vcom -work xpm -93  -incr \
"/media/ubuntu/T7/Xilinx-tools/2025.1/data/ip/xpm/xpm_VCOMP.vhd" \

vcom -work xbip_utils_v3_0_14 -93  -incr \
"../../../ipstatic/hdl/xbip_utils_v3_0_vh_rfs.vhd" \

vcom -work mult_gen_v12_0_23 -93  -incr \
"../../../ipstatic/hdl/mult_gen_v12_0_vh_rfs.vhd" \

vcom -work xbip_dsp48_wrapper_v3_0_7 -93  -incr \
"../../../ipstatic/hdl/xbip_dsp48_wrapper_v3_0_vh_rfs.vhd" \

vcom -work xbip_pipe_v3_0_10 -93  -incr \
"../../../ipstatic/hdl/xbip_pipe_v3_0_vh_rfs.vhd" \

vcom -work xbip_multadd_v3_0_22 -93  -incr \
"../../../ipstatic/hdl/xbip_multadd_v3_0_vh_rfs.vhd" \

vcom -work xil_defaultlib -93  -incr \
"../../../../../Tiny_YOLO_HW/Tiny_YOLO_HW.gen/sources_1/ip/mult_gen_0/sim/mult_gen_0.vhd" \

vlog -work xil_defaultlib \
"glbl.v"

