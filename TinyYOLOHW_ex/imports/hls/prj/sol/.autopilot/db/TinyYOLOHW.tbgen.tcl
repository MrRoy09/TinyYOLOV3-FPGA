set moduleName TinyYOLOHW
set isTopModule 1
set isCombinational 0
set isDatapathOnly 0
set isPipelined 0
set isPipelined_legacy 0
set pipeline_type loop_auto_rewind
set FunctionProtocol ap_ctrl_hs
set isOneStateSeq 0
set ProfileFlag 0
set StallSigGenFlag 0
set isEnableWaveformDebug 1
set hasInterrupt 0
set DLRegFirstOffset 0
set DLRegItemOffset 0
set svuvm_can_support 1
set cdfgNum 2
set C_modelName {TinyYOLOHW}
set C_modelType { void 0 }
set ap_memory_interface_dict [dict create]
set C_modelArgList {
	{ img_width int 32 unused {axi_slave 0}  }
	{ in_channels int 32 unused {axi_slave 0}  }
	{ out_channels int 32 unused {axi_slave 0}  }
	{ quant_M int 32 unused {axi_slave 0}  }
	{ quant_n int 32 unused {axi_slave 0}  }
	{ isMaxpool uint 1 unused {axi_slave 0}  }
	{ is_1x1 uint 1 unused {axi_slave 0}  }
	{ stride int 32 unused {axi_slave 0}  }
	{ axi_in_V_data_V int 512 regular {axi_s 0 volatile  { axi_in Data } }  }
	{ axi_in_V_keep_V int 64 regular {axi_s 0 volatile  { axi_in Keep } }  }
	{ axi_in_V_strb_V int 64 regular {axi_s 0 volatile  { axi_in Strb } }  }
	{ axi_in_V_last_V int 1 regular {axi_s 0 volatile  { axi_in Last } }  }
	{ axi_out_V_data_V int 512 regular {axi_s 1 volatile  { axi_out Data } }  }
	{ axi_out_V_keep_V int 64 regular {axi_s 1 volatile  { axi_out Keep } }  }
	{ axi_out_V_strb_V int 64 regular {axi_s 1 volatile  { axi_out Strb } }  }
	{ axi_out_V_last_V int 1 regular {axi_s 1 volatile  { axi_out Last } }  }
}
set hasAXIMCache 0
set l_AXIML2Cache [list]
set AXIMCacheInstDict [dict create]
set C_modelArgMapList {[ 
	{ "Name" : "img_width", "interface" : "axi_slave", "bundle":"control","type":"ap_none","bitwidth" : 32, "direction" : "READONLY", "offset" : {"in":16}, "offset_end" : {"in":23}} , 
 	{ "Name" : "in_channels", "interface" : "axi_slave", "bundle":"control","type":"ap_none","bitwidth" : 32, "direction" : "READONLY", "offset" : {"in":24}, "offset_end" : {"in":31}} , 
 	{ "Name" : "out_channels", "interface" : "axi_slave", "bundle":"control","type":"ap_none","bitwidth" : 32, "direction" : "READONLY", "offset" : {"in":32}, "offset_end" : {"in":39}} , 
 	{ "Name" : "quant_M", "interface" : "axi_slave", "bundle":"control","type":"ap_none","bitwidth" : 32, "direction" : "READONLY", "offset" : {"in":40}, "offset_end" : {"in":47}} , 
 	{ "Name" : "quant_n", "interface" : "axi_slave", "bundle":"control","type":"ap_none","bitwidth" : 32, "direction" : "READONLY", "offset" : {"in":48}, "offset_end" : {"in":55}} , 
 	{ "Name" : "isMaxpool", "interface" : "axi_slave", "bundle":"control","type":"ap_none","bitwidth" : 1, "direction" : "READONLY", "offset" : {"in":56}, "offset_end" : {"in":63}} , 
 	{ "Name" : "is_1x1", "interface" : "axi_slave", "bundle":"control","type":"ap_none","bitwidth" : 1, "direction" : "READONLY", "offset" : {"in":64}, "offset_end" : {"in":71}} , 
 	{ "Name" : "stride", "interface" : "axi_slave", "bundle":"control","type":"ap_none","bitwidth" : 32, "direction" : "READONLY", "offset" : {"in":72}, "offset_end" : {"in":79}} , 
 	{ "Name" : "axi_in_V_data_V", "interface" : "axis", "bitwidth" : 512, "direction" : "READONLY"} , 
 	{ "Name" : "axi_in_V_keep_V", "interface" : "axis", "bitwidth" : 64, "direction" : "READONLY"} , 
 	{ "Name" : "axi_in_V_strb_V", "interface" : "axis", "bitwidth" : 64, "direction" : "READONLY"} , 
 	{ "Name" : "axi_in_V_last_V", "interface" : "axis", "bitwidth" : 1, "direction" : "READONLY"} , 
 	{ "Name" : "axi_out_V_data_V", "interface" : "axis", "bitwidth" : 512, "direction" : "WRITEONLY"} , 
 	{ "Name" : "axi_out_V_keep_V", "interface" : "axis", "bitwidth" : 64, "direction" : "WRITEONLY"} , 
 	{ "Name" : "axi_out_V_strb_V", "interface" : "axis", "bitwidth" : 64, "direction" : "WRITEONLY"} , 
 	{ "Name" : "axi_out_V_last_V", "interface" : "axis", "bitwidth" : 1, "direction" : "WRITEONLY"} ]}
