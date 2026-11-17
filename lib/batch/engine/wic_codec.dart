// WIC 编码 + 缩放。解码直接复用 services/decoders/wic_decoder.dart。
//
// vtable 序号（IUnknown 占 0..2）：
//   IWICImagingFactory   8 CreateEncoder / 10 CreateFormatConverter /
//                        11 CreateBitmapScaler / 20 CreateBitmapFromMemory
//   IWICBitmapEncoder    3 Initialize / 10 CreateNewFrame / 11 Commit
//   IWICBitmapFrameEncode 3 Initialize / 4 SetSize / 6 SetPixelFormat /
//                        11 WriteSource / 12 Commit
//   IPropertyBag2        4 Write
//   IStream              5 Seek
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import '../../services/decoders/wic_ffi.dart';
import 'pixels.dart';

const _guidBGRA = '6FDDC324-4E03-4BFE-B185-3D77768DC90F';
const _guidPBGRA = '6FDDC324-4E03-4BFE-B185-3D77768DC910';
const _guidBGR24 = '6FDDC324-4E03-4BFE-B185-3D77768DC90C';

enum WicContainer {
  jpeg('19E4A5AA-5662-4FC5-A0C0-1758028E1057'),
  png('1B7CFAF4-713F-473C-BBCD-6137425FAEAF'),
  tiff('163BCC30-E2E9-4F0B-961D-A3E9FDB788A3'),
  bmp('0AF1D87E-FCFE-4188-BDEB-A7906471CBE3');

  const WicContainer(this.guid);
  final String guid;
}

/// 编码参数（属性包里的名字 + 值）
sealed class WicProp {
  const WicProp(this.name);
  final String name;
}

class WicFloat extends WicProp {
  const WicFloat(super.name, this.value);
  final double value;
}

class WicByte extends WicProp {
  const WicByte(super.name, this.value);
  final int value;
}

class WicBool extends WicProp {
  const WicBool(super.name, this.value);
  final bool value;
}

// —— ole32 / kernel32 ——
final DynamicLibrary _ole32 = DynamicLibrary.open('ole32.dll');
final DynamicLibrary _kernel32 = DynamicLibrary.open('kernel32.dll');

final int Function(Pointer<Void>, int, Pointer<Pointer<Void>>)
_createStreamOnHGlobal = _ole32
    .lookupFunction<
      Int32 Function(Pointer<Void>, Int32, Pointer<Pointer<Void>>),
      int Function(Pointer<Void>, int, Pointer<Pointer<Void>>)
    >('CreateStreamOnHGlobal');

final int Function(Pointer<Void>, Pointer<Pointer<Void>>)
_getHGlobalFromStream = _ole32
    .lookupFunction<
      Int32 Function(Pointer<Void>, Pointer<Pointer<Void>>),
      int Function(Pointer<Void>, Pointer<Pointer<Void>>)
    >('GetHGlobalFromStream');

final Pointer<Uint8> Function(Pointer<Void>) _globalLock = _kernel32
    .lookupFunction<
      Pointer<Uint8> Function(Pointer<Void>),
      Pointer<Uint8> Function(Pointer<Void>)
    >('GlobalLock');

final int Function(Pointer<Void>) _globalUnlock = _kernel32
    .lookupFunction<Int32 Function(Pointer<Void>), int Function(Pointer<Void>)>(
      'GlobalUnlock',
    );

Pointer<Void> _slot(Pointer<Void> obj, int index) =>
    obj.cast<Pointer<Pointer<Void>>>().value[index];

typedef _I0 = Int32 Function(Pointer<Void>);
typedef _D0 = int Function(Pointer<Void>);

int _call0(Pointer<Void> obj, int slot) =>
    _slot(obj, slot).cast<NativeFunction<_I0>>().asFunction<_D0>()(obj);

// —— 每个 isolate 一份 factory ——
Pointer<Void> _factory = nullptr;
bool _comInited = false;

bool get wicAvailable => Platform.isWindows && _ensureFactory();

bool _ensureFactory() {
  if (_factory != nullptr) return true;
  if (!Platform.isWindows) return false;
  if (!_comInited) {
    coInitializeEx(nullptr, coinitMultithreaded);
    _comInited = true;
  }
  return using((alloc) {
    final out = alloc<Pointer<Void>>();
    final hr = coCreateInstance(
      allocGuid(clsidWICImagingFactory, alloc),
      nullptr,
      clsctxInprocServer,
      allocGuid(iidWICImagingFactory, alloc),
      out,
    );
    if (hr != sOk) return false;
    _factory = out.value;
    return true;
  });
}

String _hex(int hr) =>
    '0x${hr.toUnsigned(32).toRadixString(16).padLeft(8, '0')}';

void _check(int hr, String what) {
  if (hr < 0) throw WicError('$what ${_hex(hr)}');
}

class WicError implements Exception {
  WicError(this.message);
  final String message;
  @override
  String toString() => 'WIC: $message';
}

