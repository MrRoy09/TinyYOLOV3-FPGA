// Copyright 1986-2022 Xilinx, Inc. All Rights Reserved.
// Copyright 2022-2025 Advanced Micro Devices, Inc. All Rights Reserved.
// --------------------------------------------------------------------------------
// Tool Version: Vivado v.2025.1 (lin64) Build 6140274 Wed May 21 22:58:25 MDT 2025
// Date        : Fri Feb  6 23:29:53 2026
// Host        : ubuntu-laptop-hp running 64-bit Ubuntu 24.04.3 LTS
// Command     : write_verilog -force -mode funcsim -rename_top decalper_eb_ot_sdeen_pot_pi_dehcac_xnilix -prefix
//               decalper_eb_ot_sdeen_pot_pi_dehcac_xnilix_ c_accum_0_sim_netlist.v
// Design      : c_accum_0
// Purpose     : This verilog netlist is a functional simulation representation of the design and should not be modified
//               or synthesized. This netlist cannot be used for SDF annotated simulation.
// Device      : xck26-sfvc784-2LV-c
// --------------------------------------------------------------------------------
`timescale 1 ps / 1 ps

(* CHECK_LICENSE_TYPE = "c_accum_0,c_accum_v12_0_20,{}" *) (* downgradeipidentifiedwarnings = "yes" *) (* x_core_info = "c_accum_v12_0_20,Vivado 2025.1" *) 
(* NotValidForBitStream *)
module decalper_eb_ot_sdeen_pot_pi_dehcac_xnilix
   (B,
    CLK,
    BYPASS,
    Q);
  (* x_interface_info = "xilinx.com:signal:data:1.0 b_intf DATA" *) (* x_interface_mode = "slave b_intf" *) (* x_interface_parameter = "XIL_INTERFACENAME b_intf, LAYERED_METADATA undef" *) input [15:0]B;
  (* x_interface_info = "xilinx.com:signal:clock:1.0 clk_intf CLK" *) (* x_interface_mode = "slave clk_intf" *) (* x_interface_parameter = "XIL_INTERFACENAME clk_intf, ASSOCIATED_BUSIF q_intf:sinit_intf:sset_intf:bypass_intf:c_in_intf:add_intf:b_intf, ASSOCIATED_RESET SCLR, ASSOCIATED_CLKEN CE, FREQ_HZ 100000000, FREQ_TOLERANCE_HZ 0, PHASE 0.0, INSERT_VIP 0" *) input CLK;
  (* x_interface_info = "xilinx.com:signal:data:1.0 bypass_intf DATA" *) (* x_interface_mode = "slave bypass_intf" *) (* x_interface_parameter = "XIL_INTERFACENAME bypass_intf, LAYERED_METADATA undef" *) input BYPASS;
  (* x_interface_info = "xilinx.com:signal:data:1.0 q_intf DATA" *) (* x_interface_mode = "master q_intf" *) (* x_interface_parameter = "XIL_INTERFACENAME q_intf, LAYERED_METADATA undef" *) output [15:0]Q;

  wire [15:0]B;
  wire BYPASS;
  wire CLK;
  wire [15:0]Q;

  (* C_ADD_MODE = "0" *) 
  (* C_AINIT_VAL = "0" *) 
  (* C_BYPASS_LOW = "0" *) 
  (* C_B_TYPE = "0" *) 
  (* C_B_WIDTH = "16" *) 
  (* C_CE_OVERRIDES_SCLR = "0" *) 
  (* C_HAS_BYPASS = "1" *) 
  (* C_HAS_CE = "0" *) 
  (* C_HAS_C_IN = "0" *) 
  (* C_HAS_SCLR = "0" *) 
  (* C_HAS_SINIT = "0" *) 
  (* C_HAS_SSET = "0" *) 
  (* C_IMPLEMENTATION = "1" *) 
  (* C_LATENCY = "1" *) 
  (* C_OUT_WIDTH = "16" *) 
  (* C_SCALE = "0" *) 
  (* C_SCLR_OVERRIDES_SSET = "1" *) 
  (* C_SINIT_VAL = "0" *) 
  (* C_VERBOSITY = "0" *) 
  (* C_XDEVICEFAMILY = "zynquplus" *) 
  (* downgradeipidentifiedwarnings = "yes" *) 
  (* is_du_within_envelope = "true" *) 
  decalper_eb_ot_sdeen_pot_pi_dehcac_xnilix_c_accum_v12_0_20 U0
       (.ADD(1'b1),
        .B(B),
        .BYPASS(BYPASS),
        .CE(1'b1),
        .CLK(CLK),
        .C_IN(1'b0),
        .Q(Q),
        .SCLR(1'b0),
        .SINIT(1'b0),
        .SSET(1'b0));
endmodule
`pragma protect begin_protected
`pragma protect version = 1
`pragma protect encrypt_agent = "XILINX"
`pragma protect encrypt_agent_info = "Xilinx Encryption Tool 2025.1"
`pragma protect key_keyowner="Synopsys", key_keyname="SNPS-VCS-RSA-2", key_method="rsa"
`pragma protect encoding = (enctype="BASE64", line_length=76, bytes=128)
`pragma protect key_block
qJH2Z0799kuAAqdyo9nZytkX+zBhc42v+hS7gxZ4+pzhg0B8Sfj4TGUC1143JFB/noxGdXXq+9UI
+BTXZIv2653mMRkdFWpX7XVh0Q55MS/+u0O3lIYfjbtunJf4EMaXQhXFmb7PqoUNXchOwi7MmBm4
rmZE11vM9fs2qM/RLv4=

