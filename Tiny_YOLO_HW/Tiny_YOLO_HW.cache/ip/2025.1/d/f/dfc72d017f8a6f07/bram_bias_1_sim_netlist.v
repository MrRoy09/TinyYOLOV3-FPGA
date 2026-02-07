// Copyright 1986-2022 Xilinx, Inc. All Rights Reserved.
// Copyright 2022-2025 Advanced Micro Devices, Inc. All Rights Reserved.
// --------------------------------------------------------------------------------
// Tool Version: Vivado v.2025.1 (lin64) Build 6140274 Wed May 21 22:58:25 MDT 2025
// Date        : Sat Feb  7 16:19:28 2026
// Host        : ubuntu-laptop-hp running 64-bit Ubuntu 24.04.3 LTS
// Command     : write_verilog -force -mode funcsim -rename_top decalper_eb_ot_sdeen_pot_pi_dehcac_xnilix -prefix
//               decalper_eb_ot_sdeen_pot_pi_dehcac_xnilix_ bram_bias_1_sim_netlist.v
// Design      : bram_bias_1
// Purpose     : This verilog netlist is a functional simulation representation of the design and should not be modified
//               or synthesized. This netlist cannot be used for SDF annotated simulation.
// Device      : xck26-sfvc784-2LV-c
// --------------------------------------------------------------------------------
`timescale 1 ps / 1 ps

(* CHECK_LICENSE_TYPE = "bram_bias_1,blk_mem_gen_v8_4_11,{}" *) (* downgradeipidentifiedwarnings = "yes" *) (* x_core_info = "blk_mem_gen_v8_4_11,Vivado 2025.1" *) 
(* NotValidForBitStream *)
module decalper_eb_ot_sdeen_pot_pi_dehcac_xnilix
   (clka,
    ena,
    wea,
    addra,
    dina,
    douta);
  (* x_interface_info = "xilinx.com:interface:bram:1.0 BRAM_PORTA CLK" *) (* x_interface_mode = "slave BRAM_PORTA" *) (* x_interface_parameter = "XIL_INTERFACENAME BRAM_PORTA, MEM_ADDRESS_MODE BYTE_ADDRESS, MEM_SIZE 8192, MEM_WIDTH 32, MEM_ECC NONE, MASTER_TYPE OTHER, READ_LATENCY 1" *) input clka;
  (* x_interface_info = "xilinx.com:interface:bram:1.0 BRAM_PORTA EN" *) input ena;
  (* x_interface_info = "xilinx.com:interface:bram:1.0 BRAM_PORTA WE" *) input [0:0]wea;
  (* x_interface_info = "xilinx.com:interface:bram:1.0 BRAM_PORTA ADDR" *) input [8:0]addra;
  (* x_interface_info = "xilinx.com:interface:bram:1.0 BRAM_PORTA DIN" *) input [31:0]dina;
  (* x_interface_info = "xilinx.com:interface:bram:1.0 BRAM_PORTA DOUT" *) output [31:0]douta;

  wire [8:0]addra;
  wire clka;
  wire [31:0]dina;
  wire [31:0]douta;
  wire ena;
  wire [0:0]wea;
  wire NLW_U0_dbiterr_UNCONNECTED;
  wire NLW_U0_rsta_busy_UNCONNECTED;
  wire NLW_U0_rstb_busy_UNCONNECTED;
  wire NLW_U0_s_axi_arready_UNCONNECTED;
  wire NLW_U0_s_axi_awready_UNCONNECTED;
  wire NLW_U0_s_axi_bvalid_UNCONNECTED;
  wire NLW_U0_s_axi_dbiterr_UNCONNECTED;
  wire NLW_U0_s_axi_rlast_UNCONNECTED;
  wire NLW_U0_s_axi_rvalid_UNCONNECTED;
  wire NLW_U0_s_axi_sbiterr_UNCONNECTED;
  wire NLW_U0_s_axi_wready_UNCONNECTED;
  wire NLW_U0_sbiterr_UNCONNECTED;
  wire [31:0]NLW_U0_doutb_UNCONNECTED;
  wire [8:0]NLW_U0_rdaddrecc_UNCONNECTED;
  wire [3:0]NLW_U0_s_axi_bid_UNCONNECTED;
  wire [1:0]NLW_U0_s_axi_bresp_UNCONNECTED;
  wire [8:0]NLW_U0_s_axi_rdaddrecc_UNCONNECTED;
  wire [31:0]NLW_U0_s_axi_rdata_UNCONNECTED;
  wire [3:0]NLW_U0_s_axi_rid_UNCONNECTED;
  wire [1:0]NLW_U0_s_axi_rresp_UNCONNECTED;

  (* C_ADDRA_WIDTH = "9" *) 
  (* C_ADDRB_WIDTH = "9" *) 
  (* C_ALGORITHM = "1" *) 
  (* C_AXI_ID_WIDTH = "4" *) 
  (* C_AXI_SLAVE_TYPE = "0" *) 
  (* C_AXI_TYPE = "1" *) 
  (* C_BYTE_SIZE = "9" *) 
  (* C_COMMON_CLK = "0" *) 
  (* C_COUNT_18K_BRAM = "1" *) 
  (* C_COUNT_36K_BRAM = "0" *) 
  (* C_CTRL_ECC_ALGO = "NONE" *) 
  (* C_DEFAULT_DATA = "0" *) 
  (* C_DISABLE_WARN_BHV_COLL = "0" *) 
  (* C_DISABLE_WARN_BHV_RANGE = "0" *) 
  (* C_ELABORATION_DIR = "./" *) 
  (* C_ENABLE_32BIT_ADDRESS = "0" *) 
  (* C_EN_DEEPSLEEP_PIN = "0" *) 
  (* C_EN_ECC_PIPE = "0" *) 
  (* C_EN_RDADDRA_CHG = "0" *) 
  (* C_EN_RDADDRB_CHG = "0" *) 
  (* C_EN_SAFETY_CKT = "0" *) 
  (* C_EN_SHUTDOWN_PIN = "0" *) 
  (* C_EN_SLEEP_PIN = "0" *) 
  (* C_EST_POWER_SUMMARY = "Estimated Power for IP     :     2.441648 mW" *) 
  (* C_FAMILY = "zynquplus" *) 
  (* C_HAS_AXI_ID = "0" *) 
  (* C_HAS_ENA = "1" *) 
  (* C_HAS_ENB = "0" *) 
  (* C_HAS_INJECTERR = "0" *) 
  (* C_HAS_MEM_OUTPUT_REGS_A = "1" *) 
  (* C_HAS_MEM_OUTPUT_REGS_B = "0" *) 
  (* C_HAS_MUX_OUTPUT_REGS_A = "0" *) 
  (* C_HAS_MUX_OUTPUT_REGS_B = "0" *) 
  (* C_HAS_REGCEA = "0" *) 
  (* C_HAS_REGCEB = "0" *) 
  (* C_HAS_RSTA = "0" *) 
  (* C_HAS_RSTB = "0" *) 
  (* C_HAS_SOFTECC_INPUT_REGS_A = "0" *) 
  (* C_HAS_SOFTECC_OUTPUT_REGS_B = "0" *) 
  (* C_INITA_VAL = "0" *) 
  (* C_INITB_VAL = "0" *) 
  (* C_INIT_FILE = "bram_bias_1.mem" *) 
  (* C_INIT_FILE_NAME = "no_coe_file_loaded" *) 
  (* C_INTERFACE_TYPE = "0" *) 
  (* C_LOAD_INIT_FILE = "0" *) 
  (* C_MEM_TYPE = "0" *) 
  (* C_MUX_PIPELINE_STAGES = "0" *) 
  (* C_PRIM_TYPE = "1" *) 
  (* C_READ_DEPTH_A = "512" *) 
  (* C_READ_DEPTH_B = "512" *) 
  (* C_READ_LATENCY_A = "1" *) 
  (* C_READ_LATENCY_B = "1" *) 
  (* C_READ_WIDTH_A = "32" *) 
  (* C_READ_WIDTH_B = "32" *) 
  (* C_RSTRAM_A = "0" *) 
  (* C_RSTRAM_B = "0" *) 
  (* C_RST_PRIORITY_A = "CE" *) 
  (* C_RST_PRIORITY_B = "CE" *) 
  (* C_SIM_COLLISION_CHECK = "ALL" *) 
  (* C_USE_BRAM_BLOCK = "0" *) 
  (* C_USE_BYTE_WEA = "0" *) 
  (* C_USE_BYTE_WEB = "0" *) 
  (* C_USE_DEFAULT_DATA = "0" *) 
  (* C_USE_ECC = "0" *) 
  (* C_USE_SOFTECC = "0" *) 
  (* C_USE_URAM = "0" *) 
  (* C_WEA_WIDTH = "1" *) 
  (* C_WEB_WIDTH = "1" *) 
  (* C_WRITE_DEPTH_A = "512" *) 
  (* C_WRITE_DEPTH_B = "512" *) 
  (* C_WRITE_MODE_A = "WRITE_FIRST" *) 
  (* C_WRITE_MODE_B = "WRITE_FIRST" *) 
  (* C_WRITE_WIDTH_A = "32" *) 
  (* C_WRITE_WIDTH_B = "32" *) 
  (* C_XDEVICEFAMILY = "zynquplus" *) 
  (* downgradeipidentifiedwarnings = "yes" *) 
  (* is_du_within_envelope = "true" *) 
  decalper_eb_ot_sdeen_pot_pi_dehcac_xnilix_blk_mem_gen_v8_4_11 U0
       (.addra(addra),
        .addrb({1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0}),
        .clka(clka),
        .clkb(1'b0),
        .dbiterr(NLW_U0_dbiterr_UNCONNECTED),
        .deepsleep(1'b0),
        .dina(dina),
        .dinb({1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0}),
        .douta(douta),
        .doutb(NLW_U0_doutb_UNCONNECTED[31:0]),
        .eccpipece(1'b0),
        .ena(ena),
        .enb(1'b0),
        .injectdbiterr(1'b0),
        .injectsbiterr(1'b0),
        .rdaddrecc(NLW_U0_rdaddrecc_UNCONNECTED[8:0]),
        .regcea(1'b1),
        .regceb(1'b1),
        .rsta(1'b0),
        .rsta_busy(NLW_U0_rsta_busy_UNCONNECTED),
        .rstb(1'b0),
        .rstb_busy(NLW_U0_rstb_busy_UNCONNECTED),
        .s_aclk(1'b0),
        .s_aresetn(1'b0),
        .s_axi_araddr({1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0}),
        .s_axi_arburst({1'b0,1'b0}),
        .s_axi_arid({1'b0,1'b0,1'b0,1'b0}),
        .s_axi_arlen({1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0}),
        .s_axi_arready(NLW_U0_s_axi_arready_UNCONNECTED),
        .s_axi_arsize({1'b0,1'b0,1'b0}),
        .s_axi_arvalid(1'b0),
        .s_axi_awaddr({1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0}),
        .s_axi_awburst({1'b0,1'b0}),
        .s_axi_awid({1'b0,1'b0,1'b0,1'b0}),
        .s_axi_awlen({1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0}),
        .s_axi_awready(NLW_U0_s_axi_awready_UNCONNECTED),
        .s_axi_awsize({1'b0,1'b0,1'b0}),
        .s_axi_awvalid(1'b0),
        .s_axi_bid(NLW_U0_s_axi_bid_UNCONNECTED[3:0]),
        .s_axi_bready(1'b0),
        .s_axi_bresp(NLW_U0_s_axi_bresp_UNCONNECTED[1:0]),
        .s_axi_bvalid(NLW_U0_s_axi_bvalid_UNCONNECTED),
        .s_axi_dbiterr(NLW_U0_s_axi_dbiterr_UNCONNECTED),
        .s_axi_injectdbiterr(1'b0),
        .s_axi_injectsbiterr(1'b0),
        .s_axi_rdaddrecc(NLW_U0_s_axi_rdaddrecc_UNCONNECTED[8:0]),
        .s_axi_rdata(NLW_U0_s_axi_rdata_UNCONNECTED[31:0]),
        .s_axi_rid(NLW_U0_s_axi_rid_UNCONNECTED[3:0]),
        .s_axi_rlast(NLW_U0_s_axi_rlast_UNCONNECTED),
        .s_axi_rready(1'b0),
        .s_axi_rresp(NLW_U0_s_axi_rresp_UNCONNECTED[1:0]),
        .s_axi_rvalid(NLW_U0_s_axi_rvalid_UNCONNECTED),
        .s_axi_sbiterr(NLW_U0_s_axi_sbiterr_UNCONNECTED),
        .s_axi_wdata({1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0}),
        .s_axi_wlast(1'b0),
        .s_axi_wready(NLW_U0_s_axi_wready_UNCONNECTED),
        .s_axi_wstrb(1'b0),
        .s_axi_wvalid(1'b0),
        .sbiterr(NLW_U0_sbiterr_UNCONNECTED),
        .shutdown(1'b0),
        .sleep(1'b0),
        .wea(wea),
        .web(1'b0));
endmodule
`pragma protect begin_protected
`pragma protect version = 1
`pragma protect encrypt_agent = "XILINX"
`pragma protect encrypt_agent_info = "Xilinx Encryption Tool 2025.1"
`pragma protect key_keyowner="Synopsys", key_keyname="SNPS-VCS-RSA-2", key_method="rsa"
`pragma protect encoding = (enctype="BASE64", line_length=76, bytes=128)
`pragma protect key_block
gydSV72FvW4hnoyUt6yZFJHfJqjRQWPUfYIuDKP0fpjrPOkLRbJGBr4Z9msYTvoIHRlYtXJ2YMY0
d1TIQb+FK4gKsTRru9wr397OxuFBsTRf4e+ZjpYZEdsnqYWcgMSzhN4yhPvO06GyZO15y/LKBxa8
3OKwxVlOLYXhv+sxdXg=

