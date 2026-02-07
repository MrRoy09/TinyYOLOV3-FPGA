// 0x00 : Control signals
//        bit 0  - ap_start (Read/Write/COH)
//        bit 1  - ap_done (Read/COR)
//        bit 2  - ap_idle (Read)
//        bit 3  - ap_ready (Read/COR)
//        bit 7  - auto_restart (Read/Write)
//        bit 9  - interrupt (Read)
//        others - reserved
// 0x04 : Global Interrupt Enable Register
//        bit 0  - Global Interrupt Enable (Read/Write)
//        others - reserved
// 0x08 : IP Interrupt Enable Register (Read/Write)
//        bit 0 - enable ap_done interrupt (Read/Write)
//        bit 1 - enable ap_ready interrupt (Read/Write)
//        others - reserved
// 0x0c : IP Interrupt Status Register (Read/TOW)
//        bit 0 - ap_done (Read/TOW)
//        bit 1 - ap_ready (Read/TOW)
//        others - reserved
// 0x10 : Data signal of img_width
//        bit 31~0 - img_width[31:0] (Read/Write)
// 0x14 : reserved
// 0x18 : Data signal of in_channels
//        bit 31~0 - in_channels[31:0] (Read/Write)
// 0x1c : reserved
// 0x20 : Data signal of out_channels
//        bit 31~0 - out_channels[31:0] (Read/Write)
// 0x24 : reserved
// 0x28 : Data signal of quant_M
//        bit 31~0 - quant_M[31:0] (Read/Write)
// 0x2c : reserved
// 0x30 : Data signal of quant_n
//        bit 31~0 - quant_n[31:0] (Read/Write)
// 0x34 : reserved
// 0x38 : Data signal of isMaxpool
//        bit 0  - isMaxpool[0] (Read/Write)
//        others - reserved
// 0x3c : reserved
// 0x40 : Data signal of is_1x1
//        bit 0  - is_1x1[0] (Read/Write)
//        others - reserved
// 0x44 : reserved
// 0x48 : Data signal of stride
//        bit 31~0 - stride[31:0] (Read/Write)
// 0x4c : reserved
// (SC = Self Clear, COR = Clear on Read, TOW = Toggle on Write, COH = Clear on Handshake)

#define CONTROL_ADDR_AP_CTRL           0x00
#define CONTROL_ADDR_GIE               0x04
#define CONTROL_ADDR_IER               0x08
#define CONTROL_ADDR_ISR               0x0c
#define CONTROL_ADDR_IMG_WIDTH_DATA    0x10
#define CONTROL_BITS_IMG_WIDTH_DATA    32
#define CONTROL_ADDR_IN_CHANNELS_DATA  0x18
#define CONTROL_BITS_IN_CHANNELS_DATA  32
#define CONTROL_ADDR_OUT_CHANNELS_DATA 0x20
#define CONTROL_BITS_OUT_CHANNELS_DATA 32
#define CONTROL_ADDR_QUANT_M_DATA      0x28
#define CONTROL_BITS_QUANT_M_DATA      32
#define CONTROL_ADDR_QUANT_N_DATA      0x30
#define CONTROL_BITS_QUANT_N_DATA      32
#define CONTROL_ADDR_ISMAXPOOL_DATA    0x38
#define CONTROL_BITS_ISMAXPOOL_DATA    1
#define CONTROL_ADDR_IS_1X1_DATA       0x40
#define CONTROL_BITS_IS_1X1_DATA       1
#define CONTROL_ADDR_STRIDE_DATA       0x48
#define CONTROL_BITS_STRIDE_DATA       32