# RTL Port declarations: 
set portNum 32
set portList { 
	{ ap_clk sc_in sc_logic 1 clock -1 } 
	{ ap_rst_n sc_in sc_logic 1 reset -1 active_low_sync } 
	{ axi_in_TVALID sc_in sc_logic 1 invld 11 } 
	{ axi_out_TREADY sc_in sc_logic 1 outacc 15 } 
	{ axi_in_TDATA sc_in sc_lv 512 signal 8 } 
	{ axi_in_TREADY sc_out sc_logic 1 inacc 11 } 
	{ axi_in_TKEEP sc_in sc_lv 64 signal 9 } 
	{ axi_in_TSTRB sc_in sc_lv 64 signal 10 } 
	{ axi_in_TLAST sc_in sc_lv 1 signal 11 } 
	{ axi_out_TDATA sc_out sc_lv 512 signal 12 } 
	{ axi_out_TVALID sc_out sc_logic 1 outvld 15 } 
	{ axi_out_TKEEP sc_out sc_lv 64 signal 13 } 
	{ axi_out_TSTRB sc_out sc_lv 64 signal 14 } 
	{ axi_out_TLAST sc_out sc_lv 1 signal 15 } 
	{ s_axi_control_AWVALID sc_in sc_logic 1 signal -1 } 
	{ s_axi_control_AWREADY sc_out sc_logic 1 signal -1 } 
	{ s_axi_control_AWADDR sc_in sc_lv 7 signal -1 } 
	{ s_axi_control_WVALID sc_in sc_logic 1 signal -1 } 
	{ s_axi_control_WREADY sc_out sc_logic 1 signal -1 } 
	{ s_axi_control_WDATA sc_in sc_lv 32 signal -1 } 
	{ s_axi_control_WSTRB sc_in sc_lv 4 signal -1 } 
	{ s_axi_control_ARVALID sc_in sc_logic 1 signal -1 } 
	{ s_axi_control_ARREADY sc_out sc_logic 1 signal -1 } 
	{ s_axi_control_ARADDR sc_in sc_lv 7 signal -1 } 
	{ s_axi_control_RVALID sc_out sc_logic 1 signal -1 } 
	{ s_axi_control_RREADY sc_in sc_logic 1 signal -1 } 
	{ s_axi_control_RDATA sc_out sc_lv 32 signal -1 } 
	{ s_axi_control_RRESP sc_out sc_lv 2 signal -1 } 
	{ s_axi_control_BVALID sc_out sc_logic 1 signal -1 } 
	{ s_axi_control_BREADY sc_in sc_logic 1 signal -1 } 
	{ s_axi_control_BRESP sc_out sc_lv 2 signal -1 } 
	{ interrupt sc_out sc_logic 1 signal -1 } 
}
set NewPortList {[ 
	{ "name": "s_axi_control_AWADDR", "direction": "in", "datatype": "sc_lv", "bitwidth":7, "type": "signal", "bundle":{"name": "control", "role": "AWADDR" },"address":[{"name":"TinyYOLOHW","role":"start","value":"0","valid_bit":"0"},{"name":"TinyYOLOHW","role":"continue","value":"0","valid_bit":"4"},{"name":"TinyYOLOHW","role":"auto_start","value":"0","valid_bit":"7"},{"name":"img_width","role":"data","value":"16"},{"name":"in_channels","role":"data","value":"24"},{"name":"out_channels","role":"data","value":"32"},{"name":"quant_M","role":"data","value":"40"},{"name":"quant_n","role":"data","value":"48"},{"name":"isMaxpool","role":"data","value":"56"},{"name":"is_1x1","role":"data","value":"64"},{"name":"stride","role":"data","value":"72"}] },
	{ "name": "s_axi_control_AWVALID", "direction": "in", "datatype": "sc_logic", "bitwidth":1, "type": "signal", "bundle":{"name": "control", "role": "AWVALID" } },
	{ "name": "s_axi_control_AWREADY", "direction": "out", "datatype": "sc_logic", "bitwidth":1, "type": "signal", "bundle":{"name": "control", "role": "AWREADY" } },
	{ "name": "s_axi_control_WVALID", "direction": "in", "datatype": "sc_logic", "bitwidth":1, "type": "signal", "bundle":{"name": "control", "role": "WVALID" } },
	{ "name": "s_axi_control_WREADY", "direction": "out", "datatype": "sc_logic", "bitwidth":1, "type": "signal", "bundle":{"name": "control", "role": "WREADY" } },
	{ "name": "s_axi_control_WDATA", "direction": "in", "datatype": "sc_lv", "bitwidth":32, "type": "signal", "bundle":{"name": "control", "role": "WDATA" } },
	{ "name": "s_axi_control_WSTRB", "direction": "in", "datatype": "sc_lv", "bitwidth":4, "type": "signal", "bundle":{"name": "control", "role": "WSTRB" } },
	{ "name": "s_axi_control_ARADDR", "direction": "in", "datatype": "sc_lv", "bitwidth":7, "type": "signal", "bundle":{"name": "control", "role": "ARADDR" },"address":[{"name":"TinyYOLOHW","role":"start","value":"0","valid_bit":"0"},{"name":"TinyYOLOHW","role":"done","value":"0","valid_bit":"1"},{"name":"TinyYOLOHW","role":"idle","value":"0","valid_bit":"2"},{"name":"TinyYOLOHW","role":"ready","value":"0","valid_bit":"3"},{"name":"TinyYOLOHW","role":"auto_start","value":"0","valid_bit":"7"}] },
	{ "name": "s_axi_control_ARVALID", "direction": "in", "datatype": "sc_logic", "bitwidth":1, "type": "signal", "bundle":{"name": "control", "role": "ARVALID" } },
	{ "name": "s_axi_control_ARREADY", "direction": "out", "datatype": "sc_logic", "bitwidth":1, "type": "signal", "bundle":{"name": "control", "role": "ARREADY" } },
	{ "name": "s_axi_control_RVALID", "direction": "out", "datatype": "sc_logic", "bitwidth":1, "type": "signal", "bundle":{"name": "control", "role": "RVALID" } },
	{ "name": "s_axi_control_RREADY", "direction": "in", "datatype": "sc_logic", "bitwidth":1, "type": "signal", "bundle":{"name": "control", "role": "RREADY" } },
	{ "name": "s_axi_control_RDATA", "direction": "out", "datatype": "sc_lv", "bitwidth":32, "type": "signal", "bundle":{"name": "control", "role": "RDATA" } },
	{ "name": "s_axi_control_RRESP", "direction": "out", "datatype": "sc_lv", "bitwidth":2, "type": "signal", "bundle":{"name": "control", "role": "RRESP" } },
	{ "name": "s_axi_control_BVALID", "direction": "out", "datatype": "sc_logic", "bitwidth":1, "type": "signal", "bundle":{"name": "control", "role": "BVALID" } },
	{ "name": "s_axi_control_BREADY", "direction": "in", "datatype": "sc_logic", "bitwidth":1, "type": "signal", "bundle":{"name": "control", "role": "BREADY" } },
	{ "name": "s_axi_control_BRESP", "direction": "out", "datatype": "sc_lv", "bitwidth":2, "type": "signal", "bundle":{"name": "control", "role": "BRESP" } },
	{ "name": "interrupt", "direction": "out", "datatype": "sc_logic", "bitwidth":1, "type": "signal", "bundle":{"name": "control", "role": "interrupt" } }, 
 	{ "name": "ap_clk", "direction": "in", "datatype": "sc_logic", "bitwidth":1, "type": "clock", "bundle":{"name": "ap_clk", "role": "default" }} , 
 	{ "name": "ap_rst_n", "direction": "in", "datatype": "sc_logic", "bitwidth":1, "type": "reset", "bundle":{"name": "ap_rst_n", "role": "default" }} , 
 	{ "name": "axi_in_TVALID", "direction": "in", "datatype": "sc_logic", "bitwidth":1, "type": "invld", "bundle":{"name": "axi_in_V_last_V", "role": "default" }} , 
 	{ "name": "axi_out_TREADY", "direction": "in", "datatype": "sc_logic", "bitwidth":1, "type": "outacc", "bundle":{"name": "axi_out_V_last_V", "role": "default" }} , 
 	{ "name": "axi_in_TDATA", "direction": "in", "datatype": "sc_lv", "bitwidth":512, "type": "signal", "bundle":{"name": "axi_in_V_data_V", "role": "default" }} , 
 	{ "name": "axi_in_TREADY", "direction": "out", "datatype": "sc_logic", "bitwidth":1, "type": "inacc", "bundle":{"name": "axi_in_V_last_V", "role": "default" }} , 
 	{ "name": "axi_in_TKEEP", "direction": "in", "datatype": "sc_lv", "bitwidth":64, "type": "signal", "bundle":{"name": "axi_in_V_keep_V", "role": "default" }} , 
 	{ "name": "axi_in_TSTRB", "direction": "in", "datatype": "sc_lv", "bitwidth":64, "type": "signal", "bundle":{"name": "axi_in_V_strb_V", "role": "default" }} , 
 	{ "name": "axi_in_TLAST", "direction": "in", "datatype": "sc_lv", "bitwidth":1, "type": "signal", "bundle":{"name": "axi_in_V_last_V", "role": "default" }} , 
 	{ "name": "axi_out_TDATA", "direction": "out", "datatype": "sc_lv", "bitwidth":512, "type": "signal", "bundle":{"name": "axi_out_V_data_V", "role": "default" }} , 
 	{ "name": "axi_out_TVALID", "direction": "out", "datatype": "sc_logic", "bitwidth":1, "type": "outvld", "bundle":{"name": "axi_out_V_last_V", "role": "default" }} , 
 	{ "name": "axi_out_TKEEP", "direction": "out", "datatype": "sc_lv", "bitwidth":64, "type": "signal", "bundle":{"name": "axi_out_V_keep_V", "role": "default" }} , 
 	{ "name": "axi_out_TSTRB", "direction": "out", "datatype": "sc_lv", "bitwidth":64, "type": "signal", "bundle":{"name": "axi_out_V_strb_V", "role": "default" }} , 
 	{ "name": "axi_out_TLAST", "direction": "out", "datatype": "sc_lv", "bitwidth":1, "type": "signal", "bundle":{"name": "axi_out_V_last_V", "role": "default" }}  ]}