`pragma protect key_keyowner="Aldec", key_keyname="ALDEC15_001", key_method="rsa"
`pragma protect encoding = (enctype="BASE64", line_length=76, bytes=256)
`pragma protect key_block
WHB6Zbfa5Qi47krP9T4L8UnPOlr881dWx7UcYaZfNGIQQM0gadcoXbhucIpRaUuyOKxv6yhKveRN
h0l+N9+KX6rbZ6+TRhP9JAMuPhlpI7T42QtRv5zx9+m3ct5S0NMszbFaK8zeTAYra5BGP7BHmtkr
MpKfLK5sFyaTE/A7ACtAace9MwFTHDZdl9uUs4aY6KJlm6GaypKduiqkNugukJp5vlFPX/ZapJqG
KMtMhI6grhcuYb1FJrwRZ4jW7hs9HxddSdGLzsZ0HsBcO/qaCPTst+ZA0YIQfd5ULlFmPqq39FfO
p1P+2hEH2n+LycbMj5cn4Dxfqv2R8eucM78R3w==

`pragma protect key_keyowner="Mentor Graphics Corporation", key_keyname="MGC-VELOCE-RSA", key_method="rsa"
`pragma protect encoding = (enctype="BASE64", line_length=76, bytes=128)
`pragma protect key_block
SmAzQA1VEuJXtJi5vXa2Jg7YvRqAJs6PX9HTZ1YqrJw4VfonBW3726gJ81BjlizpMkcf/Uk5sFIK
aPedVhEs4xCIZylz7gXYDshtytOA/pXUID2qV9nXr8qfI+FydSADUF3ScYDZmlkclFqlZrGq6DQ7
da3lJAzt2h/iR+cczrA=

