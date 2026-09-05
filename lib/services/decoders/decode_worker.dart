import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'decoder.dart';
import 'embedded_preview.dart';
import 'ffmpeg_decoder.dart';
import 'format_sniffer.dart';
import 'wic_decoder.dart';

/// 常驻 worker isolate 池。
///
/// 为什么不是 `Isolate.run`：那样每张图都要重付 `CoInitializeEx` +
/// `IWICImagingFactory` 创建的成本（实测每次 ~10ms），而且 isolate spawn 本身
/// 也要几 ms。常驻池只付一次。
///
/// 关键点：
///  - `WicDecoder._comInited` / `_factory` 是顶层静态，Dart 里天然 per-isolate，
///    正好当成「每个 worker 一份 COM 状态」用。
///  - 像素回传走 [TransferableTypedData]，零拷贝（内存所有权直接转移）。
///  - `ui.Image` 不能跨 isolate，所以 worker 只出 RGBA/BGRA 字节，
///    `ImageDescriptor` / `instantiateCodec` 仍在主 isolate 做（那步是 GPU 上传，很快）。
class DecodePool {
  DecodePool({int? size, this.ffmpegPath}) : size = _clampSize(size);

  /// 建议 min(4, cores/2)：再多也只是抢 CPU，还会让 ffmpeg 进程数失控
  static int _clampSize(int? requested) {
    if (requested != null && requested > 0) return math.min(requested, 8);
    final cores = Platform.numberOfProcessors;
    return math.max(1, math.min(4, cores ~/ 2));
  }

  final int size;

  /// 用户手动指定的 ffmpeg 路径（随请求下发，改了立即生效）
  String? ffmpegPath;

  final List<_Worker> _workers = [];
  final Map<int, Completer<DecodeOutcome>> _pending = {};
  int _nextId = 1;
  bool _disposed = false;
  Future<void>? _starting;

  bool get alive => _workers.isNotEmpty;

  /// 池里正在跑的任务数（设置页展示用）
  int get busy => _workers.fold(0, (a, w) => a + w.inflight);

  Future<void> start() {
    if (_disposed) return Future.value();
    return _starting ??= _startAll();
  }

  Future<void> _startAll() async {
    // 并行 spawn：串行起 4 个 isolate 会把首次外部格式解码的等待时间乘以 4
    final spawned = await Future.wait(
      List.generate(size, (i) async {
        try {
          return await _Worker.spawn(i, _onMessage, _ffmpegSlots);
        } catch (_) {
          // 起不来就少一个 worker；一个都起不来时上层走主 isolate 兜底
          return null;
        }
      }),
    );
    if (_disposed) {
      for (final w in spawned) {
        w?.kill();
      }
      return;
    }
    _workers.addAll(spawned.whereType<_Worker>());
  }

  /// ffmpeg 总并发保持在 3 左右：池里每个 worker 分一点
  int get _ffmpegSlots => math.max(1, (3 / size).ceil());

  void _onMessage(_Worker w, Object? msg) {
    if (msg is DecodeResponse) {
      w.inflight = math.max(0, w.inflight - 1);
      _pending.remove(msg.id)?.complete(msg.toOutcome());
      return;
    }
    // isolate 崩了（onError 会送来 [error, stack]）：把它挂在上面的任务全部失败掉
    if (msg is List) {
      final ids = w.jobs.toList();
      w.jobs.clear();
      w.inflight = 0;
      for (final id in ids) {
        _pending
            .remove(id)
            ?.completeError(
              DecoderException('isolate', 'worker 异常: ${msg.first}'),
            );
      }
      _workers.remove(w);
      w.kill();
    }
  }

  /// 派给最闲的 worker。返回 null 表示池不可用，调用方应走主 isolate。
  Future<DecodeOutcome>? submit({
    required String path,
    required ImageFormat format,
    required int targetWidth,
    required int maxFrames,
    required List<String> allow,
    required List<String> skip,
  }) {
    if (_disposed || _workers.isEmpty) return null;
    _workers.sort((a, b) => a.inflight.compareTo(b.inflight));
    final w = _workers.first;
    final id = _nextId++;
    final c = Completer<DecodeOutcome>();
    _pending[id] = c;
    w.inflight++;
    w.jobs.add(id);
    w.port.send(
      DecodeRequest(
        id: id,
        path: path,
        formatIndex: format.index,
        targetWidth: targetWidth,
        maxFrames: maxFrames,
        allow: allow,
        skip: skip,
        ffmpegPath: ffmpegPath,
      ),
    );
    return c.future.whenComplete(() => w.jobs.remove(id));
  }

