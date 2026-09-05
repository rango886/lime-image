import 'dart:io';
import 'dart:isolate';

import '../../core/utils.dart';
import 'decode_worker.dart';
import 'decoder.dart';
import 'embedded_preview.dart';
import 'ffmpeg_decoder.dart';
import 'format_sniffer.dart';
import 'wic_decoder.dart';

/// 某个格式在本机的可用状态
enum FormatSupport {
  /// Flutter 内置解码器直接支持
  native,

  /// 有外部解码器声称支持，且已实测成功过
  verified,

  /// 有解码器声称支持，但还没实际解过
  claimed,

  /// 试过，失败了
  failed,

  /// 没有任何解码器声称支持
  none,
}

class FormatStatus {
  FormatStatus(this.format, this.support, this.decoders);
  final ImageFormat format;
  final FormatSupport support;

  /// 声称能处理它的解码器 id
  final List<String> decoders;
}

/// 单个后端的运行时记账，设置页拿它做「实际在干活」的展示
class DecoderStat {
  int success = 0;
  int failure = 0;
  int lastMs = 0;
  int totalMs = 0;
  String? lastError;

  int get avgMs => success == 0 ? 0 : (totalMs / success).round();
}

/// 解码器优先级链 + 降级 + 黑名单 + 能力记账。
///
/// 设计依据两条实测教训：
///  1. 注册表/声明信息完全不可信 —— JXL 扩展损坏时注册项、Patterns、DLL
///     全都正常，但就是解不出来。所以能力判定只认「真的解成功过」。
///  2. 失败很贵 —— 一次失败的 ffmpeg 尝试要 30ms，image 包要 600ms。
///     同一个文件不能反复付这个学费，要记黑名单。
///
/// 实际解码默认在 [DecodePool]（常驻 worker isolate 池）里跑，主 isolate 只做
/// 记账和 GPU 上传，所以 JXL 大图 / ffmpeg 兜底都不会卡 UI。
class DecoderRegistry {
  DecoderRegistry({
    String? ffmpegPath,
    bool useIsolates = true,
    int isolateCount = 0,
  }) : _ffmpeg = FfmpegDecoder(explicitPath: ffmpegPath) {
    _useIsolates = useIsolates;
    _isolateCount = isolateCount;
    _all = [
      EmbeddedPreviewDecoder(),
      if (Platform.isWindows) WicDecoder(),
      _ffmpeg,
    ]..sort((a, b) => a.priority.compareTo(b.priority));
  }

  final FfmpegDecoder _ffmpeg;
  late final List<RawDecoder> _all;

  final Set<String> _available = {};
  bool _initialized = false;

  /// (path|decoderId) 失败记录，避免重复尝试
  final Set<String> _blacklist = {};

  /// format -> 是否已实测成功
  final Map<ImageFormat, bool> _verified = {};

  /// decoderId -> 运行时统计
  final Map<String, DecoderStat> stats = {};

  List<WicCodecInfo> _wicCodecs = const [];
  List<WicCodecInfo> get wicCodecs => _wicCodecs;

  // —— isolate 池 ——
  bool _useIsolates = true;
  int _isolateCount = 0;
  DecodePool? _pool;

  /// 池里真实的 worker 数（0 = 没启用/起不来，走主 isolate）
  int get isolateCount => _pool?.alive == true ? _pool!.size : 0;
  bool get isolatesEnabled => _useIsolates;
  int get isolateBusy => _pool?.busy ?? 0;

  /// 有多少次解码是在主 isolate 上做的（理想值：0）
  int mainIsolateDecodes = 0;

  String? get ffmpegPath => _ffmpeg.explicitPath;
  set ffmpegPath(String? v) {
    if (_ffmpeg.explicitPath == v) return;
    _ffmpeg.explicitPath = v;
    _ffmpeg.resetProbe();
    _pool?.ffmpegPath = v;
    _initialized = false;
    _probe = null;
  }

  /// 设置页改了「后台解码」相关项时调用
  void configureIsolates({bool? enabled, int? count}) {
    final newEnabled = enabled ?? _useIsolates;
    final newCount = count ?? _isolateCount;
    if (newEnabled == _useIsolates && newCount == _isolateCount) return;
    _useIsolates = newEnabled;
    _isolateCount = newCount;
    _pool?.dispose();
    _pool = null;
    if (_useIsolates) _ensurePool();
  }

  void _ensurePool() {
    if (!_useIsolates) return;
    _pool ??= DecodePool(size: _isolateCount, ffmpegPath: _ffmpeg.explicitPath);
    _pool!.start();
  }

