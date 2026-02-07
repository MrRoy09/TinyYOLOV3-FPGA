// Copyright 1986-2022 Xilinx, Inc. All Rights Reserved.
// Copyright 2022-2025 Advanced Micro Devices, Inc. All Rights Reserved.
// --------------------------------------------------------------------------------
// Tool Version: Vivado v.2025.1 (lin64) Build 6140274 Wed May 21 22:58:25 MDT 2025
// Date        : Sat Feb  7 23:50:35 2026
// Host        : ubuntu-laptop-hp running 64-bit Ubuntu 24.04.3 LTS
// Command     : write_verilog -force -mode synth_stub
//               /media/ubuntu/T7/projects/arm-bharat/Tiny_YOLO_HW/Tiny_YOLO_HW.gen/sources_1/ip/TinyYOLOHW/TinyYOLOHW_stub.v
// Design      : TinyYOLOHW
// Purpose     : Stub declaration of top-level module interface
// Device      : xck26-sfvc784-2LV-c
// --------------------------------------------------------------------------------

// This empty module with port declaration file causes synthesis tools to infer a black box for IP.
// The synthesis directives are for Synopsys Synplify support to prevent IO buffer insertion.
// Please paste the declaration into a Verilog source file or add the file as an additional source.
(* CHECK_LICENSE_TYPE = "TinyYOLOHW,rtl_kernel_wizard_v1_0_18_dummy,{}" *) (* CORE_GENERATION_INFO = "TinyYOLOHW,rtl_kernel_wizard_v1_0_18_dummy,{x_ipProduct=Vivado 2025.1,x_ipVendor=xilinx.com,x_ipLibrary=ip,x_ipName=rtl_kernel_wizard,x_ipVersion=1.0,x_ipCoreRevision=18,x_ipLanguage=VERILOG,x_ipSimLanguage=MIXED}" *) (* DowngradeIPIdentifiedWarnings = "yes" *) 
(* X_CORE_INFO = "rtl_kernel_wizard_v1_0_18_dummy,Vivado 2025.1" *) 
module TinyYOLOHW(ap_clk)
/* synthesis syn_black_box black_box_pad_pin="ap_clk" */;
  input ap_clk;
endmodule
