; ModuleID = '/media/ubuntu/T7/projects/arm-bharat/TinyYOLOHW_ex/imports/hls/prj/sol/.autopilot/db/a.g.ld.5.gdce.bc'
source_filename = "llvm-link"
target datalayout = "e-m:e-i64:64-i128:128-i256:256-i512:512-i1024:1024-i2048:2048-i4096:4096-n8:16:32:64-S128-v16:16-v24:32-v32:32-v48:64-v96:128-v192:256-v256:256-v512:512-v1024:1024"
target triple = "fpga64-xilinx-none"

%"class.hls::stream<hls::axis<ap_uint<512>, 0, 0, 0, '8', false>, 0>" = type { %"struct.hls::axis<ap_uint<512>, 0, 0, 0, '8', false>" }
%"struct.hls::axis<ap_uint<512>, 0, 0, 0, '8', false>" = type { %"struct.ap_uint<512>", %"struct.ap_uint<64>", %"struct.ap_uint<64>", %"struct.hls::axis_disabled_signal", %"struct.ap_uint<1>", %"struct.hls::axis_disabled_signal", %"struct.hls::axis_disabled_signal" }
%"struct.ap_uint<512>" = type { %"struct.ap_int_base<512, false>" }
%"struct.ap_int_base<512, false>" = type { %"struct.ssdm_int<512, false>" }
%"struct.ssdm_int<512, false>" = type { i512 }
%"struct.ap_uint<64>" = type { %"struct.ap_int_base<64, false>" }
%"struct.ap_int_base<64, false>" = type { %"struct.ssdm_int<64, false>" }
%"struct.ssdm_int<64, false>" = type { i64 }
%"struct.ap_uint<1>" = type { %"struct.ap_int_base<1, false>" }
%"struct.ap_int_base<1, false>" = type { %"struct.ssdm_int<1, false>" }
%"struct.ssdm_int<1, false>" = type { i1 }
%"struct.hls::axis_disabled_signal" = type { i8 }

; Function Attrs: noinline willreturn
define void @apatb_TinyYOLOHW_ir(i32 %img_width, i32 %in_channels, i32 %out_channels, i32 %quant_M, i32 %quant_n, i1 zeroext %isMaxpool, i1 zeroext %is_1x1, i32 %stride, %"class.hls::stream<hls::axis<ap_uint<512>, 0, 0, 0, '8', false>, 0>"* noalias nonnull dereferenceable(128) %axi_in, %"class.hls::stream<hls::axis<ap_uint<512>, 0, 0, 0, '8', false>, 0>"* noalias nonnull dereferenceable(128) %axi_out) local_unnamed_addr #0 {
entry:
  %axi_in_copy.data = alloca i512, align 512
  %axi_in_copy.keep = alloca i64, align 512
  %axi_in_copy.strb = alloca i64, align 512
  %axi_in_copy.last = alloca i1, align 512
  %axi_out_copy.data = alloca i512, align 512
  %axi_out_copy.keep = alloca i64, align 512
  %axi_out_copy.strb = alloca i64, align 512
  %axi_out_copy.last = alloca i1, align 512
  call fastcc void @copy_in(%"class.hls::stream<hls::axis<ap_uint<512>, 0, 0, 0, '8', false>, 0>"* nonnull %axi_in, i512* nonnull align 512 %axi_in_copy.data, i64* nonnull align 512 %axi_in_copy.keep, i64* nonnull align 512 %axi_in_copy.strb, i1* nonnull align 512 %axi_in_copy.last, %"class.hls::stream<hls::axis<ap_uint<512>, 0, 0, 0, '8', false>, 0>"* nonnull %axi_out, i512* nonnull align 512 %axi_out_copy.data, i64* nonnull align 512 %axi_out_copy.keep, i64* nonnull align 512 %axi_out_copy.strb, i1* nonnull align 512 %axi_out_copy.last)
  call void @apatb_TinyYOLOHW_hw(i32 %img_width, i32 %in_channels, i32 %out_channels, i32 %quant_M, i32 %quant_n, i1 %isMaxpool, i1 %is_1x1, i32 %stride, i512* %axi_in_copy.data, i64* %axi_in_copy.keep, i64* %axi_in_copy.strb, i1* %axi_in_copy.last, i512* %axi_out_copy.data, i64* %axi_out_copy.keep, i64* %axi_out_copy.strb, i1* %axi_out_copy.last)
  call void @copy_back(%"class.hls::stream<hls::axis<ap_uint<512>, 0, 0, 0, '8', false>, 0>"* %axi_in, i512* %axi_in_copy.data, i64* %axi_in_copy.keep, i64* %axi_in_copy.strb, i1* %axi_in_copy.last, %"class.hls::stream<hls::axis<ap_uint<512>, 0, 0, 0, '8', false>, 0>"* %axi_out, i512* %axi_out_copy.data, i64* %axi_out_copy.keep, i64* %axi_out_copy.strb, i1* %axi_out_copy.last)
  ret void
}

