// Windows Imaging Component 的手写 FFI 绑定。
//
// 为什么不用 package:win32：6.x 精简了 COM 表面，完全没有 WIC 接口。
// 手写反而更可控，且不引入额外依赖。
//
// 全部 vtable 序号来自 WIC 头文件的接口继承顺序：
// IUnknown 占 0..2 (QueryInterface / AddRef / Release)，派生接口从 3 开始。
import 'dart:ffi';

import 'package:ffi/ffi.dart';

// ---------------------------------------------------------------------------
// GUID
// ---------------------------------------------------------------------------

final class GUID extends Struct {
  @Uint32()
  external int data1;
  @Uint16()
  external int data2;
  @Uint16()
  external int data3;
  @Array<Uint8>(8)
  external Array<Uint8> data4;
}

/// 从 "CACAF262-9370-4615-A13B-9F5539DA4C0A" 形式填一个 GUID
Pointer<GUID> allocGuid(String s, Allocator alloc) {
  final p = alloc<GUID>();
  final t = s.replaceAll('{', '').replaceAll('}', '').replaceAll('-', '');
  p.ref.data1 = int.parse(t.substring(0, 8), radix: 16);
  p.ref.data2 = int.parse(t.substring(8, 12), radix: 16);
  p.ref.data3 = int.parse(t.substring(12, 16), radix: 16);
  for (var i = 0; i < 8; i++) {
    p.ref.data4[i] = int.parse(t.substring(16 + i * 2, 18 + i * 2), radix: 16);
  }
  return p;
}

bool guidEquals(Pointer<GUID> a, Pointer<GUID> b) {
  if (a.ref.data1 != b.ref.data1) return false;
  if (a.ref.data2 != b.ref.data2) return false;
  if (a.ref.data3 != b.ref.data3) return false;
  for (var i = 0; i < 8; i++) {
    if (a.ref.data4[i] != b.ref.data4[i]) return false;
  }
  return true;
}

// ---------------------------------------------------------------------------
// 常量
// ---------------------------------------------------------------------------

const clsidWICImagingFactory = 'CACAF262-9370-4615-A13B-9F5539DA4C0A';
const iidWICImagingFactory = 'EC5EC8A9-C395-4314-9C77-54D7A935FF70';

/// 注意：3B16811B-6A43-4EC9-**A813-3D93**0C13B940 是 IWICBitmapFrameDecode，
/// 长得极像，用错了 QI 会成功并返回 frame 自己，导致 slot 4 变成
/// GetPixelFormat，往 4 字节的 out 参数里写 16 字节 GUID → 堆损坏。
const iidWICBitmapSourceTransform = '3B16811B-6A43-4EC9-B713-3D5A0C13B940';
const iidWICBitmapDecoderInfo = 'D8CD007F-D08F-4191-9BFC-236EA7F0E4B5';

/// 32bppPBGRA：B,G,R,A + 预乘 alpha，正好对上 Skia 的 kPremul + BGRA
const guidWICPixelFormat32bppPBGRA = '6FDDC324-4E03-4BFE-B185-3D77768DC910';

const int sOk = 0;
const int clsctxInprocServer = 0x1;
const int coinitMultithreaded = 0x0;
const int coinitApartmentthreaded = 0x2;
const int genericRead = 0x80000000;

/// WICDecodeMetadataCacheOnDemand
const int wicDecodeMetadataCacheOnDemand = 0;

/// WICBitmapInterpolationModeFant：缩小质量最好的那个
const int wicInterpolationFant = 3;
const int wicDitherTypeNone = 0;
const int wicPaletteTypeCustom = 0;
const int wicBitmapTransformRotate0 = 0;

/// WICComponentType.WICDecoder
const int wicComponentDecoder = 0x1;

// ---------------------------------------------------------------------------
// ole32 导出
// ---------------------------------------------------------------------------

final DynamicLibrary _ole32 = DynamicLibrary.open('ole32.dll');

final int Function(Pointer<Void>, int) coInitializeEx = _ole32
    .lookupFunction<
      Int32 Function(Pointer<Void>, Uint32),
      int Function(Pointer<Void>, int)
    >('CoInitializeEx');

final void Function() coUninitialize = _ole32
    .lookupFunction<Void Function(), void Function()>('CoUninitialize');

final int Function(
  Pointer<GUID>,
  Pointer<Void>,
  int,
  Pointer<GUID>,
  Pointer<Pointer<Void>>,
)
coCreateInstance = _ole32
    .lookupFunction<
      Int32 Function(
        Pointer<GUID>,
        Pointer<Void>,
        Uint32,
        Pointer<GUID>,
        Pointer<Pointer<Void>>,
      ),
      int Function(
        Pointer<GUID>,
        Pointer<Void>,
        int,
        Pointer<GUID>,
        Pointer<Pointer<Void>>,
      )
    >('CoCreateInstance');

