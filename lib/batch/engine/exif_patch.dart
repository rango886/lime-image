import 'dart:typed_data';

/// 从源文件里取出 EXIF（TIFF 结构那一段，以 II / MM 开头）。
/// 支持 JPEG APP1、PNG eXIf、WebP EXIF 块；其它容器返回 null。
Uint8List? extractExif(Uint8List f) {
  if (f.length > 4 && f[0] == 0xFF && f[1] == 0xD8) return _jpegExif(f);
  if (f.length > 8 && f[0] == 0x89 && f[1] == 0x50) return _pngExif(f);
  if (f.length > 12 &&
      String.fromCharCodes(f.sublist(0, 4)) == 'RIFF' &&
      String.fromCharCodes(f.sublist(8, 12)) == 'WEBP') {
    return _webpExif(f);
  }
  return null;
}

Uint8List? _jpegExif(Uint8List f) {
  for (final seg in _jpegSegments(f)) {
    if (seg.marker != 0xE1) continue;
    final p = seg.payload;
    if (p.length > 6 &&
        p[0] == 0x45 &&
        p[1] == 0x78 &&
        p[2] == 0x69 &&
        p[3] == 0x66 &&
        p[4] == 0 &&
        p[5] == 0) {
      return Uint8List.fromList(p.sublist(6));
    }
  }
  return null;
}

/// JPEG 里的 ICC 配置（APP2 "ICC_PROFILE"），原样返回整段（含 FFE2 和长度）
List<Uint8List> extractJpegIcc(Uint8List f) {
  if (f.length < 4 || f[0] != 0xFF || f[1] != 0xD8) return const [];
  final out = <Uint8List>[];
  for (final seg in _jpegSegments(f)) {
    if (seg.marker != 0xE2) continue;
    final p = seg.payload;
    if (p.length > 12 &&
        String.fromCharCodes(p.sublist(0, 11)) == 'ICC_PROFILE') {
      out.add(Uint8List.fromList(f.sublist(seg.start, seg.end)));
    }
  }
  return out;
}

class _Seg {
  _Seg(this.marker, this.start, this.end, this.payload);
  final int marker;
  final int start;
  final int end;
  final Uint8List payload;
}

Iterable<_Seg> _jpegSegments(Uint8List f) sync* {
  var i = 2;
  while (i + 4 <= f.length) {
    if (f[i] != 0xFF) return;
    final m = f[i + 1];
    if (m == 0xD8 || (m >= 0xD0 && m <= 0xD7) || m == 0x01) {
      i += 2;
      continue;
    }
    if (m == 0xDA || m == 0xD9) return; // 到图像数据了
    final len = (f[i + 2] << 8) | f[i + 3];
    if (len < 2 || i + 2 + len > f.length) return;
    yield _Seg(m, i, i + 2 + len, Uint8List.sublistView(f, i + 4, i + 2 + len));
    i += 2 + len;
  }
}

Uint8List? _pngExif(Uint8List f) {
  var i = 8;
  while (i + 12 <= f.length) {
    final len = _u32be(f, i);
    final type = String.fromCharCodes(f.sublist(i + 4, i + 8));
    if (i + 12 + len > f.length) return null;
    if (type == 'eXIf') {
      return Uint8List.fromList(f.sublist(i + 8, i + 8 + len));
    }
    if (type == 'IDAT' || type == 'IEND') return null;
    i += 12 + len;
  }
  return null;
}

Uint8List? _webpExif(Uint8List f) {
  var i = 12;
  while (i + 8 <= f.length) {
    final type = String.fromCharCodes(f.sublist(i, i + 4));
    final len = f[i + 4] | f[i + 5] << 8 | f[i + 6] << 16 | f[i + 7] << 24;
    if (i + 8 + len > f.length) return null;
    if (type == 'EXIF') {
      var d = Uint8List.fromList(f.sublist(i + 8, i + 8 + len));
      if (d.length > 6 && String.fromCharCodes(d.sublist(0, 4)) == 'Exif') {
        d = Uint8List.fromList(d.sublist(6));
      }
      return d;
    }
    i += 8 + len + (len & 1);
  }
  return null;
}

int _u32be(Uint8List b, int o) =>
    (b[o] << 24) | (b[o + 1] << 16) | (b[o + 2] << 8) | b[o + 3];

