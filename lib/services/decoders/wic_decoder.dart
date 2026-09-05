import 'dart:ffi';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'decoder.dart';
import 'format_sniffer.dart';
import 'wic_ffi.dart';

/// 本机 WIC 解码器的枚举结果（走 COM 而不是读注册表）
class WicCodecInfo {
  WicCodecInfo(this.friendlyName, this.extensions);
  final String friendlyName;
  final Set<String> extensions;
  @override
  String toString() => '$friendlyName -> ${extensions.join(',')}';
}

/// 用 Windows Imaging Component 解码。
///
/// 本机实测已可解：TIFF / HEIC / HEIF / AVIF / JPEG XL / DDS + 35 种 RAW，
/// 零第三方依赖、零编译。
///
/// 关键实现要点（踩过的坑）：
///  1. 必须走 IWICBitmapSourceTransform 才有真正的 shrink-on-load。
///     只用 IWICBitmapScaler 是"先全解再缩"，实测零加速。
///  2. COM 要在每个 isolate 里各自 CoInitializeEx 一次。
///     顶层变量在 Dart 里是 per-isolate 的，正好用来记状态。
///  3. 注册表信息完全不可信（JXL 扩展损坏时注册项一切正常但解不出来），
///     能力判定只能靠真的解一遍。
class WicDecoder implements RawDecoder {
  WicDecoder();

  @override
  String get id => 'wic';

  @override
  int get priority => 10;

  static const _formats = {
    ImageFormat.tiff,
    ImageFormat.raw,
    ImageFormat.heif,
    ImageFormat.avif,
    ImageFormat.jxl,
    ImageFormat.dds,
    ImageFormat.jp2,
    // 下面这些 Skia 也能解，留着做兜底（例如 Skia 解失败的畸形文件）
    ImageFormat.jpeg,
    ImageFormat.png,
    ImageFormat.bmp,
    ImageFormat.ico,
    ImageFormat.gif,
  };

  @override
  bool supports(ImageFormat fmt) => _formats.contains(fmt);

  @override
  Future<bool> isAvailable() async => Platform.isWindows;

  // —— 每 isolate 一份的常驻状态 ——
  static bool _comInited = false;
  static Pointer<Void> _factory = nullptr;

  static bool _ensureFactory() {
    if (_factory != nullptr) return true;
    if (!Platform.isWindows) return false;

    if (!_comInited) {
      // S_OK / S_FALSE(已初始化) / RPC_E_CHANGED_MODE 都算能继续用
      coInitializeEx(nullptr, coinitMultithreaded);
      _comInited = true;
    }
    return using((alloc) {
      final clsid = allocGuid(clsidWICImagingFactory, alloc);
      final iid = allocGuid(iidWICImagingFactory, alloc);
      final out = alloc<Pointer<Void>>();
      final hr = coCreateInstance(clsid, nullptr, clsctxInprocServer, iid, out);
      if (hr != sOk) return false;
      _factory = out.value;
      return true;
    });
  }

  @override
  void dispose() {
    if (_factory != nullptr) {
      comRelease(_factory);
      _factory = nullptr;
    }
  }

  // ---------------------------------------------------------------------------
  // 解码主流程
  // ---------------------------------------------------------------------------

  @override
  Future<RawImageData> decode(
    String path, {
    required int targetWidth,
    int maxFrames = 1,
  }) async {
    if (!Platform.isWindows) {
      throw DecoderException(id, '仅 Windows 可用');
    }
    if (!_ensureFactory()) {
      throw DecoderException(id, 'IWICImagingFactory 创建失败');
    }
    return _decodeSync(path, targetWidth, maxFrames);
  }

