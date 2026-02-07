onbreak {quit -f}
onerror {quit -f}

vsim -voptargs="+acc" -sv_seed 1 -L xil_defaultlib -L xilinx_vip -L xpm -L xbip_utils_v3_0_14 -L mult_gen_v12_0_23 -L xbip_dsp48_wrapper_v3_0_7 -L xbip_pipe_v3_0_10 -L xbip_multadd_v3_0_22 -L xilinx_vip -L unisims_ver -L unimacro_ver -L secureip -lib xil_defaultlib xil_defaultlib.mult_gen_0 xil_defaultlib.glbl

set NumericStdNoWarnings 1
set StdArithNoWarnings 1

do {wave.do}

view wave
view structure
view signals

do {mult_gen_0.udo}

run 1000ns

quit -force
