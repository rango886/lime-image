import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'decoder.dart';
import 'format_sniffer.dart';

/// 从容器里直接抠出已经存在的 JPEG 预览图。
///
/// 实测收益（1080x2404 PSD，11.7MB）：
///   内嵌预览 2.0 ms  vs  ffmpeg 90 ms  vs  image 包 594 ms
///
/// 抠出来的是编码后的 JPEG 字节，直接走 Skia，白拿降采样能力。
class EmbeddedPreviewDecoder implements RawDecoder {
  @override
  String get id => 'embedded-preview';

  @override
  int get priority => 0;

  @override
  Future<bool> isAvailable() async => true;

  @override
  bool supports(ImageFormat fmt) =>
      fmt == ImageFormat.psd || fmt == ImageFormat.raw;

  @override
  void dispose() {}

  @override
  Future<RawImageData> decode(
    String path, {
    required int targetWidth,
    int maxFrames = 1,
  }) async {
    final sniff = await FormatSniffer.sniffFile(path);
    Uint8List? jpeg;
    int natW = 0, natH = 0;

    if (sniff.format == ImageFormat.psd) {
      final r = await _psdThumbnail(path);
      if (r != null) {
        jpeg = r.jpeg;
        natW = r.docWidth;
        natH = r.docHeight;
      }
    } else if (sniff.format == ImageFormat.raw) {
      jpeg = await _largestEmbeddedJpeg(path);
    }

    if (jpeg == null) {
      throw DecoderException(id, '容器里没有可用的内嵌预览');
    }

    final size = _jpegSize(jpeg);
    if (natW == 0 && size != null) {
      natW = size.$1;
      natH = size.$2;
    }

    return RawImageData.encoded(
      encoded: jpeg,
      width: size?.$1 ?? 0,
      height: size?.$2 ?? 0,
      naturalWidth: natW,
      naturalHeight: natH,
      decoderId: id,
      previewOnly: true,
    );
  }

  // ---------------------------------------------------------------------------
  // PSD: Image Resources 段里的 ID 1036(RGB) / 1033(BGR，旧版) 就是一整段 JPEG
  // ---------------------------------------------------------------------------

  static Future<_PsdThumb?> _psdThumbnail(String path) async {
    RandomAccessFile? f;
    try {
      f = await File(path).open();

      // File Header: 签名(4) 版本(2) 保留(6) 通道(2) 高(4) 宽(4) 深度(2) 色彩模式(2)
      final header = await f.read(26);
      if (header.length < 26) return null;
      if (String.fromCharCodes(header.sublist(0, 4)) != '8BPS') return null;
      final hd = ByteData.sublistView(header);
      final docHeight = hd.getUint32(14);
      final docWidth = hd.getUint32(18);

      // Color Mode Data: 长度(4) + 数据
      final cmLenBytes = await f.read(4);
      if (cmLenBytes.length < 4) return null;
      final cmLen = ByteData.sublistView(cmLenBytes).getUint32(0);
      await f.setPosition(26 + 4 + cmLen);

      // Image Resources: 长度(4) + 一串 8BIM 块
      final irLenBytes = await f.read(4);
      if (irLenBytes.length < 4) return null;
      final irLen = ByteData.sublistView(irLenBytes).getUint32(0);
      if (irLen <= 0 || irLen > 64 * 1024 * 1024) return null;

      final ir = await f.read(irLen);
      return _scanPsdResources(ir, docWidth, docHeight);
    } catch (_) {
      return null;
    } finally {
      await f?.close();
    }
  }

  static _PsdThumb? _scanPsdResources(Uint8List ir, int docW, int docH) {
    final d = ByteData.sublistView(ir);
    var pos = 0;
    while (pos + 12 <= ir.length) {
      if (String.fromCharCodes(ir.sublist(pos, pos + 4)) != '8BIM') break;
      final id = d.getUint16(pos + 4);
      var p = pos + 6;

      // Pascal 字符串：长度(1) + 内容，整体补齐到偶数
      final nameLen = ir[p];
      p += 1 + nameLen;
      if (nameLen % 2 == 0) p += 1;

      if (p + 4 > ir.length) break;
      final dataLen = d.getUint32(p);
      p += 4;
      if (p + dataLen > ir.length) break;

      if (id == 1036 || id == 1033) {
        // 缩略图头 28 字节: format(4) width(4) height(4) widthBytes(4)
        //                  totalSize(4) compressedSize(4) bitsPerPixel(2) planes(2)
        if (dataLen > 28) {
          final format = d.getUint32(p);
          if (format == 1) {
            // 1 = kJpegRGB，后面直接是完整 JPEG 流
            final jpeg = Uint8List.sublistView(ir, p + 28, p + dataLen);
            if (jpeg.length > 3 && jpeg[0] == 0xFF && jpeg[1] == 0xD8) {
              return _PsdThumb(
                jpeg: Uint8List.fromList(jpeg),
                docWidth: docW,
                docHeight: docH,
              );
            }
          }
        }
      }

      pos = p + dataLen;
      if (dataLen % 2 != 0) pos += 1; // 块补齐到偶数
    }
    return null;
  }

