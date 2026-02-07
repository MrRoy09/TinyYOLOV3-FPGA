-- Copyright 1986-2022 Xilinx, Inc. All Rights Reserved.
-- Copyright 2022-2025 Advanced Micro Devices, Inc. All Rights Reserved.
-- --------------------------------------------------------------------------------
-- Tool Version: Vivado v.2025.1 (lin64) Build 6140274 Wed May 21 22:58:25 MDT 2025
-- Date        : Sat Feb  7 23:50:35 2026
-- Host        : ubuntu-laptop-hp running 64-bit Ubuntu 24.04.3 LTS
-- Command     : write_vhdl -force -mode synth_stub
--               /media/ubuntu/T7/projects/arm-bharat/Tiny_YOLO_HW/Tiny_YOLO_HW.gen/sources_1/ip/TinyYOLOHW/TinyYOLOHW_stub.vhdl
-- Design      : TinyYOLOHW
-- Purpose     : Stub declaration of top-level module interface
-- Device      : xck26-sfvc784-2LV-c
-- --------------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

entity TinyYOLOHW is
  Port ( 
    ap_clk : in STD_LOGIC
  );

  attribute CHECK_LICENSE_TYPE : string;
  attribute CHECK_LICENSE_TYPE of TinyYOLOHW : entity is "TinyYOLOHW,rtl_kernel_wizard_v1_0_18_dummy,{}";
  attribute CORE_GENERATION_INFO : string;
  attribute CORE_GENERATION_INFO of TinyYOLOHW : entity is "TinyYOLOHW,rtl_kernel_wizard_v1_0_18_dummy,{x_ipProduct=Vivado 2025.1,x_ipVendor=xilinx.com,x_ipLibrary=ip,x_ipName=rtl_kernel_wizard,x_ipVersion=1.0,x_ipCoreRevision=18,x_ipLanguage=VERILOG,x_ipSimLanguage=MIXED}";
  attribute DowngradeIPIdentifiedWarnings : string;
  attribute DowngradeIPIdentifiedWarnings of TinyYOLOHW : entity is "yes";
end TinyYOLOHW;

architecture stub of TinyYOLOHW is
  attribute syn_black_box : boolean;
  attribute black_box_pad_pin : string;
  attribute syn_black_box of stub : architecture is true;
  attribute black_box_pad_pin of stub : architecture is "ap_clk";
  attribute X_CORE_INFO : string;
  attribute X_CORE_INFO of stub : architecture is "rtl_kernel_wizard_v1_0_18_dummy,Vivado 2025.1";
begin
end;