`pragma protect key_keyowner="Aldec", key_keyname="ALDEC15_001", key_method="rsa"
`pragma protect encoding = (enctype="BASE64", line_length=76, bytes=256)
`pragma protect key_block
utazTEatWVSFsON0jCrKrt8GHwQzuaRww99wQA8ZFL1AY+hyqiQM7QMVgIz3iuLSHhDi4iGvujSy
9LvQtQSjXeK1Dgi/oHSvOYJJhjvTPYqlNVT+YBEr2QboLv9D1bjuOkeGQtaezH0J9TA34xckPXWU
mZu9rJjDZiEO6PKHZJwYNSnzSgtC8Xq2xyLEGap5rxECq0PzGoM9pj2F0an1OJ40A2C0UbYMNIQf
Q4RBxP9nw/x7WILeQJcx5UxfJYkvVaK9NPiylDh28Dk8PYAJwSZVoR6FLzUSAgVCIZCKDRxMAEuj
NLuaR4vaZAU4+a/vmQ/uU4KS7+glYTYEqW1hqw==

`pragma protect key_keyowner="Mentor Graphics Corporation", key_keyname="MGC-VELOCE-RSA", key_method="rsa"
`pragma protect encoding = (enctype="BASE64", line_length=76, bytes=128)
`pragma protect key_block
dAn6U0wteATb91U92xu7wp7xSJRu+FMBeGO9Z/eKrZ4ri96zhaCgsn/KuYQkjMAZu1i4ccUrp3aC
bMcVnOMfDn6eW3kHSN7bYNWFUK5yW/VS0SeI2WPS24ZbUfkWSXA1WS6x9qR1JvISH9RTWvpwGNwS
2RSuX8mIhYdkkk58jwQ=

`pragma protect key_keyowner="Mentor Graphics Corporation", key_keyname="MGC-VERIF-SIM-RSA-2", key_method="rsa"
`pragma protect encoding = (enctype="BASE64", line_length=76, bytes=256)
`pragma protect key_block
nlHqyagwapYicKCSL6To1R48e7XkWzCb767t1beVTZFvyNaGqWtdibaVjwZsTDtkdxlq/SOLUk3F
KbE5s3ch2gI/+SSj5QE2ckgHoBCXZfP+sSRADs89SxAGiGefzrYEOBI6mMjFy6J7pCy/yHmwLC7/
YrqbxH670odUOdtOC56Ql0ir6apPV3ySUbwGBGSgvIdAiuwdNKonkW2A6aioUxz9bV3kyNMegNRU
HbAlFOnfs23DqED47rNmkewt0FE+98QIDTBXEEkTD4/Gx0UY20kRmSl9kwn47XOldtu2vUQfgpBJ
/PQodnWfRStsh8xLhXTS7qs+uwGdMzYNLcthUQ==

`pragma protect key_keyowner="Real Intent", key_keyname="RI-RSA-KEY-1", key_method="rsa"
`pragma protect encoding = (enctype="BASE64", line_length=76, bytes=256)
`pragma protect key_block
Q2cw6pmPs3bNevXq4m41+bMjHMd84ziaY5fXyUSth9mZK7LeVNuP3T4IbKMqELu/xey26Fo2i1/t
VYICL6lojT1w7ivnsHg7bBIVpCXI02vpW65ONw5EMullM8CKnu6zBOxL3NjEupKj7N580T1oID03
cimTa5ccTDel9Yxvqm3+wBzo2RDs3of+1n+f/p30oHkwPPA2t7mhzApbNAtztax8gBUjQG6NCV0n
BrReu69SB/IPim/YAsnL3awj3hOpjrLsDYE5lkoZe5bpdtAmKOUrCS9TZoNsptIPurSjiK72kjGX
WjmUYpGdB87bLnqb5oM9WDHthaCHryW1hdJXag==