; Function Attrs: argmemonly noinline willreturn
define internal fastcc void @copy_in(%"class.hls::stream<hls::axis<ap_uint<512>, 0, 0, 0, '8', false>, 0>"* noalias, i512* noalias align 512 "unpacked"="1.0" %_V_data_V, i64* noalias align 512 "unpacked"="1.1" %_V_keep_V, i64* noalias align 512 "unpacked"="1.2" %_V_strb_V, i1* noalias align 512 "unpacked"="1.3" %_V_last_V, %"class.hls::stream<hls::axis<ap_uint<512>, 0, 0, 0, '8', false>, 0>"* noalias, i512* noalias align 512 "unpacked"="3.0" %_V_data_V1, i64* noalias align 512 "unpacked"="3.1" %_V_keep_V2, i64* noalias align 512 "unpacked"="3.2" %_V_strb_V3, i1* noalias align 512 "unpacked"="3.3" %_V_last_V4) unnamed_addr #1 {
entry:
  call fastcc void @"onebyonecpy_hls.p0class.hls::stream<hls::axis<ap_uint<512>, 0, 0, 0, '8', false>, 0>.37"(i512* align 512 %_V_data_V, i64* align 512 %_V_keep_V, i64* align 512 %_V_strb_V, i1* align 512 %_V_last_V, %"class.hls::stream<hls::axis<ap_uint<512>, 0, 0, 0, '8', false>, 0>"* %0)
  call fastcc void @"onebyonecpy_hls.p0class.hls::stream<hls::axis<ap_uint<512>, 0, 0, 0, '8', false>, 0>.37"(i512* align 512 %_V_data_V1, i64* align 512 %_V_keep_V2, i64* align 512 %_V_strb_V3, i1* align 512 %_V_last_V4, %"class.hls::stream<hls::axis<ap_uint<512>, 0, 0, 0, '8', false>, 0>"* %1)
  ret void
}

; Function Attrs: argmemonly noinline willreturn
define internal fastcc void @copy_out(%"class.hls::stream<hls::axis<ap_uint<512>, 0, 0, 0, '8', false>, 0>"* noalias, i512* noalias align 512 "unpacked"="1.0" %_V_data_V, i64* noalias align 512 "unpacked"="1.1" %_V_keep_V, i64* noalias align 512 "unpacked"="1.2" %_V_strb_V, i1* noalias align 512 "unpacked"="1.3" %_V_last_V, %"class.hls::stream<hls::axis<ap_uint<512>, 0, 0, 0, '8', false>, 0>"* noalias, i512* noalias align 512 "unpacked"="3.0" %_V_data_V1, i64* noalias align 512 "unpacked"="3.1" %_V_keep_V2, i64* noalias align 512 "unpacked"="3.2" %_V_strb_V3, i1* noalias align 512 "unpacked"="3.3" %_V_last_V4) unnamed_addr #2 {
entry:
  call fastcc void @"onebyonecpy_hls.p0class.hls::stream<hls::axis<ap_uint<512>, 0, 0, 0, '8', false>, 0>"(%"class.hls::stream<hls::axis<ap_uint<512>, 0, 0, 0, '8', false>, 0>"* %0, i512* align 512 %_V_data_V, i64* align 512 %_V_keep_V, i64* align 512 %_V_strb_V, i1* align 512 %_V_last_V)
  call fastcc void @"onebyonecpy_hls.p0class.hls::stream<hls::axis<ap_uint<512>, 0, 0, 0, '8', false>, 0>"(%"class.hls::stream<hls::axis<ap_uint<512>, 0, 0, 0, '8', false>, 0>"* %1, i512* align 512 %_V_data_V1, i64* align 512 %_V_keep_V2, i64* align 512 %_V_strb_V3, i1* align 512 %_V_last_V4)
  ret void
}