/// 把 Dart 像素拷成一个 IWICBitmap（WIC 会自己复制一份）
Pointer<Void> _bitmapFrom(
  Uint8List bytes,
  int w,
  int h,
  String fmt,
  Allocator alloc,
) {
  final size = w * h * 4;
  final buf = calloc<Uint8>(size);
  try {
    buf.asTypedList(size).setRange(0, size, bytes);
    final out = alloc<Pointer<Void>>();
    final hr = _slot(_factory, 20)
        .cast<
          NativeFunction<
            Int32 Function(
              Pointer<Void>,
              Uint32,
              Uint32,
              Pointer<GUID>,
              Uint32,
              Uint32,
              Pointer<Uint8>,
              Pointer<Pointer<Void>>,
            )
          >
        >()
        .asFunction<
          int Function(
            Pointer<Void>,
            int,
            int,
            Pointer<GUID>,
            int,
            int,
            Pointer<Uint8>,
            Pointer<Pointer<Void>>,
          )
        >()(_factory, w, h, allocGuid(fmt, alloc), w * 4, size, buf, out);
    _check(hr, 'CreateBitmapFromMemory');
    return out.value;
  } finally {
    calloc.free(buf);
  }
}

/// WIC 缩放。[mode]：0 最近邻 / 1 线性 / 3 Fant / 4 高质量三次
Pix wicScale(Pix src, int w, int h, int mode) {
  if (!_ensureFactory()) throw WicError('factory');
  return using((alloc) {
    final bmp = _bitmapFrom(src.data, src.width, src.height, _guidPBGRA, alloc);
    Pointer<Void> scaler = nullptr;
    try {
      final out = alloc<Pointer<Void>>();
      _check(wicCreateBitmapScaler(_factory, out), 'CreateBitmapScaler');
      scaler = out.value;
      var hr = wicScalerInitialize(scaler, bmp, w, h, mode);
      if (hr < 0 && mode == 4) {
        hr = wicScalerInitialize(scaler, bmp, w, h, wicInterpolationFant);
      }
      _check(hr, 'Scaler.Initialize');
      final size = w * h * 4;
      final buf = calloc<Uint8>(size);
      try {
        _check(wicCopyPixels(scaler, w * 4, size, buf), 'CopyPixels');
        return Pix(w, h, Uint8List.fromList(buf.asTypedList(size)));
      } finally {
        calloc.free(buf);
      }
    } finally {
      comRelease(scaler);
      comRelease(bmp);
    }
  });
}

