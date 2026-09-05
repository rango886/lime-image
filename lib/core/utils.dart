import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import '../services/decoders/format_sniffer.dart';

/// 内置解码器直接支持的格式（Flutter engine / Skia）
const kNativeExtensions = <String>{
  '.png',
  '.jpg',
  '.jpeg',
  '.jpe',
  '.jfif',
  '.gif',
  '.webp',
  '.bmp',
  '.dib',
  '.wbmp',
  '.ico',
  '.cur',
};

/// 需要外部解码器（WIC / ffmpeg / 内嵌预览 / SVG 栅格化）的常见格式。
/// 只是给人看的速览，真正的全集由 [kKnownImageExtensions] 从
/// `kFormatExtensions` 推出来，避免两处清单走偏。
const kExtraExtensions = <String>{
  '.tif',
  '.tiff',
  '.avif',
  '.heic',
  '.heif',
  '.jxl',
  '.psd',
  '.tga',
  '.dds',
  '.svg',
  '.jp2',
  '.exr',
  '.hdr',
  '.cr2',
  '.cr3',
  '.nef',
  '.arw',
  '.dng',
  '.orf',
  '.rw2',
  '.raf',
};

const kArchiveExtensions = <String>{'.zip', '.cbz'};

/// 列文件用：认得出是图片就行。**故意**不看本机能不能解码 ——
/// 少列一个文件会让用户在浏览时莫名跳过，比点开报错更困惑。
///
/// 直接从 `kFormatExtensions` 推出来（含全部 RAW 扩展名），
/// 这样加一种格式只需要改嗅探器那一张表。
final Set<String> kKnownImageExtensions = {
  ...kNativeExtensions,
  ...kExtraExtensions,
  for (final s in kFormatExtensions.values) ...s,
};

/// 兼容旧名字
Set<String> get kSupportedExtensions => kKnownImageExtensions;

/// 实际解码用：由 `DecoderRegistry` 在探测完后端后运行时填充。
/// 初值只含内置格式，保证还没探测完时也不会误判。
Set<String> _decodable = {...kNativeExtensions};

/// 本机**真的**（或极可能）能解开的扩展名
Set<String> get decodableExtensions => _decodable;

/// 由 `ImageService.warmUp()` 在解码器探测结束后调用
void setDecodableExtensions(Iterable<String> exts) {
  _decodable = {...kNativeExtensions, ...exts.map((e) => e.toLowerCase())};
}

/// 是否是「能识别为图片」的文件（用于列目录）
bool isImageFile(String path) =>
    kKnownImageExtensions.contains(p.extension(path).toLowerCase());

/// 是否本机有解码器能处理（用于 settings.hideUndecodableFiles）
bool isDecodableFile(String path) =>
    _decodable.contains(p.extension(path).toLowerCase());

bool isNativeImageFile(String path) =>
    kNativeExtensions.contains(p.extension(path).toLowerCase());

bool isArchiveFile(String path) =>
    kArchiveExtensions.contains(p.extension(path).toLowerCase());

bool isAnimatedExtension(String path) {
  final e = p.extension(path).toLowerCase();
  return e == '.gif' || e == '.webp' || e == '.png' || e == '.apng';
}

/// 自然排序：img2.jpg < img10.jpg
int naturalCompare(String a, String b) {
  final la = a.toLowerCase();
  final lb = b.toLowerCase();
  int i = 0, j = 0;
  while (i < la.length && j < lb.length) {
    final ca = la.codeUnitAt(i);
    final cb = lb.codeUnitAt(j);
    final da = ca ^ 0x30 <= 9;
    final db = cb ^ 0x30 <= 9;
    if (da && db) {
      int si = i, sj = j;
      while (i < la.length && (la.codeUnitAt(i) ^ 0x30) <= 9) {
        i++;
      }
      while (j < lb.length && (lb.codeUnitAt(j) ^ 0x30) <= 9) {
        j++;
      }
      final na = la.substring(si, i).replaceFirst(RegExp(r'^0+(?=\d)'), '');
      final nb = lb.substring(sj, j).replaceFirst(RegExp(r'^0+(?=\d)'), '');
      if (na.length != nb.length) return na.length - nb.length;
      final c = na.compareTo(nb);
      if (c != 0) return c;
    } else {
      if (ca != cb) return ca - cb;
      i++;
      j++;
    }
  }
  if (i < la.length) return 1;
  if (j < lb.length) return -1;
  return a.compareTo(b);
}

String formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  const units = ['KB', 'MB', 'GB', 'TB'];
  double v = bytes / 1024;
  int u = 0;
  while (v >= 1024 && u < units.length - 1) {
    v /= 1024;
    u++;
  }
  return '${v.toStringAsFixed(v < 10 ? 1 : 0)} ${units[u]}';
}

String formatDate(DateTime d) =>
    '${d.year}-${pad2(d.month)}-${pad2(d.day)} ${pad2(d.hour)}:${pad2(d.minute)}';
String pad2(int v) => v.toString().padLeft(2, '0');

