import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'decoder.dart';
import 'format_sniffer.dart';

/// 用外部 ffmpeg 兜底。只处理 WIC / Skia 都拿不下的长尾格式。
///
/// 实测（1080x2404 PSD）：进程 spawn 约 30ms，纯解码约 30ms，端到端约 90ms。
/// 比纯 Dart 的 image 包（AOT 594ms）快 6~7 倍，所以不再引入 image 包。
///
/// 两个硬性约定：
///  1. 绝不走 PNG 中转（24MP PNG 编码要 300~800ms），一律 rawvideo 直出 RGBA。
///  2. 绝不加 -hwaccel。单帧场景下 D3D11 设备初始化开销远大于解码收益，
///     实测反而慢 3 倍（366ms vs 121ms）。
class FfmpegDecoder implements RawDecoder {
  FfmpegDecoder({this.explicitPath, this.maxConcurrent = 3});

  /// 用户在设置里手动指定的路径，优先级最高
  String? explicitPath;

  /// 批量缩略图时限流，否则会 spawn 出几十个进程
  final int maxConcurrent;

  @override
  String get id => 'ffmpeg';

  @override
  int get priority => 30;

  static const _formats = {
    ImageFormat.psd,
    ImageFormat.tga,
    ImageFormat.exr,
    ImageFormat.hdr,
    ImageFormat.jp2,
    ImageFormat.pcx,
    ImageFormat.qoi,
    ImageFormat.sgi,
    ImageFormat.pnm,
    ImageFormat.dds,
    // 下面这些优先给 WIC，ffmpeg 只在 WIC 失败时接手
    ImageFormat.tiff,
    ImageFormat.jxl,
    ImageFormat.avif,
  };

  @override
  bool supports(ImageFormat fmt) => _formats.contains(fmt);

  String? _resolved;
  bool _probed = false;

  /// 找 ffmpeg：显式路径 → PATH。结果缓存，避免每张图都探测。
  Future<String?> resolvePath() async {
    if (_probed) return _resolved;
    _probed = true;

    final candidates = <String>[
      if (explicitPath != null && explicitPath!.trim().isNotEmpty)
        explicitPath!.trim(),
      // 注意：Windows 上绝不能探测 'convert'，那是 system32\convert.exe（FAT→NTFS 工具）
      'ffmpeg',
    ];
    for (final c in candidates) {
      try {
        final r = await Process.run(c, const [
          '-version',
        ]).timeout(const Duration(seconds: 5));
        if (r.exitCode == 0) {
          _resolved = c;
          return c;
        }
      } catch (_) {
        // 不存在 / 不可执行，继续试下一个
      }
    }
    return null;
  }

  @override
  Future<bool> isAvailable() async => (await resolvePath()) != null;

  /// 显式路径被改动后要重新找一次
  void resetProbe() {
    _probed = false;
    _resolved = null;
  }

  @override
  void dispose() {}

  static int _running = 0;
  static final List<Completer<void>> _queue = [];

  Future<void> _acquire() async {
    if (_running < maxConcurrent) {
      _running++;
      return;
    }
    final c = Completer<void>();
    _queue.add(c);
    await c.future;
    _running++;
  }

  void _release() {
    _running--;
    if (_queue.isNotEmpty) _queue.removeAt(0).complete();
  }

  @override
  Future<RawImageData> decode(
    String path, {
    required int targetWidth,
    int maxFrames = 1,
  }) async {
    final exe = await resolvePath();
    if (exe == null) throw DecoderException(id, '未找到 ffmpeg');

    await _acquire();
    try {
      return await _run(
        exe,
        path,
        targetWidth,
      ).timeout(const Duration(seconds: 20));
    } finally {
      _release();
    }
  }

