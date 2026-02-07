// ==============================================================
// Vitis HLS - High-Level Synthesis from C, C++ and OpenCL v2025.1 (64-bit)
// Tool Version Limit: 2025.05
// Copyright 1986-2022 Xilinx, Inc. All Rights Reserved.
// Copyright 2022-2025 Advanced Micro Devices, Inc. All Rights Reserved.
// 
// ==============================================================
#ifndef __linux__

#include "xstatus.h"
#ifdef SDT
#include "xparameters.h"
#endif
#include "xtinyyolohw.h"

extern XTinyyolohw_Config XTinyyolohw_ConfigTable[];

#ifdef SDT
XTinyyolohw_Config *XTinyyolohw_LookupConfig(UINTPTR BaseAddress) {
	XTinyyolohw_Config *ConfigPtr = NULL;

	int Index;

	for (Index = (u32)0x0; XTinyyolohw_ConfigTable[Index].Name != NULL; Index++) {
		if (!BaseAddress || XTinyyolohw_ConfigTable[Index].Control_BaseAddress == BaseAddress) {
			ConfigPtr = &XTinyyolohw_ConfigTable[Index];
			break;
		}
	}

	return ConfigPtr;
}

int XTinyyolohw_Initialize(XTinyyolohw *InstancePtr, UINTPTR BaseAddress) {
	XTinyyolohw_Config *ConfigPtr;

	Xil_AssertNonvoid(InstancePtr != NULL);

	ConfigPtr = XTinyyolohw_LookupConfig(BaseAddress);
	if (ConfigPtr == NULL) {
		InstancePtr->IsReady = 0;
		return (XST_DEVICE_NOT_FOUND);
	}

	return XTinyyolohw_CfgInitialize(InstancePtr, ConfigPtr);
}
#else
XTinyyolohw_Config *XTinyyolohw_LookupConfig(u16 DeviceId) {
	XTinyyolohw_Config *ConfigPtr = NULL;

	int Index;

	for (Index = 0; Index < XPAR_XTINYYOLOHW_NUM_INSTANCES; Index++) {
		if (XTinyyolohw_ConfigTable[Index].DeviceId == DeviceId) {
			ConfigPtr = &XTinyyolohw_ConfigTable[Index];
			break;
		}
	}

	return ConfigPtr;
}

int XTinyyolohw_Initialize(XTinyyolohw *InstancePtr, u16 DeviceId) {
	XTinyyolohw_Config *ConfigPtr;

	Xil_AssertNonvoid(InstancePtr != NULL);

	ConfigPtr = XTinyyolohw_LookupConfig(DeviceId);
	if (ConfigPtr == NULL) {
		InstancePtr->IsReady = 0;
		return (XST_DEVICE_NOT_FOUND);
	}

	return XTinyyolohw_CfgInitialize(InstancePtr, ConfigPtr);
}
#endif

#endif