final int Function(Pointer<Void>) propVariantClear = _ole32
    .lookupFunction<Int32 Function(Pointer<Void>), int Function(Pointer<Void>)>(
      'PropVariantClear',
    );

// ---------------------------------------------------------------------------
// vtable 调用辅助
// ---------------------------------------------------------------------------

/// 取接口指针 [obj] 的 vtable 第 [index] 项函数地址
Pointer<Void> _slot(Pointer<Void> obj, int index) {
  final vtbl = obj.cast<Pointer<Pointer<Void>>>().value;
  return vtbl[index];
}

typedef _QueryInterfaceNative = Int32 Function(
  Pointer<Void>,
  Pointer<GUID>,
  Pointer<Pointer<Void>>,
);
typedef _RefNative = Int32 Function(Pointer<Void>);

int comQueryInterface(
  Pointer<Void> obj,
  Pointer<GUID> iid,
  Pointer<Pointer<Void>> out,
) => _slot(obj, 0)
    .cast<NativeFunction<_QueryInterfaceNative>>()
    .asFunction<
      int Function(Pointer<Void>, Pointer<GUID>, Pointer<Pointer<Void>>)
    >()(obj, iid, out);

int comRelease(Pointer<Void> obj) {
  if (obj == nullptr) return 0;
  return _slot(obj, 2)
      .cast<NativeFunction<_RefNative>>()
      .asFunction<int Function(Pointer<Void>)>()(obj);
}

// ---------------------------------------------------------------------------
// IWICImagingFactory
// ---------------------------------------------------------------------------

typedef _CreateDecoderFromFilenameNative = Int32 Function(
  Pointer<Void> self,
  Pointer<Utf16> filename,
  Pointer<GUID> vendor,
  Uint32 desiredAccess,
  Int32 metadataOptions,
  Pointer<Pointer<Void>> decoder,
);

int wicCreateDecoderFromFilename(
  Pointer<Void> factory,
  Pointer<Utf16> filename,
  int metadataOptions,
  Pointer<Pointer<Void>> out,
) => _slot(factory, 3)
    .cast<NativeFunction<_CreateDecoderFromFilenameNative>>()
    .asFunction<
      int Function(
        Pointer<Void>,
        Pointer<Utf16>,
        Pointer<GUID>,
        int,
        int,
        Pointer<Pointer<Void>>,
      )
    >()(factory, filename, nullptr, genericRead, metadataOptions, out);

typedef _CreateOneOutNative = Int32 Function(
  Pointer<Void>,
  Pointer<Pointer<Void>>,
);

/// CreateFormatConverter = vtable 10
int wicCreateFormatConverter(
  Pointer<Void> factory,
  Pointer<Pointer<Void>> out,
) =>
    _slot(factory, 10)
        .cast<NativeFunction<_CreateOneOutNative>>()
        .asFunction<int Function(Pointer<Void>, Pointer<Pointer<Void>>)>()(
      factory,
      out,
    );

/// CreateBitmapScaler = vtable 11
int wicCreateBitmapScaler(Pointer<Void> factory, Pointer<Pointer<Void>> out) =>
    _slot(factory, 11)
        .cast<NativeFunction<_CreateOneOutNative>>()
        .asFunction<int Function(Pointer<Void>, Pointer<Pointer<Void>>)>()(
      factory,
      out,
    );

typedef _CreateComponentEnumeratorNative = Int32 Function(
  Pointer<Void>,
  Uint32,
  Uint32,
  Pointer<Pointer<Void>>,
);

/// CreateComponentEnumerator = vtable 23
int wicCreateComponentEnumerator(
  Pointer<Void> factory,
  int componentTypes,
  int options,
  Pointer<Pointer<Void>> out,
) => _slot(factory, 23)
    .cast<NativeFunction<_CreateComponentEnumeratorNative>>()
    .asFunction<
      int Function(Pointer<Void>, int, int, Pointer<Pointer<Void>>)
    >()(factory, componentTypes, options, out);

// ---------------------------------------------------------------------------
// IWICBitmapDecoder
// ---------------------------------------------------------------------------

typedef _GetUintOutNative = Int32 Function(Pointer<Void>, Pointer<Uint32>);

/// GetFrameCount = vtable 12
int wicGetFrameCount(Pointer<Void> decoder, Pointer<Uint32> out) =>
    _slot(decoder, 12)
        .cast<NativeFunction<_GetUintOutNative>>()
        .asFunction<int Function(Pointer<Void>, Pointer<Uint32>)>()(
      decoder,
      out,
    );

