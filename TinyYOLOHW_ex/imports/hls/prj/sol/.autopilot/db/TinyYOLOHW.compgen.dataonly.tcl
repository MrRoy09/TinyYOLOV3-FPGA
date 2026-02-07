# This script segment is generated automatically by AutoPilot

set axilite_register_dict [dict create]
set port_control {
img_width { 
	dir I
	width 32
	depth 1
	mode ap_none
	offset 16
	offset_end 23
}
in_channels { 
	dir I
	width 32
	depth 1
	mode ap_none
	offset 24
	offset_end 31
}
out_channels { 
	dir I
	width 32
	depth 1
	mode ap_none
	offset 32
	offset_end 39
}
quant_M { 
	dir I
	width 32
	depth 1
	mode ap_none
	offset 40
	offset_end 47
}
quant_n { 
	dir I
	width 32
	depth 1
	mode ap_none
	offset 48
	offset_end 55
}
isMaxpool { 
	dir I
	width 1
	depth 1
	mode ap_none
	offset 56
	offset_end 63
}
is_1x1 { 
	dir I
	width 1
	depth 1
	mode ap_none
	offset 64
	offset_end 71
}
stride { 
	dir I
	width 32
	depth 1
	mode ap_none
	offset 72
	offset_end 79
}
ap_start { }
ap_done { }
ap_ready { }
ap_idle { }
interrupt {
}
}
dict set axilite_register_dict control $port_control


