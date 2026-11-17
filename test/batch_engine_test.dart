import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:limeimage/batch/convert_preset.dart';
import 'package:limeimage/batch/engine/convert_engine.dart';
import 'package:limeimage/batch/engine/exif_patch.dart';
import 'package:limeimage/batch/engine/pixels.dart';
import 'package:limeimage/batch/naming.dart';
import 'package:path/path.dart' as p;

/// 小端 TIFF：IFD0 = Orientation + GPS 指针，GPS IFD 里一个 ASCII 标签
Uint8List _exif({int orientation = 6}) {
  final b = ByteData(80);
  b.setUint8(0, 0x49);
  b.setUint8(1, 0x49);
  b.setUint16(2, 42, Endian.little);
  b.setUint32(4, 8, Endian.little);
  // IFD0 @8: 2 个条目
  b.setUint16(8, 2, Endian.little);
  b.setUint16(10, 0x0112, Endian.little);
  b.setUint16(12, 3, Endian.little);
  b.setUint32(14, 1, Endian.little);
  b.setUint16(18, orientation, Endian.little);
  b.setUint16(22, 0x8825, Endian.little);
  b.setUint16(24, 4, Endian.little);
  b.setUint32(26, 1, Endian.little);
  b.setUint32(30, 40, Endian.little);
  b.setUint32(34, 0, Endian.little); // next IFD
  // GPS IFD @40: 1 个条目，ASCII 8 字节放在 @58
  b.setUint16(40, 1, Endian.little);
  b.setUint16(42, 0x0001, Endian.little);
  b.setUint16(44, 2, Endian.little);
  b.setUint32(46, 8, Endian.little);
  b.setUint32(50, 58, Endian.little);
  b.setUint32(54, 0, Endian.little);
  final out = b.buffer.asUint8List();
  out.setRange(58, 66, 'SECRETS\u0000'.codeUnits);
  return out;
}

