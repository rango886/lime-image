import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart' show getCrc32;
import 'package:crypto/crypto.dart' show md5;
import 'package:exif/exif.dart';

import '../../models/image_metadata.dart';
import 'tiff.dart';
import 'xmp.dart';

/// Call in the metadata worker, never in the image decoding path.
Future<ImageMetadata> readImageMetadata(String path) async {
  RandomAccessFile? file;
  final reader = _Reader();
  try {
    file = File(path).openSync();
    reader.file = file;
    reader.length = file.lengthSync();
    final head = reader.at(0, reader.length < 12 ? reader.length : 12);
    if (_starts(head, '\u00ff\u00d8')) {
      await reader.jpeg();
    } else if (_starts(head, '\u0089PNG\r\n\u001a\n')) {
      await reader.png();
    } else if (_starts(head, 'RIFF') &&
        head.length >= 12 &&
        latin1.decode(head.sublist(8, 12)) == 'WEBP') {
      await reader.webp();
    } else if (_starts(head, 'II') || _starts(head, 'MM')) {
      await reader.tiff(reader.at, reader.length);
    } else {
      reader.warnings.add('该格式的元数据暂不支持（当前支持 JPEG、PNG、WebP、经典 TIFF）。');
    }
  } catch (e) {
    reader.warnings.add('读取失败：$e');
  } finally {
    file?.closeSync();
  }
  return ImageMetadata(
    fields: reader.fields,
    warnings: reader.warnings.toSet().toList(),
  );
}

bool _starts(List<int> data, String prefix) {
  if (data.length < prefix.length) return false;
  for (var i = 0; i < prefix.length; i++) {
    if (data[i] != prefix.codeUnitAt(i)) return false;
  }
  return true;
}

class _Reader {
  late RandomAccessFile file;
  late int length;
  final fields = <MetadataField>[];
  final warnings = <String>[];
  var _bytes = 0;
  var _operations = 0;
  var _expanded = 0;

  Uint8List at(int offset, int count) {
    if (++_operations > 20000) throw const FormatException('元数据访问次数超过安全限制');
    if (offset < 0 || count < 0 || offset + count > length) {
      throw const FormatException('容器长度/偏移越界或数据截断');
    }
    // Includes chunk headers, but not skipped pixel data.
    if ((_bytes += count) > metadataLimit + 512 * 1024) {
      throw const FormatException('元数据读取超过安全限制');
    }
    file.setPositionSync(offset);
    final result = file.readSync(count);
    if (result.length != count) throw const FormatException('文件数据截断');
    return result;
  }

  void add(Iterable<MetadataField> values) {
    for (final value in values) {
      if (fields.length >= 4096) throw const FormatException('元数据字段数量超过安全限制');
      fields.add(value);
    }
  }

  void xmp(Uint8List bytes) {
    try {
      add(parseXmp(utf8.decode(bytes).replaceFirst(RegExp(r'\x00+$'), '')));
    } catch (e) {
      warnings.add('XMP 解析失败：$e');
    }
  }

  Future<void> exif(Uint8List bytes) async {
    final data = _starts(bytes, 'Exif\u0000\u0000')
        ? Uint8List.sublistView(bytes, 6)
        : bytes;
    await tiff(
      (offset, count) => Uint8List.sublistView(data, offset, offset + count),
      data.length,
    );
  }

  Future<void> tiff(ReadAt read, int size) async {
    final normalizer = TiffMetadata(read, size);
    try {
      final bytes = normalizer.normalize();
      final tags = await readExifFromBytes(
        bytes,
        // MakerNotes and thumbnail pointers were removed by the bounded copier.
        // Keep details enabled so UserComment is not silently discarded.
        details: true,
        truncateTags: false,
        strict: true,
      );
      for (final entry in tags.entries) {
        final tag = entry.value;
        // Relocated structural pointers are not original metadata values.
        if (const {0x8769, 0x8825, 0xa005}.contains(tag.tag)) continue;
        var value = tag.printable;
        if (tag.tag >= 0x9c9b && tag.tag <= 0x9c9f) {
          final bytes = tag.values.toList().whereType<int>().toList();
          final units = <int>[];
          for (var i = 0; i + 1 < bytes.length; i += 2) {
            final unit = bytes[i] | bytes[i + 1] << 8;
            if (unit == 0) break;
            units.add(unit);
          }
          value = String.fromCharCodes(units);
        }
        add([MetadataField('EXIF', entry.key, value)]);
      }
    } catch (e) {
      warnings.add('EXIF / TIFF 解析失败：$e');
    } finally {
      warnings.addAll(normalizer.warnings);
      for (final packet in normalizer.xmp) {
        xmp(packet);
      }
    }
  }