  Future<RawImageData> _run(String exe, String path, int targetWidth) async {
    final args = <String>[
      '-hide_banner',
      // 保留 info 级别是刻意的：要从 stderr 里读出实际输出尺寸
      '-loglevel', 'info',
      '-nostdin',
      '-i', path,
      '-frames:v', '1',
      // 只缩不放。用引号包住表达式而不是转义逗号：
      // 'scale=min(iw\,W)' 在 Dart 源码里很容易因为转义层数弄错，
      // 变成未转义的逗号 -> filterchain 解析失败。命名参数形式无此风险。
      if (targetWidth > 0) ...[
        '-vf',
        "scale=w='min(iw,$targetWidth)':h=-1:flags=lanczos",
      ],
      '-pix_fmt', 'rgba',
      '-f', 'rawvideo',
      'pipe:1',
    ];

    final proc = await Process.start(exe, args);
    // stdout 是二进制像素，stderr 是文本日志，必须并发读，否则管道会堵死
    final stdoutFuture = _collect(proc.stdout);
    final stderrFuture = proc.stderr
        .transform(const Utf8Decoder(allowMalformed: true))
        .join();
    final exitFuture = proc.exitCode;

    final bytes = await stdoutFuture;
    final log = await stderrFuture;
    final code = await exitFuture;

    if (code != 0 && bytes.isEmpty) {
      throw DecoderException(id, 'ffmpeg 退出码 $code: ${_lastLine(log)}');
    }

    final dims = _parseDims(log);
    if (dims == null) {
      throw DecoderException(id, '无法从 ffmpeg 输出解析尺寸: ${_lastLine(log)}');
    }
    final (natW, natH, outW, outH) = dims;

    final expect = outW * outH * 4;
    if (bytes.length < expect) {
      throw DecoderException(
        id,
        '像素数据不完整: 期望 $expect 实得 ${bytes.length} ($outW x $outH)',
      );
    }
    final pixels = bytes.length == expect
        ? bytes
        : Uint8List.sublistView(bytes, 0, expect);

    // ffmpeg 的 rgba 是直通 alpha，Skia 要的是预乘，必须转
    _premultiply(pixels);

    return RawImageData.pixels(
      frames: [pixels],
      width: outW,
      height: outH,
      format: RawPixelFormat.rgba8888,
      naturalWidth: natW,
      naturalHeight: natH,
      decoderId: id,
    );
  }

  static Future<Uint8List> _collect(Stream<List<int>> s) async {
    final chunks = <List<int>>[];
    var total = 0;
    await for (final c in s) {
      chunks.add(c);
      total += c.length;
    }
    final out = Uint8List(total);
    var off = 0;
    for (final c in chunks) {
      out.setRange(off, off + c.length, c);
      off += c.length;
    }
    return out;
  }

  /// 从 ffmpeg 日志里抓输入尺寸和输出尺寸。
  /// 输入行:  Stream #0:0: Video: psd, gbrap, 1080x2404, ...
  /// 输出行:  Stream #0:0: Video: rawvideo (RGBA / 0x41424752), rgba, 512x1140, ...
  ///
  /// 坐过的坑：rawvideo 会打印 fourcc `0x41424752`，宽松的正则会把
  /// 它当成 `0x414247` 这个尺寸。所以必须要求尺寸前面是逗号 + 空白。
  static (int, int, int, int)? _parseDims(String log) {
    final dimRe = RegExp(r',\s*(\d{1,6})x(\d{1,6})(?![\dxX])');
    final codecRe = RegExp(r'Video:\s*([A-Za-z0-9_]+)');
    int? natW, natH, outW, outH;

    for (final line in log.split('\n')) {
      if (!line.contains('Video:')) continue;
      final cm = codecRe.firstMatch(line);
      final dm = dimRe.firstMatch(line);
      if (cm == null || dm == null) continue;
      final codec = cm.group(1)!;
      final w = int.parse(dm.group(1)!);
      final h = int.parse(dm.group(2)!);
      if (w == 0 || h == 0) continue;
      if (codec == 'rawvideo' || codec == 'wrapped_avframe') {
        outW = w;
        outH = h;
      } else {
        natW ??= w;
        natH ??= h;
      }
    }
    outW ??= natW;
    outH ??= natH;
    if (outW == null || outH == null) return null;
    return (natW ?? outW, natH ?? outH, outW, outH);
  }

  /// 直通 alpha -> 预乘。先扫一遍，全不透明就直接跳过写入。
  static void _premultiply(Uint8List p) {
    var hasAlpha = false;
    for (var i = 3; i < p.length; i += 4) {
      if (p[i] != 255) {
        hasAlpha = true;
        break;
      }
    }
    if (!hasAlpha) return;
    for (var i = 0; i < p.length; i += 4) {
      final a = p[i + 3];
      if (a == 255) continue;
      if (a == 0) {
        p[i] = 0;
        p[i + 1] = 0;
        p[i + 2] = 0;
        continue;
      }
      p[i] = (p[i] * a + 127) ~/ 255;
      p[i + 1] = (p[i + 1] * a + 127) ~/ 255;
      p[i + 2] = (p[i + 2] * a + 127) ~/ 255;
    }
  }

  static String _lastLine(String log) {
    final lines = log
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();
    if (lines.isEmpty) return '(无输出)';
    return lines.sublist(math.max(0, lines.length - 2)).join(' | ');
  }
}
