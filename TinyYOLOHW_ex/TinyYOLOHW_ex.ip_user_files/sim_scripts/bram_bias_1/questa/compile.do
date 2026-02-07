vlib questa_lib/work
vlib questa_lib/msim

vlib questa_lib/msim/xilinx_vip
vlib questa_lib/msim/xpm
vlib questa_lib/msim/blk_mem_gen_v8_4_11
vlib questa_lib/msim/xil_defaultlib

vmap xilinx_vip questa_lib/msim/xilinx_vip
vmap xpm questa_lib/msim/xpm
vmap blk_mem_gen_v8_4_11 questa_lib/msim/blk_mem_gen_v8_4_11
vmap xil_defaultlib questa_lib/msim/xil_defaultlib

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

vlog -work xpm -64 -incr -mfcu  -sv -L axi4stream_vip_v1_1_21 -L axi_vip_v1_1_21 -L xilinx_vip "+incdir+../../../../../../../Xilinx-tools/2025.1/data/rsb/busdef" "+incdir+/media/ubuntu/T7/Xilinx-tools/2025.1/Vivado/data/xilinx_vip/include" \
"/media/ubuntu/T7/Xilinx-tools/2025.1/Vivado/data/ip/xpm/xpm_memory/hdl/xpm_memory.sv" \
"/media/ubuntu/T7/Xilinx-tools/2025.1/Vivado/data/ip/xpm/xpm_cdc/hdl/xpm_cdc.sv" \
"/media/ubuntu/T7/Xilinx-tools/2025.1/Vivado/data/ip/xpm/xpm_fifo/hdl/xpm_fifo.sv" \

vcom -work xpm -64 -93  \
"/media/ubuntu/T7/Xilinx-tools/2025.1/data/ip/xpm/xpm_VCOMP.vhd" \

vlog -work blk_mem_gen_v8_4_11 -64 -incr -mfcu  "+incdir+../../../../../../../Xilinx-tools/2025.1/data/rsb/busdef" "+incdir+/media/ubuntu/T7/Xilinx-tools/2025.1/Vivado/data/xilinx_vip/include" \
"../../../ipstatic/simulation/blk_mem_gen_v8_4.v" \

vlog -work xil_defaultlib -64 -incr -mfcu  "+incdir+../../../../../../../Xilinx-tools/2025.1/data/rsb/busdef" "+incdir+/media/ubuntu/T7/Xilinx-tools/2025.1/Vivado/data/xilinx_vip/include" \
"../../../../../Tiny_YOLO_HW/Tiny_YOLO_HW.gen/sources_1/ip/bram_bias_1/sim/bram_bias_1.v" \

vlog -work xil_defaultlib \
"glbl.v"

