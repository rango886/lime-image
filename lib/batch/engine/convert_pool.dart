import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;

import '../convert_preset.dart';
import 'convert_engine.dart';

/// 发给 worker 的任务
class ConvertJob {
  ConvertJob({
    required this.path,
    required this.preset,
    this.cropOverride,
    this.previewMax = 0,
  });

  final String path;
  final ConvertPreset preset;
  final List<double>? cropOverride;

  /// >0 表示预览：会多返回两张缩小的图，而且 worker 会缓存解码结果
  final int previewMax;
}

class _Worker {
  _Worker(this.isolate, this.port);
  final Isolate isolate;
  final SendPort port;
  Completer<ConvertResult>? busy;
}

/// 常驻 isolate 池。每个 worker 同时只跑一个任务，排队的任务可以整体取消。
class ConvertPool {
  ConvertPool({int? size, this.ffmpegPath})
    : size = size ?? math.max(1, math.min(4, Platform.numberOfProcessors ~/ 2));

  final int size;
  String? ffmpegPath;

  final List<_Worker> _workers = [];
  final List<(ConvertJob, Completer<ConvertResult>)> _queue = [];
  final ReceivePort _rx = ReceivePort();
  Future<void>? _starting;
  final Map<int, _Worker> _byId = {};
  bool _disposed = false;

  Future<void> start() => _starting ??= _spawnAll();

  Future<void> _spawnAll() async {
    final ready = <int, Completer<SendPort>>{};
    _rx.listen((msg) {
      if (msg is! List) return;
      final id = msg[0] as int;
      if (msg[1] is SendPort) {
        ready[id]?.complete(msg[1] as SendPort);
        return;
      }
      final w = _byId[id];
      final c = w?.busy;
      if (w == null || c == null) return;
      w.busy = null;
      c.complete(ConvertResult.fromMessage(msg[1] as Map));
      _pump();
    });
    for (var i = 0; i < size; i++) {
      ready[i] = Completer<SendPort>();
      final iso = await Isolate.spawn(_workerMain, [
        i,
        _rx.sendPort,
        ffmpegPath,
      ], debugName: 'convert-$i');
      final port = await ready[i]!.future;
      final w = _Worker(iso, port);
      _workers.add(w);
      _byId[i] = w;
    }
  }

  Future<ConvertResult> submit(ConvertJob job) {
    final c = Completer<ConvertResult>();
    _queue.add((job, c));
    start().then((_) => _pump());
    return c.future;
  }

  int get pending => _queue.length;

  /// 丢掉还没开始的任务（返回的 future 以「已取消」结束）
  void cancelPending() {
    for (final (_, c) in _queue) {
      c.complete(ConvertResult()..skipped = '已取消');
    }
    _queue.clear();
  }

  void _pump() {
    if (_disposed) return;
    for (final w in _workers) {
      if (_queue.isEmpty) return;
      if (w.busy != null) continue;
      final (job, c) = _queue.removeAt(0);
      w.busy = c;
      w.port.send({
        'path': job.path,
        'preset': job.preset.toJson(),
        'crop': job.cropOverride,
        'previewMax': job.previewMax,
        'ffmpeg': ffmpegPath,
      });
    }
  }

  void dispose() {
    _disposed = true;
    cancelPending();
    for (final w in _workers) {
      w.isolate.kill(priority: Isolate.immediate);
      w.busy?.complete(ConvertResult()..skipped = '已取消');
    }
    _workers.clear();
    _rx.close();
  }
}

Future<void> _workerMain(List<Object?> init) async {
  final id = init[0] as int;
  final reply = init[1] as SendPort;
  final rx = ReceivePort();
  reply.send([id, rx.sendPort]);

  final engine = ConvertEngine(ffmpegPath: init[2] as String?);
  // 预览会对同一张图反复跑，缓存最近一张的解码结果
  String? cachedKey;
  SourceImage? cached;

  await for (final msg in rx) {
    final m = msg as Map;
    final path = m['path'] as String;
    final preview = (m['previewMax'] as int) > 0;
    final preset = ConvertPreset.fromJson(
      (m['preset'] as Map).cast<String, dynamic>(),
    );
    if (m['ffmpeg'] != engine.ffmpegPath) {
      engine.ffmpegPath = m['ffmpeg'] as String?;
    }
    ConvertResult r;
    try {
      SourceImage src;
      final stat = await File(path).stat();
      final key = '$path|${stat.modified.millisecondsSinceEpoch}|${stat.size}';
      if (preview && key == cachedKey && cached != null) {
        src = cached;
      } else {
        src = await engine.load(
          path,
          checkAnimated: preview || preset.animated == AnimatedPolicy.skip,
        );
        if (preview) {
          cachedKey = key;
          cached = src;
        } else {
          cachedKey = null;
          cached = null;
        }
      }
      r = await engine.process(
        src,
        preset,
        cropOverride: (m['crop'] as List?)?.cast<double>(),
        previewMax: m['previewMax'] as int,
      );
    } catch (e) {
      r = ConvertResult()..error = _msg(e);
    }
    reply.send([id, r.toMessage()]);
  }
}

String _msg(Object e) {
  if (e is FormatException) return e.message;
  final s = e.toString();
  return s.length > 200 ? '${s.substring(0, 200)}…' : s;
}
