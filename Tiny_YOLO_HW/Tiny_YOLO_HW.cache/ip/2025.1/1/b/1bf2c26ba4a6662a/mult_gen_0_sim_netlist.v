// Copyright 1986-2022 Xilinx, Inc. All Rights Reserved.
// Copyright 2022-2025 Advanced Micro Devices, Inc. All Rights Reserved.
// --------------------------------------------------------------------------------
// Tool Version: Vivado v.2025.1 (lin64) Build 6140274 Wed May 21 22:58:25 MDT 2025
// Date        : Fri Feb  6 23:39:02 2026
// Host        : ubuntu-laptop-hp running 64-bit Ubuntu 24.04.3 LTS
// Command     : write_verilog -force -mode funcsim -rename_top decalper_eb_ot_sdeen_pot_pi_dehcac_xnilix -prefix
//               decalper_eb_ot_sdeen_pot_pi_dehcac_xnilix_ mult_gen_0_sim_netlist.v
// Design      : mult_gen_0
// Purpose     : This verilog netlist is a functional simulation representation of the design and should not be modified
//               or synthesized. This netlist cannot be used for SDF annotated simulation.
// Device      : xck26-sfvc784-2LV-c
// --------------------------------------------------------------------------------
`timescale 1 ps / 1 ps

(* CHECK_LICENSE_TYPE = "mult_gen_0,xbip_multadd_v3_0_22,{}" *) (* downgradeipidentifiedwarnings = "yes" *) (* x_core_info = "xbip_multadd_v3_0_22,Vivado 2025.1" *) 
(* NotValidForBitStream *)
module decalper_eb_ot_sdeen_pot_pi_dehcac_xnilix
   (CLK,
    CE,
    SCLR,
    A,
    B,
    C,
    SUBTRACT,
    P,
    PCOUT);
  (* x_interface_info = "xilinx.com:signal:clock:1.0 clk_intf CLK" *) (* x_interface_mode = "slave clk_intf" *) (* x_interface_parameter = "XIL_INTERFACENAME clk_intf, ASSOCIATED_BUSIF pcout_intf:p_intf:subtract_intf:pcin_intf:c_intf:b_intf:a_intf, ASSOCIATED_RESET SCLR, ASSOCIATED_CLKEN CE, FREQ_HZ 100000000, FREQ_TOLERANCE_HZ 0, PHASE 0.0, INSERT_VIP 0" *) input CLK;
  (* x_interface_info = "xilinx.com:signal:clockenable:1.0 ce_intf CE" *) (* x_interface_mode = "slave ce_intf" *) (* x_interface_parameter = "XIL_INTERFACENAME ce_intf, POLARITY ACTIVE_HIGH" *) input CE;
  (* x_interface_info = "xilinx.com:signal:reset:1.0 sclr_intf RST" *) (* x_interface_mode = "slave sclr_intf" *) (* x_interface_parameter = "XIL_INTERFACENAME sclr_intf, POLARITY ACTIVE_HIGH, INSERT_VIP 0" *) input SCLR;
  (* x_interface_info = "xilinx.com:signal:data:1.0 a_intf DATA" *) (* x_interface_mode = "slave a_intf" *) (* x_interface_parameter = "XIL_INTERFACENAME a_intf, LAYERED_METADATA undef" *) input [7:0]A;
  (* x_interface_info = "xilinx.com:signal:data:1.0 b_intf DATA" *) (* x_interface_mode = "slave b_intf" *) (* x_interface_parameter = "XIL_INTERFACENAME b_intf, LAYERED_METADATA undef" *) input [7:0]B;
  (* x_interface_info = "xilinx.com:signal:data:1.0 c_intf DATA" *) (* x_interface_mode = "slave c_intf" *) (* x_interface_parameter = "XIL_INTERFACENAME c_intf, LAYERED_METADATA undef" *) input [31:0]C;
  (* x_interface_info = "xilinx.com:signal:data:1.0 subtract_intf DATA" *) (* x_interface_mode = "slave subtract_intf" *) (* x_interface_parameter = "XIL_INTERFACENAME subtract_intf, LAYERED_METADATA undef" *) input SUBTRACT;
  (* x_interface_info = "xilinx.com:signal:data:1.0 p_intf DATA" *) (* x_interface_mode = "master p_intf" *) (* x_interface_parameter = "XIL_INTERFACENAME p_intf, LAYERED_METADATA undef" *) output [47:0]P;
  (* x_interface_info = "xilinx.com:signal:data:1.0 pcout_intf DATA" *) (* x_interface_mode = "master pcout_intf" *) (* x_interface_parameter = "XIL_INTERFACENAME pcout_intf, LAYERED_METADATA undef" *) output [47:0]PCOUT;

  wire [7:0]A;
  wire [7:0]B;
  wire [31:0]C;
  wire CE;
  wire CLK;
  wire [47:0]P;
  wire [47:0]PCOUT;
  wire SCLR;
  wire SUBTRACT;

  (* C_AB_LATENCY = "-1" *) 
  (* C_A_TYPE = "0" *) 
  (* C_A_WIDTH = "8" *) 
  (* C_B_TYPE = "0" *) 
  (* C_B_WIDTH = "8" *) 
  (* C_CE_OVERRIDES_SCLR = "0" *) 
  (* C_C_LATENCY = "-1" *) 
  (* C_C_TYPE = "0" *) 
  (* C_C_WIDTH = "32" *) 
  (* C_OUT_HIGH = "47" *) 
  (* C_OUT_LOW = "0" *) 
  (* C_TEST_CORE = "0" *) 
  (* C_USE_PCIN = "0" *) 
  (* C_VERBOSITY = "0" *) 
  (* C_XDEVICEFAMILY = "zynquplus" *) 
  (* downgradeipidentifiedwarnings = "yes" *) 
  (* is_du_within_envelope = "true" *) 
  decalper_eb_ot_sdeen_pot_pi_dehcac_xnilix_xbip_multadd_v3_0_22 U0
       (.A(A),
        .B(B),
        .C(C),
        .CE(CE),
        .CLK(CLK),
        .P(P),
        .PCIN({1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0}),
        .PCOUT(PCOUT),
        .SCLR(SCLR),
        .SUBTRACT(SUBTRACT));
endmodule
`pragma protect begin_protected
`pragma protect version = 1
`pragma protect encrypt_agent = "XILINX"
`pragma protect encrypt_agent_info = "Xilinx Encryption Tool 2025.1"
`pragma protect key_keyowner="Synopsys", key_keyname="SNPS-VCS-RSA-2", key_method="rsa"
`pragma protect encoding = (enctype="BASE64", line_length=76, bytes=128)
`pragma protect key_block
sFFAkcjgopoZNqqWq5tag3pA5gaGOIr9+e0yJBGg1WhXoYGz1+8qyEa1GP3lj+49jInOmzC44ilZ
nR4cgYsZt0DYL7gG9F9F1uNho0xAgMqJ2U17w4gDFSyeqXVr+Bmysxht2WpGrJ1hnLK+g/CyvKmf
XJ6SVXXaEq5ajLY582U=