`pragma protect key_keyowner="Xilinx", key_keyname="xilinxt_2025.1-2029.x", key_method="rsa"
`pragma protect encoding = (enctype="BASE64", line_length=76, bytes=256)
`pragma protect key_block
CMrbdswO9h3udUI4EzGXPEyT+75CcBwshoNqB5kZga3iJur14srcLGa/RDAV+Zym2OyqdvdTdcr5
GuFxFRek5FCsQm7CFqk9Fd8KdtvF0cIensBG4soi+8gZXsJBIoRWxWrupwYkgbLnNAwtGLQe4r4N
/DEaWmCLhEAyprbCr1rF2HLvKAe7xGEZv4LUiz1BtLW9bx4lBJlUi4p07S1f1M81VlpmEzB/pSlG
O3T0V9NyiEw7n3obA7IGUIADJz78+OnQK3oD3rpkaN6o2omjwlI4ktvpzk6zBpaABZtnufDc7uFj
IfAtwtBgMDt/Uwuam3pkjaTb471V/zpZUiVR2g==

`pragma protect key_keyowner="Metrics Technologies Inc.", key_keyname="DSim", key_method="rsa"
`pragma protect encoding = (enctype="BASE64", line_length=76, bytes=256)
`pragma protect key_block
QeBmeoEvsssgZwlIb9giohinE2USjblVgG4EnuSSoo4QEoKnAiEa2LvlR5bawut/qJGGkBeT+v6a
4gSTIbTPKDzgj9wvZICmoe525mQQrcvhJeJT7dvqBLpwdBHfeEBv/ASCCidtmDt3GACkKkjtvCXZ
LkyjhHLKdPsgBkIk3dm5iKEYgcb565ZE2EEKifNHApjB7HgTxe8Ee2t/VjU/zG4o3dP7OB8V4Ggm
Uwtyw5+SeujHvpRas19QRpi0oiY1ir6iBfFM/L5sThsUBXPPVLKSGXY2frltnOpohc2MxvV+gb3M
1ne0v4MdYAMCA7WRPazQH1Z+8Xj3zrOaylQsTQ==

`pragma protect key_keyowner="Atrenta", key_keyname="ATR-SG-RSA-1", key_method="rsa"
`pragma protect encoding = (enctype="BASE64", line_length=76, bytes=384)
`pragma protect key_block
XQjlpOg/SoPFYHbqfBNYhx0DZtJeVTQcfDBqZigEAUEamC/xRY57NZ+HcKH//lpADK8Y4bjcGE1F
BeQXum00ATly67nGoDFZ1dGyBSh90CjByVLTreEWgYFeN61BhvuoFGjdtVSKYEouVO7UNXKTD+gX
WvKKw4HzHi5TlmDRPSRgFfXDUK0DUUY0n59IDHk2QG9qccsgtbWOg9+Ju4gdlK37MWSB6kgDVwLO
du00UwlTXeM6L06OwQ/hZw3O4PX5vhTNzJkQU+ctBulkVHsqKIHynuJM+m6PWGnM0IpJSUJk5xqU
zy/0KYKBKPuupC9LopEyMkvSaHu+jXF/dqfXOruAtaRTy6wGp1tW+MLhsFg5P7gXGNTuZFrjcJcp
SG4uz7+GErFrW1XvdfdE4KU4At8MOyJTIxnEckNiNw79zD6VXLyI/FLwPoXmzW7uB9aTTubIaHyL
/naLOaSg7/NRPbnoZxWbiQw+jivdDEqmGUmXmpXHqYqnS7kJRUaXnwAG

`pragma protect key_keyowner="Cadence Design Systems.", key_keyname="CDS_RSA_KEY_VER_1", key_method="rsa"
`pragma protect encoding = (enctype="BASE64", line_length=76, bytes=256)
`pragma protect key_block
l4nhPdFzeEuwDYDP1DNUEkCfqBW9S/njIChcbuhzoBq1nsZXYGs1It2HLE51fTAYzGl3RNNwMGaT
vdaJbCrZmBLg6OXIyanFNizPcTnQLr3n0I9t8atVvhBs6he4FXs5WLip9SIKhhUoS40A1UqBKQPT
yjDkLlZQNC2uGAJQHpxOUfMLNq9TDCsAzs7up1IfvdLXMwaQ8TglYcLhD3Xu/Eps862F6RBAfyha
s5qysTIavY3HhYV5/T4INzqS8Eb9wtSYXK4fMI2dcXYJkiUDkiXMwtMzEKd7oYn39AzEbUpWL7xN
UcyvLSEoJSlCYJmpMHABcBCn3FkvOW427bCWFQ==

