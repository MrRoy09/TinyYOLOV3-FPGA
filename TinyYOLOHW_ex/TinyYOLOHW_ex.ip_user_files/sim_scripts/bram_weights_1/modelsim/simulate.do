onbreak {quit -f}
onerror {quit -f}

vsim -voptargs="+acc" -sv_seed 1 -L xil_defaultlib -L xilinx_vip -L xpm -L blk_mem_gen_v8_4_11 -L xilinx_vip -L unisims_ver -L unimacro_ver -L secureip -lib xil_defaultlib xil_defaultlib.bram_weights_1 xil_defaultlib.glbl

set NumericStdNoWarnings 1
set StdArithNoWarnings 1

do {wave.do}

view wave
view structure
view signals

do {bram_weights_1.udo}

run 1000ns

quit -force