`pragma protect key_keyowner="Mentor Graphics Corporation", key_keyname="MGC-VERIF-SIM-RSA-2", key_method="rsa"
`pragma protect encoding = (enctype="BASE64", line_length=76, bytes=256)
`pragma protect key_block
iAph5JWb/chMQpLPX1UoLjQDxN5l2I8McM/k2xN5wRht7HXoE6F5yV8luDjn3zkI6vnfUYo7BaI1
mogRRx+R3XcwxvhHr+lngh4+/YLVex1TFncl+kiUMAsu3M/FjFSiqGMVMdKTNLDqr35DuZJVyuiF
lTwXob/KkbQDJiJjBEoxbt+968rKRKRyJGcqIjm4mqRBdqMcgo3HOJFG74SFsWAQrxvXfBhdLSG3
OfoLfls9XDojBjp7G83k0h82g1eeWgBfydm/OcX9o48Pst93NvI4ua8WShZL8MCvRWYqWZrrjrWi
cfUjXAF5SDACjq1/OU6arz/Idz6/a7AP/jmexw==

`pragma protect key_keyowner="Real Intent", key_keyname="RI-RSA-KEY-1", key_method="rsa"
`pragma protect encoding = (enctype="BASE64", line_length=76, bytes=256)
`pragma protect key_block
BY49GZBxBT/gjZDPyaSWlti/sctckoR7jK6NuWdhnF9tiyNfVU7BqjjwxSnyMi0Uucv1BKHXC18h
8hQbFWnNtrq71ilURotXux7sssHlVJ2i1CsJWU18DOcBWxm2ai89uwvxDJh3TJkBJixB5KPvsDhL
lWOjTvZWPoR+Ixy+Tzo+U5Vx7z7SOakRwTrn3u7+c3vmCEBphE+HKeJExhBAoOEd0SXK5iwXaByW
D7Wb7zq6NNUmnCyaJ2BG9kGxLVsf+md7SlocuaFsYyaRZhwPyTucxIlz1tLYwcytKzx0ovoax3no
nYgzlzP/F0/PDWk9BqXgr/tuclc4EZYX0cf4ng==

