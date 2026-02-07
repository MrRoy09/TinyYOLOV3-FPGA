// ==============================================================
// Vitis HLS - High-Level Synthesis from C, C++ and OpenCL v2025.1 (64-bit)
// Tool Version Limit: 2025.05
// Copyright 1986-2022 Xilinx, Inc. All Rights Reserved.
// Copyright 2022-2025 Advanced Micro Devices, Inc. All Rights Reserved.
// 
// ==============================================================
/***************************** Include Files *********************************/
#include "xtinyyolohw.h"

/************************** Function Implementation *************************/
#ifndef __linux__
int XTinyyolohw_CfgInitialize(XTinyyolohw *InstancePtr, XTinyyolohw_Config *ConfigPtr) {
    Xil_AssertNonvoid(InstancePtr != NULL);
    Xil_AssertNonvoid(ConfigPtr != NULL);

    InstancePtr->Control_BaseAddress = ConfigPtr->Control_BaseAddress;
    InstancePtr->IsReady = XIL_COMPONENT_IS_READY;

    return XST_SUCCESS;
}
#endif

void XTinyyolohw_Start(XTinyyolohw *InstancePtr) {
    u32 Data;

    Xil_AssertVoid(InstancePtr != NULL);
    Xil_AssertVoid(InstancePtr->IsReady == XIL_COMPONENT_IS_READY);

    Data = XTinyyolohw_ReadReg(InstancePtr->Control_BaseAddress, XTINYYOLOHW_CONTROL_ADDR_AP_CTRL) & 0x80;
    XTinyyolohw_WriteReg(InstancePtr->Control_BaseAddress, XTINYYOLOHW_CONTROL_ADDR_AP_CTRL, Data | 0x01);
}

u32 XTinyyolohw_IsDone(XTinyyolohw *InstancePtr) {
    u32 Data;

    Xil_AssertNonvoid(InstancePtr != NULL);
    Xil_AssertNonvoid(InstancePtr->IsReady == XIL_COMPONENT_IS_READY);

    Data = XTinyyolohw_ReadReg(InstancePtr->Control_BaseAddress, XTINYYOLOHW_CONTROL_ADDR_AP_CTRL);
    return (Data >> 1) & 0x1;
}

u32 XTinyyolohw_IsIdle(XTinyyolohw *InstancePtr) {
    u32 Data;

    Xil_AssertNonvoid(InstancePtr != NULL);
    Xil_AssertNonvoid(InstancePtr->IsReady == XIL_COMPONENT_IS_READY);

    Data = XTinyyolohw_ReadReg(InstancePtr->Control_BaseAddress, XTINYYOLOHW_CONTROL_ADDR_AP_CTRL);
    return (Data >> 2) & 0x1;
}

u32 XTinyyolohw_IsReady(XTinyyolohw *InstancePtr) {
    u32 Data;

    Xil_AssertNonvoid(InstancePtr != NULL);
    Xil_AssertNonvoid(InstancePtr->IsReady == XIL_COMPONENT_IS_READY);

    Data = XTinyyolohw_ReadReg(InstancePtr->Control_BaseAddress, XTINYYOLOHW_CONTROL_ADDR_AP_CTRL);
    // check ap_start to see if the pcore is ready for next input
    return !(Data & 0x1);
}

void XTinyyolohw_EnableAutoRestart(XTinyyolohw *InstancePtr) {
    Xil_AssertVoid(InstancePtr != NULL);
    Xil_AssertVoid(InstancePtr->IsReady == XIL_COMPONENT_IS_READY);

    XTinyyolohw_WriteReg(InstancePtr->Control_BaseAddress, XTINYYOLOHW_CONTROL_ADDR_AP_CTRL, 0x80);
}

void XTinyyolohw_DisableAutoRestart(XTinyyolohw *InstancePtr) {
    Xil_AssertVoid(InstancePtr != NULL);
    Xil_AssertVoid(InstancePtr->IsReady == XIL_COMPONENT_IS_READY);

    XTinyyolohw_WriteReg(InstancePtr->Control_BaseAddress, XTINYYOLOHW_CONTROL_ADDR_AP_CTRL, 0);
}

void XTinyyolohw_Set_img_width(XTinyyolohw *InstancePtr, u32 Data) {
    Xil_AssertVoid(InstancePtr != NULL);
    Xil_AssertVoid(InstancePtr->IsReady == XIL_COMPONENT_IS_READY);

    XTinyyolohw_WriteReg(InstancePtr->Control_BaseAddress, XTINYYOLOHW_CONTROL_ADDR_IMG_WIDTH_DATA, Data);
}

u32 XTinyyolohw_Get_img_width(XTinyyolohw *InstancePtr) {
    u32 Data;

    Xil_AssertNonvoid(InstancePtr != NULL);
    Xil_AssertNonvoid(InstancePtr->IsReady == XIL_COMPONENT_IS_READY);

    Data = XTinyyolohw_ReadReg(InstancePtr->Control_BaseAddress, XTINYYOLOHW_CONTROL_ADDR_IMG_WIDTH_DATA);
    return Data;
}