  RawImageData _decodeSync(String path, int targetWidth, int maxFrames) {
    return using((alloc) {
      final pathW = path.toNativeUtf16(allocator: alloc);
      final decoderOut = alloc<Pointer<Void>>();

      var hr = wicCreateDecoderFromFilename(
        _factory,
        pathW,
        wicDecodeMetadataCacheOnDemand,
        decoderOut,
      );
      if (hr != sOk) {
        throw DecoderException(
          id,
          'CreateDecoderFromFilename 失败 hr=${_hex(hr)}',
        );
      }
      final decoder = decoderOut.value;

      try {
        final cntPtr = alloc<Uint32>();
        hr = wicGetFrameCount(decoder, cntPtr);
        final frameCount = hr == sOk ? cntPtr.value : 1;
        final wantFrames = math.max(1, math.min(frameCount, maxFrames));

        final pixelFrames = <Uint8List>[];
        var outW = 0, outH = 0, natW = 0, natH = 0;
        var orientation = 1;

        for (var fi = 0; fi < wantFrames; fi++) {
          final frameOut = alloc<Pointer<Void>>();
          hr = wicGetFrame(decoder, fi, frameOut);
          if (hr != sOk) {
            if (fi == 0) {
              throw DecoderException(id, 'GetFrame(0) 失败 hr=${_hex(hr)}');
            }
            break;
          }
          final frame = frameOut.value;
          try {
            final wPtr = alloc<Uint32>();
            final hPtr = alloc<Uint32>();
            hr = wicGetSize(frame, wPtr, hPtr);
            if (hr != sOk) {
              throw DecoderException(id, 'GetSize 失败 hr=${_hex(hr)}');
            }
            if (fi == 0) {
              natW = wPtr.value;
              natH = hPtr.value;
              orientation = _readOrientation(frame, alloc);
            }

            final r = _copyFrame(frame, natW, natH, targetWidth, alloc);
            pixelFrames.add(r.pixels);
            outW = r.width;
            outH = r.height;
          } finally {
            comRelease(frame);
          }
        }

        return RawImageData.pixels(
          frames: pixelFrames,
          width: outW,
          height: outH,
          format: RawPixelFormat.bgra8888,
          naturalWidth: natW,
          naturalHeight: natH,
          orientation: orientation,
          decoderId: id,
          // WIC 拿不到通用的帧间隔，多帧时给个保守默认值
          delays: List<Duration>.filled(
            pixelFrames.length,
            pixelFrames.length > 1
                ? const Duration(milliseconds: 100)
                : Duration.zero,
          ),
        );
      } finally {
        comRelease(decoder);
      }
    });
  }

  /// 把一帧拷成 PBGRA。优先走 SourceTransform（真降采样），否则 Scaler + Converter。
  _FrameBytes _copyFrame(
    Pointer<Void> frame,
    int natW,
    int natH,
    int targetWidth,
    Allocator alloc,
  ) {
    final dstFmt = allocGuid(guidWICPixelFormat32bppPBGRA, alloc);

    var tw = math.min(targetWidth <= 0 ? natW : targetWidth, natW);
    if (tw < 1) tw = 1;
    var th = math.max(1, (natH * tw / natW).round());

    // ---- 路线 A: IWICBitmapSourceTransform ----
    // JPEG / TIFF / RAW 能给 1/2 1/4 1/8 的原生降采样，直接省掉整分辨率解码
    if (tw < natW) {
      final iid = allocGuid(iidWICBitmapSourceTransform, alloc);
      final xformOut = alloc<Pointer<Void>>();
      if (comQueryInterface(frame, iid, xformOut) == sOk) {
        final xform = xformOut.value;
        try {
          final cw = alloc<Uint32>()..value = tw;
          final ch = alloc<Uint32>()..value = th;
          if (wicGetClosestSize(xform, cw, ch) == sOk &&
              cw.value > 0 &&
              cw.value < natW) {
            final probe = allocGuid(guidWICPixelFormat32bppPBGRA, alloc);
            if (wicGetClosestPixelFormat(xform, probe) == sOk &&
                guidEquals(probe, dstFmt)) {
              final bytes = _alloc(cw.value, ch.value, alloc);
              final hr = wicTransformCopyPixels(
                xform,
                cw.value,
                ch.value,
                dstFmt,
                bytes.stride,
                bytes.size,
                bytes.buf,
              );
              if (hr == sOk) {
                return _FrameBytes(_toDart(bytes), cw.value, ch.value);
              }
            }
          }
        } finally {
          comRelease(xform);
        }
      }
    }

    // ---- 路线 B: Scaler(可选) + FormatConverter ----
    Pointer<Void> source = frame;
    Pointer<Void> scaler = nullptr;
    Pointer<Void> conv = nullptr;
    try {
      if (tw < natW) {
        final out = alloc<Pointer<Void>>();
        if (wicCreateBitmapScaler(_factory, out) == sOk) {
          scaler = out.value;
          if (wicScalerInitialize(
                scaler,
                frame,
                tw,
                th,
                wicInterpolationFant,
              ) ==
              sOk) {
            source = scaler;
          }
        }
      } else {
        tw = natW;
        th = natH;
      }

      final convOut = alloc<Pointer<Void>>();
      if (wicCreateFormatConverter(_factory, convOut) != sOk) {
        throw DecoderException(id, 'CreateFormatConverter 失败');
      }
      conv = convOut.value;
      final hrInit = wicConverterInitialize(conv, source, dstFmt);
      if (hrInit != sOk) {
        throw DecoderException(
          id,
          'FormatConverter.Initialize 失败 hr=${_hex(hrInit)}',
        );
      }

      final wPtr = alloc<Uint32>();
      final hPtr = alloc<Uint32>();
      if (wicGetSize(conv, wPtr, hPtr) != sOk) {
        throw DecoderException(id, '转换后 GetSize 失败');
      }
      final bytes = _alloc(wPtr.value, hPtr.value, alloc);
      final hr = wicCopyPixels(conv, bytes.stride, bytes.size, bytes.buf);
      if (hr != sOk) {
        throw DecoderException(id, 'CopyPixels 失败 hr=${_hex(hr)}');
      }
      return _FrameBytes(_toDart(bytes), wPtr.value, hPtr.value);
    } finally {
      comRelease(conv);
      comRelease(scaler);
    }
  }