  void dispose() {
    _disposed = true;
    for (final w in _workers) {
      w.kill();
    }
    _workers.clear();
    for (final c in _pending.values) {
      if (!c.isCompleted) {
        c.completeError(DecoderException('isolate', '解码池已关闭'));
      }
    }
    _pending.clear();
    _starting = null;
  }
}

class _Worker {
  _Worker(this.index, this.isolate, this.port, this._rp);

  static Future<_Worker> spawn(
    int index,
    void Function(_Worker, Object?) onMessage,
    int ffmpegSlots,
  ) async {
    final rp = ReceivePort();
    final ready = Completer<SendPort>();
    late final _Worker worker;
    rp.listen((msg) {
      if (msg is SendPort) {
        ready.complete(msg);
        return;
      }
      onMessage(worker, msg);
    });
    final iso = await Isolate.spawn(
      _workerMain,
      _WorkerInit(rp.sendPort, ffmpegSlots),
      debugName: 'limeimage-decode-$index',
      onError: rp.sendPort,
      errorsAreFatal: false,
    );
    final port = await ready.future.timeout(const Duration(seconds: 10));
    return worker = _Worker(index, iso, port, rp);
  }

  final int index;
  final Isolate isolate;
  final SendPort port;
  final ReceivePort _rp;

  int inflight = 0;
  final Set<int> jobs = {};

  void kill() {
    try {
      port.send(null); // 让它先自己释放 COM 对象
    } catch (_) {}
    isolate.kill(priority: Isolate.beforeNextEvent);
    _rp.close();
  }
}

// ---------------------------------------------------------------------------
// 消息
// ---------------------------------------------------------------------------

class _WorkerInit {
  const _WorkerInit(this.reply, this.ffmpegSlots);
  final SendPort reply;
  final int ffmpegSlots;
}

class DecodeRequest {
  const DecodeRequest({
    required this.id,
    required this.path,
    required this.formatIndex,
    required this.targetWidth,
    required this.maxFrames,
    required this.allow,
    required this.skip,
    required this.ffmpegPath,
  });

  final int id;
  final String path;
  final int formatIndex;
  final int targetWidth;
  final int maxFrames;

  /// 本机可用的解码器 id（主 isolate 探测好的结果）
  final List<String> allow;

  /// 黑名单：这个文件在这些解码器上已经失败过
  final List<String> skip;
  final String? ffmpegPath;
}

class DecodeResponse {
  DecodeResponse({
    required this.id,
    required this.tried,
    required this.failures,
    required this.elapsedMs,
    this.decoderId,
    this.payload,
    this.frameCount = 0,
    this.width = 0,
    this.height = 0,
    this.naturalWidth = 0,
    this.naturalHeight = 0,
    this.orientation = 1,
    this.isEncoded = false,
    this.previewOnly = false,
    this.bgra = true,
    this.delaysMs = const [],
    this.error,
  });

  final int id;
  final List<String> tried;

  /// decoderId -> 错误文本
  final Map<String, String> failures;
  final int elapsedMs;

  final String? decoderId;
  final TransferableTypedData? payload;
  final int frameCount;
  final int width;
  final int height;
  final int naturalWidth;
  final int naturalHeight;
  final int orientation;
  final bool isEncoded;
  final bool previewOnly;
  final bool bgra;
  final List<int> delaysMs;
  final String? error;

  bool get ok => decoderId != null && payload != null;

  DecodeOutcome toOutcome() {
    if (!ok) {
      return DecodeOutcome(
        data: null,
        tried: tried,
        failures: failures,
        elapsedMs: elapsedMs,
      );
    }
    final bytes = payload!.materialize().asUint8List();
    final RawImageData data;
    if (isEncoded) {
      data = RawImageData.encoded(
        encoded: bytes,
        width: width,
        height: height,
        naturalWidth: naturalWidth,
        naturalHeight: naturalHeight,
        orientation: orientation,
        decoderId: decoderId!,
        previewOnly: previewOnly,
      );
    } else {
      final stride = width * height * 4;
      final frames = <Uint8List>[];
      for (var i = 0; i < frameCount; i++) {
        final off = i * stride;
        if (off + stride > bytes.length) break;
        frames.add(Uint8List.sublistView(bytes, off, off + stride));
      }
      data = RawImageData.pixels(
        frames: frames,
        width: width,
        height: height,
        format: bgra ? RawPixelFormat.bgra8888 : RawPixelFormat.rgba8888,
        naturalWidth: naturalWidth,
        naturalHeight: naturalHeight,
        orientation: orientation,
        decoderId: decoderId!,
        previewOnly: previewOnly,
        delays: delaysMs.map((v) => Duration(milliseconds: v)).toList(),
      );
    }
    return DecodeOutcome(
      data: data,
      tried: tried,
      failures: failures,
      elapsedMs: elapsedMs,
    );
  }
}

