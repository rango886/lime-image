import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart' show getCrc32;
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:limeimage/services/metadata_service.dart';

List<int> u32(int n, [Endian endian = Endian.big]) =>
    (ByteData(4)..setUint32(0, n, endian)).buffer.asUint8List();
List<int> u16(int n, [Endian endian = Endian.big]) =>
    (ByteData(2)..setUint16(0, n, endian)).buffer.asUint8List();
const packet =
    '<r:RDF xmlns:r="http://www.w3.org/1999/02/22-rdf-syntax-ns#"><r:Description xmlns:d="http://purl.org/dc/elements/1.1/" d:title="测试"/></r:RDF>';
List<int> chunk(String name, List<int> bytes, {bool badCrc = false}) => [
  ...u32(bytes.length),
  ...ascii.encode(name),
  ...bytes,
  ...u32(badCrc ? 0 : getCrc32([...ascii.encode(name), ...bytes])),
];
List<int> png(List<List<int>> chunks) => [
  137,
  80,
  78,
  71,
  13,
  10,
  26,
  10,
  ...chunk('IHDR', [...u32(1), ...u32(1), 8, 2, 0, 0, 0]),
  for (final c in chunks) ...c,
  ...chunk('IEND', []),
];
List<int> riff(String name, List<int> data) => [
  ...ascii.encode(name),
  ...u32(data.length, Endian.little),
  ...data,
  if (data.length.isOdd) 0,
];
List<int> webp(List<List<int>> chunks) {
  final body = [...ascii.encode('WEBP'), for (final c in chunks) ...c];
  return [...ascii.encode('RIFF'), ...u32(body.length, Endian.little), ...body];
}

List<int> jpeg(List<List<int>> segments) => [
  255,
  216,
  for (final data in segments) ...[255, 225, ...u16(data.length + 2), ...data],
  255,
  217,
];
List<int> standard(String text) => [
  ...ascii.encode('http://ns.adobe.com/xap/1.0/\u0000'),
  ...utf8.encode(text),
];
List<int> fragment(String guid, List<int> data, int total, int offset) => [
  ...ascii.encode('http://ns.adobe.com/xmp/extension/\u0000$guid'),
  ...u32(total),
  ...u32(offset),
  ...data,
];
String reference(String guid) =>
    '<r:RDF xmlns:r="http://www.w3.org/1999/02/22-rdf-syntax-ns#"><r:Description xmlns:n="http://ns.adobe.com/xmp/note/" n:HasExtendedXMP="$guid"/></r:RDF>';

/// TIFF copyright and XMP, optionally placing the primary IFD far beyond the header.
List<int> tiffTable(Endian e, int offset) {
  final copyright = ascii.encode('Example author\u0000');
  final xmp = utf8.encode(packet);
  final values = offset + 2 + 24 + 4;
  return [
    ...u16(2, e),
    ...u16(0x8298, e),
    ...u16(2, e),
    ...u32(copyright.length, e),
    ...u32(values, e),
    ...u16(700, e),
    ...u16(1, e),
    ...u32(xmp.length, e),
    ...u32(values + copyright.length, e),
    ...u32(0, e),
    ...copyright,
    ...xmp,
  ];
}

List<int> tiffHead(Endian e, [int offset = 8]) => [
  if (e == Endian.little) ...[73, 73] else ...[77, 77],
  ...u16(42, e),
  ...u32(offset, e),
];
List<int> tiff(Endian e) => [...tiffHead(e), ...tiffTable(e, 8)];