void XTinyyolohw_Set_in_channels(XTinyyolohw *InstancePtr, u32 Data) {
    Xil_AssertVoid(InstancePtr != NULL);
    Xil_AssertVoid(InstancePtr->IsReady == XIL_COMPONENT_IS_READY);

    XTinyyolohw_WriteReg(InstancePtr->Control_BaseAddress, XTINYYOLOHW_CONTROL_ADDR_IN_CHANNELS_DATA, Data);
}

u32 XTinyyolohw_Get_in_channels(XTinyyolohw *InstancePtr) {
    u32 Data;

    Xil_AssertNonvoid(InstancePtr != NULL);
    Xil_AssertNonvoid(InstancePtr->IsReady == XIL_COMPONENT_IS_READY);

    Data = XTinyyolohw_ReadReg(InstancePtr->Control_BaseAddress, XTINYYOLOHW_CONTROL_ADDR_IN_CHANNELS_DATA);
    return Data;
}

void XTinyyolohw_Set_out_channels(XTinyyolohw *InstancePtr, u32 Data) {
    Xil_AssertVoid(InstancePtr != NULL);
    Xil_AssertVoid(InstancePtr->IsReady == XIL_COMPONENT_IS_READY);

    XTinyyolohw_WriteReg(InstancePtr->Control_BaseAddress, XTINYYOLOHW_CONTROL_ADDR_OUT_CHANNELS_DATA, Data);
}

u32 XTinyyolohw_Get_out_channels(XTinyyolohw *InstancePtr) {
    u32 Data;

    Xil_AssertNonvoid(InstancePtr != NULL);
    Xil_AssertNonvoid(InstancePtr->IsReady == XIL_COMPONENT_IS_READY);

    Data = XTinyyolohw_ReadReg(InstancePtr->Control_BaseAddress, XTINYYOLOHW_CONTROL_ADDR_OUT_CHANNELS_DATA);
    return Data;
}

void XTinyyolohw_Set_quant_M(XTinyyolohw *InstancePtr, u32 Data) {
    Xil_AssertVoid(InstancePtr != NULL);
    Xil_AssertVoid(InstancePtr->IsReady == XIL_COMPONENT_IS_READY);

    XTinyyolohw_WriteReg(InstancePtr->Control_BaseAddress, XTINYYOLOHW_CONTROL_ADDR_QUANT_M_DATA, Data);
}

u32 XTinyyolohw_Get_quant_M(XTinyyolohw *InstancePtr) {
    u32 Data;

    Xil_AssertNonvoid(InstancePtr != NULL);
    Xil_AssertNonvoid(InstancePtr->IsReady == XIL_COMPONENT_IS_READY);

    Data = XTinyyolohw_ReadReg(InstancePtr->Control_BaseAddress, XTINYYOLOHW_CONTROL_ADDR_QUANT_M_DATA);
    return Data;
}

void XTinyyolohw_Set_quant_n(XTinyyolohw *InstancePtr, u32 Data) {
    Xil_AssertVoid(InstancePtr != NULL);
    Xil_AssertVoid(InstancePtr->IsReady == XIL_COMPONENT_IS_READY);

    XTinyyolohw_WriteReg(InstancePtr->Control_BaseAddress, XTINYYOLOHW_CONTROL_ADDR_QUANT_N_DATA, Data);
}

u32 XTinyyolohw_Get_quant_n(XTinyyolohw *InstancePtr) {
    u32 Data;

    Xil_AssertNonvoid(InstancePtr != NULL);
    Xil_AssertNonvoid(InstancePtr->IsReady == XIL_COMPONENT_IS_READY);

    Data = XTinyyolohw_ReadReg(InstancePtr->Control_BaseAddress, XTINYYOLOHW_CONTROL_ADDR_QUANT_N_DATA);
    return Data;
}

void XTinyyolohw_Set_isMaxpool(XTinyyolohw *InstancePtr, u32 Data) {
    Xil_AssertVoid(InstancePtr != NULL);
    Xil_AssertVoid(InstancePtr->IsReady == XIL_COMPONENT_IS_READY);

    XTinyyolohw_WriteReg(InstancePtr->Control_BaseAddress, XTINYYOLOHW_CONTROL_ADDR_ISMAXPOOL_DATA, Data);
}

u32 XTinyyolohw_Get_isMaxpool(XTinyyolohw *InstancePtr) {
    u32 Data;

    Xil_AssertNonvoid(InstancePtr != NULL);
    Xil_AssertNonvoid(InstancePtr->IsReady == XIL_COMPONENT_IS_READY);

    Data = XTinyyolohw_ReadReg(InstancePtr->Control_BaseAddress, XTINYYOLOHW_CONTROL_ADDR_ISMAXPOOL_DATA);
    return Data;
}

void XTinyyolohw_Set_is_1x1(XTinyyolohw *InstancePtr, u32 Data) {
    Xil_AssertVoid(InstancePtr != NULL);
    Xil_AssertVoid(InstancePtr->IsReady == XIL_COMPONENT_IS_READY);

    XTinyyolohw_WriteReg(InstancePtr->Control_BaseAddress, XTINYYOLOHW_CONTROL_ADDR_IS_1X1_DATA, Data);
}