  Future<void> jpeg() async {
    var p = 2;
    final extended = <String, List<_Fragment>>{};
    final references = <String>{};
    for (var markers = 0; ; markers++) {
      if (markers >= 4096) throw const FormatException('JPEG 段数超过安全限制');
      if (at(p++, 1)[0] != 255) throw const FormatException('无效 JPEG 标记');
      var marker = at(p++, 1)[0];
      var fill = 0;
      while (marker == 255) {
        if (++fill > 4096) throw const FormatException('JPEG 填充超过安全限制');
        marker = at(p++, 1)[0];
      }
      if (marker == 0xda || marker == 0xd9) break;
      if (marker == 1 || (marker >= 0xd0 && marker <= 0xd7)) continue;
      final count = ByteData.sublistView(at(p, 2)).getUint16(0) - 2;
      p += 2;
      if (count < 0 || p + count > length) {
        throw const FormatException('无效 JPEG 段长度');
      }
      if (marker == 0xe1) {
        final data = at(p, count);
        if (_starts(data, 'Exif\u0000\u0000')) {
          await exif(data);
        } else if (_starts(data, 'http://ns.adobe.com/xap/1.0/\u0000')) {
          final before = fields.length;
          xmp(Uint8List.sublistView(data, 29));
          for (final field in fields.skip(before)) {
            if (field.namespace == 'http://ns.adobe.com/xmp/note/' &&
                field.name.endsWith(':HasExtendedXMP')) {
              references.add(field.value.toUpperCase());
            }
          }
        } else if (_starts(data, 'http://ns.adobe.com/xmp/extension/\u0000')) {
          try {
            if (data.length < 75) throw const FormatException('分片头截断');
            final guid = ascii.decode(data.sublist(35, 67)).toUpperCase();
            if (!RegExp(r'^[0-9A-F]{32}$').hasMatch(guid)) {
              throw const FormatException('无效 GUID');
            }
            final header = ByteData.sublistView(data);
            final total = header.getUint32(67);
            final offset = header.getUint32(71);
            if (total == 0 ||
                total > metadataLimit ||
                offset + data.length - 75 > total) {
              throw const FormatException('分片长度/偏移超过安全限制');
            }
            extended
                .putIfAbsent(guid, () => [])
                .add(_Fragment(total, offset, Uint8List.sublistView(data, 75)));
          } catch (e) {
            warnings.add('Extended XMP 解析失败：$e');
          }
        }
      }
      p += count;
    }
    for (final guid in references) {
      try {
        final parts = extended.remove(guid);
        if (parts == null) throw const FormatException('缺少分片');
        parts.sort((a, b) => a.offset.compareTo(b.offset));
        final total = parts.first.total;
        var cursor = 0;
        for (final part in parts) {
          if (part.total != total ||
              part.offset != cursor ||
              part.data.isEmpty) {
            throw const FormatException('分片重叠、缺失或长度不一致');
          }
          cursor += part.data.length;
        }
        if (cursor != total) throw const FormatException('分片不完整');
        final bytes = Uint8List(total);
        for (final part in parts) {
          bytes.setRange(
            part.offset,
            part.offset + part.data.length,
            part.data,
          );
        }
        if (md5.convert(bytes).toString().toUpperCase() != guid) {
          throw const FormatException('MD5 校验失败');
        }
        xmp(bytes);
      } catch (e) {
        warnings.add('Extended XMP $guid：$e');
      }
    }
    if (extended.isNotEmpty) {
      warnings.add('存在未被标准 XMP 引用的 Extended XMP 分片，未合并。');
    }
  }

  Future<void> webp() async {
    final end = ByteData.sublistView(at(4, 4)).getUint32(0, Endian.little) + 8;
    if (end < 12 || end > length) {
      throw const FormatException('无效 WebP RIFF 长度');
    }
    var p = 12;
    while (p < end) {
      if (p + 8 > end) throw const FormatException('WebP 块头截断');
      final head = at(p, 8);
      final name = latin1.decode(head.sublist(0, 4));
      final size = ByteData.sublistView(head).getUint32(4, Endian.little);
      p += 8;
      final next = p + size + (size & 1);
      if (next > end) throw const FormatException('WebP 块越界');
      if (name == 'EXIF') {
        await exif(at(p, size));
      } else if (name == 'XMP ') {
        xmp(at(p, size));
      }
      p = next;
    }
  }

