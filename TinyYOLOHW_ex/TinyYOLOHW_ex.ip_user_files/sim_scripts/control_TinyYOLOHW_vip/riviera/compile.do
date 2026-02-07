transcript off
onbreak {quit -force}
onerror {quit -force}
transcript on

vlib work
vlib riviera/xilinx_vip
vlib riviera/xpm
vlib riviera/axi_infrastructure_v1_1_0
vlib riviera/xil_defaultlib
vlib riviera/axi_vip_v1_1_21

vmap xilinx_vip riviera/xilinx_vip
vmap xpm riviera/xpm
vmap axi_infrastructure_v1_1_0 riviera/axi_infrastructure_v1_1_0
vmap xil_defaultlib riviera/xil_defaultlib
vmap axi_vip_v1_1_21 riviera/axi_vip_v1_1_21

vlog -work xilinx_vip  -incr -l axi4stream_vip_v1_1_21 "+incdir+/media/ubuntu/T7/Xilinx-tools/2025.1/Vivado/data/xilinx_vip/include" -l xilinx_vip -l xpm -l axi_infrastructure_v1_1_0 -l xil_defaultlib -l axi_vip_v1_1_21 \
"/media/ubuntu/T7/Xilinx-tools/2025.1/Vivado/data/xilinx_vip/hdl/axi4stream_vip_axi4streampc.sv" \
"/media/ubuntu/T7/Xilinx-tools/2025.1/Vivado/data/xilinx_vip/hdl/axi_vip_axi4pc.sv" \
"/media/ubuntu/T7/Xilinx-tools/2025.1/Vivado/data/xilinx_vip/hdl/xil_common_vip_pkg.sv" \
"/media/ubuntu/T7/Xilinx-tools/2025.1/Vivado/data/xilinx_vip/hdl/axi4stream_vip_pkg.sv" \
"/media/ubuntu/T7/Xilinx-tools/2025.1/Vivado/data/xilinx_vip/hdl/axi_vip_pkg.sv" \
"/media/ubuntu/T7/Xilinx-tools/2025.1/Vivado/data/xilinx_vip/hdl/axi4stream_vip_if.sv" \
"/media/ubuntu/T7/Xilinx-tools/2025.1/Vivado/data/xilinx_vip/hdl/axi_vip_if.sv" \
"/media/ubuntu/T7/Xilinx-tools/2025.1/Vivado/data/xilinx_vip/hdl/clk_vip_if.sv" \
"/media/ubuntu/T7/Xilinx-tools/2025.1/Vivado/data/xilinx_vip/hdl/rst_vip_if.sv" \

vlog -work xpm  -incr -l axi4stream_vip_v1_1_21 "+incdir+../../../ipstatic/hdl" "+incdir+../../../../../../../Xilinx-tools/2025.1/data/rsb/busdef" "+incdir+/media/ubuntu/T7/Xilinx-tools/2025.1/Vivado/data/xilinx_vip/include" -l xilinx_vip -l xpm -l axi_infrastructure_v1_1_0 -l xil_defaultlib -l axi_vip_v1_1_21 \
"/media/ubuntu/T7/Xilinx-tools/2025.1/Vivado/data/ip/xpm/xpm_cdc/hdl/xpm_cdc.sv" \
"/media/ubuntu/T7/Xilinx-tools/2025.1/Vivado/data/ip/xpm/xpm_fifo/hdl/xpm_fifo.sv" \
"/media/ubuntu/T7/Xilinx-tools/2025.1/Vivado/data/ip/xpm/xpm_memory/hdl/xpm_memory.sv" \

vcom -work xpm -93  -incr \
"/media/ubuntu/T7/Xilinx-tools/2025.1/data/ip/xpm/xpm_VCOMP.vhd" \

vlog -work axi_infrastructure_v1_1_0  -incr -v2k5 "+incdir+../../../ipstatic/hdl" "+incdir+../../../../../../../Xilinx-tools/2025.1/data/rsb/busdef" "+incdir+/media/ubuntu/T7/Xilinx-tools/2025.1/Vivado/data/xilinx_vip/include" -l xilinx_vip -l xpm -l axi_infrastructure_v1_1_0 -l xil_defaultlib -l axi_vip_v1_1_21 \
"../../../ipstatic/hdl/axi_infrastructure_v1_1_vl_rfs.v" \

vlog -work xil_defaultlib  -incr -l axi4stream_vip_v1_1_21 "+incdir+../../../ipstatic/hdl" "+incdir+../../../../../../../Xilinx-tools/2025.1/data/rsb/busdef" "+incdir+/media/ubuntu/T7/Xilinx-tools/2025.1/Vivado/data/xilinx_vip/include" -l xilinx_vip -l xpm -l axi_infrastructure_v1_1_0 -l xil_defaultlib -l axi_vip_v1_1_21 \
"../../../../TinyYOLOHW_ex.gen/sources_1/ip/control_TinyYOLOHW_vip/sim/control_TinyYOLOHW_vip_pkg.sv" \

vlog -work axi_vip_v1_1_21  -incr -l axi4stream_vip_v1_1_21 "+incdir+../../../ipstatic/hdl" "+incdir+../../../../../../../Xilinx-tools/2025.1/data/rsb/busdef" "+incdir+/media/ubuntu/T7/Xilinx-tools/2025.1/Vivado/data/xilinx_vip/include" -l xilinx_vip -l xpm -l axi_infrastructure_v1_1_0 -l xil_defaultlib -l axi_vip_v1_1_21 \
"../../../ipstatic/hdl/axi_vip_v1_1_vl_rfs.sv" \

vlog -work xil_defaultlib  -incr -l axi4stream_vip_v1_1_21 "+incdir+../../../ipstatic/hdl" "+incdir+../../../../../../../Xilinx-tools/2025.1/data/rsb/busdef" "+incdir+/media/ubuntu/T7/Xilinx-tools/2025.1/Vivado/data/xilinx_vip/include" -l xilinx_vip -l xpm -l axi_infrastructure_v1_1_0 -l xil_defaultlib -l axi_vip_v1_1_21 \
"../../../../TinyYOLOHW_ex.gen/sources_1/ip/control_TinyYOLOHW_vip/sim/control_TinyYOLOHW_vip.sv" \

vlog -work xil_defaultlib \
"glbl.v"