typedef _GetFrameNative = Int32 Function(
  Pointer<Void>,
  Uint32,
  Pointer<Pointer<Void>>,
);

/// GetFrame = vtable 13
int wicGetFrame(Pointer<Void> decoder, int index, Pointer<Pointer<Void>> out) =>
    _slot(decoder, 13)
        .cast<NativeFunction<_GetFrameNative>>()
        .asFunction<int Function(Pointer<Void>, int, Pointer<Pointer<Void>>)>()(
      decoder,
      index,
      out,
    );

// ---------------------------------------------------------------------------
// IWICBitmapSource（IWICBitmapFrameDecode / Scaler / FormatConverter 都继承它）
// ---------------------------------------------------------------------------

typedef _GetSizeNative = Int32 Function(
  Pointer<Void>,
  Pointer<Uint32>,
  Pointer<Uint32>,
);

/// GetSize = vtable 3
int wicGetSize(Pointer<Void> src, Pointer<Uint32> w, Pointer<Uint32> h) =>
    _slot(src, 3)
        .cast<NativeFunction<_GetSizeNative>>()
        .asFunction<
          int Function(Pointer<Void>, Pointer<Uint32>, Pointer<Uint32>)
        >()(src, w, h);

typedef _CopyPixelsNative = Int32 Function(
  Pointer<Void>,
  Pointer<Void>,
  Uint32,
  Uint32,
  Pointer<Uint8>,
);

/// CopyPixels = vtable 7
///
/// IWICBitmapSource 有 5 个方法，别漏掉 GetResolution：
///   3 GetSize / 4 GetPixelFormat / 5 GetResolution / 6 CopyPalette / 7 CopyPixels
/// 所有派生接口（Scaler / FormatConverter / BitmapFrameDecode）都从 8 开始。
int wicCopyPixels(
  Pointer<Void> src,
  int stride,
  int bufferSize,
  Pointer<Uint8> buffer,
) => _slot(src, 7)
    .cast<NativeFunction<_CopyPixelsNative>>()
    .asFunction<
      int Function(Pointer<Void>, Pointer<Void>, int, int, Pointer<Uint8>)
    >()(src, nullptr, stride, bufferSize, buffer);

/// IWICBitmapFrameDecode::GetMetadataQueryReader = vtable 8
int wicFrameGetMetadataReader(
  Pointer<Void> frame,
  Pointer<Pointer<Void>> out,
) =>
    _slot(frame, 8)
        .cast<NativeFunction<_CreateOneOutNative>>()
        .asFunction<int Function(Pointer<Void>, Pointer<Pointer<Void>>)>()(
      frame,
      out,
    );

// ---------------------------------------------------------------------------
// IWICBitmapScaler / IWICFormatConverter 的 Initialize（都在 vtable 8）
// ---------------------------------------------------------------------------

typedef _ScalerInitNative = Int32 Function(
  Pointer<Void>,
  Pointer<Void>,
  Uint32,
  Uint32,
  Int32,
);

int wicScalerInitialize(
  Pointer<Void> scaler,
  Pointer<Void> source,
  int width,
  int height,
  int mode,
) => _slot(scaler, 8)
    .cast<NativeFunction<_ScalerInitNative>>()
    .asFunction<
      int Function(Pointer<Void>, Pointer<Void>, int, int, int)
    >()(scaler, source, width, height, mode);

typedef _ConverterInitNative = Int32 Function(
  Pointer<Void>,
  Pointer<Void>,
  Pointer<GUID>,
  Int32,
  Pointer<Void>,
  Double,
  Int32,
);

int wicConverterInitialize(
  Pointer<Void> conv,
  Pointer<Void> source,
  Pointer<GUID> dstFormat,
) =>
    _slot(conv, 8)
        .cast<NativeFunction<_ConverterInitNative>>()
        .asFunction<
          int Function(
            Pointer<Void>,
            Pointer<Void>,
            Pointer<GUID>,
            int,
            Pointer<Void>,
            double,
            int,
          )
        >()(
      conv,
      source,
      dstFormat,
      wicDitherTypeNone,
      nullptr,
      0.0,
      wicPaletteTypeCustom,
    );

// ---------------------------------------------------------------------------
// IWICBitmapSourceTransform —— 真正的 shrink-on-load 入口
// ---------------------------------------------------------------------------

typedef _TransformCopyPixelsNative = Int32 Function(
  Pointer<Void> self,
  Pointer<Void> rect,
  Uint32 width,
  Uint32 height,
  Pointer<GUID> dstFormat,
  Int32 transform,
  Uint32 stride,
  Uint32 bufferSize,
  Pointer<Uint8> buffer,
);

