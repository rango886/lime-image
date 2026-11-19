import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:limeimage/batch/batch_state.dart';
import 'package:limeimage/batch/engine/convert_engine.dart';
import 'package:limeimage/batch/preset_store.dart';
import 'package:limeimage/models/settings.dart';
import 'package:limeimage/services/image_service.dart';
import 'package:limeimage/ui/batch/batch_file_list.dart';
import 'package:limeimage/ui/batch/batch_page.dart';
import 'package:limeimage/ui/batch/batch_preview.dart';
import 'package:limeimage/ui/theme.dart';

import 'helpers/fs_retry.dart';

void main() {
  late Directory dir;
  late BatchState s;
  late ImageService images;
  final settings = Settings();
  final sourcePath =
      'C:\\${List.filled(12, 'very-long-source-folder').join('\\')}\\source.png';
  final targetPath =
      'D:\\${List.filled(14, 'very-long-target-folder').join('\\')}\\result.jpg';

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('lime-layout-');
    s = BatchState(
      settings: settings,
      store: await PresetStore.openAt(dir.path),
    );
    s.preview = PreviewData(sourcePath)
      ..loading = false
      ..targetPath = targetPath
      ..result = (ConvertResult()
        ..srcFormat = 'PNG'
        ..srcW = 4000
        ..srcH = 3000
        ..outW = 1000
        ..outH = 1000
        ..srcSize = 1234567);
    images = ImageService(settings);
  });

  tearDown(() async {
    s.dispose();
    images.dispose();
    await deleteTempDir(dir);
  });

  Future<void> show(WidgetTester tester, Size size) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: LimeTheme.build(Brightness.light, 0xff8bc34a),
        home: Material(
          child: BatchPage(state: s, images: images, settings: settings),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets(
    'info and paths live below the larger preview; sidebar stays resizable',
    (tester) async {
      await show(tester, const Size(1320, 840));
      final list = find.byType(BatchFileList);
      final info = find.byType(BatchInfoPanel);
      final preview = find.byType(BatchPreview);
      expect(tester.getSize(list).width, 320);
      expect(tester.getSize(preview).width, greaterThan(612));
      expect(tester.getTopLeft(info).dx, tester.getTopLeft(preview).dx);
      expect(tester.getTopLeft(info).dy, tester.getBottomLeft(preview).dy);
      expect(tester.getTopRight(info).dx, tester.getTopRight(preview).dx);
      expect(
        tester.getTopLeft(info).dx,
        greaterThan(tester.getTopRight(list).dx),
      );
      expect(tester.getSize(info).height, lessThan(200));
      expect(find.descendant(of: preview, matching: info), findsNothing);
      expect(find.text('处理顺序（启用的步骤依次叠加）'), findsNothing);
      expect(find.textContaining('自动摆正 → 裁切'), findsNothing);
      expect(find.text('包含子文件夹'), findsNothing);
      expect(
        tester
            .widget<Text>(
              find.descendant(of: info, matching: find.byType(Text)).first,
            )
            .data,
        '格式',
      );
      expect(
        find.descendant(of: info, matching: find.text(sourcePath)),
        findsOneWidget,
      );
      expect(
        find.descendant(of: info, matching: find.text(targetPath)),
        findsOneWidget,
      );
      expect(
        find.descendant(of: info, matching: find.text('source.png')),
        findsNothing,
      );
      expect(
        find.descendant(of: info, matching: find.text('result.jpg')),
        findsNothing,
      );

      final fileMenu = find.descendant(
        of: list,
        matching: find.byIcon(Icons.more_horiz),
      );
      await tester.tap(fileMenu);
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('包含子文件夹'), findsOneWidget);
      await tester.tap(fileMenu);
      await tester.pump(const Duration(milliseconds: 200));

      final handle = find.byKey(const ValueKey('batch-sidebar-resizer'));
      await tester.drag(handle, const Offset(100, 0));
      await tester.pump();
      expect(tester.getSize(list).width, greaterThan(320));
      expect(tester.getSize(info).width, tester.getSize(preview).width);
      await tester.drag(handle, const Offset(1000, 0));
      await tester.pump();
      expect(tester.getSize(preview).width, greaterThanOrEqualTo(480));
      await tester.drag(handle, const Offset(-1000, 0));
      await tester.pump();
      expect(tester.getSize(list).width, 280);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 400));
    },
  );

  testWidgets(
    'preview footer shows complete paths on separate horizontally scrollable rows',
    (tester) async {
      await show(tester, const Size(900, 560));
      final source = find.byKey(const ValueKey('batch-source-path'));
      final target = find.byKey(const ValueKey('batch-target-path'));
      expect(tester.widget<Text>(source).data, sourcePath);
      expect(tester.widget<Text>(target).data, targetPath);
      expect(tester.widget<Text>(source).overflow, isNull);
      expect(tester.widget<Text>(target).overflow, isNull);
      expect(tester.getTopLeft(source).dx, tester.getTopLeft(target).dx);
      expect(
        tester.getBottomLeft(source).dy,
        lessThan(tester.getTopLeft(target).dy),
      );
      final scroll = find.ancestor(
        of: source,
        matching: find.byWidgetPredicate(
          (w) =>
              w is SingleChildScrollView &&
              w.scrollDirection == Axis.horizontal,
        ),
      );
      expect(
        tester.widget<SingleChildScrollView>(scroll).scrollDirection,
        Axis.horizontal,
      );
      final before = tester.getTopLeft(source).dx;
      await tester.drag(scroll, const Offset(-400, 0));
      await tester.pump(const Duration(milliseconds: 400));
      expect(tester.getTopLeft(source).dx, lessThan(before));
      final actionBar = find.byKey(const ValueKey('batch-action-bar'));
      expect(find.descendant(of: actionBar, matching: source), findsNothing);
      expect(find.descendant(of: actionBar, matching: target), findsNothing);
      expect(tester.getSize(actionBar).height, 46);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 400));
    },
  );

  testWidgets(
    'medium windows prioritize preview width and compact information',
    (tester) async {
      await show(tester, const Size(1100, 700));
      expect(find.byType(BatchFileList), findsNothing);
      expect(tester.getSize(find.byType(BatchPreview)).width, 760);
      expect(tester.getSize(find.byType(BatchInfoPanel)).height, lessThan(200));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('paths remain in the preview footer while converting', (
    tester,
  ) async {
    s.running = true;
    s.runTotal = 10;
    s.runDone = 3;
    await show(tester, const Size(1440, 900));
    final info = find.byType(BatchInfoPanel);
    final action = find.byKey(const ValueKey('batch-action-bar'));
    expect(
      find.descendant(of: info, matching: find.text(sourcePath)),
      findsOneWidget,
    );
    expect(
      find.descendant(of: info, matching: find.text(targetPath)),
      findsOneWidget,
    );
    expect(
      find.descendant(of: action, matching: find.text('3 / 10')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: action, matching: find.text('取消')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('narrow window opens a resizable sidebar without overflow', (
    tester,
  ) async {
    await show(tester, const Size(900, 560));
    expect(find.byType(BatchFileList), findsNothing);
    await tester.tap(find.byTooltip('文件列表'));
    await tester.pump();
    expect(find.byType(BatchFileList), findsOneWidget);
    expect(find.byType(BatchInfoPanel), findsOneWidget);
    await tester.drag(
      find.byKey(const ValueKey('batch-sidebar-resizer')),
      const Offset(1000, 0),
    );
    await tester.pump();
    expect(
      tester.getSize(find.byType(BatchFileList)).width,
      lessThanOrEqualTo(552),
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 400));
  });

  testWidgets('info panel keeps steady height and avoids flashing on switch', (
    tester,
  ) async {
    Future<void> pumpPage() => tester.pumpWidget(
      MaterialApp(
        theme: LimeTheme.build(Brightness.light, 0xff8bc34a),
        home: Material(
          child: BatchPage(state: s, images: images, settings: settings),
        ),
      ),
    );

    await show(tester, const Size(1320, 840));
    final info = find.byType(BatchInfoPanel);
    final loadedHeight = tester.getSize(info).height;

    // 切换到新图片时的中间状态：loading = true 且 result = null
    s.preview = PreviewData(sourcePath)..loading = true;
    await pumpPage();

    expect(tester.getSize(info).height, loadedHeight);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(
      find.descendant(of: info, matching: find.text('4000 × 3000')),
      findsOneWidget,
    );

    // 超过 180ms 仍未完成时，温和淡化；拿到新结果后恢复不透明并更新数值
    await tester.pump(const Duration(milliseconds: 200));
    expect(
      tester
          .widget<AnimatedOpacity>(
            find.descendant(of: info, matching: find.byType(AnimatedOpacity)),
          )
          .opacity,
      0.55,
    );

    s.preview = PreviewData(sourcePath)
      ..loading = false
      ..targetPath = targetPath
      ..result = (ConvertResult()
        ..srcFormat = 'JPEG'
        ..srcW = 1920
        ..srcH = 1080
        ..outW = 960
        ..outH = 540
        ..srcSize = 654321);
    await pumpPage();
    expect(
      tester
          .widget<AnimatedOpacity>(
            find.descendant(of: info, matching: find.byType(AnimatedOpacity)),
          )
          .opacity,
      1.0,
    );
    expect(
      find.descendant(of: info, matching: find.text('1920 × 1080')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 400));
  });
}