set ArgLastReadFirstWriteLatency {
	TinyYOLOHW {
		img_width {Type I LastRead -1 FirstWrite -1}
		in_channels {Type I LastRead -1 FirstWrite -1}
		out_channels {Type I LastRead -1 FirstWrite -1}
		quant_M {Type I LastRead -1 FirstWrite -1}
		quant_n {Type I LastRead -1 FirstWrite -1}
		isMaxpool {Type I LastRead -1 FirstWrite -1}
		is_1x1 {Type I LastRead -1 FirstWrite -1}
		stride {Type I LastRead -1 FirstWrite -1}
		axi_in_V_data_V {Type I LastRead 0 FirstWrite -1}
		axi_in_V_keep_V {Type I LastRead 0 FirstWrite -1}
		axi_in_V_strb_V {Type I LastRead 0 FirstWrite -1}
		axi_in_V_last_V {Type I LastRead 0 FirstWrite -1}
		axi_out_V_data_V {Type O LastRead -1 FirstWrite 0}
		axi_out_V_keep_V {Type O LastRead -1 FirstWrite 0}
		axi_out_V_strb_V {Type O LastRead -1 FirstWrite 0}
		axi_out_V_last_V {Type O LastRead -1 FirstWrite 0}}}

set hasDtUnsupportedChannel 0