`pragma protect data_method = "AES128-CBC"
`pragma protect encoding = (enctype = "BASE64", line_length = 76, bytes = 2048)
`pragma protect data_block
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
`pragma protect end_protected
`pragma protect begin_protected
`pragma protect version = 1
`pragma protect encrypt_agent = "XILINX"
`pragma protect encrypt_agent_info = "Xilinx Encryption Tool 2025.1"
`pragma protect key_keyowner="Synopsys", key_keyname="SNPS-VCS-RSA-2", key_method="rsa"
`pragma protect encoding = (enctype="BASE64", line_length=76, bytes=128)
`pragma protect key_block
qJH2Z0799kuAAqdyo9nZytkX+zBhc42v+hS7gxZ4+pzhg0B8Sfj4TGUC1143JFB/noxGdXXq+9UI
+BTXZIv2653mMRkdFWpX7XVh0Q55MS/+u0O3lIYfjbtunJf4EMaXQhXFmb7PqoUNXchOwi7MmBm4
rmZE11vM9fs2qM/RLv4=

`pragma protect key_keyowner="Aldec", key_keyname="ALDEC15_001", key_method="rsa"
`pragma protect encoding = (enctype="BASE64", line_length=76, bytes=256)
`pragma protect key_block
utazTEatWVSFsON0jCrKrt8GHwQzuaRww99wQA8ZFL1AY+hyqiQM7QMVgIz3iuLSHhDi4iGvujSy
9LvQtQSjXeK1Dgi/oHSvOYJJhjvTPYqlNVT+YBEr2QboLv9D1bjuOkeGQtaezH0J9TA34xckPXWU
mZu9rJjDZiEO6PKHZJwYNSnzSgtC8Xq2xyLEGap5rxECq0PzGoM9pj2F0an1OJ40A2C0UbYMNIQf
Q4RBxP9nw/x7WILeQJcx5UxfJYkvVaK9NPiylDh28Dk8PYAJwSZVoR6FLzUSAgVCIZCKDRxMAEuj
NLuaR4vaZAU4+a/vmQ/uU4KS7+glYTYEqW1hqw==

`pragma protect key_keyowner="Mentor Graphics Corporation", key_keyname="MGC-VELOCE-RSA", key_method="rsa"
`pragma protect encoding = (enctype="BASE64", line_length=76, bytes=128)
`pragma protect key_block
dAn6U0wteATb91U92xu7wp7xSJRu+FMBeGO9Z/eKrZ4ri96zhaCgsn/KuYQkjMAZu1i4ccUrp3aC
bMcVnOMfDn6eW3kHSN7bYNWFUK5yW/VS0SeI2WPS24ZbUfkWSXA1WS6x9qR1JvISH9RTWvpwGNwS
2RSuX8mIhYdkkk58jwQ=

`pragma protect key_keyowner="Mentor Graphics Corporation", key_keyname="MGC-VERIF-SIM-RSA-2", key_method="rsa"
`pragma protect encoding = (enctype="BASE64", line_length=76, bytes=256)
`pragma protect key_block
nlHqyagwapYicKCSL6To1R48e7XkWzCb767t1beVTZFvyNaGqWtdibaVjwZsTDtkdxlq/SOLUk3F
KbE5s3ch2gI/+SSj5QE2ckgHoBCXZfP+sSRADs89SxAGiGefzrYEOBI6mMjFy6J7pCy/yHmwLC7/
YrqbxH670odUOdtOC56Ql0ir6apPV3ySUbwGBGSgvIdAiuwdNKonkW2A6aioUxz9bV3kyNMegNRU
HbAlFOnfs23DqED47rNmkewt0FE+98QIDTBXEEkTD4/Gx0UY20kRmSl9kwn47XOldtu2vUQfgpBJ
/PQodnWfRStsh8xLhXTS7qs+uwGdMzYNLcthUQ==

`pragma protect key_keyowner="Real Intent", key_keyname="RI-RSA-KEY-1", key_method="rsa"
`pragma protect encoding = (enctype="BASE64", line_length=76, bytes=256)
`pragma protect key_block
Q2cw6pmPs3bNevXq4m41+bMjHMd84ziaY5fXyUSth9mZK7LeVNuP3T4IbKMqELu/xey26Fo2i1/t
VYICL6lojT1w7ivnsHg7bBIVpCXI02vpW65ONw5EMullM8CKnu6zBOxL3NjEupKj7N580T1oID03
cimTa5ccTDel9Yxvqm3+wBzo2RDs3of+1n+f/p30oHkwPPA2t7mhzApbNAtztax8gBUjQG6NCV0n
BrReu69SB/IPim/YAsnL3awj3hOpjrLsDYE5lkoZe5bpdtAmKOUrCS9TZoNsptIPurSjiK72kjGX
WjmUYpGdB87bLnqb5oM9WDHthaCHryW1hdJXag==

`pragma protect key_keyowner="Xilinx", key_keyname="xilinxt_2025.1-2029.x", key_method="rsa"
`pragma protect encoding = (enctype="BASE64", line_length=76, bytes=256)
`pragma protect key_block
CMrbdswO9h3udUI4EzGXPEyT+75CcBwshoNqB5kZga3iJur14srcLGa/RDAV+Zym2OyqdvdTdcr5
GuFxFRek5FCsQm7CFqk9Fd8KdtvF0cIensBG4soi+8gZXsJBIoRWxWrupwYkgbLnNAwtGLQe4r4N
/DEaWmCLhEAyprbCr1rF2HLvKAe7xGEZv4LUiz1BtLW9bx4lBJlUi4p07S1f1M81VlpmEzB/pSlG
O3T0V9NyiEw7n3obA7IGUIADJz78+OnQK3oD3rpkaN6o2omjwlI4ktvpzk6zBpaABZtnufDc7uFj
IfAtwtBgMDt/Uwuam3pkjaTb471V/zpZUiVR2g==

