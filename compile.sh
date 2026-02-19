v++ --link --platform /media/ubuntu/T7/Xilinx-tools/2025.1/Vitis/base_platforms/xilinx_kv260_base_202510_1/xilinx_kv260_base_202510_1.xpfm --clock.id
4:TinyYOLOV3_HW_Complete_1.ap_clk -o TinyYOLOV3_HW.xclbin TinyYOLOV3_HW_Complete.xo
xclbinutil --input TinyYOLOV3_HW.xclbin --dump-section BITSTREAM:RAW:TinyYOLOV3_HW.bit && \
  echo 'all: { TinyYOLOV3_HW.bit }' > TinyYOLOV3_HW.bif && \
  bootgen -image TinyYOLOV3_HW.bif -arch zynqmp -process_bitstream bin -w -o TinyYOLOV3_HW.bit.bin
