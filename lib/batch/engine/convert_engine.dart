import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import '../../services/decoders/decoder.dart';
import '../../services/decoders/ffmpeg_decoder.dart';
import '../../services/decoders/format_sniffer.dart';
import '../../services/decoders/wic_decoder.dart';
import '../convert_preset.dart';
import 'exif_patch.dart';
import 'ffmpeg_codec.dart';
import 'pixels.dart';
import 'wic_codec.dart';

/// 解码好的源图（未摆正）
class SourceImage {
  SourceImage({
    required this.pix,
    required this.orientation,
    required this.format,
    required this.fileSize,
    required this.animated,
    this.fileBytes,
  });

  final Pix pix;
  final int orientation;
  final ImageFormat format;
  final int fileSize;
  final bool animated;

  /// JPEG / PNG / WebP 会整份读进来，用来搬 EXIF / ICC
  final Uint8List? fileBytes;
}

/// 一次转换的结果。在 isolate 之间传递时大块数据用 [TransferableTypedData]。
class ConvertResult {
  ConvertResult();

  String? error;
  String? skipped;
  Uint8List? bytes;
  String ext = '';
  OutputFormat format = OutputFormat.jpeg;
  int outW = 0, outH = 0;
  int srcW = 0, srcH = 0;
  int srcSize = 0;
  String srcFormat = '';
  bool srcAlpha = false;
  bool outAlpha = false;
  bool exifKept = false;
  bool srcHasExif = false;
  bool srcHasGps = false;
  int quality = 0;
  bool keepOriginal = false;
  String? taken;
  int decodeMs = 0, encodeMs = 0;

  /// 摆正后的源图上，裁切框的归一化位置 (x, y, w, h)
  List<double>? cropRect;

  /// 只在预览时填：摆正后的源图 / 编码前的结果（都缩到预览尺寸）
  Pix? srcPreview;
  Pix? outPreview;

  bool get ok => error == null && skipped == null;

  Map<String, Object?> toMessage() => {
    'error': error,
    'skipped': skipped,
    'bytes': bytes == null ? null : TransferableTypedData.fromList([bytes!]),
    'ext': ext,
    'format': format.index,
    'outW': outW,
    'outH': outH,
    'srcW': srcW,
    'srcH': srcH,
    'srcSize': srcSize,
    'srcFormat': srcFormat,
    'srcAlpha': srcAlpha,
    'outAlpha': outAlpha,
    'exifKept': exifKept,
    'srcHasExif': srcHasExif,
    'srcHasGps': srcHasGps,
    'quality': quality,
    'keepOriginal': keepOriginal,
    'taken': taken,
    'decodeMs': decodeMs,
    'encodeMs': encodeMs,
    'cropRect': cropRect,
    'srcPreview': _pixMsg(srcPreview),
    'outPreview': _pixMsg(outPreview),
  };

  factory ConvertResult.fromMessage(Map m) {
    final r = ConvertResult()
      ..error = m['error'] as String?
      ..skipped = m['skipped'] as String?
      ..ext = m['ext'] as String
      ..format = OutputFormat.values[m['format'] as int]
      ..outW = m['outW'] as int
      ..outH = m['outH'] as int
      ..srcW = m['srcW'] as int
      ..srcH = m['srcH'] as int
      ..srcSize = m['srcSize'] as int
      ..srcFormat = m['srcFormat'] as String
      ..srcAlpha = m['srcAlpha'] as bool
      ..outAlpha = m['outAlpha'] as bool
      ..exifKept = m['exifKept'] as bool
      ..srcHasExif = m['srcHasExif'] as bool
      ..srcHasGps = m['srcHasGps'] as bool
      ..quality = m['quality'] as int
      ..keepOriginal = m['keepOriginal'] as bool
      ..taken = m['taken'] as String?
      ..decodeMs = m['decodeMs'] as int
      ..encodeMs = m['encodeMs'] as int
      ..cropRect = (m['cropRect'] as List?)?.cast<double>()
      ..srcPreview = _pixFrom(m['srcPreview'])
      ..outPreview = _pixFrom(m['outPreview']);
    final b = m['bytes'] as TransferableTypedData?;
    if (b != null) r.bytes = b.materialize().asUint8List();
    return r;
  }