/// 编码成 [container]。[src] 是预乘像素；[alpha] 为 false 时调用方应已铺好背景。
Uint8List wicEncode(
  Pix src,
  WicContainer container, {
  required bool alpha,
  List<WicProp> props = const [],
}) {
  if (!_ensureFactory()) throw WicError('factory');
  return using((alloc) {
    final straight = alpha ? unpremultiplied(src) : src.data;
    final bmp = _bitmapFrom(straight, src.width, src.height, _guidBGRA, alloc);
    Pointer<Void> stream = nullptr,
        encoder = nullptr,
        frame = nullptr,
        bag = nullptr,
        conv = nullptr;
    try {
      final out = alloc<Pointer<Void>>();
      _check(_createStreamOnHGlobal(nullptr, 1, out), 'CreateStreamOnHGlobal');
      stream = out.value;

      // CreateEncoder
      _check(
        _slot(_factory, 8)
            .cast<
              NativeFunction<
                Int32 Function(
                  Pointer<Void>,
                  Pointer<GUID>,
                  Pointer<GUID>,
                  Pointer<Pointer<Void>>,
                )
              >
            >()
            .asFunction<
              int Function(
                Pointer<Void>,
                Pointer<GUID>,
                Pointer<GUID>,
                Pointer<Pointer<Void>>,
              )
            >()(_factory, allocGuid(container.guid, alloc), nullptr, out),
        'CreateEncoder',
      );
      encoder = out.value;

      // Initialize(stream, WICBitmapEncoderNoCache)
      _check(
        _slot(encoder, 3)
            .cast<
              NativeFunction<
                Int32 Function(Pointer<Void>, Pointer<Void>, Int32)
              >
            >()
            .asFunction<int Function(Pointer<Void>, Pointer<Void>, int)>()(
          encoder,
          stream,
          2,
        ),
        'Encoder.Initialize',
      );

      // CreateNewFrame
      final bagOut = alloc<Pointer<Void>>();
      _check(
        _slot(encoder, 10)
            .cast<
              NativeFunction<
                Int32 Function(
                  Pointer<Void>,
                  Pointer<Pointer<Void>>,
                  Pointer<Pointer<Void>>,
                )
              >
            >()
            .asFunction<
              int Function(
                Pointer<Void>,
                Pointer<Pointer<Void>>,
                Pointer<Pointer<Void>>,
              )
            >()(encoder, out, bagOut),
        'CreateNewFrame',
      );
      frame = out.value;
      bag = bagOut.value;

      if (bag != nullptr) {
        for (final p in props) {
          _writeProp(bag, p, alloc);
        }
      }

      // Frame.Initialize(bag)
      _check(
        _slot(frame, 3)
            .cast<
              NativeFunction<Int32 Function(Pointer<Void>, Pointer<Void>)>
            >()
            .asFunction<int Function(Pointer<Void>, Pointer<Void>)>()(
          frame,
          bag,
        ),
        'Frame.Initialize',
      );
      // SetSize
      _check(
        _slot(frame, 4)
            .cast<
              NativeFunction<Int32 Function(Pointer<Void>, Uint32, Uint32)>
            >()
            .asFunction<int Function(Pointer<Void>, int, int)>()(
          frame,
          src.width,
          src.height,
        ),
        'SetSize',
      );
      // SetPixelFormat（编码器会改成它支持的最接近的格式）
      final fmt = allocGuid(alpha ? _guidBGRA : _guidBGR24, alloc);
      _check(
        _slot(frame, 6)
            .cast<
              NativeFunction<Int32 Function(Pointer<Void>, Pointer<GUID>)>
            >()
            .asFunction<int Function(Pointer<Void>, Pointer<GUID>)>()(
          frame,
          fmt,
        ),
        'SetPixelFormat',
      );

      Pointer<Void> source = bmp;
      if (!guidEquals(fmt, allocGuid(_guidBGRA, alloc))) {
        _check(
          wicCreateFormatConverter(_factory, out),
          'CreateFormatConverter',
        );
        conv = out.value;
        _check(wicConverterInitialize(conv, bmp, fmt), 'Converter.Initialize');
        source = conv;
      }

      // WriteSource
      _check(
        _slot(frame, 11)
            .cast<
              NativeFunction<
                Int32 Function(Pointer<Void>, Pointer<Void>, Pointer<Void>)
              >
            >()
            .asFunction<
              int Function(Pointer<Void>, Pointer<Void>, Pointer<Void>)
            >()(frame, source, nullptr),
        'WriteSource',
      );
      _check(_call0(frame, 12), 'Frame.Commit');
      _check(_call0(encoder, 11), 'Encoder.Commit');

      // 流的长度：Seek 到末尾
      final pos = alloc<Uint64>();
      _check(
        _slot(stream, 5)
            .cast<
              NativeFunction<
                Int32 Function(Pointer<Void>, Int64, Uint32, Pointer<Uint64>)
              >
            >()
            .asFunction<
              int Function(Pointer<Void>, int, int, Pointer<Uint64>)
            >()(stream, 0, 2, pos),
        'Seek',
      );
      final len = pos.value;
      _check(_getHGlobalFromStream(stream, out), 'GetHGlobalFromStream');
      final hg = out.value;
      final p = _globalLock(hg);
      if (p == nullptr) throw WicError('GlobalLock');
      try {
        return Uint8List.fromList(p.asTypedList(len));
      } finally {
        _globalUnlock(hg);
      }
    } finally {
      comRelease(conv);
      comRelease(bag);
      comRelease(frame);
      comRelease(encoder);
      comRelease(stream);
      comRelease(bmp);
    }
  });
}

/// PROPBAG2 (x64, 40 字节)：dwType@0 vt@4 cfType@6 dwHint@8 pstrName@16 clsid@24
/// VARIANT (x64, 24 字节)：vt@0 值@8
void _writeProp(Pointer<Void> bag, WicProp p, Allocator alloc) {
  final pb = alloc<Uint8>(40);
  final v = alloc<Uint8>(24);
  for (var i = 0; i < 40; i++) {
    pb[i] = 0;
  }
  for (var i = 0; i < 24; i++) {
    v[i] = 0;
  }
  (pb + 16).cast<Pointer<Utf16>>().value = p.name.toNativeUtf16(
    allocator: alloc,
  );
  switch (p) {
    case WicFloat(:final value):
      (pb + 4).cast<Uint16>().value = 4; // VT_R4
      v.cast<Uint16>().value = 4;
      (v + 8).cast<Float>().value = value;
    case WicByte(:final value):
      (pb + 4).cast<Uint16>().value = 17; // VT_UI1
      v.cast<Uint16>().value = 17;
      (v + 8).value = value;
    case WicBool(:final value):
      (pb + 4).cast<Uint16>().value = 11; // VT_BOOL
      v.cast<Uint16>().value = 11;
      (v + 8).cast<Int16>().value = value ? -1 : 0;
  }
  // 编码器不认识的属性会返回错误，忽略即可
  _slot(bag, 4)
      .cast<
        NativeFunction<
          Int32 Function(Pointer<Void>, Uint32, Pointer<Uint8>, Pointer<Uint8>)
        >
      >()
      .asFunction<
        int Function(Pointer<Void>, int, Pointer<Uint8>, Pointer<Uint8>)
      >()(bag, 1, pb, v);
}