`pragma protect key_keyowner="Metrics Technologies Inc.", key_keyname="DSim", key_method="rsa"
`pragma protect encoding = (enctype="BASE64", line_length=76, bytes=256)
`pragma protect key_block
QeBmeoEvsssgZwlIb9giohinE2USjblVgG4EnuSSoo4QEoKnAiEa2LvlR5bawut/qJGGkBeT+v6a
4gSTIbTPKDzgj9wvZICmoe525mQQrcvhJeJT7dvqBLpwdBHfeEBv/ASCCidtmDt3GACkKkjtvCXZ
LkyjhHLKdPsgBkIk3dm5iKEYgcb565ZE2EEKifNHApjB7HgTxe8Ee2t/VjU/zG4o3dP7OB8V4Ggm
Uwtyw5+SeujHvpRas19QRpi0oiY1ir6iBfFM/L5sThsUBXPPVLKSGXY2frltnOpohc2MxvV+gb3M
1ne0v4MdYAMCA7WRPazQH1Z+8Xj3zrOaylQsTQ==

`pragma protect key_keyowner="Atrenta", key_keyname="ATR-SG-RSA-1", key_method="rsa"
`pragma protect encoding = (enctype="BASE64", line_length=76, bytes=384)
`pragma protect key_block
XQjlpOg/SoPFYHbqfBNYhx0DZtJeVTQcfDBqZigEAUEamC/xRY57NZ+HcKH//lpADK8Y4bjcGE1F
BeQXum00ATly67nGoDFZ1dGyBSh90CjByVLTreEWgYFeN61BhvuoFGjdtVSKYEouVO7UNXKTD+gX
WvKKw4HzHi5TlmDRPSRgFfXDUK0DUUY0n59IDHk2QG9qccsgtbWOg9+Ju4gdlK37MWSB6kgDVwLO
du00UwlTXeM6L06OwQ/hZw3O4PX5vhTNzJkQU+ctBulkVHsqKIHynuJM+m6PWGnM0IpJSUJk5xqU
zy/0KYKBKPuupC9LopEyMkvSaHu+jXF/dqfXOruAtaRTy6wGp1tW+MLhsFg5P7gXGNTuZFrjcJcp
SG4uz7+GErFrW1XvdfdE4KU4At8MOyJTIxnEckNiNw79zD6VXLyI/FLwPoXmzW7uB9aTTubIaHyL
/naLOaSg7/NRPbnoZxWbiQw+jivdDEqmGUmXmpXHqYqnS7kJRUaXnwAG

`pragma protect key_keyowner="Cadence Design Systems.", key_keyname="CDS_RSA_KEY_VER_1", key_method="rsa"
`pragma protect encoding = (enctype="BASE64", line_length=76, bytes=256)
`pragma protect key_block
l4nhPdFzeEuwDYDP1DNUEkCfqBW9S/njIChcbuhzoBq1nsZXYGs1It2HLE51fTAYzGl3RNNwMGaT
vdaJbCrZmBLg6OXIyanFNizPcTnQLr3n0I9t8atVvhBs6he4FXs5WLip9SIKhhUoS40A1UqBKQPT
yjDkLlZQNC2uGAJQHpxOUfMLNq9TDCsAzs7up1IfvdLXMwaQ8TglYcLhD3Xu/Eps862F6RBAfyha
s5qysTIavY3HhYV5/T4INzqS8Eb9wtSYXK4fMI2dcXYJkiUDkiXMwtMzEKd7oYn39AzEbUpWL7xN
UcyvLSEoJSlCYJmpMHABcBCn3FkvOW427bCWFQ==

`pragma protect key_keyowner="Mentor Graphics Corporation", key_keyname="MGC-PREC-RSA", key_method="rsa"
`pragma protect encoding = (enctype="BASE64", line_length=76, bytes=256)
`pragma protect key_block
JtbjOi/DIoFQBGtEsgQnu7Gx2wpijyhnl9DJUf/xNq1qfk9woBl03hMJzCutG+vn+WvLqAdgyURC
fhgRf+zC+8ewBfYt3rS+iNjHK8I4SLcfOOpaiYRz6T/mKOUgF+qlg7HFi1ZmHf5Df0ZMZSK0n0Nb
SMTPcy3vNx3OONE0G+JyhsRkze32Caj+X6gPWgBXXwG5JoNYmvFWvp5zkDF5/FmOiDVtoCdwwdTp
95XYsOEenRZ0b3/H4PF8y7gA7Xk34uj5lk4yMkahqyqIHxj4DXyQbWi5kwbbH4jSg3G0wOskgudS
gvaFNfEF8xnWmtfYGcXfRUiT3Cf5CF5fH7gc7w==