  static Object? _pixMsg(Pix? p) => p == null
      ? null
      : [
          p.width,
          p.height,
          TransferableTypedData.fromList([p.data]),
        ];

  static Pix? _pixFrom(Object? o) {
    if (o is! List) return null;
    return Pix(
      o[0] as int,
      o[1] as int,
      (o[2] as TransferableTypedData).materialize().asUint8List(),
    );
  }
}

/// 转换引擎：一个 isolate 一个实例
class ConvertEngine {
  ConvertEngine({this.ffmpegPath});

  String? ffmpegPath;
  String? _ffmpeg;
  bool _ffmpegProbed = false;

  final WicDecoder _wic = WicDecoder();

  Future<String?> ffmpeg() async {
    if (!_ffmpegProbed) {
      _ffmpegProbed = true;
      _ffmpeg = await FfmpegEncoder.locate(ffmpegPath);
    }
    return _ffmpeg;
  }

  // —— 解码 ——

  Future<SourceImage> load(String path, {bool checkAnimated = false}) async {
    final file = File(path);
    final size = await file.length();
    final sniff = await FormatSniffer.sniffFile(path);
    if (sniff.format == ImageFormat.svg) {
      throw const FormatException('不支持 SVG');
    }
    Uint8List? bytes;
    if (sniff.format == ImageFormat.jpeg ||
        sniff.format == ImageFormat.png ||
        sniff.format == ImageFormat.webp) {
      bytes = await file.readAsBytes();
    }

    RawImageData? raw;
    Object? lastError;
    if (Platform.isWindows) {
      try {
        raw = await _wic.decode(
          path,
          targetWidth: 0,
          maxFrames: checkAnimated && sniff.format.animated ? 2 : 1,
        );
      } catch (e) {
        lastError = e;
      }
    }
    if (raw == null) {
      final exe = await ffmpeg();
      if (exe != null) {
        try {
          raw = await FfmpegDecoder(explicitPath: exe)
              .decode(path, targetWidth: 0);
        } catch (e) {
          lastError = e;
        }
      }
    }
    if (raw == null || raw.isEncoded || raw.frames.isEmpty) {
      throw FormatException(_short(lastError) ?? '无法解码');
    }
    final px = raw.frames.first;
    if (raw.format == RawPixelFormat.rgba8888) rgbaToBgraInPlace(px);

    var orientation = raw.orientation;
    if (orientation == 1 && bytes != null) {
      final exif = extractExif(bytes);
      if (exif != null) orientation = exifOrientation(exif);
    }
    return SourceImage(
      pix: Pix(raw.width, raw.height, px),
      orientation: orientation,
      format: sniff.format,
      fileSize: size,
      animated: raw.frames.length > 1,
      fileBytes: bytes,
    );
  }

  static String? _short(Object? e) {
    if (e == null) return null;
    var s = e.toString();
    if (e is DecoderException) s = e.message;
    if (e is FormatException) s = e.message;
    return s.length > 160 ? '${s.substring(0, 160)}…' : s;
  }

  // —— 处理 ——