/// 一次池内解码的完整结果：成功的数据 + 失败记账（主 isolate 要拿去更新黑名单）
class DecodeOutcome {
  const DecodeOutcome({
    required this.data,
    required this.tried,
    required this.failures,
    required this.elapsedMs,
  });
  final RawImageData? data;
  final List<String> tried;
  final Map<String, String> failures;
  final int elapsedMs;
}

// ---------------------------------------------------------------------------
// worker 侧
// ---------------------------------------------------------------------------

Future<void> _workerMain(_WorkerInit init) async {
  final rp = ReceivePort();
  init.reply.send(rp.sendPort);

  final ffmpeg = FfmpegDecoder(maxConcurrent: init.ffmpegSlots);
  final decoders = <RawDecoder>[
    EmbeddedPreviewDecoder(),
    if (Platform.isWindows) WicDecoder(),
    ffmpeg,
  ]..sort((a, b) => a.priority.compareTo(b.priority));

  await for (final msg in rp) {
    if (msg == null) break;
    if (msg is! DecodeRequest) continue;
    ffmpeg.explicitPath = msg.ffmpegPath;
    init.reply.send(await _handle(msg, decoders));
  }

  for (final d in decoders) {
    d.dispose();
  }
  rp.close();
}

Future<DecodeResponse> _handle(
  DecodeRequest req,
  List<RawDecoder> decoders,
) async {
  final sw = Stopwatch()..start();
  final fmt = ImageFormat.values[req.formatIndex];
  final tried = <String>[];
  final failures = <String, String>{};

  // 太糊的内嵌预览先留着当兜底：真解码器全挂了也好过什么都不显示
  RawImageData? weakPreview;

  for (final d in decoders) {
    if (!req.allow.contains(d.id)) continue;
    if (req.skip.contains(d.id)) continue;
    if (!d.supports(fmt)) continue;
    tried.add(d.id);
    try {
      final r = await d.decode(
        req.path,
        targetWidth: req.targetWidth,
        maxFrames: req.maxFrames,
      );
      if (r.previewOnly &&
          req.targetWidth > 0 &&
          r.effectiveWidth < req.targetWidth * 0.8) {
        weakPreview ??= r;
        continue;
      }
      return _success(req.id, r, tried, failures, sw.elapsedMilliseconds);
    } catch (e) {
      failures[d.id] = e.toString();
    }
  }

  if (weakPreview != null) {
    return _success(
      req.id,
      weakPreview,
      tried,
      failures,
      sw.elapsedMilliseconds,
    );
  }
  return DecodeResponse(
    id: req.id,
    tried: tried,
    failures: failures,
    elapsedMs: sw.elapsedMilliseconds,
  );
}

/// `TransferableTypedData` 对「视图」的语义不够明确（会不会把整个底层 buffer
/// 一起搬过去），所以只在真的是部分视图时拷一份，保证接收端偏移正确。
Uint8List _own(Uint8List b) =>
    b.offsetInBytes == 0 && b.lengthInBytes == b.buffer.lengthInBytes
    ? b
    : Uint8List.fromList(b);

DecodeResponse _success(
  int id,
  RawImageData r,
  List<String> tried,
  Map<String, String> failures,
  int elapsedMs,
) {
  final payload = TransferableTypedData.fromList(
    (r.isEncoded ? [r.encoded!] : r.frames).map(_own).toList(),
  );
  return DecodeResponse(
    id: id,
    tried: tried,
    failures: failures,
    elapsedMs: elapsedMs,
    decoderId: r.decoderId,
    payload: payload,
    frameCount: r.isEncoded ? 1 : r.frames.length,
    width: r.width,
    height: r.height,
    naturalWidth: r.naturalWidth,
    naturalHeight: r.naturalHeight,
    orientation: r.orientation,
    isEncoded: r.isEncoded,
    previewOnly: r.previewOnly,
    bgra: r.format == RawPixelFormat.bgra8888,
    delaysMs: r.delays.map((d) => d.inMilliseconds).toList(),
  );
}