  /// 启动时调用。只做「不花钱」的部分：平台判断 + 扩展名集合。
  ///
  /// 冷启动教训：原来这里同步跑 WIC 的 COM 枚举（装了 Store 图像扩展时会连带
  /// 加载一堆 DLL，几百 ms）、spawn 一个 ffmpeg 进程探版本（Defender 扫描又是
  /// 上百 ms）、再起 4 个 isolate —— 全都压在首帧上。现在这些都挪进
  /// [_probeInBackground]，首帧之后再做。
  Future<void> initialize({bool probeInBackground = true}) async {
    if (_initialized) return;
    _initialized = true;
    _available.clear();
    for (final d in _all) {
      if (d.id == 'ffmpeg') {
        // 乐观假设可用。真不在 PATH 上时后台探测会把它摘掉，
        // 期间万一用到了，解码链自己会失败并记账，代价远小于开机 spawn 一个进程。
        _available.add(d.id);
        continue;
      }
      if (await d.isAvailable()) _available.add(d.id);
    }
    setDecodableExtensions(decodableExtensions);
    if (probeInBackground) _probe ??= _probeInBackground();
  }

  /// 设置页「重新检测」：立即做完整探测（不带为首帧让路的延迟）
  Future<void> reprobeNow() async {
    resetProbeResults();
    await initialize(probeInBackground: false);
    await (_probe = _probeInBackground(immediate: true));
  }

  Future<void>? _probe;

  /// 后台探测：ffmpeg 真实可用性 + WIC codec 枚举 + 预热 isolate 池。
  /// 探测完成后返回，设置页可以 `await registry.probed` 拿到准确结果。
  Future<void> get probed async {
    await initialize();
    await _probe;
  }

  Future<void> _probeInBackground({bool immediate = false}) async {
    // 先把首帧让出去
    if (!immediate) {
      await Future<void>.delayed(const Duration(milliseconds: 400));
    }
    if (!await _ffmpeg.isAvailable()) _available.remove('ffmpeg');

    if (Platform.isWindows && _available.contains('wic')) {
      // COM 枚举是同步阻塞的，扔到临时 isolate 里跑，别卡 UI 线程。
      // 走 COM 而非注册表，才能看到 Store 扩展装的那些 codec。
      try {
        _wicCodecs = await Isolate.run(WicDecoder.enumerateDecoders);
      } catch (_) {
        _wicCodecs = const [];
      }
    }
    setDecodableExtensions(decodableExtensions);
    // 池的启动放最后：等到这会儿再抢 CPU 已经不影响开窗速度了
    _ensurePool();
    await _pool?.start();
  }

  bool get ffmpegAvailable => _available.contains('ffmpeg');
  bool get wicAvailable => _available.contains('wic');

  /// 声称能处理 [fmt] 的解码器（已过滤掉本机不可用的）
  List<RawDecoder> chainFor(ImageFormat fmt) =>
      _all.where((d) => _available.contains(d.id) && d.supports(fmt)).toList();

  /// 本机（可能）能解开的扩展名集合。给 `isDecodableFile()` 用。
  ///
  /// 刻意乐观：只要链上有解码器声称支持就算数。真正的「不支持」要等实际解过
  /// 才知道，而列文件时不可能为每个文件付一次解码代价。
  Set<String> get decodableExtensions {
    final out = <String>{};
    // SVG 走 vector 旁路（上层按 bucket 重新栅格化），不需要任何外部解码器
    out.addAll(extensionsOf(ImageFormat.svg));
    for (final f in ImageFormat.values) {
      if (f == ImageFormat.unknown) continue;
      if (f.skiaNative) {
        out.addAll(extensionsOf(f));
        continue;
      }
      if (_verified[f] == false && chainFor(f).isEmpty) continue;
      if (chainFor(f).isNotEmpty) out.addAll(extensionsOf(f));
    }
    // WIC 自己报的扩展名（Store 图像扩展装了什么就多认什么）
    for (final c in _wicCodecs) {
      out.addAll(c.extensions.where(kKnownImageExtensions.contains));
    }
    return out;
  }

  /// 给设置页用的能力总览
  List<FormatStatus> report() {
    final out = <FormatStatus>[];
    for (final f in ImageFormat.values) {
      if (f == ImageFormat.unknown) continue;
      if (f.skiaNative) {
        out.add(FormatStatus(f, FormatSupport.native, const ['skia']));
        continue;
      }
      if (f == ImageFormat.svg) {
        // SVG 不走位图管线，是按 bucket 重新栅格化的旁路
        out.add(FormatStatus(f, FormatSupport.native, const ['vector']));
        continue;
      }
      final chain = chainFor(f).map((d) => d.id).toList();
      final FormatSupport s;
      if (chain.isEmpty) {
        s = FormatSupport.none;
      } else if (_verified[f] == true) {
        s = FormatSupport.verified;
      } else if (_verified[f] == false) {
        s = FormatSupport.failed;
      } else {
        s = FormatSupport.claimed;
      }
      out.add(FormatStatus(f, s, chain));
    }
    return out;
  }