  Future<ConvertResult> process(
    SourceImage src,
    ConvertPreset p, {
    List<double>? cropOverride,
    int previewMax = 0,
  }) async {
    final r = ConvertResult()
      ..srcSize = src.fileSize
      ..srcFormat = src.format.label;
    final sw = Stopwatch()..start();

    if (src.animated && p.animated == AnimatedPolicy.skip) {
      return r..skipped = '动图';
    }

    final exif = src.fileBytes == null ? null : extractExif(src.fileBytes!);
    r.srcHasExif = exif != null;
    r.srcHasGps = exif != null && _hasGps(exif);
    if (exif != null) r.taken = exifTakenStamp(exif);

    // 1. 摆正
    var px = orient(src.pix, p.autoOrient ? src.orientation : 1);
    r.srcW = px.width;
    r.srcH = px.height;
    r.srcAlpha = px.hasAlpha;
    if (previewMax > 0) r.srcPreview = _shrink(px, previewMax);

    final applyUser = switch (p.rotateScope) {
      RotateScope.all => true,
      RotateScope.landscape => px.width > px.height,
      RotateScope.portrait => px.height > px.width,
    };

    // 2. 裁切（在摆正后的坐标里）
    final rect = cropOverride != null
        ? _fromNormalized(cropOverride, px.width, px.height)
        : cropRectFor(p, px);
    if (rect != null && !rect.covers(px.width, px.height)) {
      r.cropRect = [
        rect.x / px.width,
        rect.y / px.height,
        rect.w / px.width,
        rect.h / px.height,
      ];
      px = crop(px, rect);
    }

    // 3. 旋转 / 翻转
    if (applyUser) {
      px = orient(px, switch (p.rotate) {
        RotateBy.none => 1,
        RotateBy.cw90 => 6,
        RotateBy.r180 => 3,
        RotateBy.ccw90 => 8,
      });
      if (p.flipH) px = orient(px, 2);
      if (p.flipV) px = orient(px, 4);
    }

    // 4. 缩放
    final (tw, th) = resizeTarget(p, px.width, px.height);
    if (tw != px.width || th != px.height) {
      px = _scale(px, tw, th, p.filter);
    }
    r.decodeMs = sw.elapsedMilliseconds;
    sw.reset();

    // 5. 编码
    final fmt = resolveFormat(p.format, src.format);
    r.format = fmt;
    r.ext = p.extFor(fmt);
    r.outW = px.width;
    r.outH = px.height;
    final alpha = fmt.supportsAlpha && px.hasAlpha;
    r.outAlpha = alpha;
    final enc = (!alpha && px.hasAlpha) ? flatten(px, p.background) : px;
    if (previewMax > 0) r.outPreview = _shrink(enc, previewMax);

    var quality = switch (fmt) {
      OutputFormat.jpeg => p.jpegQuality,
      OutputFormat.webp => p.webpQuality,
      OutputFormat.avif => p.avifQuality,
      _ => 0,
    };
    var bytes = await _encode(enc, fmt, p, quality, alpha);
    final lossyNow =
        fmt == OutputFormat.jpeg ||
        fmt == OutputFormat.avif ||
        (fmt == OutputFormat.webp && !p.webpLossless);
    if (p.limitSize && lossyNow && bytes.length > p.maxKb * 1024) {
      // 二分找不超过上限的最高质量
      var lo = 1, hi = quality - 1;
      Uint8List? best;
      var bestQ = 0;
      while (lo <= hi) {
        final mid = (lo + hi) ~/ 2;
        final b = await _encode(enc, fmt, p, mid, alpha);
        if (b.length <= p.maxKb * 1024) {
          best = b;
          bestQ = mid;
          lo = mid + 1;
        } else {
          hi = mid - 1;
        }
      }
      if (best != null) {
        bytes = best;
        quality = bestQ;
      } else {
        bytes = await _encode(enc, fmt, p, 1, alpha);
        quality = 1;
      }
    }
    r.quality = quality;

    // 6. 元数据
    if (p.metadata != MetadataPolicy.strip && exif != null) {
      final patched = patchExif(
        exif,
        resetOrientation: p.autoOrient,
        stripGps: p.metadata == MetadataPolicy.stripGps,
        width: px.width,
        height: px.height,
      );
      if (patched != null) {
        if (fmt == OutputFormat.jpeg) {
          bytes = insertJpegSegments(bytes, patched, const []);
          r.exifKept = true;
        } else if (fmt == OutputFormat.png) {
          bytes = insertPngExif(bytes, patched);
          r.exifKept = true;
        }
      }
    }
    if (fmt == OutputFormat.jpeg && src.fileBytes != null) {
      final icc = extractJpegIcc(src.fileBytes!);
      if (icc.isNotEmpty) bytes = insertJpegSegments(bytes, null, icc);
    }

    r.encodeMs = sw.elapsedMilliseconds;
    r.bytes = bytes;
    if (p.keepIfLarger && bytes.length >= src.fileSize) r.keepOriginal = true;
    return r;
  }