`pragma protect key_keyowner="Synplicity", key_keyname="SYNP15_1", key_method="rsa"
`pragma protect encoding = (enctype="BASE64", line_length=76, bytes=256)
`pragma protect key_block
Pqf8yRWx493aUm93afx+Qr/er8Qqhq6yjdHbU6Y0KEvXsAiut6LiLIo0w0AZ6/4r3BTmpMsOUNtK
385IelBJPrHfptdoyyB1haqDeD6ZM0NsqR5YjO5LsmZEOUNA5qIZmW961DQgofMPU6q0QMDWReBF
ofyZulhpp6bgU/csLKZPkDzMh277emWAFE4dGVLTa3hoLeAd8GNSaBzmtVKeHj/Wq4adBmqmH/VM
OH6jSZRgWH2sPFkBB3a9cMVjc1+xsf1LlCo7sLprWt05xqHM4b7v0XC/JEaYjgLwwQOjcKEpKDpb
asoUnoXJUBVuYG0aZOaIeajwxKvpOgliZl11Ug==

`pragma protect data_method = "AES128-CBC"
`pragma protect encoding = (enctype = "BASE64", line_length = 76, bytes = 1696)
`pragma protect data_block
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
`pragma protect end_protected
`pragma protect begin_protected
`pragma protect version = 1
`pragma protect encrypt_agent = "XILINX"
`pragma protect encrypt_agent_info = "Xilinx Encryption Tool 2025.1"
`pragma protect key_keyowner="Synopsys", key_keyname="SNPS-VCS-RSA-2", key_method="rsa"
`pragma protect encoding = (enctype="BASE64", line_length=76, bytes=128)
`pragma protect key_block
VTOlYQtH4VCjR3Kao0Yp1sfKixsJQ/U6ENIt8cDRA/SC1s13qaZL21XX7lc1zPxU+gOHZAFgrQx4
xtBHsWBZPgf7jOfU/XvgS+qWV0bRTzj2ltD9e7LeeP1F68kY9cPwMYJ8OMbRNzv/gdQk27gYr5Kf
bPpdQQXxxi5sI3WaJGU=

`pragma protect key_keyowner="Aldec", key_keyname="ALDEC15_001", key_method="rsa"
`pragma protect encoding = (enctype="BASE64", line_length=76, bytes=256)
`pragma protect key_block
GzYbkwqhFa1kQ1aCgfpFCorGKs2cpbxDmMi0HN2Qa+pUMntdx8A7ovD56dCMmGHLi0ulUbuhJUZx
63r/TXg18wlnC6nSK8vPHebNi5PgZNRMkMxMY0oQRAhh8kmCPdzT0TzvlR62rgzynrVEZW+M/qDi
NvjHL6CLAPD5mF2jJHhTsaPLwIKDgXDFMBISlG7+M4UO+BmRcN5qAgeFezLmxF45fu9ButsBxQH/
qGkN9d2c4dqO+iUVVVElLCAbVJo+Nk1Gxd6gYYwhCFyUUZVdVxrRx/+TvsNGpkVPMWioiAFmv5fF
fgfLhGhCeTGIn1URpbKV7nnDDxjwMHtobPj+Ag==

`pragma protect key_keyowner="Mentor Graphics Corporation", key_keyname="MGC-VELOCE-RSA", key_method="rsa"
`pragma protect encoding = (enctype="BASE64", line_length=76, bytes=128)
`pragma protect key_block
Y+wtnM8VYeb8gi/k154YmkOlSb95GrApH7GgYRJlCv7+P4G5ceGtz5D7NiG3NITH29OGKr2Sozpr
y6K2sEul1BfB6Ujj/vGloRVAuuD9ntTQ3nr5jvmo2CEu6KG1GP4tz9DE9WwSPUNOQty/WnrHuBjj
3sRbV3HurkV/OsyQsHo=

`pragma protect key_keyowner="Mentor Graphics Corporation", key_keyname="MGC-VERIF-SIM-RSA-2", key_method="rsa"
`pragma protect encoding = (enctype="BASE64", line_length=76, bytes=256)
`pragma protect key_block
UyU6iYOqLEdOo/DwGtsJQZoJ85VNrYNBwpyFapSfbF0ziT4pzX1BF9NTbFpdn9bRbdLB8bIyl+P9
hwo+XDS17lNcY33SMFw/6muJcbt7DFBlcq74qlCnNSn7TYO9tAbGG2VlqOrstPzvlvEB9qFPRKFK
iyZgq7XO8mV0F1ZZx25F17SqbPU6OnmqjrKueSP0fX8rLZR0/yQKL/ZoQQMMTzhlYdPUBs8NoU4L
dYrcbcsi/e06NavZ46WLvhRBDklmVK6dHhe7Mcavw+HSheNtbUC+3dDCZUHvZnjk9s0iBvz+LzqP
i8MhER2hs/NGbRyJMicTkrGHGpmgtdtx4MOLNQ==

`pragma protect key_keyowner="Real Intent", key_keyname="RI-RSA-KEY-1", key_method="rsa"
`pragma protect encoding = (enctype="BASE64", line_length=76, bytes=256)
`pragma protect key_block
A2V0LadQCOGqL5d6+P+EL0KWr4x7RSrYpS9kmDV0Euja9EdB37OlirGPlhQh9UYhouvY2UkNuy/1
XLx2Ydql762M8gQ34Ain5rs6binDV8/aEKnUjJs8adRdHgJv3X0BPA9mDwppQXHYV7CZYzotQ+Wf
IedY5qg09K3/dp+1NWTjBNgeO7rcFFt7oCEwT2LOKcus83emu+oN+ZnNHT1tQMh6grFof9vonrSt
rZfhC0d7EyUittfIXJ9b3vuvDocJipxRXt6T+/kIgsd+InBeKuqmiup92G0Foiy+oF6WHfan7Oni
fCvuQKPWg9bMYjsOPjfra+Z7WuAofQSxocTeCQ==

