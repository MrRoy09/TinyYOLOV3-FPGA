transcript off
onbreak {quit -force}
onerror {quit -force}
transcript on

asim +access +r +m+control_TinyYOLOHW_vip -sv_seed 1 -L xil_defaultlib -L xilinx_vip -L xpm -L axi_infrastructure_v1_1_0 -L axi_vip_v1_1_21 -L xilinx_vip -L unisims_ver -L unimacro_ver -L secureip -O5 xil_defaultlib.control_TinyYOLOHW_vip xil_defaultlib.glbl

do {control_TinyYOLOHW_vip.udo}

run 1000ns

endsim

quit -force