  static bool _hasGps(Uint8List tiff) {
    try {
      final le = tiff[0] == 0x49;
      final bd = ByteData.sublistView(tiff);
      final e = le ? Endian.little : Endian.big;
      final ifd0 = bd.getUint32(4, e);
      final n = bd.getUint16(ifd0, e);
      for (var k = 0; k < n; k++) {
        if (bd.getUint16(ifd0 + 2 + k * 12, e) == 0x8825) {
          final gps = bd.getUint32(ifd0 + 2 + k * 12 + 8, e);
          return gps + 2 <= tiff.length && bd.getUint16(gps, e) > 0;
        }
      }
    } catch (_) {}
    return false;
  }

  Pix _scale(Pix px, int w, int h, ResizeFilter f) {
    if (Platform.isWindows && wicAvailable) {
      try {
        return wicScale(px, w, h, switch (f) {
          ResizeFilter.quality => 4,
          ResizeFilter.linear => 1,
          ResizeFilter.nearest => 0,
        });
      } catch (_) {}
    }
    return resizeDart(px, w, h, nearest: f == ResizeFilter.nearest);
  }

  Pix _shrink(Pix px, int max) {
    final long = math.max(px.width, px.height);
    if (long <= max) return px;
    final s = max / long;
    return _scale(
      px,
      math.max(1, (px.width * s).round()),
      math.max(1, (px.height * s).round()),
      ResizeFilter.linear,
    );
  }

  Future<Uint8List> _encode(
    Pix px,
    OutputFormat fmt,
    ConvertPreset p,
    int quality,
    bool alpha,
  ) async {
    final wic = Platform.isWindows && wicAvailable;
    switch (fmt) {
      case OutputFormat.jpeg:
        if (wic) {
          return wicEncode(
            px,
            WicContainer.jpeg,
            alpha: false,
            props: [
              WicFloat('ImageQuality', quality / 100),
              WicByte('JpegYCrCbSubsampling', switch (p.jpegSubsampling) {
                JpegSubsampling.s420 => 1,
                JpegSubsampling.s422 => 2,
                JpegSubsampling.s444 => 3,
              }),
            ],
          );
        }
        return (await _ff()).jpeg(
          px,
          quality: quality,
          s444: p.jpegSubsampling == JpegSubsampling.s444,
        );
      case OutputFormat.png:
        if (wic) return wicEncode(px, WicContainer.png, alpha: alpha);
        return (await _ff()).png(px, alpha: alpha);
      case OutputFormat.tiff:
        if (wic) {
          return wicEncode(
            px,
            WicContainer.tiff,
            alpha: alpha,
            props: [
              WicByte('TiffCompressionMethod', switch (p.tiffCompression) {
                TiffCompression.none => 1,
                TiffCompression.lzw => 4,
                TiffCompression.zip => 6,
              }),
            ],
          );
        }
        return (await _ff()).tiff(
          px,
          alpha: alpha,
          algo: switch (p.tiffCompression) {
            TiffCompression.none => 'raw',
            TiffCompression.lzw => 'lzw',
            TiffCompression.zip => 'deflate',
          },
        );
      case OutputFormat.bmp:
        if (wic) {
          return wicEncode(
            px,
            WicContainer.bmp,
            alpha: alpha,
            props: [if (alpha) const WicBool('EnableV5Header32bppBGRA', true)],
          );
        }
        return (await _ff()).bmp(px, alpha: alpha);
      case OutputFormat.webp:
        return (await _ff()).webp(
          px,
          quality: quality,
          lossless: p.webpLossless,
          effort: p.webpEffort,
          alpha: alpha,
        );
      case OutputFormat.avif:
        return (await _ff()).avif(px, quality: quality, speed: p.avifSpeed);
      case OutputFormat.keep:
        throw StateError('keep 应该已经解析成具体格式');
    }
  }

