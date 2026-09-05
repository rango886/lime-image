// 解码器实测工具。decoders/ 目录刻意不依赖 dart:ui / flutter，
// 所以可以直接 `dart run tool/decoder_probe.dart [文件或目录...]` 跑。
import 'dart:io';

import 'package:limeimage/services/decoders/decoder_registry.dart';
import 'package:limeimage/services/decoders/format_sniffer.dart';

Future<void> main(List<String> args) async {
  // --target=N 模拟不同 bucket，用来验证内嵌预览快路径的取舍
  var target = 1024;
  final files = <String>[];
  for (final a in args) {
    if (a.startsWith('--target=')) {
      target = int.tryParse(a.substring(9)) ?? target;
    } else {
      files.add(a);
    }
  }

  final reg = DecoderRegistry();
  await reg.initialize();

  print('=== 后端可用性 ===');
  print('  WIC     : ${reg.wicAvailable}');
  print('  ffmpeg  : ${reg.ffmpegAvailable}');

  print('\n=== 本机 WIC 解码器（COM 枚举，注册表看不全）===');
  for (final c in reg.wicCodecs) {
    final e = c.extensions.toList()..sort();
    print(
      '  ${c.friendlyName.padRight(32)} '
      '${e.take(12).join(' ')}${e.length > 12 ? ' …(${e.length})' : ''}',
    );
  }

  final targets = <String>[];
  for (final a in files) {
    if (FileSystemEntity.isDirectorySync(a)) {
      targets.addAll(
        Directory(a)
            .listSync()
            .whereType<File>()
            .map((f) => f.path)
            .where((p) => !p.endsWith('.raw')),
      );
    } else if (FileSystemEntity.isFileSync(a)) {
      targets.add(a);
    }
  }

  if (targets.isNotEmpty) {
    targets.sort();
    print('\n=== 解码矩阵 (targetWidth=$target) ===');
    print(
      '${'FILE'.padRight(26)}${'SNIFF'.padRight(21)}'
      '${'DECODER'.padRight(18)}${'RESULT'.padRight(23)}TIME',
    );
    print('-' * 104);

    for (final path in targets) {
      final name = path.split(Platform.pathSeparator).last;
      final sniff = await FormatSniffer.sniffFile(path);

      if (sniff.format.skiaNative) {
        print(
          '${_cut(name, 25).padRight(26)}${_cut('$sniff', 20).padRight(21)}'
          '${'(skia)'.padRight(18)}Flutter 内置路径',
        );
        continue;
      }

      final sw = Stopwatch()..start();
      try {
        final r = await reg.decode(path, sniff, targetWidth: target);
        sw.stop();
        final what = r.isEncoded
            ? 'encoded ${r.encoded!.length}B ${r.width}x${r.height}'
            : '${r.width}x${r.height} ${r.format.name}';
        print(
          '${_cut(name, 25).padRight(26)}${_cut('$sniff', 20).padRight(21)}'
          '${r.decoderId.padRight(18)}${_cut(what, 22).padRight(23)}'
          '${(sw.elapsedMicroseconds / 1000).toStringAsFixed(1)}ms'
          '${r.previewOnly ? '  [preview]' : ''}'
          '${r.orientation != 1 ? '  [orient=${r.orientation}]' : ''}',
        );
      } catch (e) {
        sw.stop();
        print(
          '${_cut(name, 25).padRight(26)}${_cut('$sniff', 20).padRight(21)}'
          '${'-'.padRight(18)}${_cut(e.toString(), 45)}',
        );
      }
    }
  }

  print('\n=== 格式支持总览 ===');
  for (final s in reg.report()) {
    final mark = switch (s.support) {
      FormatSupport.native => '内置',
      FormatSupport.verified => '已验证',
      FormatSupport.claimed => '声称支持',
      FormatSupport.failed => '失败',
      FormatSupport.none => '不支持',
    };
    print(
      '  ${s.format.label.padRight(14)}${mark.padRight(10)}'
      '${s.decoders.join(', ')}',
    );
  }

  reg.dispose();
}

String _cut(String s, int n) => s.length <= n ? s : '${s.substring(0, n - 1)}…';