set PerformanceInfo {[
	{"Name" : "Latency", "Min" : "-1", "Max" : "-1"}
	, {"Name" : "Interval", "Min" : "0", "Max" : "0"}
]}

set PipelineEnableSignalInfo {[
	{"Pipeline" : "0", "EnableSignal" : "ap_enable_pp0"}
]}

set Spec2ImplPortList { 
	axi_in_V_data_V { axis {  { axi_in_TDATA in_data 0 512 } } }
	axi_in_V_keep_V { axis {  { axi_in_TKEEP in_data 0 64 } } }
	axi_in_V_strb_V { axis {  { axi_in_TSTRB in_data 0 64 } } }
	axi_in_V_last_V { axis {  { axi_in_TVALID in_vld 0 1 }  { axi_in_TREADY in_acc 1 1 }  { axi_in_TLAST in_data 0 1 } } }
	axi_out_V_data_V { axis {  { axi_out_TDATA out_data 1 512 } } }
	axi_out_V_keep_V { axis {  { axi_out_TKEEP out_data 1 64 } } }
	axi_out_V_strb_V { axis {  { axi_out_TSTRB out_data 1 64 } } }
	axi_out_V_last_V { axis {  { axi_out_TREADY out_acc 0 1 }  { axi_out_TVALID out_vld 1 1 }  { axi_out_TLAST out_data 1 1 } } }
}

set maxi_interface_dict [dict create]

# RTL port scheduling information:
set fifoSchedulingInfoList { 
}

# RTL bus port read request latency information:
set busReadReqLatencyList { 
}

# RTL bus port write response latency information:
set busWriteResLatencyList { 
}

# RTL array port load latency information:
set memoryLoadLatencyList { 
}
