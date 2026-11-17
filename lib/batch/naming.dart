import 'dart:io';

import 'package:path/path.dart' as p;

import 'convert_preset.dart';

/// 文件名模板里能用的变量
const kNameVariables = [
  '{name}',
  '{n}',
  '{w}',
  '{h}',
  '{date}',
  '{taken}',
  '{parent}',
];

final _illegal = RegExp(r'[<>:"/\\|?*\x00-\x1F]');

String _two(int v) => v.toString().padLeft(2, '0');

/// 按模板生成不带扩展名的文件名
String renderName(
  String template, {
  required String source,
  required int seq,
  required int digits,
  required int width,
  required int height,
  String? taken,
  DateTime? now,
}) {
  final t = now ?? DateTime.now();
  final base = p.basenameWithoutExtension(source);
  final out = template.replaceAllMapped(RegExp(r'\{(\w+)\}'), (m) {
    switch (m[1]) {
      case 'name':
        return base;
      case 'n':
        return seq.toString().padLeft(digits, '0');
      case 'w':
        return '$width';
      case 'h':
        return '$height';
      case 'date':
        return '${t.year}${_two(t.month)}${_two(t.day)}';
      case 'taken':
        return taken ?? base;
      case 'parent':
        return p.basename(p.dirname(source));
      default:
        return m[0]!;
    }
  });
  var clean = out.replaceAll(_illegal, '_').trim();
  while (clean.endsWith('.')) {
    clean = clean.substring(0, clean.length - 1);
  }
  return clean.isEmpty ? base : clean;
}

/// 输出目录。[root] 是用户加进来的那个文件夹（直接加的文件为 null）
String outputDir(ConvertPreset preset, String source, String? root) {
  final dir = p.dirname(source);
  switch (preset.place) {
    case OutputPlace.same:
      return dir;
    case OutputPlace.subfolder:
      final sub = preset.subfolder.replaceAll(_illegal, '_').trim();
      return sub.isEmpty ? dir : p.join(dir, sub);
    case OutputPlace.custom:
      final base = preset.customDir.trim();
      if (base.isEmpty) return dir;
      if (preset.keepStructure && root != null && p.isWithin(root, dir)) {
        return p.join(base, p.basename(root), p.relative(dir, from: root));
      }
      if (preset.keepStructure && root != null && p.equals(root, dir)) {
        return p.join(base, p.basename(root));
      }
      return base;
  }
}

/// 处理重名：返回最终路径；跳过时返回 null。
/// [claimed] 是这一批里已经分出去的路径（小写），批内撞名一律编号。
String? resolveConflict(
  String path,
  ConflictPolicy policy,
  Set<String> claimed,
) {
  String key(String s) => p.normalize(s).toLowerCase();
  if (!claimed.contains(key(path))) {
    final onDisk = File(path).existsSync();
    if (!onDisk || policy == ConflictPolicy.overwrite) {
      claimed.add(key(path));
      return path;
    }
    if (policy == ConflictPolicy.skip) return null;
  }
  final dir = p.dirname(path);
  final stem = p.basenameWithoutExtension(path);
  final ext = p.extension(path);
  for (var i = 2; i < 100000; i++) {
    final c = p.join(dir, '$stem ($i)$ext');
    if (!claimed.contains(key(c)) && !File(c).existsSync()) {
      claimed.add(key(c));
      return c;
    }
  }
  return null;
}
