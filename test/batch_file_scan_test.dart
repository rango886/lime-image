import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:limeimage/batch/batch_state.dart';
import 'package:limeimage/batch/preset_store.dart';
import 'package:limeimage/models/settings.dart';
import 'package:path/path.dart' as p;

// 扫描只需要文件名，不依赖 ffmpeg、图片解码或预览 isolate。
class _ScanState extends BatchState {
  _ScanState(PresetStore store) : super(settings: Settings(), store: store);

  @override
  void schedulePreview({bool immediate = false}) {}
}

void main() {
  late Directory dir;
  late BatchState s;
  late String images;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('lime-scan-');
    s = _ScanState(await PresetStore.openAt(p.join(dir.path, 'cfg')));
    images = p.join(dir.path, 'images');
    await Directory(images).create();
  });

  tearDown(() async {
    s.dispose();
    await dir.delete(recursive: true);
  });

  Future<String> image(String relative) async {
    final f = File(p.join(images, relative));
    await f.parent.create(recursive: true);
    await f.writeAsBytes([0]);
    return f.path;
  }

  test(
    'toggle rescans loaded folders and preserves direct item state',
    () async {
      final direct = await image('a.png');
      final nested = await image(p.join('sub', 'b.png'));
      await s.setRecursive(false);
      await s.addPaths([images]);
      expect(s.items.map((i) => i.path), [direct]);
      final first = s.current!;
      s.toggleChecked(first, false);

      await s.setRecursive(true);
      expect(s.items.map((i) => i.path), [direct, nested]);
      expect(s.current, same(first));
      expect(first.checked, isFalse);
      await s.setRecursive(false);
      expect(s.items, [first]);
      await s.setRecursive(true);
      expect(s.items.length, 2, reason: '重复扫描不能产生重复条目');
    },
  );

  test('folder with images only in descendants is remembered', () async {
    final nested = await image(p.join('sub', 'deep', 'b.png'));
    await s.setRecursive(false);
    await s.addPaths([images]);
    expect(s.items, isEmpty);
    await s.setRecursive(true);
    expect(s.current?.path, nested);
    await s.setRecursive(false);
    expect(s.items, isEmpty);
    expect(s.selected, -1);
    expect(s.preview, isNull);
  });

  test(
    'explicit files and explicit subfolder roots survive disabling recursion',
    () async {
      final explicit = await image(p.join('sub', 'explicit.png'));
      final direct = await image(p.join('other', 'direct.png'));
      await image(p.join('other', 'deep', 'nested.png'));
      await s.addPaths([images, explicit, p.dirname(direct)]);
      expect(s.items.length, 3);
      await s.setRecursive(false);
      expect(s.items.map((i) => i.path), unorderedEquals([explicit, direct]));
    },
  );

  test('rescan still excludes conversion output folders', () async {
    final good = await image(p.join('sub', 'b.png'));
    await image(p.join(s.preset.subfolder, 'old.png'));
    await s.setRecursive(false);
    await s.addPaths([images]);
    await s.setRecursive(true);
    expect(s.items.map((i) => i.path), [good]);
  });

  test(
    'rapid toggles and queued additions end in the requested state',
    () async {
      final direct = await image('a.png');
      await image(p.join('sub', 'b.png'));
      await Future.wait([
        s.addPaths([images]),
        s.setRecursive(false),
        s.setRecursive(true),
        s.setRecursive(false),
      ]);
      expect(s.recursive, isFalse);
      expect(s.items.map((i) => i.path), [direct]);
      s.clear();
      await s.setRecursive(true);
      expect(s.items, isEmpty, reason: '清空后不能恢复已清空的文件夹');
    },
  );
}