void main() {
  late Directory temp;
  var index = 0;
  setUp(
    () async => temp = await Directory.systemTemp.createTemp('lime-formats-'),
  );
  tearDown(() async => temp.delete(recursive: true));
  Future<String> save(List<int> bytes) async {
    // Deliberately wrong extension verifies signature-based detection.
    final file = File('${temp.path}/${index++}.bin');
    await file.writeAsBytes(bytes);
    return file.path;
  }

  test(
    'PNG EXIF, UTF-8 iTXt, Latin-1 text, compressed text and XMP after IDAT',
    () async {
      final path = await save(
        png([
          chunk('eXIf', tiff(Endian.little)),
          chunk('IDAT', [0, 1, 2, 3]),
          chunk('tEXt', latin1.encode('Author\u0000René')),
          chunk('zTXt', [
            ...ascii.encode('parameters\u0000'),
            0,
            ...zlib.encode(latin1.encode('steps: 30')),
          ]),
          chunk('iTXt', [
            ...ascii.encode('prompt\u0000'),
            0,
            0,
            ...ascii.encode('zh\u0000'),
            ...utf8.encode('提示\u0000中文描述'),
          ]),
          chunk('iTXt', [
            ...ascii.encode('XML:com.adobe.xmp\u0000'),
            1,
            0,
            0,
            0,
            ...zlib.encode(utf8.encode(packet)),
          ]),
        ]),
      );
      final result = await readImageMetadata(path);
      expect(result.warnings, isEmpty);
      expect(
        result.fields.map((f) => f.value),
        containsAll(['Example author', 'René', 'steps: 30', '中文描述', '测试']),
      );
      expect(result.fields.where((f) => f.source == 'PNG Text').length, 3);
      expect(result.fields.any((f) => f.name == 'prompt [zh / 提示]'), isTrue);
    },
  );

  test('PNG corrupt text isolated; huge compressed output bounded', () async {
    final result = await readImageMetadata(
      await save(
        png([
          chunk('tEXt', ascii.encode('bad\u0000bad'), badCrc: true),
          chunk('zTXt', [
            ...ascii.encode('bomb\u0000'),
            0,
            ...zlib.encode(List.filled(3 * 1024 * 1024, 65)),
          ]),
          chunk('tEXt', ascii.encode('Author\u0000Still readable')),
        ]),
      ),
    );
    expect(result.warnings.any((w) => w.contains('CRC')), isTrue);
    expect(result.warnings.any((w) => w.contains('2 MB')), isTrue);
    expect(result.fields.any((f) => f.name == 'bomb'), isFalse);
  });

  test('PNG malformed text and out-of-bounds chunk are reported', () async {
    final badText = await readImageMetadata(
      await save(
        png([
          chunk('iTXt', [65, 0, 1]),
        ]),
      ),
    );
    expect(badText.warnings, isNotEmpty);
    final badChunk = await readImageMetadata(
      await save([
        137,
        80,
        78,
        71,
        13,
        10,
        26,
        10,
        ...u32(0xffffffff),
        ...ascii.encode('iTXt'),
      ]),
    );
    expect(badChunk.warnings.single, contains('越界'));
  });

  for (final prefixed in [false, true]) {
    test('WebP odd padding, EXIF prefix=$prefixed and XMP', () async {
      final result = await readImageMetadata(
        await save(
          webp([
            riff('VP8 ', [1, 2, 3]),
            riff('EXIF', [
              if (prefixed) ...ascii.encode('Exif\u0000\u0000'),
              ...tiff(Endian.big),
            ]),
            riff('XMP ', utf8.encode(packet)),
          ]),
        ),
      );
      expect(result.warnings, isEmpty);
      expect(
        result.fields.map((f) => f.value),
        containsAll(['Example author', '测试']),
      );
    });
  }
  test('WebP RIFF and child lengths validated', () async {
    final result = await readImageMetadata(
      await save([
        ...ascii.encode('RIFF'),
        ...u32(100, Endian.little),
        ...ascii.encode('WEBP'),
      ]),
    );
    expect(result.warnings.single, contains('RIFF'));
    final child = await readImageMetadata(
      await save(
        webp([
          [...ascii.encode('XMP '), ...u32(99999, Endian.little)],
        ]),
      ),
    );
    expect(child.warnings.single, contains('越界'));
  });

  for (final endian in [Endian.little, Endian.big]) {
    test(
      'TIFF endian=$endian and distant IFD without whole file read',
      () async {
        final file = File('${temp.path}/large.tif');
        final raf = await file.open(mode: FileMode.write);
        const offset = 16 * 1024 * 1024;
        await raf.writeFrom(tiffHead(endian, offset));
        await raf.setPosition(offset);
        await raf.writeFrom(tiffTable(endian, offset));
        await raf.close();
        final result = await readImageMetadata(file.path);
        expect(result.warnings, isEmpty);
        expect(
          result.fields.map((f) => f.value),
          containsAll(['Example author', '测试']),
        );
      },
    );
  }
  test('TIFF relocated EXIF/GPS and long UserComment', () async {
    const e = Endian.little;
    final comment = [
      ...ascii.encode('ASCII\u0000\u0000\u0000'),
      ...ascii.encode('C' * 500),
    ];
    final result = await readImageMetadata(
      await save([
        ...tiffHead(e),
        ...u16(2, e),
        ...u16(0x8825, e),
        ...u16(4, e),
        ...u32(1, e),
        ...u32(38, e),
        ...u16(0x8769, e),
        ...u16(4, e),
        ...u32(1, e),
        ...u32(56, e),
        ...u32(0, e),
        ...u16(1, e),
        ...u16(1, e),
        ...u16(2, e),
        ...u32(2, e),
        78,
        0,
        0,
        0,
        ...u32(0, e),
        ...u16(1, e),
        ...u16(0x9286, e),
        ...u16(7, e),
        ...u32(comment.length, e),
        ...u32(74, e),
        ...u32(0, e),
        ...comment,
      ]),
    );
    expect(result.warnings, isEmpty);
    expect(result.fields.map((f) => f.value), containsAll(['N', 'C' * 500]));
    expect(result.fields.any((f) => f.name.contains('Offset')), isFalse);
  });

  test(
    'PNG metadata after large pixel chunk is found without reading pixels',
    () async {
      final file = File('${temp.path}/large.png');
      final raf = await file.open(mode: FileMode.write);
      const size = 16 * 1024 * 1024;
      await raf.writeFrom([
        137,
        80,
        78,
        71,
        13,
        10,
        26,
        10,
        ...u32(size),
        ...ascii.encode('IDAT'),
      ]);
      await raf.setPosition(16 + size + 4);
      await raf.writeFrom([
        ...chunk('tEXt', ascii.encode('Author\u0000after pixels')),
        ...chunk('IEND', []),
      ]);
      await raf.close();
      final result = await readImageMetadata(file.path);
      expect(result.warnings, isEmpty);
      expect(result.fields.single.value, 'after pixels');
    },
  );

  test(
    'TIFF cycles, invalid offsets, unsupported BigTIFF and excessive counts',
    () async {
      const e = Endian.little;
      for (final target in [8, 0xffffffff]) {
        final result = await readImageMetadata(
          await save([
            ...tiffHead(e),
            ...u16(1, e),
            ...u16(0x8769, e),
            ...u16(4, e),
            ...u32(1, e),
            ...u32(target, e),
            ...u32(0, e),
          ]),
        );
        expect(result.warnings, isNotEmpty);
      }
      final big = await readImageMetadata(
        await save([73, 73, 43, 0, 8, 0, 0, 0]),
      );
      expect(big.warnings.single, contains('BigTIFF'));
      final count = await readImageMetadata(
        await save([...tiffHead(e), ...u16(65535, e)]),
      );
      expect(count.warnings.single, contains('安全限制'));
    },
  );

  test('Extended XMP >64KB reassembles out of order with MD5 and namespace reference', () async {
    final text = packet.replaceFirst('测试', '长' * 25000);
    final data = utf8.encode(text);
    final guid = md5.convert(data).toString().toUpperCase();
    final result = await readImageMetadata(
      await save(
        jpeg([
          fragment(guid, data.sublist(50000), data.length, 50000),
          standard(reference(guid)),
          fragment(guid, data.sublist(0, 50000), data.length, 0),
        ]),
      ),
    );
    expect(result.warnings, isEmpty);
    expect(result.fields.any((f) => f.value.length == 25000), isTrue);
  });

  test(
    'Extended XMP missing, overlapping, unreferenced and wrong digest rejected',
    () async {
      final data = utf8.encode(packet);
      final guid = md5.convert(data).toString().toUpperCase();
      final cases = [
        [standard(reference(guid))],
        [
          standard(reference(guid)),
          fragment(guid, data, data.length, 0),
          fragment(guid, data, data.length, 0),
        ],
        [fragment(guid, data, data.length, 0)],
        [
          standard(reference('0' * 32)),
          fragment('0' * 32, data, data.length, 0),
        ],
        [
          standard(reference(guid)),
          fragment(guid, data.sublist(1), data.length, 1),
        ],
        [standard(reference(guid)), fragment(guid, data, 0xffffffff, 0)],
      ];
      for (final segments in cases) {
        final result = await readImageMetadata(await save(jpeg(segments)));
        expect(result.warnings.any((w) => w.contains('Extended XMP')), isTrue);
        expect(result.fields.any((f) => f.value == '测试'), isFalse);
      }
    },
  );
}
