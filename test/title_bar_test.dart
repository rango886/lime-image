import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:limeimage/models/settings.dart';
import 'package:limeimage/services/folder_service.dart';
import 'package:limeimage/services/image_service.dart';
import 'package:limeimage/services/settings_service.dart';
import 'package:limeimage/state/viewer_state.dart';
import 'package:limeimage/ui/title_bar.dart';
import 'package:limeimage/ui/viewer_page.dart';

class _Marks extends Fake implements MarksService {}

void main() {
  test('title hide delay defaults to 200ms, custom delays survive loading', () {
    expect(Settings().titleBarHideDelayMs, 200);
    expect(Settings.fromJson({}).titleBarHideDelayMs, 200);
    expect(
      Settings.fromJson({'titleBarHideDelayMs': 500}).titleBarHideDelayMs,
      500,
    );
  });

  testWidgets('title hides after leaving above window and cancels on reentry', (
    tester,
  ) async {
    final dir = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('lime-title-'),
    ))!;
    final service = await SettingsService.load(directory: dir);
    final state = ViewerState(
      settingsService: service,
      folder: FolderService(service.settings),
      images: ImageService(service.settings),
      marks: _Marks(),
    );
    addTearDown(() async {
      state.dispose();
      service.dispose();
      await dir.delete(recursive: true);
    });
    await tester.pumpWidget(MaterialApp(home: ViewerPage(state: state)));
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(200, 100));
    await mouse.moveTo(const Offset(200, 10));
    await tester.pump();
    bool visible() => tester.widget<TitleBar>(find.byType(TitleBar)).visible;
    expect(visible(), isTrue);
    await mouse.moveTo(const Offset(200, -10));
    await tester.pump(const Duration(milliseconds: 199));
    expect(visible(), isTrue);
    await tester.pump(const Duration(milliseconds: 1));
    expect(visible(), isFalse);

    await mouse.moveTo(const Offset(200, 10));
    await tester.pump();
    expect(visible(), isTrue);
    await mouse.moveTo(const Offset(200, -10));
    await tester.pump(const Duration(milliseconds: 100));
    await mouse.moveTo(const Offset(200, 10));
    await tester.pump(const Duration(milliseconds: 250));
    expect(visible(), isTrue);

    await mouse.moveTo(const Offset(200, 100));
    await tester.pump(const Duration(milliseconds: 200));
    expect(visible(), isFalse);
    await mouse.removePointer();
    await tester.pumpWidget(const SizedBox());
  });
}