  // ---------------------------------------------------------------------------
  // RAW: 扫出文件里最大的那段 JPEG。
  // CR2/NEF/ARW/DNG/RAF/ORF 的预览都是完整 JPEG，通常靠前，
  // 且很多是全尺寸的 —— 这也是各家看图器"打开 RAW 很快"的真正原因。
  // ---------------------------------------------------------------------------

  static const int _rawScanLimit = 24 * 1024 * 1024;
  static const int _minPreviewBytes = 8 * 1024;

  static Future<Uint8List?> _largestEmbeddedJpeg(String path) async {
    RandomAccessFile? f;
    try {
      f = await File(path).open();
      final len = await f.length();
      final take = math.min(len, _rawScanLimit);
      final buf = await f.read(take);
      return _scanLargestJpeg(buf);
    } catch (_) {
      return null;
    } finally {
      await f?.close();
    }
  }

  static Uint8List? _scanLargestJpeg(Uint8List b) {
    Uint8List? best;
    var i = 0;
    final n = b.length;
    while (i + 3 < n) {
      // 找 SOI: FF D8 FF
      if (b[i] != 0xFF || b[i + 1] != 0xD8 || b[i + 2] != 0xFF) {
        i++;
        continue;
      }
      final start = i;
      final end = _findJpegEnd(b, start);
      if (end > start) {
        final size = end - start;
        if (size >= _minPreviewBytes && (best == null || size > best.length)) {
          best = Uint8List.sublistView(b, start, end);
        }
        i = end;
      } else {
        i = start + 2;
      }
    }
    return best == null ? null : Uint8List.fromList(best);
  }

  /// 按 JPEG 段结构走到 EOI，而不是无脑搜 FFD9
  /// （压缩数据里可能出现 FFD9 字节，直接搜会截断）
  static int _findJpegEnd(Uint8List b, int start) {
    var i = start + 2;
    final n = b.length;
    while (i + 1 < n) {
      if (b[i] != 0xFF) {
        i++;
        continue;
      }
      final marker = b[i + 1];
      // 填充字节
      if (marker == 0xFF) {
        i++;
        continue;
      }
      // 无长度字段的标记
      if (marker == 0x01 || (marker >= 0xD0 && marker <= 0xD7)) {
        i += 2;
        continue;
      }
      if (marker == 0xD9) return i + 2; // EOI
      if (marker == 0xD8) {
        i += 2;
        continue;
      }
      if (i + 3 >= n) return -1;
      final segLen = (b[i + 2] << 8) | b[i + 3];
      if (segLen < 2) return -1;
      if (marker == 0xDA) {
        // SOS：进入熵编码数据，逐字节扫到下一个非 RSTn / 非填充标记
        i += 2 + segLen;
        while (i + 1 < n) {
          if (b[i] == 0xFF) {
            final m = b[i + 1];
            if (m == 0x00 || m == 0xFF || (m >= 0xD0 && m <= 0xD7)) {
              i += 2;
              continue;
            }
            break; // 遇到真正的标记，回到外层循环处理
          }
          i++;
        }
        continue;
      }
      i += 2 + segLen;
    }
    return -1;
  }

  /// 从 JPEG 的 SOFn 段读尺寸
  static (int, int)? _jpegSize(Uint8List b) {
    if (b.length < 4 || b[0] != 0xFF || b[1] != 0xD8) return null;
    final d = ByteData.sublistView(b);
    var i = 2;
    while (i + 9 < b.length) {
      if (b[i] != 0xFF) {
        i++;
        continue;
      }
      final marker = b[i + 1];
      if (marker == 0xD8 ||
          marker == 0x01 ||
          (marker >= 0xD0 && marker <= 0xD7)) {
        i += 2;
        continue;
      }
      if (i + 3 >= b.length) break;
      final segLen = d.getUint16(i + 2);
      final isSof =
          marker >= 0xC0 &&
          marker <= 0xCF &&
          marker != 0xC4 &&
          marker != 0xC8 &&
          marker != 0xCC;
      if (isSof) {
        return (d.getUint16(i + 7), d.getUint16(i + 5));
      }
      if (segLen < 2) break;
      i += 2 + segLen;
    }
    return null;
  }
}

class _PsdThumb {
  _PsdThumb({
    required this.jpeg,
    required this.docWidth,
    required this.docHeight,
  });
  final Uint8List jpeg;
  final int docWidth;
  final int docHeight;
}