  Future<FfmpegEncoder> _ff() async {
    final exe = await ffmpeg();
    if (exe == null) throw const FormatException('需要 ffmpeg');
    return FfmpegEncoder(exe);
  }
}

/// 「保持原格式」时实际用哪种
OutputFormat resolveFormat(OutputFormat f, ImageFormat src) {
  if (f != OutputFormat.keep) return f;
  return switch (src) {
    ImageFormat.jpeg => OutputFormat.jpeg,
    ImageFormat.png || ImageFormat.gif || ImageFormat.ico => OutputFormat.png,
    ImageFormat.webp => OutputFormat.webp,
    ImageFormat.bmp => OutputFormat.bmp,
    ImageFormat.tiff => OutputFormat.tiff,
    ImageFormat.avif => OutputFormat.avif,
    _ => OutputFormat.jpeg,
  };
}

IRect? _fromNormalized(List<double> n, int w, int h) {
  final x = (n[0] * w).round().clamp(0, w - 1);
  final y = (n[1] * h).round().clamp(0, h - 1);
  final cw = (n[2] * w).round().clamp(1, w - x);
  final ch = (n[3] * h).round().clamp(1, h - y);
  return IRect(x, y, cw, ch);
}

/// 按预设算裁切区域（摆正后的坐标）。不裁返回 null。
IRect? cropRectFor(ConvertPreset p, Pix px) {
  final w = px.width, h = px.height;
  switch (p.crop) {
    case CropMode.none:
      return null;
    case CropMode.ratio:
      var rw = p.ratioW, rh = p.ratioH;
      if (rw <= 0 || rh <= 0) return null;
      if (p.ratioFollowOrientation && (w > h) != (rw > rh) && w != h) {
        final t = rw;
        rw = rh;
        rh = t;
      }
      final a = rw / rh;
      int cw, ch;
      if (w / h > a) {
        ch = h;
        cw = math.max(1, (h * a).round());
      } else {
        cw = w;
        ch = math.max(1, (w / a).round());
      }
      return _anchored(w, h, cw, ch, p.anchor);
    case CropMode.margin:
      double v(double m, int total) =>
          p.marginUnit == MarginUnit.px ? m : total * m / 100;
      final l = v(p.marginLeft, w).round();
      final r = v(p.marginRight, w).round();
      final t = v(p.marginTop, h).round();
      final b = v(p.marginBottom, h).round();
      final cw = math.max(1, w - l - r);
      final ch = math.max(1, h - t - b);
      return IRect(math.min(l, w - 1), math.min(t, h - 1), cw, ch);
    case CropMode.fixed:
      return _anchored(
        w,
        h,
        math.min(math.max(1, p.fixedW), w),
        math.min(math.max(1, p.fixedH), h),
        p.anchor,
      );
    case CropMode.trim:
      return trimBounds(px, p.trimTolerance, p.trimPadding);
  }
}

IRect _anchored(int w, int h, int cw, int ch, int anchor) {
  final (fx, fy) = anchorFactor(anchor);
  return IRect(((w - cw) * fx).round(), ((h - ch) * fy).round(), cw, ch);
}

(int, int) resizeTarget(ConvertPreset p, int w, int h) {
  double s;
  final v = p.resizeValue;
  switch (p.resize) {
    case ResizeMode.none:
      return (w, h);
    case ResizeMode.longEdge:
      s = v / math.max(w, h);
    case ResizeMode.shortEdge:
      s = v / math.min(w, h);
    case ResizeMode.width:
      s = v / w;
    case ResizeMode.height:
      s = v / h;
    case ResizeMode.fit:
      s = math.min(p.fitW / w, p.fitH / h);
    case ResizeMode.percent:
      s = v / 100;
  }
  if (!s.isFinite || s <= 0) return (w, h);
  if (p.noUpscale && s > 1) s = 1;
  return (math.max(1, (w * s).round()), math.max(1, (h * s).round()));
}
