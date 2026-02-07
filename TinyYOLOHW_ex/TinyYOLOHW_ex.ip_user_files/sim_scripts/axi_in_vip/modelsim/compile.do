vlib modelsim_lib/work
vlib modelsim_lib/msim

vlib modelsim_lib/msim/xilinx_vip
vlib modelsim_lib/msim/xpm
vlib modelsim_lib/msim/axis_infrastructure_v1_1_1
vlib modelsim_lib/msim/xil_defaultlib
vlib modelsim_lib/msim/axi4stream_vip_v1_1_21

vmap xilinx_vip modelsim_lib/msim/xilinx_vip
vmap xpm modelsim_lib/msim/xpm
vmap axis_infrastructure_v1_1_1 modelsim_lib/msim/axis_infrastructure_v1_1_1
vmap xil_defaultlib modelsim_lib/msim/xil_defaultlib
vmap axi4stream_vip_v1_1_21 modelsim_lib/msim/axi4stream_vip_v1_1_21

vlog -work xilinx_vip -64 -incr -mfcu  -sv -L axi4stream_vip_v1_1_21 -L axi_vip_v1_1_21 -L xilinx_vip "+incdir+/media/ubuntu/T7/Xilinx-tools/2025.1/Vivado/data/xilinx_vip/include" \
"/media/ubuntu/T7/Xilinx-tools/2025.1/Vivado/data/xilinx_vip/hdl/axi4stream_vip_axi4streampc.sv" \
"/media/ubuntu/T7/Xilinx-tools/2025.1/Vivado/data/xilinx_vip/hdl/axi_vip_axi4pc.sv" \
"/media/ubuntu/T7/Xilinx-tools/2025.1/Vivado/data/xilinx_vip/hdl/xil_common_vip_pkg.sv" \
"/media/ubuntu/T7/Xilinx-tools/2025.1/Vivado/data/xilinx_vip/hdl/axi4stream_vip_pkg.sv" \
"/media/ubuntu/T7/Xilinx-tools/2025.1/Vivado/data/xilinx_vip/hdl/axi_vip_pkg.sv" \
"/media/ubuntu/T7/Xilinx-tools/2025.1/Vivado/data/xilinx_vip/hdl/axi4stream_vip_if.sv" \
"/media/ubuntu/T7/Xilinx-tools/2025.1/Vivado/data/xilinx_vip/hdl/axi_vip_if.sv" \
"/media/ubuntu/T7/Xilinx-tools/2025.1/Vivado/data/xilinx_vip/hdl/clk_vip_if.sv" \
"/media/ubuntu/T7/Xilinx-tools/2025.1/Vivado/data/xilinx_vip/hdl/rst_vip_if.sv" \

vlog -work xpm -64 -incr -mfcu  -sv -L axi4stream_vip_v1_1_21 -L axi_vip_v1_1_21 -L xilinx_vip "+incdir+../../../ipstatic/hdl" "+incdir+../../../../../../../Xilinx-tools/2025.1/data/rsb/busdef" "+incdir+/media/ubuntu/T7/Xilinx-tools/2025.1/Vivado/data/xilinx_vip/include" \
"/media/ubuntu/T7/Xilinx-tools/2025.1/Vivado/data/ip/xpm/xpm_cdc/hdl/xpm_cdc.sv" \
"/media/ubuntu/T7/Xilinx-tools/2025.1/Vivado/data/ip/xpm/xpm_fifo/hdl/xpm_fifo.sv" \
"/media/ubuntu/T7/Xilinx-tools/2025.1/Vivado/data/ip/xpm/xpm_memory/hdl/xpm_memory.sv" \

vcom -work xpm -64 -93  \
"/media/ubuntu/T7/Xilinx-tools/2025.1/data/ip/xpm/xpm_VCOMP.vhd" \

vlog -work axis_infrastructure_v1_1_1 -64 -incr -mfcu  "+incdir+../../../ipstatic/hdl" "+incdir+../../../../../../../Xilinx-tools/2025.1/data/rsb/busdef" "+incdir+/media/ubuntu/T7/Xilinx-tools/2025.1/Vivado/data/xilinx_vip/include" \
"../../../ipstatic/hdl/axis_infrastructure_v1_1_vl_rfs.v" \

vlog -work xil_defaultlib -64 -incr -mfcu  -sv -L axi4stream_vip_v1_1_21 -L axi_vip_v1_1_21 -L xilinx_vip "+incdir+../../../ipstatic/hdl" "+incdir+../../../../../../../Xilinx-tools/2025.1/data/rsb/busdef" "+incdir+/media/ubuntu/T7/Xilinx-tools/2025.1/Vivado/data/xilinx_vip/include" \
"../../../../TinyYOLOHW_ex.gen/sources_1/ip/axi_in_vip/sim/axi_in_vip_pkg.sv" \

vlog -work axi4stream_vip_v1_1_21 -64 -incr -mfcu  -sv -L axi4stream_vip_v1_1_21 -L axi_vip_v1_1_21 -L xilinx_vip "+incdir+../../../ipstatic/hdl" "+incdir+../../../../../../../Xilinx-tools/2025.1/data/rsb/busdef" "+incdir+/media/ubuntu/T7/Xilinx-tools/2025.1/Vivado/data/xilinx_vip/include" \
"../../../ipstatic/hdl/axi4stream_vip_v1_1_vl_rfs.sv" \

vlog -work xil_defaultlib -64 -incr -mfcu  -sv -L axi4stream_vip_v1_1_21 -L axi_vip_v1_1_21 -L xilinx_vip "+incdir+../../../ipstatic/hdl" "+incdir+../../../../../../../Xilinx-tools/2025.1/data/rsb/busdef" "+incdir+/media/ubuntu/T7/Xilinx-tools/2025.1/Vivado/data/xilinx_vip/include" \
"../../../../TinyYOLOHW_ex.gen/sources_1/ip/axi_in_vip/sim/axi_in_vip.sv" \

vlog -work xil_defaultlib \
"glbl.v"