/// 改写一份 EXIF：
///  - [resetOrientation] 方向写回 1（像素已经摆正了）
///  - [stripGps] 抹掉 GPS 目录
///  - 去掉缩略图（IFD1），里面是原图的旧样子
///  - 更新 PixelXDimension / PixelYDimension
/// 结构异常时返回 null，调用方就不写元数据了。
Uint8List? patchExif(
  Uint8List src, {
  required bool resetOrientation,
  required bool stripGps,
  required int width,
  required int height,
}) {
  if (src.length < 8) return null;
  final t = Uint8List.fromList(src);
  final le = t[0] == 0x49 && t[1] == 0x49;
  final be = t[0] == 0x4D && t[1] == 0x4D;
  if (!le && !be) return null;
  final bd = ByteData.sublistView(t);
  final endian = le ? Endian.little : Endian.big;
  int u16(int o) => bd.getUint16(o, endian);
  int u32(int o) => bd.getUint32(o, endian);
  void w16(int o, int v) => bd.setUint16(o, v, endian);
  void w32(int o, int v) => bd.setUint32(o, v, endian);
  bool ok(int o, int n) => o >= 0 && o + n <= t.length;

  const typeSize = {
    1: 1,
    2: 1,
    3: 2,
    4: 4,
    5: 8,
    6: 1,
    7: 1,
    8: 2,
    9: 4,
    10: 8,
    11: 4,
    12: 8,
  };

  try {
    final ifd0 = u32(4);
    if (!ok(ifd0, 2)) return null;
    final n0 = u16(ifd0);
    if (!ok(ifd0 + 2, n0 * 12 + 4)) return null;
    int? exifIfd, gpsIfd;
    for (var k = 0; k < n0; k++) {
      final e = ifd0 + 2 + k * 12;
      final tag = u16(e);
      if (tag == 0x0112 && resetOrientation) w16(e + 8, 1);
      if (tag == 0x8769) exifIfd = u32(e + 8);
      if (tag == 0x8825) gpsIfd = u32(e + 8);
    }
    // 断开 IFD1（缩略图）
    w32(ifd0 + 2 + n0 * 12, 0);

    if (exifIfd != null && ok(exifIfd, 2)) {
      final n = u16(exifIfd);
      if (ok(exifIfd + 2, n * 12)) {
        for (var k = 0; k < n; k++) {
          final e = exifIfd + 2 + k * 12;
          final tag = u16(e);
          if (tag != 0xA002 && tag != 0xA003) continue;
          final v = tag == 0xA002 ? width : height;
          if (u16(e + 2) == 3) {
            w16(e + 8, v.clamp(0, 0xFFFF));
          } else if (u16(e + 2) == 4) {
            w32(e + 8, v);
          }
        }
      }
    }

    if (stripGps && gpsIfd != null && ok(gpsIfd, 2)) {
      final n = u16(gpsIfd);
      if (ok(gpsIfd + 2, n * 12)) {
        for (var k = 0; k < n; k++) {
          final e = gpsIfd + 2 + k * 12;
          final size = (typeSize[u16(e + 2)] ?? 1) * u32(e + 4);
          if (size > 4) {
            final off = u32(e + 8);
            if (ok(off, size)) t.fillRange(off, off + size, 0);
          }
          t.fillRange(e, e + 12, 0);
        }
        w16(gpsIfd, 0);
      }
    }
    return t;
  } catch (_) {
    return null;
  }
}

/// 把 EXIF / ICC 段插到 JPEG 的 SOI（以及紧跟的 JFIF APP0）后面
Uint8List insertJpegSegments(
  Uint8List jpeg,
  Uint8List? exif,
  List<Uint8List> icc,
) {
  if (jpeg.length < 4 || jpeg[0] != 0xFF || jpeg[1] != 0xD8) return jpeg;
  final extra = BytesBuilder(copy: false);
  if (exif != null && exif.length + 8 <= 0xFFFF) {
    final len = exif.length + 8;
    extra.add([0xFF, 0xE1, len >> 8, len & 0xFF, 0x45, 0x78, 0x69, 0x66, 0, 0]);
    extra.add(exif);
  }
  for (final seg in icc) {
    extra.add(seg);
  }
  if (extra.isEmpty) return jpeg;

  var at = 2;
  if (jpeg.length > 6 && jpeg[2] == 0xFF && jpeg[3] == 0xE0) {
    at = 4 + ((jpeg[4] << 8) | jpeg[5]);
  }
  // 原本已有的 APP1(EXIF) 去掉，避免出现两份
  final rest = BytesBuilder(copy: false);
  var i = at;
  while (i + 4 <= jpeg.length && jpeg[i] == 0xFF) {
    final m = jpeg[i + 1];
    if (m < 0xE0 || m > 0xEF) break;
    final len = (jpeg[i + 2] << 8) | jpeg[i + 3];
    final drop = (m == 0xE1 && exif != null) || (m == 0xE2 && icc.isNotEmpty);
    if (!drop) rest.add(Uint8List.sublistView(jpeg, i, i + 2 + len));
    i += 2 + len;
  }
  final out = BytesBuilder(copy: false)
    ..add(Uint8List.sublistView(jpeg, 0, at))
    ..add(extra.takeBytes())
    ..add(rest.takeBytes())
    ..add(Uint8List.sublistView(jpeg, i));
  return out.takeBytes();
}

