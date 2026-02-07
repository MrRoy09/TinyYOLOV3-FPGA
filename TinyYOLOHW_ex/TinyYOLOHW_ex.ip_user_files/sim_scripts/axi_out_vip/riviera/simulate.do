transcript off
onbreak {quit -force}
onerror {quit -force}
transcript on

asim +access +r +m+axi_out_vip -sv_seed 1 -L xil_defaultlib -L xilinx_vip -L xpm -L axis_infrastructure_v1_1_1 -L axi4stream_vip_v1_1_21 -L xilinx_vip -L unisims_ver -L unimacro_ver -L secureip -O5 xil_defaultlib.axi_out_vip xil_defaultlib.glbl

do {axi_out_vip.udo}

run 1000ns

endsim

quit -force
