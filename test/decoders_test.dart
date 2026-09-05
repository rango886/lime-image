import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:limeimage/services/decoders/decoder_registry.dart';
import 'package:limeimage/services/decoders/embedded_preview.dart';
import 'package:limeimage/services/decoders/format_sniffer.dart';

Uint8List _b(List<int> head, {int pad = 0}) =>
    Uint8List.fromList([...head, ...List.filled(pad, 0)]);

void main() {
  group('FormatSniffer 魔术字节', () {
    test('常见格式', () {
      expect(
        FormatSniffer.sniff(_b([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A], pad: 32))
            .format,
        ImageFormat.png,
      );
      expect(
        FormatSniffer.sniff(_b([0xFF, 0xD8, 0xFF, 0xE0], pad: 32)).format,
        ImageFormat.jpeg,
      );
      expect(
        FormatSniffer.sniff(_b([0x38, 0x42, 0x50, 0x53], pad: 32)).format,
        ImageFormat.psd,
      );
      expect(
        FormatSniffer.sniff(_b([0x76, 0x2F, 0x31, 0x01], pad: 32)).format,
        ImageFormat.exr,
      );
    });

    test('JXL 两种签名都要认（曾经只认了一种）', () {
      // 裸码流
      final naked = FormatSniffer.sniff(
        _b([0xFF, 0x0A, 0x3A, 0x1F, 0x1C, 0x00], pad: 32),
      );
      expect(naked.format, ImageFormat.jxl);
      expect(naked.detail, 'codestream');

      // ISOBMFF 封装
      final boxed = FormatSniffer.sniff(
        _b([
          0x00,
          0x00,
          0x00,
          0x0C,
          0x4A,
          0x58,
          0x4C,
          0x20,
          0x0D,
          0x0A,
          0x87,
          0x0A,
        ], pad: 32),
      );
      expect(boxed.format, ImageFormat.jxl);
      expect(boxed.detail, 'ISOBMFF');
    });

    test('ISOBMFF brand 区分 HEIC / AVIF / CR3', () {
      Uint8List ftyp(String brand) => _b([
        0, 0, 0, 0x20, // box size
        0x66, 0x74, 0x79, 0x70, // 'ftyp'
        ...brand.codeUnits,
      ], pad: 32);

      expect(FormatSniffer.sniff(ftyp('avif')).format, ImageFormat.avif);
      expect(FormatSniffer.sniff(ftyp('heic')).format, ImageFormat.heif);
      expect(FormatSniffer.sniff(ftyp('mif1')).format, ImageFormat.heif);
      final cr3 = FormatSniffer.sniff(ftyp('crx '));
      expect(cr3.format, ImageFormat.raw);
      expect(cr3.detail, 'CR3');
    });

    test('TIFF vs RAW 靠扩展名区分（魔术字节相同）', () {
      final tiffHead = _b([0x49, 0x49, 0x2A, 0x00], pad: 32);
      expect(
        FormatSniffer.sniff(tiffHead, ext: '.tif').format,
        ImageFormat.tiff,
      );
      expect(
        FormatSniffer.sniff(tiffHead, ext: '.cr2').format,
        ImageFormat.raw,
      );
      expect(
        FormatSniffer.sniff(tiffHead, ext: '.nef').format,
        ImageFormat.raw,
      );
    });

    test('改错后缀时以内容为准', () {
      // 实际是 PNG 但后缀写成 .jpg
      expect(
        FormatSniffer.sniff(
          _b([0x89, 0x50, 0x4E, 0x47], pad: 32),
          ext: '.jpg',
        ).format,
        ImageFormat.png,
      );
    });

    test('RAW 各家私有签名', () {
      expect(
        FormatSniffer.sniff(_b('FUJIFILM'.codeUnits, pad: 32)).format,
        ImageFormat.raw,
      );
      expect(
        FormatSniffer.sniff(_b('FOVb'.codeUnits, pad: 32)).format,
        ImageFormat.raw,
      );
    });
  });

  group('PSD 内嵌缩略图', () {
    /// 造一个最小 PSD：头 + 空 ColorModeData + 含 1036 资源的 ImageResources
    Uint8List buildPsd(Uint8List jpeg, {int docW = 1080, int docH = 2404}) {
      final out = BytesBuilder();
      void u32(int v) => out.add([
        (v >> 24) & 0xFF,
        (v >> 16) & 0xFF,
        (v >> 8) & 0xFF,
        v & 0xFF,
      ]);
      void u16(int v) => out.add([(v >> 8) & 0xFF, v & 0xFF]);

      // File Header (26)
      out.add('8BPS'.codeUnits);
      u16(1); // version
      out.add(List.filled(6, 0)); // reserved
      u16(4); // channels
      u32(docH);
      u32(docW);
      u16(8); // depth
      u16(3); // RGB
      u32(0); // Color Mode Data 长度

      // Image Resources
      final res = BytesBuilder();
      void ru32(int v) => res.add([
        (v >> 24) & 0xFF,
        (v >> 16) & 0xFF,
        (v >> 8) & 0xFF,
        v & 0xFF,
      ]);
      void ru16(int v) => res.add([(v >> 8) & 0xFF, v & 0xFF]);

      res.add('8BIM'.codeUnits);
      ru16(1036);
      res.add([0, 0]); // 空 Pascal 字符串 + 补齐
      final thumbData = BytesBuilder();
      void tu32(int v) => thumbData.add([
        (v >> 24) & 0xFF,
        (v >> 16) & 0xFF,
        (v >> 8) & 0xFF,
        v & 0xFF,
      ]);
      tu32(1); // format = kJpegRGB
      tu32(71);
      tu32(160);
      tu32(71 * 3);
      tu32(71 * 160 * 3);
      tu32(jpeg.length);
      thumbData.add([0, 24]); // bitsPerPixel
      thumbData.add([0, 1]); // planes
      thumbData.add(jpeg);
      final td = thumbData.toBytes();
      ru32(td.length);
      res.add(td);
      if (td.length % 2 != 0) res.add([0]);

      final rb = res.toBytes();
      u32(rb.length);
      out.add(rb);
      return out.toBytes();
    }

    /// 一段最小但结构合法的 JPEG：SOI + SOF0 + EOI
    Uint8List minimalJpeg(int w, int h) {
      final b = BytesBuilder();
      b.add([0xFF, 0xD8]); // SOI
      b.add([0xFF, 0xC0, 0x00, 0x11, 0x08]); // SOF0, len=17, precision=8
      b.add([(h >> 8) & 0xFF, h & 0xFF]);
      b.add([(w >> 8) & 0xFF, w & 0xFF]);
      b.add([0x03]); // 3 components
      b.add([1, 0x22, 0, 2, 0x11, 1, 3, 0x11, 1]);
      // 塞点填充让它超过 _minPreviewBytes 门槛不是必需的（PSD 路径不看大小）
      b.add([0xFF, 0xD9]); // EOI
      return b.toBytes();
    }

    test('能抠出 1036 资源里的 JPEG 并读出尺寸', () async {
      final jpeg = minimalJpeg(71, 160);
      final psd = buildPsd(jpeg);
      final f = File(
        '${Directory.systemTemp.path}/limeimage_test_${DateTime.now().microsecondsSinceEpoch}.psd',
      );
      await f.writeAsBytes(psd);
      addTearDown(() => f.existsSync() ? f.deleteSync() : null);

      final d = EmbeddedPreviewDecoder();
      final r = await d.decode(f.path, targetWidth: 256);

      expect(r.isEncoded, isTrue);
      expect(r.previewOnly, isTrue);
      expect(r.encoded!.sublist(0, 2), [0xFF, 0xD8]);
      expect(r.width, 71);
      expect(r.height, 160);
      // 文档尺寸来自 PSD 头，不是缩略图尺寸
      expect(r.naturalWidth, 1080);
      expect(r.naturalHeight, 2404);
    });

    test('没有缩略图资源时应抛异常而不是返回垃圾', () async {
      final out = BytesBuilder();
      out.add('8BPS'.codeUnits);
      out.add([0, 1]);
      out.add(List.filled(6, 0));
      out.add([0, 4]);
      out.add([0, 0, 0x09, 0x64]);
      out.add([0, 0, 0x04, 0x38]);
      out.add([0, 8]);
      out.add([0, 3]);
      out.add([0, 0, 0, 0]); // ColorModeData 长度
      out.add([0, 0, 0, 0]); // ImageResources 长度 = 0
      final f = File(
        '${Directory.systemTemp.path}/limeimage_test_nothumb_${DateTime.now().microsecondsSinceEpoch}.psd',
      );
      await f.writeAsBytes(out.toBytes());
      addTearDown(() => f.existsSync() ? f.deleteSync() : null);

      final d = EmbeddedPreviewDecoder();
      await expectLater(
        d.decode(f.path, targetWidth: 256),
        throwsA(isA<Exception>()),
      );
    });

    test('worker isolate 池里解码，主 isolate 不参与', () async {
      final psd = buildPsd(minimalJpeg(71, 160));
      final f = File(
        '${Directory.systemTemp.path}/limeimage_test_pool_${DateTime.now().microsecondsSinceEpoch}.psd',
      );
      await f.writeAsBytes(psd);
      addTearDown(() => f.existsSync() ? f.deleteSync() : null);

      final reg = DecoderRegistry(useIsolates: true, isolateCount: 2);
      addTearDown(reg.dispose);
      // probed = 初始化 + 后台探测（池启动）都做完
      await reg.probed;
      expect(reg.isolateCount, 2);

      final r = await reg.decode(
        f.path,
        const SniffResult(ImageFormat.psd),
        targetWidth: 64,
      );
      expect(r.decoderId, 'embedded-preview');
      expect(r.isEncoded, isTrue);
      expect(r.encoded!.sublist(0, 2), [0xFF, 0xD8]);
      expect(r.naturalWidth, 1080);
      // 重点：没有回退到主 isolate
      expect(reg.mainIsolateDecodes, 0);
      expect(reg.stats['embedded-preview']?.success, 1);
    });
  });

  group('DecoderRegistry', () {
    test('内置格式不该进外部解码链', () async {
      final reg = DecoderRegistry();
      await reg.initialize();
      addTearDown(reg.dispose);

      for (final f in ImageFormat.values.where((f) => f.skiaNative)) {
        final status = reg.report().firstWhere((s) => s.format == f);
        expect(
          status.support,
          FormatSupport.native,
          reason: '${f.label} 应该走 Skia 内置路径',
        );
      }
    });

    test('SVG 不在位图解码链里（应走 flutter_svg 旁路）', () async {
      final reg = DecoderRegistry();
      await reg.initialize();
      addTearDown(reg.dispose);
      expect(reg.chainFor(ImageFormat.svg), isEmpty);
    });

    test('Windows 上 WIC 应可用并枚举出解码器', () async {
      final reg = DecoderRegistry();
      addTearDown(reg.dispose);
      // WIC 的 COM 枚举现在在后台 isolate 里做（不卡主 isolate）
      await reg.probed;
      expect(reg.wicAvailable, isTrue);
      expect(reg.wicCodecs, isNotEmpty);
      // 内置 codec 至少应有 PNG / JPEG / TIFF
      final allExt = reg.wicCodecs.expand((c) => c.extensions).toSet();
      expect(allExt, containsAll(<String>['.png', '.tiff']));
    }, skip: !Platform.isWindows);
  });
}