`pragma protect key_keyowner="Xilinx", key_keyname="xilinxt_2025.1-2029.x", key_method="rsa"
`pragma protect encoding = (enctype="BASE64", line_length=76, bytes=256)
`pragma protect key_block
qGnCvL35qO7cbUEKCL50yDv1UvezcqBz601zctKop1954QlcjemzZWZHg1zJ00nJaToNdH2S8AKX
n8hNJvbQ+x5HEGL5DoSU9m5qjXd8xxocnZ0yzuZX/dGCT8kDn3gWJR2Gz13pT+w2LQUno1fX+MsC
ehgwvjBBT6GeYjdxHi+aybQUP9AblSxX/z3vh857SGCPohEWvghOgORCHAe45YD+ZWnL62FLxMM2
c+Ozq/Au/Q4q1Yzlzcfv8Mnsvg7OqOeEamQHbuYOfdkJUuYqOwsskEWW348u7FXtsf8m7P3pZyyz
IWyTDAW4igGguMPLHfbtK/twZx8ScJQmOKzglg==

`pragma protect key_keyowner="Metrics Technologies Inc.", key_keyname="DSim", key_method="rsa"
`pragma protect encoding = (enctype="BASE64", line_length=76, bytes=256)
`pragma protect key_block
Hz+6K8+wh5/fukU4ZWNDXGsq6hreSVCSPP67nA6kUz9Vpjy4TtTnOrrl1BWY0ivEC7Ldyw8VI60A
VO/WPlt409LdAZdMZGsEZ1JuTZ0m9LPcgu9CPCyoMECctmd8LHE+otY6etTmYABB9syY61rk2hrv
RgbcyT/HCK9TzWxSm+XMqvx2nvagCLkMDPh/JZv51fj2zcKaBPnxsz8rnDipaeo0fEyVRC3Y1F/V
U3RmXojBjIumPHSJkQ537dENJEIA0Ra65u8EM/+ItUn1bcryLcIbKy1xGadrHmHdHRUoRcAodO2C
B48bNVeL0VnGg8P9ACIB04lMNzn5p6A1tPOb4Q==