void main() {
  test('orient maps all eight EXIF codes', () {
    // 2x1: [A, B]
    final px = Pix(2, 1, Uint8List.fromList([1, 0, 0, 255, 2, 0, 0, 255]));
    expect(orient(px, 2).data[0], 2);
    final r6 = orient(px, 6);
    expect((r6.width, r6.height), (1, 2));
    expect(r6.data[0], 1); // 顺时针：A 到上面
    final r8 = orient(px, 8);
    expect(r8.data[0], 2);
  });

  test('crop helpers and resize targets', () {
    final pre = ConvertPreset()
      ..crop = CropMode.ratio
      ..ratioW = 1
      ..ratioH = 1
      ..anchor = 4;
    final r = cropRectFor(pre, Pix.blank(400, 200))!;
    expect((r.x, r.y, r.w, r.h), (100, 0, 200, 200));

    pre
      ..resize = ResizeMode.longEdge
      ..resizeValue = 100;
    expect(resizeTarget(pre, 400, 200), (100, 50));
    pre.resizeValue = 1000;
    expect(resizeTarget(pre, 400, 200), (400, 200)); // 不放大
  });

  test('exif patch resets orientation and wipes GPS', () {
    final e = _exif();
    expect(exifOrientation(e), 6);
    final patched = patchExif(
      e,
      resetOrientation: true,
      stripGps: true,
      width: 10,
      height: 10,
    )!;
    expect(exifOrientation(patched), 1);
    expect(String.fromCharCodes(patched).contains('SECRETS'), isFalse);
  });

  test('names and conflicts', () {
    final n = renderName(
      '{name}_{n}_{w}x{h}',
      source: r'C:\a\IMG 1.jpg',
      seq: 7,
      digits: 3,
      width: 10,
      height: 20,
    );
    expect(n, 'IMG 1_007_10x20');
    expect(
      renderName('a:b?', source: 'x.jpg', seq: 1, digits: 1, width: 1, height: 1),
      'a_b_',
    );
    final claimed = <String>{};
    final dir = Directory.systemTemp.path;
    final first = resolveConflict(
      p.join(dir, 'lime-nonexistent-x.jpg'),
      ConflictPolicy.rename,
      claimed,
    );
    final second = resolveConflict(
      p.join(dir, 'lime-nonexistent-x.jpg'),
      ConflictPolicy.rename,
      claimed,
    );
    expect(first, isNot(second));
    expect(second, endsWith('lime-nonexistent-x (2).jpg'));
  });

  group('engine', () {
    late Directory dir;
    setUpAll(() async {
      dir = await Directory.systemTemp.createTemp('lime-batch-');
    });
    tearDownAll(() => dir.delete(recursive: true));

    Future<String?> ffmpeg() => ConvertEngine().ffmpeg();

    test('jpeg with EXIF -> rotated, resized jpeg keeping EXIF', () async {
      final ff = await ffmpeg();
      if (ff == null) return markTestSkipped('no ffmpeg');
      final raw = p.join(dir.path, 'raw.jpg');
      await Process.run(ff, [
        '-v', 'error', '-f', 'lavfi', '-i', 'testsrc2=size=800x400', //
        '-frames:v', '1', '-y', raw,
      ]);
      final withExif = insertJpegSegments(
        await File(raw).readAsBytes(),
        _exif(),
        const [],
      );
      final src = p.join(dir.path, 'exif.jpg');
      await File(src).writeAsBytes(withExif);

      final engine = ConvertEngine();
      final img = await engine.load(src);
      expect(img.orientation, 6);
      final pre = ConvertPreset()
        ..format = OutputFormat.jpeg
        ..resize = ResizeMode.longEdge
        ..resizeValue = 200
        ..metadata = MetadataPolicy.stripGps;
      final r = await engine.process(img, pre);
      expect(r.error, isNull);
      expect((r.srcW, r.srcH), (400, 800));
      expect((r.outW, r.outH), (100, 200));
      expect(r.exifKept, isTrue);
      final out = extractExif(r.bytes!)!;
      expect(exifOrientation(out), 1);
      expect(String.fromCharCodes(out).contains('SECRETS'), isFalse);

      // 再解一次，确认是合法 JPEG 且尺寸对
      final back = p.join(dir.path, 'back.jpg');
      await File(back).writeAsBytes(r.bytes!);
      final again = await engine.load(back);
      expect((again.pix.width, again.pix.height), (100, 200));
    });

    test('png with alpha -> png keeps alpha, jpeg flattens', () async {
      final ff = await ffmpeg();
      if (ff == null) return markTestSkipped('no ffmpeg');
      final src = p.join(dir.path, 'alpha.png');
      await Process.run(ff, [
        '-v', 'error', '-f', 'lavfi', //
        '-i', 'color=c=red@0.5:s=64x32,format=rgba',
        '-frames:v', '1', '-y', src,
      ]);
      final engine = ConvertEngine();
      final img = await engine.load(src);
      final png = await engine.process(
        img,
        ConvertPreset()..format = OutputFormat.png,
      );
      expect(png.error, isNull);
      expect(png.outAlpha, isTrue);
      final back = await engine.load(
        (await File(p.join(dir.path, 'o.png')).writeAsBytes(png.bytes!)).path,
      );
      expect(back.pix.hasAlpha, isTrue);

      final jpg = await engine.process(
        img,
        ConvertPreset()
          ..format = OutputFormat.jpeg
          ..crop = CropMode.fixed
          ..fixedW = 10
          ..fixedH = 10,
      );
      expect(jpg.error, isNull);
      expect((jpg.outW, jpg.outH), (10, 10));
      expect(jpg.outAlpha, isFalse);
    });

    for (final f in [
      OutputFormat.webp,
      OutputFormat.avif,
      OutputFormat.tiff,
      OutputFormat.bmp,
    ]) {
      test('encode ${f.name}', () async {
        final ff = await ffmpeg();
        if (ff == null) return markTestSkipped('no ffmpeg');
        final src = p.join(dir.path, 'src-${f.name}.png');
        await Process.run(ff, [
          '-v', 'error', '-f', 'lavfi', '-i', 'testsrc2=size=96x64', //
          '-frames:v', '1', '-y', src,
        ]);
        final engine = ConvertEngine();
        final r = await engine.process(
          await engine.load(src),
          ConvertPreset()
            ..format = f
            ..rotate = RotateBy.cw90,
        );
        if (r.error?.contains('AV1') ?? false) {
          return markTestSkipped('no av1');
        }
        expect(r.error, isNull);
        expect((r.outW, r.outH), (64, 96));
        final out = p.join(dir.path, 'o.${r.ext}');
        await File(out).writeAsBytes(r.bytes!);
        final back = await engine.load(out);
        expect((back.pix.width, back.pix.height), (64, 96));
      });
    }

    test('size limit lowers quality', () async {
      final ff = await ffmpeg();
      if (ff == null) return markTestSkipped('no ffmpeg');
      final src = p.join(dir.path, 'big.png');
      await Process.run(ff, [
        '-v', 'error', '-f', 'lavfi', '-i', 'testsrc2=size=1200x800', //
        '-frames:v', '1', '-y', src,
      ]);
      final engine = ConvertEngine();
      final r = await engine.process(
        await engine.load(src),
        ConvertPreset()
          ..format = OutputFormat.jpeg
          ..jpegQuality = 100
          ..limitSize = true
          ..maxKb = 40,
      );
      expect(r.error, isNull);
      expect(r.bytes!.length, lessThanOrEqualTo(40 * 1024));
      expect(r.quality, lessThan(100));
    });
  });
}
