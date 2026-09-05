import 'dart:typed_data';

const metadataLimit = 2 * 1024 * 1024;
typedef ReadAt = Uint8List Function(int offset, int length);

/// Copies only bounded metadata IFDs into a compact TIFF for the EXIF package.
/// No strip/tile/thumbnail pixels or unbounded file prefix are read.
class TiffMetadata {
  TiffMetadata(this.readAt, this.length);
  final ReadAt readAt;
  final int length;
  final warnings = <String>[];
  final xmp = <Uint8List>[];
  final _output = Uint8List(metadataLimit);
  final _visited = <int>{};
  int _used = 8;
  int _read = 0;
  int _entries = 0;
  late Endian _endian;

  Uint8List _get(int offset, int size) {
    if (offset < 0 || size < 0 || offset + size > length) {
      throw const FormatException('TIFF 偏移越界');
    }
    if ((_read += size) > metadataLimit) {
      throw const FormatException('TIFF 元数据超过 2 MB 安全限制');
    }
    return readAt(offset, size);
  }

  int _reserve(int size) {
    if (_used + size > metadataLimit) {
      throw const FormatException('TIFF 元数据超过 2 MB 安全限制');
    }
    final offset = _used;
    _used += size;
    return offset;
  }

  Uint8List normalize() {
    final head = _get(0, 8);
    if (head[0] == 73 && head[1] == 73) {
      _endian = Endian.little;
    } else if (head[0] == 77 && head[1] == 77) {
      _endian = Endian.big;
    } else {
      throw const FormatException('无效 TIFF 字节序');
    }
    final h = ByteData.sublistView(head);
    if (h.getUint16(2, _endian) == 43) {
      throw const FormatException('BigTIFF 暂不支持');
    }
    if (h.getUint16(2, _endian) != 42) {
      throw const FormatException('无效 TIFF 签名');
    }
    _output.setRange(0, 8, head);
    final first = h.getUint32(4, _endian);
    final copied = first == 0 ? 0 : _ifd(first, 0);
    ByteData.sublistView(_output).setUint32(4, copied, _endian);
    return Uint8List.sublistView(_output, 0, _used);
  }

  int _ifd(int offset, int depth) {
    if (depth > 8 || _visited.length >= 32) {
      throw const FormatException('TIFF IFD 超过安全限制');
    }
    if (!_visited.add(offset)) throw const FormatException('TIFF IFD 循环或重复引用');
    final count = ByteData.sublistView(_get(offset, 2)).getUint16(0, _endian);
    if ((_entries += count) > 4096) {
      throw const FormatException('TIFF 标签超过安全限制');
    }
    final raw = _get(offset + 2, count * 12 + 4);
    final table = ByteData.sublistView(raw);
    final entries = <Uint8List>[];
    // These contain pixel offsets/lengths, thumbnails or proprietary offset structures.
    const excluded = {0x111, 0x117, 0x144, 0x145, 0x201, 0x202, 0x927c, 0xea1c};
    const sizes = {
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
      13: 4,
    };
    for (var i = 0; i < count; i++) {
      final p = i * 12;
      final tag = table.getUint16(p, _endian);
      if (excluded.contains(tag)) continue;
      if (tag == 0x14a) {
        warnings.add('TIFF SubIFD 预览/子图元数据暂不展开。');
        continue;
      }
      final type = table.getUint16(p + 2, _endian);
      final unit = sizes[type];
      if (unit == null) {
        warnings.add('TIFF 标签 0x${tag.toRadixString(16)} 的类型 $type 暂不支持。');
        continue;
      }
      final n = table.getUint32(p + 4, _endian);
      final size = n * unit;
      final entry = Uint8List.fromList(raw.sublist(p, p + 12));
      final e = ByteData.sublistView(entry);
      if (tag == 0x8769 || tag == 0x8825 || tag == 0xa005) {
        if ((type != 4 && type != 13) || n != 1) {
          throw const FormatException('无效 TIFF IFD 指针');
        }
        final target = table.getUint32(p + 8, _endian);
        e.setUint16(2, 4, _endian);
        e.setUint32(8, target == 0 ? 0 : _ifd(target, depth + 1), _endian);
      } else if (size > 4 || tag == 700) {
        final value = size > 4
            ? _get(table.getUint32(p + 8, _endian), size)
            : Uint8List.sublistView(entry, 8, 8 + size);
        if (tag == 700) {
          xmp.add(Uint8List.fromList(value));
          continue;
        }
        final dest = _reserve(size);
        _output.setRange(dest, dest + size, value);
        e.setUint32(8, dest, _endian);
      }
      entries.add(entry);
    }
    final dest = _reserve(2 + entries.length * 12 + 4);
    final out = ByteData.sublistView(_output);
    out.setUint16(dest, entries.length, _endian);
    for (var i = 0; i < entries.length; i++) {
      _output.setRange(dest + 2 + i * 12, dest + 14 + i * 12, entries[i]);
    }
    // First primary image and its EXIF/GPS/Interop only; do not mislabel other pages.
    if (table.getUint32(count * 12, _endian) != 0) {
      warnings.add('TIFF 仅显示首个主 IFD 及其 EXIF/GPS；后续页/缩略图元数据未读取。');
    }
    return dest;
  }
}