`pragma protect key_keyowner="Aldec", key_keyname="ALDEC15_001", key_method="rsa"
`pragma protect encoding = (enctype="BASE64", line_length=76, bytes=256)
`pragma protect key_block
NcdWw5L7sYfIH0Cdov7Bke2D8I04RX/DdCzIHseczGZo7EIAPR4CQLip3n/mD4eMBVu2oWxNv6TH
N1mtwFk4Ng+rY/eTKxgMRWXt2hocYSpWG6psCiME1d3SBP2ifKwHodIJR8IgM8dM8qDzzKEbLPlh
zqnrAcnjAZnnXvDnpJiNHgjk9FGRmYNhqL48alhec8IuYs+UP2Z4FH8eHM+tlelZZLX7tZlDaccP
rD3gT62SZ+5p1uUuRfNqC+ypA/E5yBifz7WdWpHc7Jh+GJj7fLTYAMmU+yqhNVugl7pkoMgW55d5
7GF1oVn4cYY6oYBOSTvnn9zmof3cvLNyZGN6sQ==

`pragma protect key_keyowner="Mentor Graphics Corporation", key_keyname="MGC-VELOCE-RSA", key_method="rsa"
`pragma protect encoding = (enctype="BASE64", line_length=76, bytes=128)
`pragma protect key_block
Q1/v2i5Ee6JYHD3UK/BesFiR51KSucOawbcXvgOKCgsEce6KMvcBvC29ODh652QMDwbB0FbF6E1c
/0S21uFIaRNsyb+GFzMq5LbGrks1RuLunsdGsQjDqwgJlfcgLowuIzNJBhaaCfIRMjinNfSlGEI8
lJjmTxFm3jV+wXpGwEw=