u32 XTinyyolohw_Get_is_1x1(XTinyyolohw *InstancePtr) {
    u32 Data;

    Xil_AssertNonvoid(InstancePtr != NULL);
    Xil_AssertNonvoid(InstancePtr->IsReady == XIL_COMPONENT_IS_READY);

    Data = XTinyyolohw_ReadReg(InstancePtr->Control_BaseAddress, XTINYYOLOHW_CONTROL_ADDR_IS_1X1_DATA);
    return Data;
}

void XTinyyolohw_Set_stride(XTinyyolohw *InstancePtr, u32 Data) {
    Xil_AssertVoid(InstancePtr != NULL);
    Xil_AssertVoid(InstancePtr->IsReady == XIL_COMPONENT_IS_READY);

    XTinyyolohw_WriteReg(InstancePtr->Control_BaseAddress, XTINYYOLOHW_CONTROL_ADDR_STRIDE_DATA, Data);
}

u32 XTinyyolohw_Get_stride(XTinyyolohw *InstancePtr) {
    u32 Data;

    Xil_AssertNonvoid(InstancePtr != NULL);
    Xil_AssertNonvoid(InstancePtr->IsReady == XIL_COMPONENT_IS_READY);

    Data = XTinyyolohw_ReadReg(InstancePtr->Control_BaseAddress, XTINYYOLOHW_CONTROL_ADDR_STRIDE_DATA);
    return Data;
}

void XTinyyolohw_InterruptGlobalEnable(XTinyyolohw *InstancePtr) {
    Xil_AssertVoid(InstancePtr != NULL);
    Xil_AssertVoid(InstancePtr->IsReady == XIL_COMPONENT_IS_READY);

    XTinyyolohw_WriteReg(InstancePtr->Control_BaseAddress, XTINYYOLOHW_CONTROL_ADDR_GIE, 1);
}

void XTinyyolohw_InterruptGlobalDisable(XTinyyolohw *InstancePtr) {
    Xil_AssertVoid(InstancePtr != NULL);
    Xil_AssertVoid(InstancePtr->IsReady == XIL_COMPONENT_IS_READY);

    XTinyyolohw_WriteReg(InstancePtr->Control_BaseAddress, XTINYYOLOHW_CONTROL_ADDR_GIE, 0);
}

void XTinyyolohw_InterruptEnable(XTinyyolohw *InstancePtr, u32 Mask) {
    u32 Register;

    Xil_AssertVoid(InstancePtr != NULL);
    Xil_AssertVoid(InstancePtr->IsReady == XIL_COMPONENT_IS_READY);

    Register =  XTinyyolohw_ReadReg(InstancePtr->Control_BaseAddress, XTINYYOLOHW_CONTROL_ADDR_IER);
    XTinyyolohw_WriteReg(InstancePtr->Control_BaseAddress, XTINYYOLOHW_CONTROL_ADDR_IER, Register | Mask);
}

void XTinyyolohw_InterruptDisable(XTinyyolohw *InstancePtr, u32 Mask) {
    u32 Register;

    Xil_AssertVoid(InstancePtr != NULL);
    Xil_AssertVoid(InstancePtr->IsReady == XIL_COMPONENT_IS_READY);

    Register =  XTinyyolohw_ReadReg(InstancePtr->Control_BaseAddress, XTINYYOLOHW_CONTROL_ADDR_IER);
    XTinyyolohw_WriteReg(InstancePtr->Control_BaseAddress, XTINYYOLOHW_CONTROL_ADDR_IER, Register & (~Mask));
}

void XTinyyolohw_InterruptClear(XTinyyolohw *InstancePtr, u32 Mask) {
    Xil_AssertVoid(InstancePtr != NULL);
    Xil_AssertVoid(InstancePtr->IsReady == XIL_COMPONENT_IS_READY);

    XTinyyolohw_WriteReg(InstancePtr->Control_BaseAddress, XTINYYOLOHW_CONTROL_ADDR_ISR, Mask);
}

u32 XTinyyolohw_InterruptGetEnabled(XTinyyolohw *InstancePtr) {
    Xil_AssertNonvoid(InstancePtr != NULL);
    Xil_AssertNonvoid(InstancePtr->IsReady == XIL_COMPONENT_IS_READY);

    return XTinyyolohw_ReadReg(InstancePtr->Control_BaseAddress, XTINYYOLOHW_CONTROL_ADDR_IER);
}

u32 XTinyyolohw_InterruptGetStatus(XTinyyolohw *InstancePtr) {
    Xil_AssertNonvoid(InstancePtr != NULL);
    Xil_AssertNonvoid(InstancePtr->IsReady == XIL_COMPONENT_IS_READY);

    return XTinyyolohw_ReadReg(InstancePtr->Control_BaseAddress, XTINYYOLOHW_CONTROL_ADDR_ISR);
}

