import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:limeimage/core/strip_transform.dart';
import 'package:limeimage/models/enums.dart';
import 'package:limeimage/models/settings.dart';
import 'package:limeimage/services/folder_service.dart';
import 'package:limeimage/services/image_service.dart';
import 'package:limeimage/services/settings_service.dart';
import 'package:limeimage/state/viewer_state.dart';
import 'package:limeimage/ui/comic_view.dart';

class _SettingsService extends Fake implements SettingsService {
  @override
  final Settings settings = Settings()
    ..showHud = false
    ..progressiveQuality = false
    ..smoothWheelScroll = false;
}

class _Marks extends Fake implements MarksService {}

class _Images extends Fake implements ImageService {
  _Images(this.pages);
  final Map<String, DecodedImage> pages;
  @override
  final Set<String> keepAlive = {};
  @override
  DecodedImage? cached(String path, {int? minWidth}) => pages[path];
  @override
  Future<DecodedImage> load(String path, {required int targetWidth}) async =>
      pages[path]!;
}

void expectPoint(Offset actual, Offset expected, [double tolerance = 1e-7]) {
  expect(actual.dx, closeTo(expected.dx, tolerance));
  expect(actual.dy, closeTo(expected.dy, tolerance));
}

void main() {
  test('unbounded zoom preserves scene anchor, including deep comic pages', () {
    final t = StripTransform()..offset = const Offset(420, -1234567);
    const focal = Offset(173, 289);
    final point = t.toScene(focal);
    for (final scale in [0.1, 0.01, 20.0, 100.0, 0.2, 1.0]) {
      expect(t.zoomAt(scale, focal), isTrue);
      expectPoint(t.toScene(focal), point);
    }
  });

  test('repeated reciprocal zoom does not accumulate visible drift', () {
    final t = StripTransform()..offset = const Offset(-1700, -900000);
    final original = t.offset;
    const focal = Offset(613, 371);
    for (var i = 0; i < 1000; i++) {
      t.zoomAt(t.scale * 1.08, focal);
      t.zoomAt(t.scale / 1.08, focal);
    }
    expectPoint(t.offset, original, 1e-6);
    expect(t.scale, closeTo(1, 1e-12));
  });

  test('invalid scales leave the transform intact', () {
    final t = StripTransform();
    for (final scale in [0.0, -1.0, double.nan, double.infinity]) {
      expect(t.zoomAt(scale, const Offset(100, 100)), isFalse);
    }
    expect(t.scale, 1);
    expect(t.offset, Offset.zero);
  });

  for (final comic in [false, true]) {
    testWidgets(
      '${comic ? 'comic' : 'long strip'}: real wheel anchors and free drag',
      (tester) async {
        final recorder = ui.PictureRecorder();
        Canvas(recorder).drawColor(Colors.red, BlendMode.src);
        final picture = recorder.endRecording();
        final bitmap = picture.toImageSync(20, 40);
        picture.dispose();
        final settings = _SettingsService();
        final mode = comic ? ViewMode.comic : ViewMode.longStrip;
        settings.settings.mouseFor(mode).wheel = WheelAction.zoom;
        final folder = FolderService(settings.settings)
          ..entries = [FileEntry('a.png'), FileEntry('b.png')]
          ..index = 0;
        final images = _Images({
          for (final path in ['a.png', 'b.png'])
            path: DecodedImage(
              path: path,
              naturalWidth: 20,
              naturalHeight: 40,
              decodedWidth: 20,
              frames: [AnimFrame(bitmap, Duration.zero)],
              orientation: 1,
              fileBytes: 0,
              truncatedFrames: false,
            ),
        });
        final state =
            ViewerState(
                settingsService: settings,
                folder: folder,
                images: images,
                marks: _Marks(),
              )
              ..mode = mode
              ..image = images.pages['a.png']
              ..viewport = const Size(700, 500);
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Padding(
                // Nonzero global origin catches viewport/global coordinate mistakes.
                padding: const EdgeInsets.only(left: 37, top: 51),
                child: SizedBox(
                  width: 700,
                  height: 500,
                  child: ListenableBuilder(
                    listenable: state,
                    builder: (_, _) => comic
                        ? ComicView(state: state)
                        : LongStripView(state: state),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final first = find.byType(RawImage).first;
        expect(tester.getRect(first).left, 37);
        expect(tester.getRect(first).top, 51);
        expect(tester.getRect(first).width, 700);
        const focal = Offset(183, 247);
        final scenePoint = state.stripTransform.toScene(focal);
        final original = tester.getRect(first);
        for (var i = 0; i < 20; i++) {
          await tester.sendEventToBinding(
            const PointerScrollEvent(
              position: Offset(220, 298),
              scrollDelta: Offset(0, 120),
            ),
          );
          await tester.pump();
          expectPoint(state.stripTransform.toScene(focal), scenePoint);
          final rect = tester.getRect(find.byType(RawImage).first);
          // Check the actual rendered page, not just the transform arithmetic.
          expectPoint(
            rect.topLeft +
                Offset(
                  scenePoint.dx * rect.width / original.width,
                  scenePoint.dy * rect.height / original.height,
                ),
            focal + const Offset(37, 51),
          );
        }
        expect(state.stripZoom, lessThan(0.3));
        // Zooming out past fit leaves whitespace; no automatic recentering.
        expect(state.stripTransform.offset.dx, greaterThan(0));
        for (var i = 0; i < 20; i++) {
          await tester.sendEventToBinding(
            const PointerScrollEvent(
              position: Offset(220, 298),
              scrollDelta: Offset(0, -120),
            ),
          );
          await tester.pump();
        }
        expectPoint(state.stripTransform.offset, Offset.zero);
        expect(state.stripZoom, closeTo(1, 1e-12));
        final gesture = await tester.startGesture(
          const Offset(200, 200),
          kind: PointerDeviceKind.mouse,
        );
        await gesture.moveBy(const Offset(250, 180));
        await gesture.up();
        await tester.pump();
        expectPoint(state.stripTransform.offset, const Offset(250, 180));
        state.resetStripView();
        await tester.pump();
        expectPoint(state.stripTransform.offset, Offset.zero);
        if (comic) {
          state.panStripBy(const Offset(-190, -1800));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 250));
          await tester.pumpAndSettle();
          expect(folder.index, 1);
          final before = tester.getRect(find.byType(RawImage).last);
          const globalFocal = Offset(220, 298);
          final fraction = Offset(
            (globalFocal.dx - before.left) / before.width,
            (globalFocal.dy - before.top) / before.height,
          );
          for (var i = 0; i < 25; i++) {
            await tester.sendEventToBinding(
              const PointerScrollEvent(
                position: globalFocal,
                scrollDelta: Offset(0, -120),
              ),
            );
            await tester.pump();
            final after = tester.getRect(find.byType(RawImage).last);
            expectPoint(
              after.topLeft +
                  Offset(after.width * fraction.dx, after.height * fraction.dy),
              globalFocal,
            );
          }
          // Delayed current-page sync must not re-layout or reset the anchor.
          final offset = state.stripTransform.offset;
          await tester.pump(const Duration(milliseconds: 500));
          await tester.pumpAndSettle();
          expectPoint(state.stripTransform.offset, offset);
        }
        settings.settings.smoothWheelScroll = true;
        state.wheelScroll(240, horizontal: false);
        await tester.pump(const Duration(milliseconds: 16));
        state.setStripZoom(state.stripZoom * 1.08, focal: focal);
        final anchored = state.stripTransform.offset;
        await tester.pump(const Duration(milliseconds: 500));
        await tester.pumpAndSettle();
        expectPoint(state.stripTransform.offset, anchored);
        await tester.pumpWidget(const SizedBox());
        state.dispose();
        folder.dispose();
        bitmap.dispose();
      },
    );
  }
}