`pragma protect key_keyowner="Mentor Graphics Corporation", key_keyname="MGC-VERIF-SIM-RSA-2", key_method="rsa"
`pragma protect encoding = (enctype="BASE64", line_length=76, bytes=256)
`pragma protect key_block
e9vrqjhg+6pAjhPPBh4qLHpaye8XgNpLf4jtVtdUqCDF77sIaNPF7NsSF7fgS5BfqkyL2qKKDLGi
snnGuDkZHi9sKefZF2bZYuMm/h3jdKr6XngC32Mz1Ft7OKAgAAJDmmhVmfnC7I06Xq7VpQMU7MLA
mTNGE/CyidQoaLK9G9HIbpmKRjJF1Ga6Lkvteync2kaLn/6gu07PzPBhUtpV/gxKJJBBFgUKXii6
781/ab6p2RamSHb69DxQ8D2Opd7plPb9tk5IUP/QaCWhXcc7C09KOZvb4E0ps5OaoqaeLTc/Sgb6
Gd2wVaRSNpgKcmnRLNOLgVwdWI4dT42B+PNV2Q==

`pragma protect key_keyowner="Real Intent", key_keyname="RI-RSA-KEY-1", key_method="rsa"
`pragma protect encoding = (enctype="BASE64", line_length=76, bytes=256)
`pragma protect key_block
aZTNUoTW5Jyk9/pOTK/Wz2pZNFP4naYpT1NxdRYjLDDnXr7ywnQY6s2AHx5r/xrOC5be9gCA0gTW
i29905iBrcOQ0IvcLhHBzbqD6oVrG7RNOUFwlXenqPyUob8RE0Mmrh13fn4BvUV7FVMEgQgwO9Ey
ISxXbKt3w9fz3RJhoamlsWV62pbX272HDKCFI1l73M5oRsDuJiMM4OlOspZOcMI7dl96XJ2mU5vK
8l5EiIPaiRRvxrqpUL9uy5M2w69D/e4ypnPBeveofjZ5mZYsOK4KoSwTWMxxm2kOOkce5+r9mW1a
gPCvjYTIXERm8vf5eG0F3pgd/8/bc2q6oN7Thg==