; Function Attrs: argmemonly noinline willreturn
define internal fastcc void @"onebyonecpy_hls.p0class.hls::stream<hls::axis<ap_uint<512>, 0, 0, 0, '8', false>, 0>"(%"class.hls::stream<hls::axis<ap_uint<512>, 0, 0, 0, '8', false>, 0>"* noalias %dst, i512* noalias align 512 "unpacked"="1.0" %src_V_data_V, i64* noalias align 512 "unpacked"="1.1" %src_V_keep_V, i64* noalias align 512 "unpacked"="1.2" %src_V_strb_V, i1* noalias align 512 "unpacked"="1.3" %src_V_last_V) unnamed_addr #3 {
entry:
  %0 = icmp eq %"class.hls::stream<hls::axis<ap_uint<512>, 0, 0, 0, '8', false>, 0>"* %dst, null
  br i1 %0, label %ret, label %copy

copy:                                             ; preds = %entry
  call fastcc void @"streamcpy_hls.p0class.hls::stream<hls::axis<ap_uint<512>, 0, 0, 0, '8', false>, 0>.32"(%"class.hls::stream<hls::axis<ap_uint<512>, 0, 0, 0, '8', false>, 0>"* nonnull %dst, i512* align 512 %src_V_data_V, i64* align 512 %src_V_keep_V, i64* align 512 %src_V_strb_V, i1* align 512 %src_V_last_V)
  br label %ret

ret:                                              ; preds = %copy, %entry
  ret void
}

; Function Attrs: argmemonly noinline willreturn
define internal fastcc void @"streamcpy_hls.p0class.hls::stream<hls::axis<ap_uint<512>, 0, 0, 0, '8', false>, 0>.32"(%"class.hls::stream<hls::axis<ap_uint<512>, 0, 0, 0, '8', false>, 0>"* noalias nocapture, i512* noalias nocapture align 512 "unpacked"="1.0" %_V_data_V, i64* noalias nocapture align 512 "unpacked"="1.1" %_V_keep_V, i64* noalias nocapture align 512 "unpacked"="1.2" %_V_strb_V, i1* noalias nocapture align 512 "unpacked"="1.3" %_V_last_V) unnamed_addr #4 {
entry:
  %1 = alloca i512
  %2 = alloca i64
  %3 = alloca i64
  %4 = alloca i1
  %5 = alloca %"class.hls::stream<hls::axis<ap_uint<512>, 0, 0, 0, '8', false>, 0>"
  br label %empty

empty:                                            ; preds = %push, %entry
  %6 = bitcast i512* %_V_data_V to i8*
  %7 = call i1 @fpga_fifo_not_empty_64(i8* %6)
  br i1 %7, label %push, label %ret

push:                                             ; preds = %empty
  %8 = bitcast i512* %1 to i8*
  %9 = bitcast i512* %_V_data_V to i8*
  call void @fpga_fifo_pop_64(i8* %8, i8* %9)
  %10 = load volatile i512, i512* %1
  %11 = bitcast i64* %3 to i8*
  %12 = bitcast i64* %_V_keep_V to i8*
  call void @fpga_fifo_pop_8(i8* %11, i8* %12)
  %13 = load volatile i64, i64* %3
  %14 = bitcast i64* %2 to i8*
  %15 = bitcast i64* %_V_strb_V to i8*
  call void @fpga_fifo_pop_8(i8* %14, i8* %15)
  %16 = load volatile i64, i64* %2
  %17 = bitcast i1* %4 to i8*
  %18 = bitcast i1* %_V_last_V to i8*
  call void @fpga_fifo_pop_1(i8* %17, i8* %18)
  %19 = bitcast i1* %4 to i8*
  %20 = load i8, i8* %19
  %21 = trunc i8 %20 to i1
  %.fca.0.0.0.0.0.insert = insertvalue %"class.hls::stream<hls::axis<ap_uint<512>, 0, 0, 0, '8', false>, 0>" undef, i512 %10, 0, 0, 0, 0, 0
  %.fca.0.1.0.0.0.insert = insertvalue %"class.hls::stream<hls::axis<ap_uint<512>, 0, 0, 0, '8', false>, 0>" %.fca.0.0.0.0.0.insert, i64 %13, 0, 1, 0, 0, 0
  %.fca.0.2.0.0.0.insert = insertvalue %"class.hls::stream<hls::axis<ap_uint<512>, 0, 0, 0, '8', false>, 0>" %.fca.0.1.0.0.0.insert, i64 %16, 0, 2, 0, 0, 0
  %.fca.0.4.0.0.0.insert = insertvalue %"class.hls::stream<hls::axis<ap_uint<512>, 0, 0, 0, '8', false>, 0>" %.fca.0.2.0.0.0.insert, i1 %21, 0, 4, 0, 0, 0
  store %"class.hls::stream<hls::axis<ap_uint<512>, 0, 0, 0, '8', false>, 0>" %.fca.0.4.0.0.0.insert, %"class.hls::stream<hls::axis<ap_uint<512>, 0, 0, 0, '8', false>, 0>"* %5
  %22 = bitcast %"class.hls::stream<hls::axis<ap_uint<512>, 0, 0, 0, '8', false>, 0>"* %5 to i8*
  %23 = bitcast %"class.hls::stream<hls::axis<ap_uint<512>, 0, 0, 0, '8', false>, 0>"* %0 to i8*
  call void @fpga_fifo_push_128(i8* %22, i8* %23)
  br label %empty, !llvm.loop !5