  /// 清掉实测记录和黑名单（设置页「重新检测」用）
  void resetProbeResults() {
    _blacklist.clear();
    _verified.clear();
    stats.clear();
    mainIsolateDecodes = 0;
    _initialized = false;
    _ffmpeg.resetProbe();
    _probe = null;
  }

  DecoderStat _stat(String id) => stats.putIfAbsent(id, DecoderStat.new);

  /// 按优先级依次尝试。[targetWidth] 会用来判断内嵌预览够不够清晰。
  Future<RawImageData> decode(
    String path,
    SniffResult sniff, {
    required int targetWidth,
    int maxFrames = 1,
  }) async {
    await initialize();

    final chain = chainFor(sniff.format)
        .where((d) => !_blacklist.contains('$path|${d.id}'))
        .toList();
    if (chain.isEmpty) {
      throw UnsupportedFormatException(sniff.format, const []);
    }

    if (_useIsolates) {
      final r = await _decodeInPool(path, sniff, targetWidth, maxFrames);
      if (r != null) return r;
      // 池不可用（起不来 / 已崩），降级到主 isolate，宁可卡一下也要能看图
    }
    return _decodeInline(path, sniff, targetWidth, maxFrames);
  }

  Future<RawImageData?> _decodeInPool(
    String path,
    SniffResult sniff,
    int targetWidth,
    int maxFrames,
  ) async {
    _ensurePool();
    final pool = _pool;
    if (pool == null) return null;
    // 池是懒启动的（开机不 spawn），第一次真的要解外部格式时才等它起来。
    // start() 幂等且缓存 future，之后的调用不花钱。
    await pool.start();
    if (!pool.alive) return null;
    final future = pool.submit(
      path: path,
      format: sniff.format,
      targetWidth: targetWidth,
      maxFrames: maxFrames,
      allow: _available.toList(),
      skip: _all
          .map((d) => d.id)
          .where((id) => _blacklist.contains('$path|$id'))
          .toList(),
    );
    if (future == null) return null;

    final DecodeOutcome out;
    try {
      out = await future;
    } catch (_) {
      return null; // worker 崩了 -> 交给主 isolate 重试
    }

    _applyFailures(path, sniff.format, out.failures);

    final data = out.data;
    if (data == null) {
      _throwFor(sniff.format, out.tried, out.failures);
    }
    final st = _stat(data.decoderId);
    st.success++;
    st.lastMs = out.elapsedMs;
    st.totalMs += out.elapsedMs;
    _verified[sniff.format] = true;
    return data;
  }

  void _applyFailures(
    String path,
    ImageFormat fmt,
    Map<String, String> failures,
  ) {
    for (final e in failures.entries) {
      _blacklist.add('$path|${e.key}');
      _verified[fmt] ??= false;
      final st = _stat(e.key);
      st.failure++;
      st.lastError = e.value;
    }
  }

  Never _throwFor(
    ImageFormat fmt,
    List<String> tried,
    Map<String, String> failures,
  ) {
    if (failures.isNotEmpty) {
      throw DecoderException(
        tried.join('->'),
        '${fmt.label} 解码失败',
        failures.values.last,
      );
    }
    throw UnsupportedFormatException(fmt, tried);
  }

  /// 主 isolate 兜底路径。只有 isolate 池不可用时才会走到，会卡 UI。
  Future<RawImageData> _decodeInline(
    String path,
    SniffResult sniff,
    int targetWidth,
    int maxFrames,
  ) async {
    mainIsolateDecodes++;
    final tried = <String>[];
    final failures = <String, String>{};
    RawImageData? weakPreview;

    for (final d in chainFor(sniff.format)) {
      final key = '$path|${d.id}';
      if (_blacklist.contains(key)) continue;
      tried.add(d.id);
      final sw = Stopwatch()..start();
      try {
        final r = await d.decode(
          path,
          targetWidth: targetWidth,
          maxFrames: maxFrames,
        );

        // 内嵌预览只在「够清晰」时才采用，否则继续找真解码器。
        // 这样缩略图/胶片条能吃到 2ms 的快路径，主视图不会被糊图糊住。
        if (r.previewOnly &&
            targetWidth > 0 &&
            r.effectiveWidth < targetWidth * 0.8) {
          weakPreview ??= r;
          continue;
        }

        final st = _stat(d.id);
        st.success++;
        st.lastMs = sw.elapsedMilliseconds;
        st.totalMs += st.lastMs;
        _verified[sniff.format] = true;
        return r;
      } catch (e) {
        failures[d.id] = e.toString();
      }
    }
    _applyFailures(path, sniff.format, failures);

    if (weakPreview != null) {
      _verified[sniff.format] = true;
      return weakPreview;
    }
    _throwFor(sniff.format, tried, failures);
  }

  void dispose() {
    _pool?.dispose();
    _pool = null;
    for (final d in _all) {
      d.dispose();
    }
  }
}