`pragma protect key_keyowner="Xilinx", key_keyname="xilinxt_2025.1-2029.x", key_method="rsa"
`pragma protect encoding = (enctype="BASE64", line_length=76, bytes=256)
`pragma protect key_block
YieYDWbGgHp2hdwdmE3X0BVvIf2P/4zs8UUX9cFCsWUKGrYwEILOqUwZMaARqAu62eSGZbVY1Wzf
tEnYcJ9vgJtCvafp+ig3zQ4LT0kerFyFg1HviiGhKrwfWA0/6R3efpON8rUcilOZdppD50YSAs0k
B4nFOANFmWq2BYWCJzBaAAU0AvZmAxV0CPruE/FSTagC3P0N2Hj3RkziBZqOCIffTeU2f/cVCI/8
k3zPs/QA/LeQbpazLa6iDEkJ5aoGwzfLJ+LLx/DsKiGH0nMEkBsRV1wPTIQ+g23LsHksqiGV0D2b
0mCk349HjVeLL1kRZoGnOoRpjZsD9W8I8bG5AQ==

`pragma protect key_keyowner="Metrics Technologies Inc.", key_keyname="DSim", key_method="rsa"
`pragma protect encoding = (enctype="BASE64", line_length=76, bytes=256)
`pragma protect key_block
PzncTlQ2HB9FIuULqkrin+HIwyzGgk1bQO2+bPxxmlYUL/wZB93yJg65Zq3a9cxg1wjla2Pyq4g/
K6Y9gqty2uzydzaJu1Yuo9lLKlX6TomwpmzpHMmZIi94Rn1jyid/bl+qD9D4EVbUx9vAijUEQ/A3
kVWJHPmmNVCbwuM0LkGyB+pRj7RD/QnpYEfZmq+JsrkbUg0XFOKz67dCeUvhwsTCt5ubosBde6l+
u7hJNxze7i1rOmfa3zIsGJnmukFqQdI2rvAz60j9RNUSS2irSSHo8AU3S5ldbD+uy8l4MWyw6t1P
bsvN6fh6RvtJx8BXw9Yahr0qD3V5cJNLCBAAyw==

`pragma protect key_keyowner="Atrenta", key_keyname="ATR-SG-RSA-1", key_method="rsa"
`pragma protect encoding = (enctype="BASE64", line_length=76, bytes=384)
`pragma protect key_block
Y7gYFpQJteZVzaC1/6afzpkdhCRQmNMjobhN7Y2wyMW4PGqs/W3NnqUBUh1qN/xZbKbtYmzWzmpk
dqnkJjOZdJAxW3gcWZo+cRzmzJN86EpEfXrHARC1zyIQogmUd+8c7zsCJSb9ETAoIe9wCybMZ/Au
1bPTFoZmPF/riSxQ/I2lkK8BWuCJgJMCqebv/zDRXDdNw6ZimyAYYwVY8EuTtIvnWLj9wHMQlUXr
Eu6NX2y4ZQo3LKzdfvxv4PVkwB/7hoACLLQVy8NemNTFrMu8CELcdluAlPlsvJzLQzbkKIdVuKkO
6VkIDC5e85pc5yDn+iyCa00csKh17/L6KM2kST+cNtg0GEdeYLYPwnuvkJuAtTqiI6xT/jUfGiTq
oRLh6bPzYW0rk1aM/WYkSe7z+PMZ8BheY8RoPYxeq4IURayZ8nWyOnhjTdO33u3Lje1sOOq9DyQz
UbeYB6GJBTWWdXs/rMQwyDcQa3ZXqZKqnlrEO0jDW1qdqAUyhJs5CjPh

`pragma protect key_keyowner="Cadence Design Systems.", key_keyname="CDS_RSA_KEY_VER_1", key_method="rsa"
`pragma protect encoding = (enctype="BASE64", line_length=76, bytes=256)
`pragma protect key_block
OU+W5/VvSyWT8kz+18cP7hycJY9YHioJsVTlU0IV+xYo4xFvdSrNIbp6WqQP8nE1ZlZmhhiU24oq
iROV46LKDedCfGCS/COpnHQBM7+UNBsY8IzaQ6nE42f0DpH2VF/fvfgSW6gL3pj3pgyv6Bca/b+I
S0euLs+SfN5gLNRt07v+EN/kQQ7BUDd28x+gFzIeJlr28BnP5WGnpu23nvS0lG1yV92fmK2dryOv
GKRUjN+awrhSHLvV2z7GxvtKzBeyASXqeR1liO/0k99zUa0LGhAbtWK9uJJ5VcQQT+1oPUnxPlub
kT1lpU1jFos3D+YTWb9FVBqw3DwesA1DnPnilw==