double clampDouble(double v, double lo, double hi) =>
    math.min(math.max(v, lo), hi);

/// ---------------------------------------------------------------------------
/// 双页并排布局
/// ---------------------------------------------------------------------------

/// 两张图先等比缩放到同一高度（取较高的那张）再横排，
/// 这样一大一小的两页不会一高一低、看着像错位。
class DoublePageLayout {
  const DoublePageLayout({
    required this.height,
    required this.w1,
    required this.w2,
    required this.gap,
  });

  /// 两张图共同的高度
  final double height;

  /// 归一化后的第一 / 第二张宽度
  final double w1;
  final double w2;
  final double gap;

  double get width => w1 + gap + w2;
}

DoublePageLayout doublePageLayout(
  double w1,
  double h1,
  double w2,
  double h2,
  double gap,
) {
  final h = math.max(h1, h2);
  double norm(double w, double hh) => hh <= 0 ? w : w * h / hh;
  return DoublePageLayout(
    height: h,
    w1: norm(w1, h1),
    w2: norm(w2, h2),
    gap: gap,
  );
}

/// ---------------------------------------------------------------------------
/// 轻量图片尺寸探测：只读文件头，不解码，用于漫画模式的滚动区间估算
/// ---------------------------------------------------------------------------
class ProbedSize {
  const ProbedSize(this.width, this.height);
  final int width;
  final int height;
  double get aspect => height == 0 ? 1 : width / height;
}

Future<ProbedSize?> probeImageSize(String path) async {
  RandomAccessFile? f;
  try {
    f = await File(path).open();
    final len = await f.length();
    final head = await f.read(math.min(len, 65536));
    return parseImageSize(head);
  } catch (_) {
    return null;
  } finally {
    await f?.close();
  }
}

ProbedSize? parseImageSize(Uint8List b) {
  if (b.length < 16) return null;
  final d = ByteData.sublistView(b);
  // PNG
  if (b[0] == 0x89 && b[1] == 0x50 && b[2] == 0x4E && b[3] == 0x47) {
    return ProbedSize(d.getUint32(16), d.getUint32(20));
  }
  // GIF
  if (b[0] == 0x47 && b[1] == 0x49 && b[2] == 0x46) {
    return ProbedSize(
      d.getUint16(6, Endian.little),
      d.getUint16(8, Endian.little),
    );
  }
  // BMP
  if (b[0] == 0x42 && b[1] == 0x4D) {
    return ProbedSize(
      d.getInt32(18, Endian.little).abs(),
      d.getInt32(22, Endian.little).abs(),
    );
  }
  // WEBP
  if (b.length > 30 &&
      b[0] == 0x52 &&
      b[1] == 0x49 &&
      b[2] == 0x46 &&
      b[3] == 0x46 &&
      b[8] == 0x57 &&
      b[9] == 0x45 &&
      b[10] == 0x42 &&
      b[11] == 0x50) {
    final fourcc = String.fromCharCodes(b.sublist(12, 16));
    if (fourcc == 'VP8 ') {
      return ProbedSize(
        d.getUint16(26, Endian.little) & 0x3FFF,
        d.getUint16(28, Endian.little) & 0x3FFF,
      );
    } else if (fourcc == 'VP8L') {
      final bits = d.getUint32(21, Endian.little);
      return ProbedSize((bits & 0x3FFF) + 1, ((bits >> 14) & 0x3FFF) + 1);
    } else if (fourcc == 'VP8X') {
      final w = b[24] | (b[25] << 8) | (b[26] << 16);
      final h = b[27] | (b[28] << 8) | (b[29] << 16);
      return ProbedSize(w + 1, h + 1);
    }
  }
  // JPEG
  if (b[0] == 0xFF && b[1] == 0xD8) {
    int i = 2;
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
      final segLen = d.getUint16(i + 2);
      if (marker >= 0xC0 &&
          marker <= 0xCF &&
          marker != 0xC4 &&
          marker != 0xC8 &&
          marker != 0xCC) {
        return ProbedSize(d.getUint16(i + 7), d.getUint16(i + 5));
      }
      i += 2 + segLen;
    }
  }
  // TIFF
  if ((b[0] == 0x49 && b[1] == 0x49 && b[2] == 0x2A) ||
      (b[0] == 0x4D && b[1] == 0x4D && b[2] == 0x00)) {
    final little = b[0] == 0x49;
    final endian = little ? Endian.little : Endian.big;
    try {
      final ifd = d.getUint32(4, endian);
      final count = d.getUint16(ifd, endian);
      int? w, h;
      for (var k = 0; k < count; k++) {
        final off = ifd + 2 + k * 12;
        final tag = d.getUint16(off, endian);
        final type = d.getUint16(off + 2, endian);
        final value = type == 3
            ? d.getUint16(off + 8, endian)
            : d.getUint32(off + 8, endian);
        if (tag == 0x0100) w = value;
        if (tag == 0x0101) h = value;
      }
      if (w != null && h != null) return ProbedSize(w, h);
    } catch (_) {}
  }
  return null;
}