/// 在 PNG 第一个 IDAT 前插一个 eXIf 块
Uint8List insertPngExif(Uint8List png, Uint8List exif) {
  var i = 8;
  while (i + 12 <= png.length) {
    final len = _u32be(png, i);
    final type = String.fromCharCodes(png.sublist(i + 4, i + 8));
    if (type == 'IDAT') {
      final chunk = BytesBuilder(copy: false);
      final head = ByteData(8)
        ..setUint32(0, exif.length)
        ..setUint8(4, 0x65) // e
        ..setUint8(5, 0x58) // X
        ..setUint8(6, 0x49) // I
        ..setUint8(7, 0x66); // f
      final typeAndData = Uint8List(4 + exif.length)
        ..setRange(0, 4, const [0x65, 0x58, 0x49, 0x66])
        ..setRange(4, 4 + exif.length, exif);
      final crc = ByteData(4)..setUint32(0, _crc32(typeAndData));
      chunk
        ..add(head.buffer.asUint8List())
        ..add(exif)
        ..add(crc.buffer.asUint8List());
      return (BytesBuilder(copy: false)
            ..add(Uint8List.sublistView(png, 0, i))
            ..add(chunk.takeBytes())
            ..add(Uint8List.sublistView(png, i)))
          .takeBytes();
    }
    i += 12 + len;
  }
  return png;
}

final List<int> _crcTable = List<int>.generate(256, (n) {
  var c = n;
  for (var k = 0; k < 8; k++) {
    c = (c & 1) != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1;
  }
  return c;
});

int _crc32(Uint8List data) {
  var c = 0xFFFFFFFF;
  for (final b in data) {
    c = _crcTable[(c ^ b) & 0xFF] ^ (c >> 8);
  }
  return c ^ 0xFFFFFFFF;
}

/// EXIF 里的拍摄时间（DateTimeOriginal，退而求其次 DateTime），格式 yyyyMMdd_HHmmss
String? exifTakenStamp(Uint8List tiff) {
  if (tiff.length < 8) return null;
  final le = tiff[0] == 0x49;
  final bd = ByteData.sublistView(tiff);
  final endian = le ? Endian.little : Endian.big;
  try {
    String? read(int ifd, int want) {
      final n = bd.getUint16(ifd, endian);
      for (var k = 0; k < n; k++) {
        final e = ifd + 2 + k * 12;
        if (bd.getUint16(e, endian) != want) continue;
        final cnt = bd.getUint32(e + 4, endian);
        final off = cnt > 4 ? bd.getUint32(e + 8, endian) : e + 8;
        if (off + cnt > tiff.length) return null;
        return String.fromCharCodes(tiff.sublist(off, off + cnt))
            .replaceAll('\u0000', '')
            .trim();
      }
      return null;
    }

    int? pointer(int ifd, int want) {
      final n = bd.getUint16(ifd, endian);
      for (var k = 0; k < n; k++) {
        final e = ifd + 2 + k * 12;
        if (bd.getUint16(e, endian) == want) return bd.getUint32(e + 8, endian);
      }
      return null;
    }

    final ifd0 = bd.getUint32(4, endian);
    final exif = pointer(ifd0, 0x8769);
    final raw =
        (exif != null ? read(exif, 0x9003) : null) ?? read(ifd0, 0x0132);
    if (raw == null) return null;
    final m = RegExp(r'(\d{4}):(\d{2}):(\d{2})\s+(\d{2}):(\d{2}):(\d{2})')
        .firstMatch(raw);
    if (m == null) return null;
    return '${m[1]}${m[2]}${m[3]}_${m[4]}${m[5]}${m[6]}';
  } catch (_) {
    return null;
  }
}

/// EXIF 方向（1..8），读不到返回 1
int exifOrientation(Uint8List tiff) {
  if (tiff.length < 8) return 1;
  final le = tiff[0] == 0x49;
  final bd = ByteData.sublistView(tiff);
  final endian = le ? Endian.little : Endian.big;
  try {
    final ifd0 = bd.getUint32(4, endian);
    final n = bd.getUint16(ifd0, endian);
    for (var k = 0; k < n; k++) {
      final e = ifd0 + 2 + k * 12;
      if (bd.getUint16(e, endian) == 0x0112) {
        final v = bd.getUint16(e + 8, endian);
        return v >= 1 && v <= 8 ? v : 1;
      }
    }
  } catch (_) {}
  return 1;
}