`pragma protect data_method = "AES128-CBC"
`pragma protect encoding = (enctype = "BASE64", line_length = 76, bytes = 2096)
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
sFFAkcjgopoZNqqWq5tag3pA5gaGOIr9+e0yJBGg1WhXoYGz1+8qyEa1GP3lj+49jInOmzC44ilZ
nR4cgYsZt0DYL7gG9F9F1uNho0xAgMqJ2U17w4gDFSyeqXVr+Bmysxht2WpGrJ1hnLK+g/CyvKmf
XJ6SVXXaEq5ajLY582U=

`pragma protect key_keyowner="Aldec", key_keyname="ALDEC15_001", key_method="rsa"
`pragma protect encoding = (enctype="BASE64", line_length=76, bytes=256)
`pragma protect key_block
NcdWw5L7sYfIH0Cdov7Bke2D8I04RX/DdCzIHseczGZo7EIAPR4CQLip3n/mD4eMBVu2oWxNv6TH
N1mtwFk4Ng+rY/eTKxgMRWXt2hocYSpWG6psCiME1d3SBP2ifKwHodIJR8IgM8dM8qDzzKEbLPlh
zqnrAcnjAZnnXvDnpJiNHgjk9FGRmYNhqL48alhec8IuYs+UP2Z4FH8eHM+tlelZZLX7tZlDaccP
rD3gT62SZ+5p1uUuRfNqC+ypA/E5yBifz7WdWpHc7Jh+GJj7fLTYAMmU+yqhNVugl7pkoMgW55d5
7GF1oVn4cYY6oYBOSTvnn9zmof3cvLNyZGN6sQ==

`pragma protect key_keyowner="Mentor Graphics Corporation", key_keyname="MGC-VELOCE-RSA", key_method="rsa"
`pragma protect encoding = (enctype="BASE64", line_length=76, bytes=128)
`pragma protect key_block
Q1/v2i5Ee6JYHD3UK/BesFiR51KSucOawbcXvgOKCgsEce6KMvcBvC29ODh652QMDwbB0FbF6E1c
/0S21uFIaRNsyb+GFzMq5LbGrks1RuLunsdGsQjDqwgJlfcgLowuIzNJBhaaCfIRMjinNfSlGEI8
lJjmTxFm3jV+wXpGwEw=

`pragma protect key_keyowner="Mentor Graphics Corporation", key_keyname="MGC-VERIF-SIM-RSA-2", key_method="rsa"
`pragma protect encoding = (enctype="BASE64", line_length=76, bytes=256)
`pragma protect key_block
e9vrqjhg+6pAjhPPBh4qLHpaye8XgNpLf4jtVtdUqCDF77sIaNPF7NsSF7fgS5BfqkyL2qKKDLGi
snnGuDkZHi9sKefZF2bZYuMm/h3jdKr6XngC32Mz1Ft7OKAgAAJDmmhVmfnC7I06Xq7VpQMU7MLA
mTNGE/CyidQoaLK9G9HIbpmKRjJF1Ga6Lkvteync2kaLn/6gu07PzPBhUtpV/gxKJJBBFgUKXii6
781/ab6p2RamSHb69DxQ8D2Opd7plPb9tk5IUP/QaCWhXcc7C09KOZvb4E0ps5OaoqaeLTc/Sgb6
Gd2wVaRSNpgKcmnRLNOLgVwdWI4dT42B+PNV2Q==

`pragma protect key_keyowner="Real Intent", key_keyname="RI-RSA-KEY-1", key_method="rsa"
`pragma protect encoding = (enctype="BASE64", line_length=76, bytes=256)
`pragma protect key_block
aZTNUoTW5Jyk9/pOTK/Wz2pZNFP4naYpT1NxdRYjLDDnXr7ywnQY6s2AHx5r/xrOC5be9gCA0gTW
i29905iBrcOQ0IvcLhHBzbqD6oVrG7RNOUFwlXenqPyUob8RE0Mmrh13fn4BvUV7FVMEgQgwO9Ey
ISxXbKt3w9fz3RJhoamlsWV62pbX272HDKCFI1l73M5oRsDuJiMM4OlOspZOcMI7dl96XJ2mU5vK
8l5EiIPaiRRvxrqpUL9uy5M2w69D/e4ypnPBeveofjZ5mZYsOK4KoSwTWMxxm2kOOkce5+r9mW1a
gPCvjYTIXERm8vf5eG0F3pgd/8/bc2q6oN7Thg==