`pragma protect key_keyowner="Xilinx", key_keyname="xilinxt_2025.1-2029.x", key_method="rsa"
`pragma protect encoding = (enctype="BASE64", line_length=76, bytes=256)
`pragma protect key_block
gBZ/OpTly3bfLHbomTqtmjE6ctUpfHNw2/c63WLq8ANFzYZgcSJxtBeJhakJhjPRfSrftPXT1qID
Afd/6FM7ePB7OEd53fhALUlIWcF9wieSlWaK7OGpHaufjKqTlxLtQ3m2SV7+39Z2q+ZjfXUqm89t
oXtBqobGuwqS1E1iGfh4ERpzOvxkehzBlLUIval6l1ChuT8MatH6nDpzkeIPPMwx1Y2ElmbMeiQz
USc63AtuCT9BtkYVbi11SUknHdYLpaCwOlvjzerfuXcuhT6uMv+MUtLRPE/imzZQbZBsbzQnEiEj
zFLiXfSrOALHLb/q8GoGarZLpeq9pjPHr8ak0g==

`pragma protect key_keyowner="Metrics Technologies Inc.", key_keyname="DSim", key_method="rsa"
`pragma protect encoding = (enctype="BASE64", line_length=76, bytes=256)
`pragma protect key_block
UfV9JimfG1DqsMZiSDIYIB/KrinhbXfZJzf8i/Zn6NvxHuPvQQaSH49XLaREkRI/rvTz24fXSEYs
Uw3inZBzSaQYZjgKT+gkiv4L1X/o9lapvzK0cITMpyd69SOHy5zDGO6iOWhFb+Lw0AsGOOiQw3oY
IC5XLLst3iy8Dzq38vxih/JEH1ouy5KTWS/l0R/KY4cDTF0wowRLksjFkWI9GplLybas43Qx9/58
Ddj/lC7GECai0VQMudSdmyuMQiAN2w0BGM8vvlkjT/5OuPxHwQ0upBDVbC/OglYwJchSwEC37/Yy
3V9qOXhHFHl2owxSvTUySmCzgyyRnSnMEb7ebQ==

`pragma protect key_keyowner="Atrenta", key_keyname="ATR-SG-RSA-1", key_method="rsa"
`pragma protect encoding = (enctype="BASE64", line_length=76, bytes=384)
`pragma protect key_block
QpXNEcdJYq9iYnkk1MReBPHWTlA3sKGH8p5CSus39N0N3ksCVjvPcxxwDG+HaGtEr4ahFoRA6WrY
ERH5ojpIltTJBtD96XeoltpD0Ruy0pOYrvx6qWnLn0IRyhmhXHj9HHPfGc6a132JxYuDpY9B9l2X
hMM0/wFKcjGrjZLzl09gb+KbmxNmVWuzXoQv/8c7hK+2ck5almcekkVa7kbSazV3bfw16WtVolYQ
AO6qW5QeqeBHxmq0WqHhBG9iswb0S2lFvWlJj9P9zMQiNGf72jBnUm3aNzAG9jnI73fe0QXXRVik
Qx2Q+xTam8Bfp3fbkHd8PTZGtNcF6qFvMpNfQ7qts4qeK4AxICAHV/g4P28zkMAZtB2HWyRu4W6J
UeA96xD4+BIcuTBvDr7MgAXyMrGBjy9x+ZZJoOzTyREFiWaoIlAwBm4F/tveo77E6jh+u+3sFZOm
8wdChsgrdHARachGuviOThOil/uOoJw1RQXRozNIoQm0iM7k0XWDlAWX

`pragma protect key_keyowner="Cadence Design Systems.", key_keyname="CDS_RSA_KEY_VER_1", key_method="rsa"
`pragma protect encoding = (enctype="BASE64", line_length=76, bytes=256)
`pragma protect key_block
INccIx4if87EOfBjaiD3HsyuEWc+7I1mUD2xf+ja7nsnwF7s9WhkiVWMePDGPDB5+nDTeXNUnUUL
+gS6wxqH6wFJtBL9OHfLESr5BBvAK6E4SA2f5PZhHsCiVf+Xq4mF/fda3WvCtmceJmhuztQ1XjsV
a2cpUi97LgdIcXRxiis6WSlwCRJGBafYY2yyPVOPFuKCmkWgI+ViAV4RZFo9BqWkE7RKBlxPREdR
iXLYeYOZlnmZ9QBmwfalje6a6dtzpF871pVwYwakGD+xwP9UF2n/SbMf7uszaKwKKQ6Ey1OnEaUM
zyVyng712DY0khfwIfLRqMsfq1eWEQjxJewXkw==