  Future<void> png() async {
    var p = 8;
    while (p < length) {
      final header = at(p, 8);
      final size = ByteData.sublistView(header).getUint32(0);
      final name = latin1.decode(header.sublist(4));
      p += 8;
      if (p + size + 4 > length) throw const FormatException('PNG 块越界');
      if (name == 'IEND') {
        if (size != 0) throw const FormatException('无效 PNG IEND');
        return;
      }
      if (const {'eXIf', 'iTXt', 'tEXt', 'zTXt'}.contains(name)) {
        final data = at(p, size);
        final crc = ByteData.sublistView(at(p + size, 4)).getUint32(0);
        if (getCrc32(data, getCrc32(header.sublist(4))) != crc) {
          warnings.add('PNG $name CRC 校验失败，已跳过。');
        } else if (name == 'eXIf') {
          await exif(data);
        } else {
          try {
            _pngText(name, data);
          } catch (e) {
            warnings.add('PNG $name 文本解析失败：$e');
          }
        }
      }
      p += size + 4;
    }
    throw const FormatException('PNG 缺少 IEND');
  }

  void _pngText(String kind, Uint8List data) {
    var p = 0;
    Uint8List terminated() {
      final end = data.indexOf(0, p);
      if (end < 0) throw const FormatException('PNG 文本字段未终止');
      final value = Uint8List.sublistView(data, p, end);
      p = end + 1;
      return value;
    }

    final keyBytes = terminated();
    if (keyBytes.isEmpty || keyBytes.length > 79) {
      throw const FormatException('PNG 文本关键字长度无效');
    }
    final key = latin1.decode(keyBytes);
    var compressed = false;
    var language = '';
    var translated = '';
    if (kind == 'zTXt') {
      if (p >= data.length || data[p++] != 0) {
        throw const FormatException('PNG 压缩方法暂不支持');
      }
      compressed = true;
    } else if (kind == 'iTXt') {
      if (p + 2 > data.length || data[p] > 1 || data[p + 1] != 0) {
        throw const FormatException('无效 iTXt 压缩头');
      }
      compressed = data[p] == 1;
      p += 2;
      language = ascii.decode(terminated());
      translated = utf8.decode(terminated());
    }
    var bytes = Uint8List.sublistView(data, p);
    if (compressed) {
      if (_expanded >= metadataLimit) {
        throw const FormatException('PNG 文本解压后总量超过 2 MB 安全限制');
      }
      try {
        bytes = _inflate(bytes, metadataLimit - _expanded);
      } catch (_) {
        // Stop subsequent compressed chunks from repeatedly exhausting the budget.
        _expanded = metadataLimit;
        rethrow;
      }
    }
    _expanded += bytes.length;
    if (_expanded > metadataLimit) {
      throw const FormatException('PNG 文本解压后总量超过 2 MB 安全限制');
    }
    if (key == 'XML:com.adobe.xmp') {
      xmp(bytes);
    } else {
      final value = kind == 'iTXt' ? utf8.decode(bytes) : latin1.decode(bytes);
      final suffix = [
        if (language.isNotEmpty) language,
        if (translated.isNotEmpty) translated,
      ].join(' / ');
      add([
        MetadataField(
          'PNG Text',
          suffix.isEmpty ? key : '$key [$suffix]',
          value,
        ),
      ]);
    }
  }
}

class _Fragment {
  _Fragment(this.total, this.offset, this.data);
  final int total;
  final int offset;
  final Uint8List data;
}

Uint8List _inflate(Uint8List input, int limit) {
  final output = _LimitedSink(limit);
  final decoder = zlib.decoder.startChunkedConversion(output);
  // Feed small chunks to bound transient native decoder allocations too.
  for (var p = 0; p < input.length; p += 256) {
    decoder.add(
      Uint8List.sublistView(
        input,
        p,
        p + 256 < input.length ? p + 256 : input.length,
      ),
    );
  }
  decoder.close();
  return output.bytes.takeBytes();
}

class _LimitedSink implements Sink<List<int>> {
  _LimitedSink(this.limit);
  final int limit;
  final bytes = BytesBuilder(copy: false);
  @override
  void add(List<int> data) {
    if (bytes.length + data.length > limit) {
      throw const FormatException('PNG 文本解压后超过 2 MB 安全限制');
    }
    bytes.add(data);
  }

  @override
  void close() {}
}