`pragma protect key_keyowner="Xilinx", key_keyname="xilinxt_2025.1-2029.x", key_method="rsa"
`pragma protect encoding = (enctype="BASE64", line_length=76, bytes=256)
`pragma protect key_block
YieYDWbGgHp2hdwdmE3X0BVvIf2P/4zs8UUX9cFCsWUKGrYwEILOqUwZMaARqAu62eSGZbVY1Wzf
tEnYcJ9vgJtCvafp+ig3zQ4LT0kerFyFg1HviiGhKrwfWA0/6R3efpON8rUcilOZdppD50YSAs0k
B4nFOANFmWq2BYWCJzBaAAU0AvZmAxV0CPruE/FSTagC3P0N2Hj3RkziBZqOCIffTeU2f/cVCI/8
k3zPs/QA/LeQbpazLa6iDEkJ5aoGwzfLJ+LLx/DsKiGH0nMEkBsRV1wPTIQ+g23LsHksqiGV0D2b
0mCk349HjVeLL1kRZoGnOoRpjZsD9W8I8bG5AQ==

`pragma protect key_keyowner="Metrics Technologies Inc.", key_keyname="DSim", key_method="rsa"
`pragma protect encoding = (enctype="BASE64", line_length=76, bytes=256)
`pragma protect key_block
PzncTlQ2HB9FIuULqkrin+HIwyzGgk1bQO2+bPxxmlYUL/wZB93yJg65Zq3a9cxg1wjla2Pyq4g/
K6Y9gqty2uzydzaJu1Yuo9lLKlX6TomwpmzpHMmZIi94Rn1jyid/bl+qD9D4EVbUx9vAijUEQ/A3
kVWJHPmmNVCbwuM0LkGyB+pRj7RD/QnpYEfZmq+JsrkbUg0XFOKz67dCeUvhwsTCt5ubosBde6l+
u7hJNxze7i1rOmfa3zIsGJnmukFqQdI2rvAz60j9RNUSS2irSSHo8AU3S5ldbD+uy8l4MWyw6t1P
bsvN6fh6RvtJx8BXw9Yahr0qD3V5cJNLCBAAyw==

