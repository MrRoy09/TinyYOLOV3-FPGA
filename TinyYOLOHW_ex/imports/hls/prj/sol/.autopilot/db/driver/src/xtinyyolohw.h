// ==============================================================
// Vitis HLS - High-Level Synthesis from C, C++ and OpenCL v2025.1 (64-bit)
// Tool Version Limit: 2025.05
// Copyright 1986-2022 Xilinx, Inc. All Rights Reserved.
// Copyright 2022-2025 Advanced Micro Devices, Inc. All Rights Reserved.
// 
// ==============================================================
#ifndef XTINYYOLOHW_H
#define XTINYYOLOHW_H

#ifdef __cplusplus
extern "C" {
#endif

/***************************** Include Files *********************************/
#ifndef __linux__
#include "xil_types.h"
#include "xil_assert.h"
#include "xstatus.h"
#include "xil_io.h"
#else
#include <stdint.h>
#include <assert.h>
#include <dirent.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <unistd.h>
#include <stddef.h>
#endif
#include "xtinyyolohw_hw.h"

/**************************** Type Definitions ******************************/
#ifdef __linux__
typedef uint8_t u8;
typedef uint16_t u16;
typedef uint32_t u32;
typedef uint64_t u64;
#else
typedef struct {
#ifdef SDT
    char *Name;
#else
    u16 DeviceId;
#endif
    u64 Control_BaseAddress;
} XTinyyolohw_Config;
#endif

typedef struct {
    u64 Control_BaseAddress;
    u32 IsReady;
} XTinyyolohw;

typedef u32 word_type;

/***************** Macros (Inline Functions) Definitions *********************/
#ifndef __linux__
#define XTinyyolohw_WriteReg(BaseAddress, RegOffset, Data) \
    Xil_Out32((BaseAddress) + (RegOffset), (u32)(Data))
#define XTinyyolohw_ReadReg(BaseAddress, RegOffset) \
    Xil_In32((BaseAddress) + (RegOffset))
#else
#define XTinyyolohw_WriteReg(BaseAddress, RegOffset, Data) \
    *(volatile u32*)((BaseAddress) + (RegOffset)) = (u32)(Data)
#define XTinyyolohw_ReadReg(BaseAddress, RegOffset) \
    *(volatile u32*)((BaseAddress) + (RegOffset))

#define Xil_AssertVoid(expr)    assert(expr)
#define Xil_AssertNonvoid(expr) assert(expr)

#define XST_SUCCESS             0
#define XST_DEVICE_NOT_FOUND    2
#define XST_OPEN_DEVICE_FAILED  3
#define XIL_COMPONENT_IS_READY  1
#endif

/************************** Function Prototypes *****************************/
#ifndef __linux__
#ifdef SDT
int XTinyyolohw_Initialize(XTinyyolohw *InstancePtr, UINTPTR BaseAddress);
XTinyyolohw_Config* XTinyyolohw_LookupConfig(UINTPTR BaseAddress);
#else
int XTinyyolohw_Initialize(XTinyyolohw *InstancePtr, u16 DeviceId);
XTinyyolohw_Config* XTinyyolohw_LookupConfig(u16 DeviceId);
#endif
int XTinyyolohw_CfgInitialize(XTinyyolohw *InstancePtr, XTinyyolohw_Config *ConfigPtr);
#else
int XTinyyolohw_Initialize(XTinyyolohw *InstancePtr, const char* InstanceName);
int XTinyyolohw_Release(XTinyyolohw *InstancePtr);
#endif

void XTinyyolohw_Start(XTinyyolohw *InstancePtr);
u32 XTinyyolohw_IsDone(XTinyyolohw *InstancePtr);
u32 XTinyyolohw_IsIdle(XTinyyolohw *InstancePtr);
u32 XTinyyolohw_IsReady(XTinyyolohw *InstancePtr);
void XTinyyolohw_EnableAutoRestart(XTinyyolohw *InstancePtr);
void XTinyyolohw_DisableAutoRestart(XTinyyolohw *InstancePtr);

void XTinyyolohw_Set_img_width(XTinyyolohw *InstancePtr, u32 Data);
u32 XTinyyolohw_Get_img_width(XTinyyolohw *InstancePtr);
void XTinyyolohw_Set_in_channels(XTinyyolohw *InstancePtr, u32 Data);
u32 XTinyyolohw_Get_in_channels(XTinyyolohw *InstancePtr);
void XTinyyolohw_Set_out_channels(XTinyyolohw *InstancePtr, u32 Data);
u32 XTinyyolohw_Get_out_channels(XTinyyolohw *InstancePtr);
void XTinyyolohw_Set_quant_M(XTinyyolohw *InstancePtr, u32 Data);
u32 XTinyyolohw_Get_quant_M(XTinyyolohw *InstancePtr);
void XTinyyolohw_Set_quant_n(XTinyyolohw *InstancePtr, u32 Data);
u32 XTinyyolohw_Get_quant_n(XTinyyolohw *InstancePtr);
void XTinyyolohw_Set_isMaxpool(XTinyyolohw *InstancePtr, u32 Data);
u32 XTinyyolohw_Get_isMaxpool(XTinyyolohw *InstancePtr);
void XTinyyolohw_Set_is_1x1(XTinyyolohw *InstancePtr, u32 Data);
u32 XTinyyolohw_Get_is_1x1(XTinyyolohw *InstancePtr);
void XTinyyolohw_Set_stride(XTinyyolohw *InstancePtr, u32 Data);
u32 XTinyyolohw_Get_stride(XTinyyolohw *InstancePtr);

void XTinyyolohw_InterruptGlobalEnable(XTinyyolohw *InstancePtr);
void XTinyyolohw_InterruptGlobalDisable(XTinyyolohw *InstancePtr);
void XTinyyolohw_InterruptEnable(XTinyyolohw *InstancePtr, u32 Mask);
void XTinyyolohw_InterruptDisable(XTinyyolohw *InstancePtr, u32 Mask);
void XTinyyolohw_InterruptClear(XTinyyolohw *InstancePtr, u32 Mask);
u32 XTinyyolohw_InterruptGetEnabled(XTinyyolohw *InstancePtr);
u32 XTinyyolohw_InterruptGetStatus(XTinyyolohw *InstancePtr);

#ifdef __cplusplus
}
#endif

#endif