`pragma protect key_keyowner="Synplicity", key_keyname="SYNP15_1", key_method="rsa"
`pragma protect encoding = (enctype="BASE64", line_length=76, bytes=256)
`pragma protect key_block
JcMKhDuORGRyvGNK/jrFC0GuGZQKs4xcOQRrjib/dAirK7BQZmZGxs5zwNb+NUlK1WPQ+SZNWqQO
3ro/e+1UByG4mAb6IdgsG9q9vywIuiX7TusXxcjeQurINAhG64Sn90enk6tLpv8h8TEundSsw29H
rRbxXyEBk1EhECY+mm58GQ07jLOZ+jtRxV2SP7CqdGwrr5bg/e/2m4YXJwGmXNzeiy+G7RhF6pXD
40PMsIPQSTAoQ44tR6vPNExpUUyvnQLkO+jK++Q+AZ7LHYascX8+9mfPH0CMZueKWh/WGUo1XNst
RyzNXGzJGC2/iaDtqAfnHPD+rgn5amd5xd0s0A==

`pragma protect key_keyowner="Mentor Graphics Corporation", key_keyname="MGC-PREC-RSA", key_method="rsa"
`pragma protect encoding = (enctype="BASE64", line_length=76, bytes=256)
`pragma protect key_block
QHg07jwZ4meJWD76Mavt7pW3ow0x1UUKk0l+SQkeugTuAZjwmPHr1FaOW0DMN/pesGAhYoPLSJf5
ctybhBsg0rGE/lwizY8bJ16TvgLdC/OpMqj093c7Q3dim8JPtS8MOYDayCo3dh/CdUm7X/YQK90S
7H6ZbED2DjnvaqU6F6QwNvtggovxPNoT8kc6rQtoEn8eXrvUlHb/QTlqXHW6dfyRoK8P5usFCfnr
aEej2bTbimKgduB+o7EVRnM1wEUJ2fkBKRxvvOUYeplNBaJV7XNqEGgyNUGzAM4slcL+I3/xIgSu
kdFKPkD/EAexww7H5uuhytbdpksYtoRb72SwOw==

`pragma protect data_method = "AES128-CBC"
`pragma protect encoding = (enctype = "BASE64", line_length = 76, bytes = 9728)
`pragma protect data_block
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
`pragma protect end_protected
`ifndef GLBL
`define GLBL
`timescale  1 ps / 1 ps

module glbl ();

    parameter ROC_WIDTH = 100000;
    parameter TOC_WIDTH = 0;
    parameter GRES_WIDTH = 10000;
    parameter GRES_START = 10000;

//--------   STARTUP Globals --------------
    wire GSR;
    wire GTS;
    wire GWE;
    wire PRLD;
    wire GRESTORE;
    tri1 p_up_tmp;
    tri (weak1, strong0) PLL_LOCKG = p_up_tmp;

    wire PROGB_GLBL;
    wire CCLKO_GLBL;
    wire FCSBO_GLBL;
    wire [3:0] DO_GLBL;
    wire [3:0] DI_GLBL;
   
    reg GSR_int;
    reg GTS_int;
    reg PRLD_int;
    reg GRESTORE_int;

//--------   JTAG Globals --------------
    wire JTAG_TDO_GLBL;
    wire JTAG_TCK_GLBL;
    wire JTAG_TDI_GLBL;
    wire JTAG_TMS_GLBL;
    wire JTAG_TRST_GLBL;

    reg JTAG_CAPTURE_GLBL;
    reg JTAG_RESET_GLBL;
    reg JTAG_SHIFT_GLBL;
    reg JTAG_UPDATE_GLBL;
    reg JTAG_RUNTEST_GLBL;

    reg JTAG_SEL1_GLBL = 0;
    reg JTAG_SEL2_GLBL = 0 ;
    reg JTAG_SEL3_GLBL = 0;
    reg JTAG_SEL4_GLBL = 0;

    reg JTAG_USER_TDO1_GLBL = 1'bz;
    reg JTAG_USER_TDO2_GLBL = 1'bz;
    reg JTAG_USER_TDO3_GLBL = 1'bz;
    reg JTAG_USER_TDO4_GLBL = 1'bz;

    assign (strong1, weak0) GSR = GSR_int;
    assign (strong1, weak0) GTS = GTS_int;
    assign (weak1, weak0) PRLD = PRLD_int;
    assign (strong1, weak0) GRESTORE = GRESTORE_int;

    initial begin
	GSR_int = 1'b1;
	PRLD_int = 1'b1;
	#(ROC_WIDTH)
	GSR_int = 1'b0;
	PRLD_int = 1'b0;
    end

    initial begin
	GTS_int = 1'b1;
	#(TOC_WIDTH)
	GTS_int = 1'b0;
    end

    initial begin 
	GRESTORE_int = 1'b0;
	#(GRES_START);
	GRESTORE_int = 1'b1;
	#(GRES_WIDTH);
	GRESTORE_int = 1'b0;
    end

endmodule
`endif