/// IWICBitmapSourceTransform::CopyPixels = vtable 3
int wicTransformCopyPixels(
  Pointer<Void> xform,
  int width,
  int height,
  Pointer<GUID> dstFormat,
  int stride,
  int bufferSize,
  Pointer<Uint8> buffer,
) =>
    _slot(xform, 3)
        .cast<NativeFunction<_TransformCopyPixelsNative>>()
        .asFunction<
          int Function(
            Pointer<Void>,
            Pointer<Void>,
            int,
            int,
            Pointer<GUID>,
            int,
            int,
            int,
            Pointer<Uint8>,
          )
        >()(
      xform,
      nullptr,
      width,
      height,
      dstFormat,
      wicBitmapTransformRotate0,
      stride,
      bufferSize,
      buffer,
    );

typedef _GetClosestSizeNative = Int32 Function(
  Pointer<Void>,
  Pointer<Uint32>,
  Pointer<Uint32>,
);

/// GetClosestSize = vtable 4。解码器会把请求尺寸吸附到它原生支持的档位
/// （JPEG/TIFF/RAW 通常给 1/2 1/4 1/8）
int wicGetClosestSize(
  Pointer<Void> xform,
  Pointer<Uint32> w,
  Pointer<Uint32> h,
) => _slot(xform, 4)
    .cast<NativeFunction<_GetClosestSizeNative>>()
    .asFunction<
      int Function(Pointer<Void>, Pointer<Uint32>, Pointer<Uint32>)
    >()(xform, w, h);

typedef _GetClosestPixelFormatNative = Int32 Function(
  Pointer<Void>,
  Pointer<GUID>,
);

/// GetClosestPixelFormat = vtable 5
int wicGetClosestPixelFormat(Pointer<Void> xform, Pointer<GUID> fmt) =>
    _slot(xform, 5)
        .cast<NativeFunction<_GetClosestPixelFormatNative>>()
        .asFunction<int Function(Pointer<Void>, Pointer<GUID>)>()(xform, fmt);

// ---------------------------------------------------------------------------
// IWICMetadataQueryReader
// ---------------------------------------------------------------------------

typedef _GetMetadataByNameNative = Int32 Function(
  Pointer<Void>,
  Pointer<Utf16>,
  Pointer<Void>,
);

/// GetMetadataByName = vtable 5
int wicGetMetadataByName(
  Pointer<Void> reader,
  Pointer<Utf16> name,
  Pointer<Void> propVariant,
) => _slot(reader, 5)
    .cast<NativeFunction<_GetMetadataByNameNative>>()
    .asFunction<
      int Function(Pointer<Void>, Pointer<Utf16>, Pointer<Void>)
    >()(reader, name, propVariant);

// ---------------------------------------------------------------------------
// IEnumUnknown / IWICBitmapCodecInfo —— 用于枚举本机安装了哪些 WIC 解码器
// ---------------------------------------------------------------------------

typedef _EnumNextNative = Int32 Function(
  Pointer<Void>,
  Uint32,
  Pointer<Pointer<Void>>,
  Pointer<Uint32>,
);

/// IEnumUnknown::Next = vtable 3
int enumUnknownNext(
  Pointer<Void> e,
  int count,
  Pointer<Pointer<Void>> out,
  Pointer<Uint32> fetched,
) => _slot(e, 3)
    .cast<NativeFunction<_EnumNextNative>>()
    .asFunction<
      int Function(Pointer<Void>, int, Pointer<Pointer<Void>>, Pointer<Uint32>)
    >()(e, count, out, fetched);

typedef _GetStringNative = Int32 Function(
  Pointer<Void>,
  Uint32,
  Pointer<Utf16>,
  Pointer<Uint32>,
);

/// IWICComponentInfo::GetFriendlyName = vtable 10
int wicInfoGetFriendlyName(
  Pointer<Void> info,
  int cch,
  Pointer<Utf16> buf,
  Pointer<Uint32> actual,
) => _slot(info, 10)
    .cast<NativeFunction<_GetStringNative>>()
    .asFunction<
      int Function(Pointer<Void>, int, Pointer<Utf16>, Pointer<Uint32>)
    >()(info, cch, buf, actual);

/// IWICBitmapCodecInfo::GetFileExtensions = vtable 17
int wicInfoGetFileExtensions(
  Pointer<Void> info,
  int cch,
  Pointer<Utf16> buf,
  Pointer<Uint32> actual,
) => _slot(info, 17)
    .cast<NativeFunction<_GetStringNative>>()
    .asFunction<
      int Function(Pointer<Void>, int, Pointer<Utf16>, Pointer<Uint32>)
    >()(info, cch, buf, actual);
