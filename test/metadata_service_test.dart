import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:limeimage/services/metadata_service.dart';

void main() {
  late Directory temp;
  setUp(
    () async => temp = await Directory.systemTemp.createTemp('lime-metadata-'),
  );
  tearDown(() async => temp.delete(recursive: true));

  Future<File> jpeg(List<List<int>> segments) async {
    final file = File('${temp.path}/test.jpg');
    await file.writeAsBytes([
      255,
      216,
      for (final data in segments) ...[
        255,
        225,
        (data.length + 2) >> 8,
        (data.length + 2) & 255,
        ...data,
      ],
      255,
      217,
    ]);
    return file;
  }

  List<int> xmp(String xml) => [
    ...latin1.encode('http://ns.adobe.com/xap/1.0/\u0000'),
    ...utf8.encode(xml),
  ];
  const packet =
      '<x:xmpmeta xmlns:x="adobe:ns:meta/"><r:RDF xmlns:r="http://www.w3.org/1999/02/22-rdf-syntax-ns#"><r:Description xmlns:d="http://purl.org/dc/elements/1.1/" xmlns:t="urn:test" t:tool="软件"><d:creator><r:Seq><r:li>Scott Eaton</r:li><r:li>测试</r:li></r:Seq></d:creator><d:rights><r:Alt><r:li xml:lang="x-default">版权</r:li></r:Alt></d:rights></r:Description></r:RDF></x:xmpmeta>';

  test('namespace aliases, arrays, languages and attributes', () {
    final fields = parseXmp(packet);
    expect(
      fields.map((f) => f.value),
      containsAll(['Scott Eaton', '测试', '版权', 'x-default', '软件']),
    );
    expect(fields.any((f) => f.name.contains('li[2]')), isTrue);
    expect(fields.firstWhere((f) => f.value == '软件').namespace, 'urn:test');
  });
  test('EXIF XPSubject decodes UTF-16LE', () async {
    // Little endian TIFF: one BYTE field (XPSubject), offset 26.
    final file = await jpeg([
      [
        ...latin1.encode('Exif\u0000\u0000'),
        0x49,
        0x49,
        42,
        0,
        8,
        0,
        0,
        0,
        1,
        0,
        0x9f,
        0x9c,
        1,
        0,
        6,
        0,
        0,
        0,
        26,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0x4b,
        0x6d,
        0xd5,
        0x8b,
        0,
        0,
      ],
    ]);
    final result = await readJpegMetadata(file.path);
    expect(result.warnings, isEmpty);
    expect(result.fields.single.value, '测试');
  });

  test('JPEG XMP and long values are retained', () async {
    final file = await jpeg([
      xmp(packet),
      xmp(packet.replaceFirst('版权', '长' * 500)),
    ]);
    final result = await readJpegMetadata(file.path);
    expect(result.warnings, isEmpty);
    expect(result.fields.any((f) => f.value.length == 500), isTrue);
  });
  test('empty, unsupported and truncated are distinct', () async {
    final file = await jpeg([]);
    expect((await readJpegMetadata(file.path)).warnings, isEmpty);
    await file.writeAsBytes([1, 2]);
    expect(
      (await readJpegMetadata(file.path)).warnings.single,
      contains('暂不支持'),
    );
    await file.writeAsBytes([255, 216, 255, 225, 0, 40]);
    expect(
      (await readJpegMetadata(file.path)).warnings.single,
      contains('读取失败'),
    );
  });
  test('extended XMP is explicitly reported', () async {
    final file = await jpeg([
      latin1.encode('http://ns.adobe.com/xmp/extension/\u0000abc'),
    ]);
    expect(
      (await readJpegMetadata(file.path)).warnings.single,
      contains('Extended XMP'),
    );
  });
  test('DTD and deep structures are rejected', () {
    expect(() => parseXmp('<!DOCTYPE x><x/>'), throwsFormatException);
    final deep = packet.replaceFirst(
      'Scott Eaton',
      '${'<n>' * 40}text${'</n>' * 40}',
    );
    expect(() => parseXmp(deep), throwsFormatException);
  });
  test('service cancellation and stat-based cache invalidation', () async {
    final file = await jpeg([xmp(packet)]);
    final service = MetadataService();
    final canceled = service.load(file.path);
    service.cancel();
    expect(await canceled, isNull);
    final first = await service.load(file.path);
    expect(first!.fields, isNotEmpty);
    expect(identical(await service.load(file.path), first), isTrue);
    await file.writeAsBytes([255, 216, 255, 217]);
    expect((await service.load(file.path))!.fields, isEmpty);
  });
}
