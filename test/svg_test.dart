import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:limeimage/core/utils.dart';
import 'package:limeimage/models/settings.dart';
import 'package:limeimage/services/image_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SVG 旁路', () {
    const svg = '''
<svg xmlns="http://www.w3.org/2000/svg" width="240" height="160">
  <rect width="240" height="160" fill="#123456"/>
  <circle cx="120" cy="80" r="60" fill="#9BCC3C"/>
</svg>
''';

    Future<File> writeSvg(String name, String content) async {
      final f = File(
        '${Directory.systemTemp.path}/limeimage_svg_'
        '${DateTime.now().microsecondsSinceEpoch}_$name',
      );
      await f.writeAsString(content);
      addTearDown(() => f.existsSync() ? f.deleteSync() : null);
      return f;
    }

    test('按 bucket 栅格化，naturalSize 用逻辑尺寸', () async {
      final f = await writeSvg('a.svg', svg);
      final svc = ImageService(Settings());
      addTearDown(svc.dispose);

      final img = await svc.load(f.path, targetWidth: 1000);
      expect(img.vector, isTrue);
      // 逻辑尺寸决定显示大小
      expect(img.naturalWidth, 240);
      expect(img.naturalHeight, 160);
      // 实际栅格用的是 bucket（1024），所以放大到 1:1 以上也清晰
      expect(img.decodedWidth, 1024);
      expect(img.frames.first.image.height, 683);
    });

    test('放大后能栅格出更高分辨率的版本', () async {
      final f = await writeSvg('b.svg', svg);
      final svc = ImageService(Settings());
      addTearDown(svc.dispose);

      final small = await svc.load(f.path, targetWidth: 300);
      final big = await svc.load(f.path, targetWidth: 3000);
      expect(small.decodedWidth, 512);
      expect(big.decodedWidth, 3072);
    });

    test('.svg 在可解码扩展名里', () {
      expect(isImageFile('a.svg'), isTrue);
      expect(kKnownImageExtensions.contains('.svgz'), isTrue);
    });
  });
}
