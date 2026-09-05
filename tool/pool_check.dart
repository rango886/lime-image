// 验收/排查脚本：跑一遍 isolate 解码池，确认像素形态回传正确。
// 用法: dart run tool/pool_check.dart <文件> [<文件> ...]
import 'dart:io';

import 'package:limeimage/services/decoders/decoder_registry.dart';
import 'package:limeimage/services/decoders/format_sniffer.dart';

Future<void> main(List<String> args) async {
  final reg = DecoderRegistry(useIsolates: true, isolateCount: 2);
  await reg.initialize();
  stdout.writeln(
    'workers=${reg.isolateCount} wic=${reg.wicAvailable} '
    'ffmpeg=${reg.ffmpegAvailable}',
  );

  for (final path in args) {
    final sniff = await FormatSniffer.sniffFile(path);
    final sw = Stopwatch()..start();
    try {
      final r = await reg.decode(path, sniff, targetWidth: 600);
      final first = r.isEncoded ? r.encoded! : r.frames.first;
      var nonZero = 0;
      for (var i = 0; i < first.length; i += 997) {
        if (first[i] != 0) nonZero++;
      }
      stdout.writeln(
        '${sniff.format.label}: via=${r.decoderId} ${r.width}x${r.height} '
        'nat=${r.naturalWidth}x${r.naturalHeight} frames=${r.frameCount} '
        'bytes=${first.length} nonzeroSamples=$nonZero ${sw.elapsedMilliseconds}ms',
      );
      if (!r.isEncoded && first.length != r.width * r.height * 4) {
        stdout.writeln('  !! 帧长度和尺寸不匹配');
      }
    } catch (e) {
      stdout.writeln('${sniff.format.label}: FAILED $e');
    }
  }
  stdout.writeln('mainIsolateDecodes=${reg.mainIsolateDecodes}');
  for (final e in reg.stats.entries) {
    stdout.writeln(
      'stat ${e.key}: ok=${e.value.success} '
      'fail=${e.value.failure} avg=${e.value.avgMs}ms',
    );
  }
  reg.dispose();
}
