import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:limeimage/batch/batch_state.dart';
import 'package:limeimage/batch/convert_preset.dart';
import 'package:limeimage/batch/engine/convert_engine.dart';
import 'package:limeimage/batch/preset_store.dart';
import 'package:limeimage/models/settings.dart';
import 'package:path/path.dart' as p;

/// BatchState 这一层：开始转换 / 取消 / 汇总 / 预设增删改导入导出 / 路径修正。
/// 界面按钮最终都落到这里，这层对了，界面只剩“按钮有没有接上”。
void main() {
  late Directory root;
  late Directory cfg;
  late Directory imgs;
  String? ff;

  setUpAll(() async {
    root = await Directory.systemTemp.createTemp('lime-batch-state-');
    cfg = await Directory(p.join(root.path, 'cfg')).create();
    imgs = await Directory(p.join(root.path, 'imgs')).create();
    ff = await ConvertEngine().ffmpeg();
    if (ff == null) return;
    // 12 张小图 + 子文件夹 2 张 + 一个非图片
    for (var i = 0; i < 12; i++) {
      await Process.run(ff!, [
        '-v', 'error', '-f', 'lavfi', //
        '-i', 'testsrc2=size=${320 + i * 8}x240',
        '-frames:v', '1', '-y', p.join(imgs.path, 'a$i.png'),
      ]);
    }
    final sub = await Directory(p.join(imgs.path, 'sub')).create();
    for (var i = 0; i < 2; i++) {
      await Process.run(ff!, [
        '-v', 'error', '-f', 'lavfi', '-i', 'testsrc2=size=200x100', //
        '-frames:v', '1', '-y', p.join(sub.path, 's$i.png'),
      ]);
    }
    await File(p.join(imgs.path, 'note.txt')).writeAsString('x');
  });
  tearDownAll(() => root.delete(recursive: true));

  Future<BatchState> newState() async {
    final store = await PresetStore.openAt(cfg.path);
    final s = BatchState(settings: Settings(), store: store);
    await s.init();
    return s;
  }

  test('built-in presets are created on first open', () async {
    final s = await newState();
    expect(s.presets.length, 4);
    expect(s.presetName, isNotNull);
    s.dispose();
  });

  test('addPaths: folder recursion, dedupe, quote-mangled root', () async {
    if (ff == null) return markTestSkipped('no ffmpeg');
    final s = await newState();
    // 模拟右键盘符根目录：命令行 "X:\" 被解析成 X:"
    await s.addPaths(['${imgs.path}"']);
    expect(s.items.length, 14);
    await s.addPaths([imgs.path, p.join(imgs.path, 'a0.png')]);
    expect(s.items.length, 14, reason: '重复路径不应再加');
    s.clear();
    s.setRecursive(false);
    await s.addPaths([imgs.path]);
    expect(s.items.length, 12);
    s.dispose();
  });

  test('start: converts all, writes files, fills summary', () async {
    if (ff == null) return markTestSkipped('no ffmpeg');
    final s = await newState();
    final out = p.join(root.path, 'out-full');
    s.update(
      (x) => x
        ..format = OutputFormat.jpeg
        ..resize = ResizeMode.longEdge
        ..resizeValue = 100
        ..place = OutputPlace.custom
        ..customDir = out
        ..keepStructure = true,
    );
    await s.addPaths([imgs.path]);
    final sum = (await s.start())!;
    expect(sum.cancelled, isFalse);
    expect(sum.done, 14);
    expect(sum.failed, 0);
    expect(sum.outBytes, greaterThan(0));
    expect(sum.outBytes, lessThan(sum.inBytes));
    expect(s.summary, same(sum));
    expect(s.items.every((i) => i.status == ItemStatus.done), isTrue);
    for (final i in s.items) {
      expect(File(i.outPath!).existsSync(), isTrue);
      expect(i.outPath!.endsWith('.jpg'), isTrue);
    }
    expect(
      File(p.join(out, 'imgs', 'sub', 's0.jpg')).existsSync(),
      isTrue,
      reason: '保持目录结构：<目标>/<加入的文件夹名>/<相对路径>',
    );
    // 临时文件不能留下
    final leftovers = Directory(out)
        .listSync(recursive: true)
        .where((e) => e.path.endsWith('.limetmp'));
    expect(leftovers, isEmpty);

    // 再跑一次：重名跳过
    s.update((x) => x.conflict = ConflictPolicy.skip);
    final again = (await s.start())!;
    expect(again.skipped, 14);
    expect(again.done, 0);
    s.dismissSummary();
    expect(s.summary, isNull);
    s.dispose();
  });

  test('cancel stops pending jobs and leaves the rest pending', () async {
    if (ff == null) return markTestSkipped('no ffmpeg');
    final s = await newState();
    final out = p.join(root.path, 'out-cancel');
    s.update(
      (x) => x
        ..format = OutputFormat.png
        ..place = OutputPlace.custom
        ..customDir = out,
    );
    await s.addPaths([imgs.path]);
    // 第一张完成的那一刻取消（notifyListeners 是同步的）
    void onChange() {
      if (s.runDone >= 1 && !s.cancelRequested) s.cancel();
    }

    s.addListener(onChange);
    final sum = (await s.start())!;
    s.removeListener(onChange);
    expect(sum.cancelled, isTrue);
    expect(s.running, isFalse);
    expect(sum.done, lessThan(14));
    expect(s.items.any((i) => i.status == ItemStatus.running), isFalse);
    final pending = s.items.where((i) => i.status == ItemStatus.pending);
    expect(pending.length, 14 - sum.done - sum.failed - sum.skipped);
    expect(pending, isNotEmpty);
    s.dispose();
  });

  test('presets: save as, rename, case-only rename, delete', () async {
    final s = await newState();
    s.update((x) => x.jpegQuality = 33);
    expect(s.dirty, isTrue);
    await s.savePreset('Mine');
    expect(s.presetName, 'Mine');
    expect(s.dirty, isFalse);
    expect(s.presets.any((e) => e.name == 'Mine'), isTrue);

    await s.renamePreset('Mine', 'Ours');
    expect(s.presetName, 'Ours');
    expect(s.presets.any((e) => e.name == 'Mine'), isFalse);
    expect(
      s.presets.firstWhere((e) => e.name == 'Ours').preset.jpegQuality,
      33,
    );

    // 只改大小写：Windows 上是同一个文件，不能先写后删把它删没了
    await s.renamePreset('Ours', 'OURS');
    final hits = s.presets.where((e) => e.name.toLowerCase() == 'ours');
    expect(hits.map((e) => e.name), ['OURS']);

    await s.deletePreset('OURS');
    expect(s.presetName, isNull);
    expect(s.presets.any((e) => e.name.toLowerCase() == 'ours'), isFalse);
    s.dispose();
  });

  test('presets: export then import gets a unique name', () async {
    final s = await newState();
    s.update((x) => x.webpQuality = 61);
    await s.savePreset('Exp');
    final file = p.join(root.path, 'exp.json');
    await s.exportPreset(file);
    expect(File(file).existsSync(), isTrue);

    await s.importPreset(file);
    expect(s.presetName, 'Exp (2)');
    expect(s.preset.webpQuality, 61);
    expect(s.dirty, isFalse);

    // 坏文件不应抛异常，也不改当前预设
    final bad = p.join(root.path, 'bad.json');
    await File(bad).writeAsString('{not json');
    await s.importPreset(bad);
    expect(s.presetName, 'Exp (2)');
    s.dispose();
  });
}
