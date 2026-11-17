import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../services/settings_service.dart';
import 'convert_preset.dart';

class NamedPreset {
  NamedPreset(this.name, this.preset);
  String name;
  ConvertPreset preset;
}

/// 预设存在配置目录的 presets/ 下，一个预设一个 JSON；
/// 另外 batch.json 记上次用的参数、最近的输出目录等界面状态。
class PresetStore {
  PresetStore._(this.dir, this.stateFile);

  final Directory dir;
  final File stateFile;

  static Future<PresetStore> open() async {
    final base = await SettingsService.configDir();
    return openAt(base.path);
  }

  /// 指定配置目录（测试用）
  static Future<PresetStore> openAt(String base) async {
    final dir = Directory(p.join(base, 'presets'));
    final store = PresetStore._(dir, File(p.join(base, 'batch.json')));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
      for (final (name, preset) in ConvertPreset.builtIns()) {
        await store.save(name, preset);
      }
    }
    return store;
  }

  static String _fileName(String name) =>
      '${name.replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), '_').trim()}.json';

  Future<List<NamedPreset>> list() async {
    final out = <NamedPreset>[];
    if (!await dir.exists()) return out;
    await for (final f in dir.list()) {
      if (f is! File || !f.path.toLowerCase().endsWith('.json')) continue;
      try {
        final j = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
        final name =
            (j['name'] as String?) ?? p.basenameWithoutExtension(f.path);
        out.add(
          NamedPreset(
            name,
            ConvertPreset.fromJson(
              (j['preset'] as Map?)?.cast<String, dynamic>() ?? const {},
            ),
          ),
        );
      } catch (_) {}
    }
    out.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return out;
  }

  Future<void> save(String name, ConvertPreset preset) async {
    await dir.create(recursive: true);
    final f = File(p.join(dir.path, _fileName(name)));
    await f.writeAsString(
      const JsonEncoder.withIndent('  ')
          .convert({'name': name, 'preset': preset.toJson()}),
    );
  }

  Future<void> delete(String name) async {
    final f = File(p.join(dir.path, _fileName(name)));
    if (await f.exists()) await f.delete();
  }

  Future<void> rename(String from, String to, ConvertPreset preset) async {
    // 先写新的再删旧的：中途失败也不会把预设弄丢。
    await save(to, preset);
    final fa = _fileName(from), fb = _fileName(to);
    if (fa == fb) return; // 同名同写法：save 已经覆盖，没旧文件可删
    if (fa.toLowerCase() == fb.toLowerCase()) {
      // 只差大小写：大小写不敏感文件系统（Windows/macOS 默认）上是同一个
      // 文件，删旧会把刚写的删掉；Linux 上是两个文件，旧的要删掉。
      if (Platform.isLinux) await delete(from);
      return;
    }
    await delete(from);
  }

  /// 导入一个预设文件；同名时自动加编号
  Future<NamedPreset?> importFile(String path) async {
    try {
      final j = jsonDecode(await File(path).readAsString());
      if (j is! Map) return null;
      final map = j.cast<String, dynamic>();
      final preset = ConvertPreset.fromJson(
        (map['preset'] as Map?)?.cast<String, dynamic>() ?? map,
      );
      final base = (map['name'] as String?)?.trim().isNotEmpty == true
          ? (map['name'] as String).trim()
          : p.basenameWithoutExtension(path);
      final names = (await list()).map((e) => e.name.toLowerCase()).toSet();
      var name = base;
      for (var i = 2; names.contains(name.toLowerCase()); i++) {
        name = '$base ($i)';
      }
      await save(name, preset);
      return NamedPreset(name, preset);
    } catch (_) {
      return null;
    }
  }

  Future<void> exportFile(String path, String name, ConvertPreset preset) =>
      File(path).writeAsString(
        const JsonEncoder.withIndent('  ')
            .convert({'name': name, 'preset': preset.toJson()}),
      );

  Future<Map<String, dynamic>> readState() async {
    try {
      return jsonDecode(await stateFile.readAsString()) as Map<String, dynamic>;
    } catch (_) {
      return {};
    }
  }

  Future<void> writeState(Map<String, dynamic> state) async {
    try {
      await stateFile.writeAsString(jsonEncode(state));
    } catch (_) {}
  }
}