`pragma protect key_keyowner="Atrenta", key_keyname="ATR-SG-RSA-1", key_method="rsa"
`pragma protect encoding = (enctype="BASE64", line_length=76, bytes=384)
`pragma protect key_block
Y7gYFpQJteZVzaC1/6afzpkdhCRQmNMjobhN7Y2wyMW4PGqs/W3NnqUBUh1qN/xZbKbtYmzWzmpk
dqnkJjOZdJAxW3gcWZo+cRzmzJN86EpEfXrHARC1zyIQogmUd+8c7zsCJSb9ETAoIe9wCybMZ/Au
1bPTFoZmPF/riSxQ/I2lkK8BWuCJgJMCqebv/zDRXDdNw6ZimyAYYwVY8EuTtIvnWLj9wHMQlUXr
Eu6NX2y4ZQo3LKzdfvxv4PVkwB/7hoACLLQVy8NemNTFrMu8CELcdluAlPlsvJzLQzbkKIdVuKkO
6VkIDC5e85pc5yDn+iyCa00csKh17/L6KM2kST+cNtg0GEdeYLYPwnuvkJuAtTqiI6xT/jUfGiTq
oRLh6bPzYW0rk1aM/WYkSe7z+PMZ8BheY8RoPYxeq4IURayZ8nWyOnhjTdO33u3Lje1sOOq9DyQz
UbeYB6GJBTWWdXs/rMQwyDcQa3ZXqZKqnlrEO0jDW1qdqAUyhJs5CjPh

`pragma protect key_keyowner="Cadence Design Systems.", key_keyname="CDS_RSA_KEY_VER_1", key_method="rsa"
`pragma protect encoding = (enctype="BASE64", line_length=76, bytes=256)
`pragma protect key_block
OU+W5/VvSyWT8kz+18cP7hycJY9YHioJsVTlU0IV+xYo4xFvdSrNIbp6WqQP8nE1ZlZmhhiU24oq
iROV46LKDedCfGCS/COpnHQBM7+UNBsY8IzaQ6nE42f0DpH2VF/fvfgSW6gL3pj3pgyv6Bca/b+I
S0euLs+SfN5gLNRt07v+EN/kQQ7BUDd28x+gFzIeJlr28BnP5WGnpu23nvS0lG1yV92fmK2dryOv
GKRUjN+awrhSHLvV2z7GxvtKzBeyASXqeR1liO/0k99zUa0LGhAbtWK9uJJ5VcQQT+1oPUnxPlub
kT1lpU1jFos3D+YTWb9FVBqw3DwesA1DnPnilw==

`pragma protect key_keyowner="Mentor Graphics Corporation", key_keyname="MGC-PREC-RSA", key_method="rsa"
`pragma protect encoding = (enctype="BASE64", line_length=76, bytes=256)
`pragma protect key_block
d1bEo3Cvzm67p1Yq5NavOWhikTAV3yQtEF4J19ZeGOmIJUlB385ZU5ArjD8silvp3OMArAtS0N9k
lDm6vmv6qLmXqbW0k7TWHEA7zK2cKlIYPxNr+F+uTu3Dl5nIhOt2UPn51YAZg1hU1YN5GRoRks3U
mzXGuWn0JcbpcMiJEhumGAJNkX69S34oR3Y0yPv2cPRSyuCQhNyRlLc06R2pz5H9oIgNDYb65NIk
jXMdZgAqEPwjzKc22myAUJe6u2xT+TYk+2jpj7fhU5daLN7Wem47yEmrpkPHAfGeRYYCoCwCrb5j
wNVp7A4Y3nKw2SFSDwqSnO2N5UOi/YIZ+C4buA==

`pragma protect key_keyowner="Synplicity", key_keyname="SYNP15_1", key_method="rsa"
`pragma protect encoding = (enctype="BASE64", line_length=76, bytes=256)
`pragma protect key_block
jQK8ytCeXaD6r0UCS0369gNB1c1I5Crz7qiTz7NvzQ7G4991K0CEkqsDpyOEixILw9/5t88wZjkz
+A/duT8aBQVU9DV/WLUzweAhemIbjD68+bm+V4t8lkLMYutPA06XsXs4BTmspFsIBreaHJWVNywG
QniXAuR4oZalrLwMKanID/Q9V+RaQ5OJ7952Ao7W2EbOZNBsxY7ztswi0EZTn98jqBw8MaUw5TOE
sw/oUpGNMJuBAnuMapsYLbQTX1oSkkyBk0kIq8Oo+u+kcf8ZVMub5w4UT3MhapXf1VuQwhJppqOv
HLL4XdrXgdMJ6liiLGBoAb1KJuhfyvtTjsZcKg==

`pragma protect data_method = "AES128-CBC"
`pragma protect encoding = (enctype = "BASE64", line_length = 76, bytes = 2720)
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
`pragma protect encoding = (enctype = "BASE64", line_length = 76, bytes = 6800)
`pragma protect data_block
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
ccqzQA99nrEyrKFzTCEZ6Ag=
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