`pragma protect key_keyowner="Atrenta", key_keyname="ATR-SG-RSA-1", key_method="rsa"
`pragma protect encoding = (enctype="BASE64", line_length=76, bytes=384)
`pragma protect key_block
YDpb+UeT0rJ543Q8wCo2xSS3gpVAT+JoStgBlV5IMjJoUOWkiOPn691FGChmDi3BTq5NxC73KHHR
1galACCjeTGq6cv+0Zc2Ocm1oobdrnSPHp7TMDr5Zle8FX6WywJCiGdoWBODggZSlbOASIK/PVfY
cZM2z60M6RSvzsi3TnYHiKYHpju8THVoSgRd6r31GcbiSy9TjjARERXan0OVc79jGuAg90mmDEEq
91eqmn6NZ9yLI2fgBjFUZbtFCpmJ8WGxOL1h39niWnRK3ZXnk8jcpnZUlxLbYTPO0Z3vVr1zrvcn
RVQloU0OLqg7M95zSs7NtX5Vzvb6jGbMehWV+WMMyxWmxL2XOwsAwPSeX2dI2r77pioY7X6VzH7f
/JxMAnq9udra3WGPsUkD1G0CvPkCC3zdxjpVaflY37ztX9UONhKtzMQa8lJc1IL8GhXRY3R9Lg2c
HIeXSGkpNNuFDqKT6Khe/6Casq+SjFJq+IH9IUtz6RUZTkbFb0Xhgm2P

`pragma protect key_keyowner="Cadence Design Systems.", key_keyname="CDS_RSA_KEY_VER_1", key_method="rsa"
`pragma protect encoding = (enctype="BASE64", line_length=76, bytes=256)
`pragma protect key_block
Q+63zFEYw/LeMgxa7g8g79GGvSyIKDKD8RvvC4DHDQuGObf6n9OGZX4e17v/E/+EDEwUhsWQHFDI
Lp/aH+6fNRmhu9BEWVjxq2WRrQSl4eQjfIaSOXu2dlYh3JjRJwiUp4LteVh8RFAf5t5sRQO4dRIK
x+h28yliSgibaWEAv5FaJQ1EFbNwmgedAaSYjgf2A3afBUcBh5Uy9VHbW/zRzdhhJdsVNBjZYcFy
CVLOcf1toCRp8J4U5FlnFMOzFegUbdXFQhq2VmIhPRxWjrfTk6iR4BcMEN9UMij/5IHRAeBdksyD
CqEKsyFxosbI5KVMRZ1Ln75Zipn0JdsGekHkxg==

