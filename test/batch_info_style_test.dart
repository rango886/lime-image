import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:limeimage/batch/batch_state.dart';
import 'package:limeimage/batch/convert_preset.dart';
import 'package:limeimage/batch/engine/convert_engine.dart';
import 'package:limeimage/batch/preset_store.dart';
import 'package:limeimage/models/settings.dart';
import 'package:limeimage/ui/batch/batch_preview.dart';
import 'package:limeimage/ui/theme.dart';

import 'helpers/fs_retry.dart';

// 按需生成带系统字体的真实样式截图，不影响正常测试：
// flutter test --dart-define=UPDATE_BATCH_SCREENSHOTS=true test/batch_info_style_test.dart
const screenshots = bool.fromEnvironment('UPDATE_BATCH_SCREENSHOTS');

void main() {
  late Directory dir;
  late BatchState state;
  const source = r'V:\未分类文件\工作\抠图\ChatGPT 图像 2026年10月22日 15_16_35-1.png';
  const target = r'V:\未分类文件\工作\抠图\thumbs\ChatGPT 图像 2026年10月22日 15_16_35-1.jpg';

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('lime-info-style-');
    state = BatchState(
      settings: Settings(),
      store: await PresetStore.openAt(dir.path),
    );
    state.preview = PreviewData(source)
      ..loading = false
      ..targetPath = target
      ..outBytes = 52 * 1024
      ..result = (ConvertResult()
        ..srcFormat = 'PNG'
        ..srcW = 1448
        ..srcH = 1086
        ..outW = 513
        ..outH = 385
        ..srcSize = (2.1 * 1024 * 1024).round()
        ..format = OutputFormat.jpeg
        ..quality = 82);
  });

  tearDown(() async {
    state.dispose();
    await deleteTempDir(dir);
  });

  Future<void> loadFonts(WidgetTester tester) async {
    if (!screenshots || !Platform.isWindows) return;
    await tester.runAsync(() async {
      for (final (family, file) in [
        ('Segoe UI', 'C:/Windows/Fonts/segoeui.ttf'),
        ('Microsoft YaHei UI', 'C:/Windows/Fonts/msyh.ttc'),
        (
          'MaterialIcons',
          'build/unit_test_assets/fonts/MaterialIcons-Regular.otf',
        ),
      ]) {
        final loader = FontLoader(family)
          ..addFont(
            Future.value(ByteData.sublistView(await File(file).readAsBytes())),
          );
        await loader.load();
      }
    });
  }

  for (final brightness in Brightness.values) {
    for (final width in [480.0, 652.0, 760.0]) {
      testWidgets(
        'comparison card and labelled paths in $brightness at $width',
        (tester) async {
          await loadFonts(tester);
          await tester.binding.setSurfaceSize(Size(width, 420));
          addTearDown(() => tester.binding.setSurfaceSize(null));
          const capture = ValueKey('info-capture');
          await tester.pumpWidget(
            MaterialApp(
              theme: LimeTheme.build(brightness, 0xff009688),
              home: Scaffold(
                body: Align(
                  alignment: Alignment.topCenter,
                  child: RepaintBoundary(
                    key: capture,
                    child: BatchInfoPanel(state: state),
                  ),
                ),
              ),
            ),
          );
          await tester.pump();
          final card = find.byKey(const ValueKey('batch-comparison-card'));
          expect(card, findsOneWidget);
          expect(
            find.byKey(const ValueKey('batch-size-delta')),
            findsOneWidget,
          );
          expect(find.text('-98%'), findsOneWidget);
          expect(find.byTooltip('复制路径'), findsNWidgets(2));
          expect(
            tester
                .widget<Text>(find.byKey(const ValueKey('batch-source-path')))
                .data,
            source,
          );
          expect(
            tester
                .widget<Text>(find.byKey(const ValueKey('batch-target-path')))
                .data,
            target,
          );
          expect(tester.takeException(), isNull);

          String? copied;
          tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            SystemChannels.platform,
            (call) async {
              if (call.method == 'Clipboard.setData') {
                copied = (call.arguments as Map)['text'] as String?;
              }
              return null;
            },
          );
          addTearDown(
            () => tester.binding.defaultBinaryMessenger
                .setMockMethodCallHandler(SystemChannels.platform, null),
          );
          await tester.tap(find.byTooltip('复制路径').last);
          await tester.pump(const Duration(milliseconds: 400));
          expect(copied, target);

          if (screenshots && width == 760) {
            await tester.runAsync(() async {
              final boundary = tester.renderObject<RenderRepaintBoundary>(
                find.byKey(capture),
              );
              final image = await boundary.toImage(pixelRatio: 2);
              final bytes = await image.toByteData(
                format: ui.ImageByteFormat.png,
              );
              final file = File('build/batch-info-${brightness.name}.png');
              await file.parent.create(recursive: true);
              await file.writeAsBytes(bytes!.buffer.asUint8List());
              image.dispose();
            });
          }
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump(const Duration(milliseconds: 400));
        },
      );
    }
  }
}