ret:                                              ; preds = %empty
  ret void
}

; Function Attrs: argmemonly noinline willreturn
define internal fastcc void @"onebyonecpy_hls.p0class.hls::stream<hls::axis<ap_uint<512>, 0, 0, 0, '8', false>, 0>.37"(i512* noalias align 512 "unpacked"="0.0" %dst_V_data_V, i64* noalias align 512 "unpacked"="0.1" %dst_V_keep_V, i64* noalias align 512 "unpacked"="0.2" %dst_V_strb_V, i1* noalias align 512 "unpacked"="0.3" %dst_V_last_V, %"class.hls::stream<hls::axis<ap_uint<512>, 0, 0, 0, '8', false>, 0>"* noalias %src) unnamed_addr #3 {
entry:
  %0 = icmp eq %"class.hls::stream<hls::axis<ap_uint<512>, 0, 0, 0, '8', false>, 0>"* %src, null
  br i1 %0, label %ret, label %copy

copy:                                             ; preds = %entry
  call fastcc void @"streamcpy_hls.p0class.hls::stream<hls::axis<ap_uint<512>, 0, 0, 0, '8', false>, 0>.40"(i512* align 512 %dst_V_data_V, i64* align 512 %dst_V_keep_V, i64* align 512 %dst_V_strb_V, i1* align 512 %dst_V_last_V, %"class.hls::stream<hls::axis<ap_uint<512>, 0, 0, 0, '8', false>, 0>"* nonnull %src)
  br label %ret

ret:                                              ; preds = %copy, %entry
  ret void
}

; Function Attrs: argmemonly noinline willreturn
define internal fastcc void @"streamcpy_hls.p0class.hls::stream<hls::axis<ap_uint<512>, 0, 0, 0, '8', false>, 0>.40"(i512* noalias nocapture align 512 "unpacked"="0.0" %_V_data_V, i64* noalias nocapture align 512 "unpacked"="0.1" %_V_keep_V, i64* noalias nocapture align 512 "unpacked"="0.2" %_V_strb_V, i1* noalias nocapture align 512 "unpacked"="0.3" %_V_last_V, %"class.hls::stream<hls::axis<ap_uint<512>, 0, 0, 0, '8', false>, 0>"* noalias nocapture) unnamed_addr #4 {
entry:
  %1 = alloca %"class.hls::stream<hls::axis<ap_uint<512>, 0, 0, 0, '8', false>, 0>"
  %2 = alloca i512
  %3 = alloca i64
  %4 = alloca i64
  %5 = alloca i1
  br label %empty

empty:                                            ; preds = %push, %entry
  %6 = bitcast %"class.hls::stream<hls::axis<ap_uint<512>, 0, 0, 0, '8', false>, 0>"* %0 to i8*
  %7 = call i1 @fpga_fifo_not_empty_128(i8* %6)
  br i1 %7, label %push, label %ret