`pragma protect key_keyowner="Synplicity", key_keyname="SYNP15_1", key_method="rsa"
`pragma protect encoding = (enctype="BASE64", line_length=76, bytes=256)
`pragma protect key_block
DPUa5DLPYRWvbPnX0U412yoWvvvHyuq43DrYmDJGTK0cR5U4U6th8icYgizC1/hUAEzt19kM/hVa
zZh7bXSWACYLpcfhPY8dRTVGDZVjpbkraw0ceBryLP7jc6Jt5JdNw88tZtZpprCB7nQ25lUL82Hf
WTwL1ZqgGIvtfHhxO0JF5L5ES5giedwQ6u5ffXG3UB6ELcpQD1NvpW5lAz4mfXyvVDCAPZN581TF
tlAy79iKbPKlJ2zFn1BS2cuRIHHe2JRxwPo+0n5VD5CXVgg+lCYxTnCxI8CdyFaTumbs4IfAKwVI
wSN/btbwDUhW9hAHWHIRo+BpdJ4qeGcTDPKtsA==

`pragma protect key_keyowner="Mentor Graphics Corporation", key_keyname="MGC-PREC-RSA", key_method="rsa"
`pragma protect encoding = (enctype="BASE64", line_length=76, bytes=256)
`pragma protect key_block
mf5hcf6JE6yLm0jNCQnHMVmogjLlPz6re0FwG67yvOJ3FuEorru0emIeAKEwgOoxjUYNWvcM7QAH
/UEeB2EIdjLl6glPAUda0HjtaCU2rdncVdM8k6DSMBggc4yo18Qx5F+1TD/RoBgoo0jNkMdDy6wJ
JHjqlN+R01z3yYIMQ9f2z6ZaYncbBYEp4+YAb7g1D7CSMxP5cFRpQznRpYp0JwqJfT9CHzlKgdab
8B288NxeLM66iYodiTS+GSRGLGtDWXpz9yeiuiPe6kJxae2GJyHIMSfluO/0Slc3m24DQNdbojf8
jdc0G2UnrDe5mCUTfYiDmpOWTUJOdYo0FK0N2g==

`pragma protect data_method = "AES128-CBC"
`pragma protect encoding = (enctype = "BASE64", line_length = 76, bytes = 21376)
`pragma protect data_block
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
eQ==
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
