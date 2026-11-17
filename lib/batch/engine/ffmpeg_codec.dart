import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'pixels.dart';

/// 通过管道把 BGRA 像素喂给 ffmpeg 编码，结果从 stdout 读回来，不落临时文件。
class FfmpegEncoder {
  FfmpegEncoder(this.exe);
  final String exe;

  static final Map<String, Set<String>> _encodersByExe = {};

  /// 本机 ffmpeg 带了哪些编码器（结果按可执行文件缓存）
  static Future<Set<String>> encoders(String exe) async {
    final cached = _encodersByExe[exe];
    if (cached != null) return cached;
    final out = <String>{};
    try {
      final r = await Process.run(exe, const [
        '-hide_banner',
        '-encoders',
      ]).timeout(const Duration(seconds: 8));
      final re = RegExp(r'^\s*[VAS][\.A-Z]{5}\s+(\S+)', multiLine: true);
      for (final m in re.allMatches('${r.stdout}')) {
        out.add(m.group(1)!);
      }
    } catch (_) {}
    return _encodersByExe[exe] = out;
  }

  /// 找可执行文件：设置里指定的路径优先，其次 PATH
  static Future<String?> locate(String? explicit) async {
    for (final c in [
      if (explicit != null && explicit.trim().isNotEmpty) explicit.trim(),
      'ffmpeg',
    ]) {
      try {
        final r = await Process.run(c, const [
          '-version',
        ]).timeout(const Duration(seconds: 5));
        if (r.exitCode == 0) return c;
      } catch (_) {}
    }
    return null;
  }

  Future<Uint8List> webp(
    Pix p, {
    required int quality,
    required bool lossless,
    required int effort,
    required bool alpha,
  }) => _run(p, alpha, [
    '-c:v',
    'libwebp',
    if (lossless) ...['-lossless', '1'] else ...['-lossless', '0'],
    '-quality',
    '$quality',
    '-compression_level',
    '$effort',
    '-pix_fmt',
    lossless ? 'bgra' : (alpha ? 'yuva420p' : 'yuv420p'),
    '-f',
    'webp',
  ]);

  Future<Uint8List> avif(
    Pix p, {
    required int quality,
    required int speed,
  }) async {
    final enc = await encoders(exe);
    // 质量 1..100 映射到 crf 63..0
    final crf = (63 - (quality.clamp(1, 100) * 63 / 100)).round();
    final List<String> codec;
    if (enc.contains('libaom-av1')) {
      codec = [
        '-c:v',
        'libaom-av1',
        '-still-picture',
        '1',
        '-crf',
        '$crf',
        '-b:v',
        '0',
        '-cpu-used',
        '${speed.clamp(0, 8)}',
      ];
    } else if (enc.contains('libsvtav1')) {
      codec = [
        '-c:v',
        'libsvtav1',
        '-crf',
        '$crf',
        '-preset',
        '${(speed + 2).clamp(0, 13)}',
      ];
    } else {
      throw const FormatException('ffmpeg 没有 AV1 编码器');
    }
    return _run(p, false, [
      ...codec,
      '-pix_fmt',
      'yuv420p',
      '-f',
      'avif',
    ], seekable: true);
  }

  Future<Uint8List> jpeg(Pix p, {required int quality, required bool s444}) {
    // mjpeg 的 q:v 是 2(好)..31(差)
    final q = (31 - (quality.clamp(1, 100) - 1) * 29 / 99).round();
    return _run(p, false, [
      '-c:v',
      'mjpeg',
      '-q:v',
      '$q',
      '-pix_fmt',
      s444 ? 'yuvj444p' : 'yuvj420p',
      '-f',
      'image2pipe',
    ]);
  }

  Future<Uint8List> png(Pix p, {required bool alpha}) => _run(p, alpha, [
    '-c:v',
    'png',
    '-pix_fmt',
    alpha ? 'rgba' : 'rgb24',
    '-f',
    'image2pipe',
  ]);

  Future<Uint8List> tiff(Pix p, {required bool alpha, required String algo}) =>
      _run(p, alpha, [
        '-c:v',
        'tiff',
        '-compression_algo',
        algo,
        '-pix_fmt',
        alpha ? 'rgba' : 'rgb24',
        '-f',
        'image2pipe',
      ]);

  Future<Uint8List> bmp(Pix p, {required bool alpha}) => _run(p, alpha, [
    '-c:v',
    'bmp',
    '-pix_fmt',
    alpha ? 'bgra' : 'bgr24',
    '-f',
    'image2pipe',
  ]);

  /// [seekable]：有的封装（AVIF）不能写管道，只能先写临时文件
  Future<Uint8List> _run(
    Pix p,
    bool alpha,
    List<String> output, {
    bool seekable = false,
  }) async {
    Directory? tmpDir;
    File? tmp;
    if (seekable) {
      tmpDir = await Directory.systemTemp.createTemp('lime-enc-');
      tmp = File('${tmpDir.path}${Platform.pathSeparator}out');
    }
    final args = [
      '-hide_banner',
      '-loglevel',
      'error',
      '-f',
      'rawvideo',
      '-pix_fmt',
      'bgra',
      '-s',
      '${p.width}x${p.height}',
      '-i',
      'pipe:0',
      '-frames:v',
      '1',
      ...output,
      if (tmp != null) ...['-y', tmp.path] else 'pipe:1',
    ];
    try {
      return await _exec(args, alpha ? unpremultiplied(p) : p.data, tmp);
    } finally {
      try {
        await tmpDir?.delete(recursive: true);
      } catch (_) {}
    }
  }

  Future<Uint8List> _exec(List<String> args, Uint8List bytes, File? tmp) async {
    final proc = await Process.start(exe, args);
    final stdoutF = _collect(proc.stdout);
    final stderrF = proc.stderr
        .transform(const Utf8Decoder(allowMalformed: true))
        .join();
    try {
      proc.stdin.add(bytes);
      await proc.stdin.flush();
      await proc.stdin.close();
    } catch (_) {
      // ffmpeg 提前退出时写管道会报错，以退出码和 stderr 为准
    }
    var out = await stdoutF;
    final log = await stderrF;
    final code = await proc.exitCode.timeout(const Duration(minutes: 2));
    if (code == 0 && tmp != null && await tmp.exists()) {
      out = await tmp.readAsBytes();
    }
    if (code != 0 || out.isEmpty) {
      final lines = log
          .split('\n')
          .map((l) => l.trim())
          .where((l) => l.isNotEmpty)
          .toList();
      throw FormatException(lines.isEmpty ? 'ffmpeg 退出码 $code' : lines.first);
    }
    return out;
  }

  static Future<Uint8List> _collect(Stream<List<int>> s) async {
    final b = BytesBuilder(copy: false);
    await for (final c in s) {
      b.add(c);
    }
    return b.takeBytes();
  }
}