push:                                             ; preds = %empty
  %8 = bitcast %"class.hls::stream<hls::axis<ap_uint<512>, 0, 0, 0, '8', false>, 0>"* %1 to i8*
  %9 = bitcast %"class.hls::stream<hls::axis<ap_uint<512>, 0, 0, 0, '8', false>, 0>"* %0 to i8*
  call void @fpga_fifo_pop_128(i8* %8, i8* %9)
  %10 = load volatile %"class.hls::stream<hls::axis<ap_uint<512>, 0, 0, 0, '8', false>, 0>", %"class.hls::stream<hls::axis<ap_uint<512>, 0, 0, 0, '8', false>, 0>"* %1
  %.fca.0.0.0.0.0.extract = extractvalue %"class.hls::stream<hls::axis<ap_uint<512>, 0, 0, 0, '8', false>, 0>" %10, 0, 0, 0, 0, 0
  %.fca.0.1.0.0.0.extract = extractvalue %"class.hls::stream<hls::axis<ap_uint<512>, 0, 0, 0, '8', false>, 0>" %10, 0, 1, 0, 0, 0
  %.fca.0.2.0.0.0.extract = extractvalue %"class.hls::stream<hls::axis<ap_uint<512>, 0, 0, 0, '8', false>, 0>" %10, 0, 2, 0, 0, 0
  %.fca.0.4.0.0.0.extract = extractvalue %"class.hls::stream<hls::axis<ap_uint<512>, 0, 0, 0, '8', false>, 0>" %10, 0, 4, 0, 0, 0
  store i512 %.fca.0.0.0.0.0.extract, i512* %2
  %11 = bitcast i512* %2 to i8*
  %12 = bitcast i512* %_V_data_V to i8*
  call void @fpga_fifo_push_64(i8* %11, i8* %12)
  store i64 %.fca.0.1.0.0.0.extract, i64* %4
  %13 = bitcast i64* %4 to i8*
  %14 = bitcast i64* %_V_keep_V to i8*
  call void @fpga_fifo_push_8(i8* %13, i8* %14)
  store i64 %.fca.0.2.0.0.0.extract, i64* %3
  %15 = bitcast i64* %3 to i8*
  %16 = bitcast i64* %_V_strb_V to i8*
  call void @fpga_fifo_push_8(i8* %15, i8* %16)
  store i1 %.fca.0.4.0.0.0.extract, i1* %5
  %17 = bitcast i1* %5 to i8*
  %18 = bitcast i1* %_V_last_V to i8*
  call void @fpga_fifo_push_1(i8* %17, i8* %18)
  br label %empty, !llvm.loop !5

ret:                                              ; preds = %empty
  ret void
}

declare i8* @malloc(i64)

declare void @free(i8*)

declare void @apatb_TinyYOLOHW_hw(i32, i32, i32, i32, i32, i1, i1, i32, i512*, i64*, i64*, i1*, i512*, i64*, i64*, i1*)

; Function Attrs: argmemonly noinline willreturn
define internal fastcc void @copy_back(%"class.hls::stream<hls::axis<ap_uint<512>, 0, 0, 0, '8', false>, 0>"* noalias, i512* noalias align 512 "unpacked"="1.0" %_V_data_V, i64* noalias align 512 "unpacked"="1.1" %_V_keep_V, i64* noalias align 512 "unpacked"="1.2" %_V_strb_V, i1* noalias align 512 "unpacked"="1.3" %_V_last_V, %"class.hls::stream<hls::axis<ap_uint<512>, 0, 0, 0, '8', false>, 0>"* noalias, i512* noalias align 512 "unpacked"="3.0" %_V_data_V1, i64* noalias align 512 "unpacked"="3.1" %_V_keep_V2, i64* noalias align 512 "unpacked"="3.2" %_V_strb_V3, i1* noalias align 512 "unpacked"="3.3" %_V_last_V4) unnamed_addr #2 {
entry:
  call fastcc void @"onebyonecpy_hls.p0class.hls::stream<hls::axis<ap_uint<512>, 0, 0, 0, '8', false>, 0>"(%"class.hls::stream<hls::axis<ap_uint<512>, 0, 0, 0, '8', false>, 0>"* %0, i512* align 512 %_V_data_V, i64* align 512 %_V_keep_V, i64* align 512 %_V_strb_V, i1* align 512 %_V_last_V)
  call fastcc void @"onebyonecpy_hls.p0class.hls::stream<hls::axis<ap_uint<512>, 0, 0, 0, '8', false>, 0>"(%"class.hls::stream<hls::axis<ap_uint<512>, 0, 0, 0, '8', false>, 0>"* %1, i512* align 512 %_V_data_V1, i64* align 512 %_V_keep_V2, i64* align 512 %_V_strb_V3, i1* align 512 %_V_last_V4)
  ret void
}