  _Buf _alloc(int w, int h, Allocator alloc) {
    final stride = w * 4;
    final size = stride * h;
    return _Buf(alloc<Uint8>(size), stride, size);
  }

  Uint8List _toDart(_Buf b) => Uint8List.fromList(b.buf.asTypedList(b.size));

  /// EXIF 方向。HEIC 手机照片基本都带，不读会横躺。
  int _readOrientation(Pointer<Void> frame, Allocator alloc) {
    final readerOut = alloc<Pointer<Void>>();
    if (wicFrameGetMetadataReader(frame, readerOut) != sOk) return 1;
    final reader = readerOut.value;
    try {
      // 不同容器的元数据路径不一样，逐个试
      const queries = [
        '/app1/ifd/{ushort=274}', // JPEG
        '/ifd/{ushort=274}', // TIFF / 多数 RAW
        '/app1/{ushort=0}/{ushort=274}',
        '/xmp/tiff:Orientation',
        '/ifd/exif/{ushort=274}',
      ];
      for (final q in queries) {
        final name = q.toNativeUtf16(allocator: alloc);
        // PROPVARIANT 在 x64 上是 24 字节，多给点并清零
        final pv = alloc<Uint8>(32);
        for (var i = 0; i < 32; i++) {
          pv[i] = 0;
        }
        final pvv = pv.cast<Void>();
        if (wicGetMetadataByName(reader, name, pvv) == sOk) {
          final vt = pv.cast<Uint16>().value;
          int? v;
          // VT_UI2=18 VT_I2=2 VT_UI4=19 VT_I4=3 VT_UI1=17
          if (vt == 18 || vt == 2) {
            v = (pv + 8).cast<Uint16>().value;
          } else if (vt == 19 || vt == 3) {
            v = (pv + 8).cast<Uint32>().value;
          } else if (vt == 17) {
            v = (pv + 8).value;
          }
          propVariantClear(pvv);
          if (v != null && v >= 1 && v <= 8) return v;
        }
      }
    } catch (_) {
      // 元数据读取永远不该让解码失败
    } finally {
      comRelease(reader);
    }
    return 1;
  }

  static String _hex(int hr) =>
      '0x${hr.toUnsigned(32).toRadixString(16).padLeft(8, '0')}';

  // ---------------------------------------------------------------------------
  // 枚举本机安装的 WIC 解码器（走 COM，能看到 Store 扩展装的那些）
  // ---------------------------------------------------------------------------

  static List<WicCodecInfo> enumerateDecoders() {
    if (!Platform.isWindows || !_ensureFactory()) return const [];
    final result = <WicCodecInfo>[];
    return using((alloc) {
      final enumOut = alloc<Pointer<Void>>();
      if (wicCreateComponentEnumerator(
            _factory,
            wicComponentDecoder,
            0,
            enumOut,
          ) !=
          sOk) {
        return result;
      }
      final e = enumOut.value;
      try {
        final item = alloc<Pointer<Void>>();
        final fetched = alloc<Uint32>();
        final infoIid = allocGuid(iidWICBitmapDecoderInfo, alloc);
        while (enumUnknownNext(e, 1, item, fetched) == sOk &&
            fetched.value == 1) {
          final unk = item.value;
          try {
            final infoOut = alloc<Pointer<Void>>();
            if (comQueryInterface(unk, infoIid, infoOut) != sOk) continue;
            final info = infoOut.value;
            try {
              final name = _getInfoString(info, wicInfoGetFriendlyName, alloc);
              final exts = _getInfoString(
                info,
                wicInfoGetFileExtensions,
                alloc,
              );
              result.add(
                WicCodecInfo(
                  name,
                  exts
                      .split(',')
                      .map((s) => s.trim().toLowerCase())
                      .where((s) => s.startsWith('.'))
                      .toSet(),
                ),
              );
            } finally {
              comRelease(info);
            }
          } finally {
            comRelease(unk);
          }
        }
      } finally {
        comRelease(e);
      }
      return result;
    });
  }

  static String _getInfoString(
    Pointer<Void> info,
    int Function(Pointer<Void>, int, Pointer<Utf16>, Pointer<Uint32>) fn,
    Allocator alloc,
  ) {
    final need = alloc<Uint32>();
    if (fn(info, 0, nullptr, need) != sOk || need.value == 0) return '';
    final cch = need.value;
    final buf = alloc<Uint16>(cch + 1).cast<Utf16>();
    if (fn(info, cch, buf, need) != sOk) return '';
    return buf.toDartString();
  }
}

class _Buf {
  _Buf(this.buf, this.stride, this.size);
  final Pointer<Uint8> buf;
  final int stride;
  final int size;
}

class _FrameBytes {
  _FrameBytes(this.pixels, this.width, this.height);
  final Uint8List pixels;
  final int width;
  final int height;
}
