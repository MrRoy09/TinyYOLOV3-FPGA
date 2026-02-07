transcript off
onbreak {quit -force}
onerror {quit -force}
transcript on

asim +access +r +m+bram_weights_1 -sv_seed 1 -L xil_defaultlib -L xilinx_vip -L xpm -L blk_mem_gen_v8_4_11 -L xilinx_vip -L unisims_ver -L unimacro_ver -L secureip -O5 xil_defaultlib.bram_weights_1 xil_defaultlib.glbl

do {bram_weights_1.udo}

run 1000ns

endsim

quit -force