declare void @TinyYOLOHW_hw_stub(i32, i32, i32, i32, i32, i1 zeroext, i1 zeroext, i32, %"class.hls::stream<hls::axis<ap_uint<512>, 0, 0, 0, '8', false>, 0>"* noalias nonnull, %"class.hls::stream<hls::axis<ap_uint<512>, 0, 0, 0, '8', false>, 0>"* noalias nonnull)

define void @TinyYOLOHW_hw_stub_wrapper(i32, i32, i32, i32, i32, i1, i1, i32, i512*, i64*, i64*, i1*, i512*, i64*, i64*, i1*) #5 {
entry:
  %16 = call i8* @malloc(i64 128)
  %17 = bitcast i8* %16 to %"class.hls::stream<hls::axis<ap_uint<512>, 0, 0, 0, '8', false>, 0>"*
  %18 = call i8* @malloc(i64 128)
  %19 = bitcast i8* %18 to %"class.hls::stream<hls::axis<ap_uint<512>, 0, 0, 0, '8', false>, 0>"*
  call void @copy_out(%"class.hls::stream<hls::axis<ap_uint<512>, 0, 0, 0, '8', false>, 0>"* %17, i512* %8, i64* %9, i64* %10, i1* %11, %"class.hls::stream<hls::axis<ap_uint<512>, 0, 0, 0, '8', false>, 0>"* %19, i512* %12, i64* %13, i64* %14, i1* %15)
  call void @TinyYOLOHW_hw_stub(i32 %0, i32 %1, i32 %2, i32 %3, i32 %4, i1 %5, i1 %6, i32 %7, %"class.hls::stream<hls::axis<ap_uint<512>, 0, 0, 0, '8', false>, 0>"* %17, %"class.hls::stream<hls::axis<ap_uint<512>, 0, 0, 0, '8', false>, 0>"* %19)
  call void @copy_in(%"class.hls::stream<hls::axis<ap_uint<512>, 0, 0, 0, '8', false>, 0>"* %17, i512* %8, i64* %9, i64* %10, i1* %11, %"class.hls::stream<hls::axis<ap_uint<512>, 0, 0, 0, '8', false>, 0>"* %19, i512* %12, i64* %13, i64* %14, i1* %15)
  call void @free(i8* %16)
  call void @free(i8* %18)
  ret void
}

declare i1 @fpga_fifo_not_empty_128(i8*)

declare i1 @fpga_fifo_not_empty_64(i8*)

declare void @fpga_fifo_pop_128(i8*, i8*)

declare void @fpga_fifo_pop_64(i8*, i8*)

declare void @fpga_fifo_pop_8(i8*, i8*)

declare void @fpga_fifo_pop_1(i8*, i8*)

declare void @fpga_fifo_push_128(i8*, i8*)

declare void @fpga_fifo_push_64(i8*, i8*)

declare void @fpga_fifo_push_8(i8*, i8*)

declare void @fpga_fifo_push_1(i8*, i8*)

attributes #0 = { noinline willreturn "fpga.wrapper.func"="wrapper" }
attributes #1 = { argmemonly noinline willreturn "fpga.wrapper.func"="copyin" }
attributes #2 = { argmemonly noinline willreturn "fpga.wrapper.func"="copyout" }
attributes #3 = { argmemonly noinline willreturn "fpga.wrapper.func"="onebyonecpy_hls" }
attributes #4 = { argmemonly noinline willreturn "fpga.wrapper.func"="streamcpy_hls" }
attributes #5 = { "fpga.wrapper.func"="stub" }

!llvm.dbg.cu = !{}
!llvm.ident = !{!0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0, !0}
!llvm.module.flags = !{!1, !2, !3}
!blackbox_cfg = !{!4}

!0 = !{!"clang version 7.0.0 "}
!1 = !{i32 2, !"Dwarf Version", i32 4}
!2 = !{i32 2, !"Debug Info Version", i32 3}
!3 = !{i32 1, !"wchar_size", i32 4}
!4 = !{}
!5 = distinct !{!5, !6}
!6 = !{!"llvm.loop.rotate.disable"}
