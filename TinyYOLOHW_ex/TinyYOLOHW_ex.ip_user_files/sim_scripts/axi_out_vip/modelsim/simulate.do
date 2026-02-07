onbreak {quit -f}
onerror {quit -f}

vsim -voptargs="+acc" -sv_seed 1 -L xil_defaultlib -L xilinx_vip -L xpm -L axis_infrastructure_v1_1_1 -L axi4stream_vip_v1_1_21 -L xilinx_vip -L unisims_ver -L unimacro_ver -L secureip -lib xil_defaultlib xil_defaultlib.axi_out_vip xil_defaultlib.glbl

set NumericStdNoWarnings 1
set StdArithNoWarnings 1

do {wave.do}

view wave
view structure
view signals

do {axi_out_vip.udo}

run 1000ns

quit -force
