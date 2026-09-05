import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:exif/exif.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../core/utils.dart';
import '../models/settings.dart';
import 'decoders/decoder.dart';
import 'decoders/decoder_registry.dart';
import 'decoders/format_sniffer.dart';

class AnimFrame {
  AnimFrame(this.image, this.duration);
  final ui.Image image;
  final Duration duration;
}

/// 一张已解码的图片（静图 = 单帧）
class DecodedImage {
  DecodedImage({
    required this.path,
    required this.naturalWidth,
    required this.naturalHeight,
    required this.decodedWidth,
    required this.frames,
    required this.orientation,
    required this.fileBytes,
    required this.truncatedFrames,
    this.vector = false,
  });

  final String path;
  final int naturalWidth;
  final int naturalHeight;
  final int decodedWidth;
  final List<AnimFrame> frames;
  final int orientation; // EXIF 1..8
  final int fileBytes;
  final bool truncatedFrames;

  /// 矢量图（SVG）：帧是按当前 bucket 重新栅格化出来的，
  /// 所以 decodedWidth 可以超过 naturalWidth，放大时值得再栅格化一次。
  final bool vector;

  bool get animated => frames.length > 1;
  int get frameCount => frames.length;
  ui.Image get image => frames.first.image;

  /// EXIF 旋转是否交换宽高
  bool get swapsAxes => orientation >= 5;
  int get displayWidth => swapsAxes ? naturalHeight : naturalWidth;
  int get displayHeight => swapsAxes ? naturalWidth : naturalHeight;

  int get memoryBytes {
    var total = 0;
    for (final f in frames) {
      total += f.image.width * f.image.height * 4;
    }
    return total;
  }

  bool _disposed = false;
  bool get disposed => _disposed;

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    for (final f in frames) {
      f.image.dispose();
    }
  }
}

class _CacheEntry {
  _CacheEntry(this.image);
  final DecodedImage image;
  int pins = 0;
}

/// 解码 + 缓存 + 预取。核心性能点：
///  1. 按视口尺寸降采样解码，绝不整分辨率进内存
///  2. 分级缓存（bucket），放大时按需再解码更高清版本
///  3. LRU 按字节数限制，正在显示的条目 pin 住不回收
class ImageService {
  ImageService(this.settings)
    : registry = DecoderRegistry(
        ffmpegPath: settings.ffmpegPath,
        useIsolates: settings.decodeInIsolate,
        isolateCount: settings.decodeIsolateCount,
      );

  Settings settings;

  /// 外部解码器链（WIC / ffmpeg / 内嵌预览）。设置页也要读它做能力展示。
  final DecoderRegistry registry;

  /// 启动后异步跑一次后端探测，不阻塞首帧
  Future<void> warmUp() => registry.initialize();

  /// 设置页改了解码相关项后同步到解码链
  void applySettings() {
    registry.ffmpegPath = settings.ffmpegPath;
    registry.configureIsolates(
      enabled: settings.decodeInIsolate,
      count: settings.decodeIsolateCount,
    );
  }

  final LinkedHashMap<String, _CacheEntry> _cache = LinkedHashMap();
  final Map<String, Future<DecodedImage>> _inflight = {};
  final Map<String, ProbedSize?> _sizeCache = {};
  int _bytes = 0;

  int get cacheBytes => _bytes;
  int get cacheCount => _cache.length;

  static const List<int> _buckets = [
    256,
    512,
    1024,
    1536,
    2048,
    3072,
    4096,
    6144,
    8192,
  ];

  int bucketFor(int targetWidth) {
    for (final b in _buckets) {
      if (targetWidth <= b) return b;
    }
    return math.max(settings.maxDecodeDimension, 8192);
  }

  String _key(String path, int bucket) => '$path|$bucket';

  /// 已缓存的最佳版本（优先满足 minWidth 的最小版本，否则最大版本）
  DecodedImage? cached(String path, {int? minWidth}) {
    final versions = <DecodedImage>[];
    for (final e in _cache.entries) {
      if (e.key.startsWith('$path|')) versions.add(e.value.image);
    }
    if (versions.isEmpty) return null;
    versions.sort((a, b) => a.decodedWidth.compareTo(b.decodedWidth));
    if (minWidth != null) {
      for (final v in versions) {
        if (v.decodedWidth >= minWidth) return v;
      }
    }
    return versions.last;
  }

  Future<ProbedSize?> size(String path) async => _sizeCache.containsKey(path)
      ? _sizeCache[path]
      : _sizeCache[path] = await probeImageSize(path);

  ProbedSize? sizeSync(String path) => _sizeCache[path];

  /// 主入口
  Future<DecodedImage> load(String path, {required int targetWidth}) {
    final bucket = bucketFor(targetWidth);
    final key = _key(path, bucket);
    final hit = _cache[key];
    if (hit != null) {
      _touch(key);
      return Future.value(hit.image);
    }
    final existing = _inflight[key];
    if (existing != null) return existing;
    final future = _decode(path, bucket).then(
      (img) {
        _insert(key, img);
        _inflight.remove(key);
        return img;
      },
      onError: (Object e, StackTrace st) {
        _inflight.remove(key);
        throw e;
      },
    );
    _inflight[key] = future;
    return future;
  }

  Future<void> prefetch(Iterable<String> paths, int targetWidth) async {
    for (final path in paths) {
      final bucket = bucketFor(targetWidth);
      if (_cache.containsKey(_key(path, bucket))) continue;
      try {
        await load(path, targetWidth: targetWidth);
      } catch (_) {}
      // 让出主线程，避免预取拖慢交互
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }
  }

  /// 漫画模式等“同屏多张”的场景里，当前可见的所有图都不能被 pin/LRU 捣掉，
  /// 否则一边滚一边被 dispose，画面就一闪一闪。
  final Set<String> keepAlive = <String>{};

  void pin(String path) {
    for (final e in _cache.entries) {
      final owner = e.key.substring(0, e.key.lastIndexOf('|'));
      // 只保护当前图 + 可见的漫画页，其他的交给 LRU，
      // 否则 pin 会愈积愈多导致缓存无法回收
      e.value.pins = (owner == path || keepAlive.contains(owner)) ? 1 : 0;
    }
  }

  void unpinAll() {
    for (final e in _cache.values) {
      e.pins = 0;
    }
  }

  void evict(String path) {
    final keys = _cache.keys.where((k) => k.startsWith('$path|')).toList();
    for (final k in keys) {
      final e = _cache.remove(k);
      if (e != null) {
        _bytes -= e.image.memoryBytes;
        e.image.dispose();
      }
    }
    _sizeCache.remove(path);
  }

  void clear() {
    for (final e in _cache.values) {
      e.image.dispose();
    }
    _cache.clear();
    _bytes = 0;
  }

  void dispose() {
    clear();
    registry.dispose();
  }

  void _touch(String key) {
    final e = _cache.remove(key);
    if (e != null) _cache[key] = e;
  }

  void _insert(String key, DecodedImage img) {
    final entry = _CacheEntry(img);
    // 刚解码出来的图先保护起来，否则大图会在 _trim() 里被立即 dispose，
    // 调用方拿到一个已销毁的 DecodedImage，表现就是“有时候不显示图片”。
    entry.pins = 1;
    _cache[key] = entry;
    _bytes += img.memoryBytes;
    _trim();
  }

  void _trim() {
    final limit = settings.maxCacheMB * 1024 * 1024;
    if (_bytes <= limit) return;
    final keys = _cache.keys.toList();
    for (final k in keys) {
      if (_bytes <= limit) break;
      final e = _cache[k]!;
      final owner = k.substring(0, k.lastIndexOf('|'));
      if (e.pins > 0 || keepAlive.contains(owner)) continue;
      _cache.remove(k);
      _bytes -= e.image.memoryBytes;
      e.image.dispose();
    }
  }

  Future<DecodedImage> _decode(String path, int bucket) async {
    final fileBytes = await File(path).length();
    final sniff = await FormatSniffer.sniffFile(path);

    // Skia 能直接吃的格式走原路径，一行不改
    if (sniff.format.skiaNative) {
      return _decodeNative(path, bucket, fileBytes);
    }
    // SVG 是矢量：按 bucket 重新栅格化，别塞进位图管线
    if (sniff.format == ImageFormat.svg) {
      return _decodeSvg(path, bucket, fileBytes);
    }
    return _decodeExternal(path, bucket, fileBytes, sniff);
  }

  // ---------------------------------------------------------------------------
  // SVG：每个 bucket 单独栅格化一次，缩放永远清晰
  // ---------------------------------------------------------------------------
  Future<DecodedImage> _decodeSvg(
    String path,
    int bucket,
    int fileBytes,
  ) async {
    final raw = await File(path).readAsBytes();
    // .svgz / 被 gzip 过的 .svg
    final bytes = (raw.length > 2 && raw[0] == 0x1F && raw[1] == 0x8B)
        ? Uint8List.fromList(gzip.decode(raw))
        : raw;
    final text = utf8.decode(bytes, allowMalformed: true);

    final info = await vg.loadPicture(SvgStringLoader(text), null);
    try {
      var logicalW = info.size.width;
      var logicalH = info.size.height;
      if (!logicalW.isFinite || logicalW <= 0) logicalW = 512;
      if (!logicalH.isFinite || logicalH <= 0) logicalH = 512;

      final maxDim = settings.maxDecodeDimension;
      var rasterW = math.min(bucket, maxDim).toDouble();
      var rasterH = logicalH * rasterW / logicalW;
      if (rasterH > maxDim) {
        rasterH = maxDim.toDouble();
        rasterW = logicalW * rasterH / logicalH;
      }
      final rw = math.max(1, rasterW.round());
      final rh = math.max(1, rasterH.round());

      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);
      canvas.scale(rw / logicalW, rh / logicalH);
      canvas.drawPicture(info.picture);
      final pic = recorder.endRecording();
      final image = await pic.toImage(rw, rh);
      pic.dispose();

      return DecodedImage(
        path: path,
        naturalWidth: logicalW.round(),
        naturalHeight: logicalH.round(),
        decodedWidth: rw,
        frames: [AnimFrame(image, Duration.zero)],
        orientation: 1,
        fileBytes: fileBytes,
        truncatedFrames: false,
        vector: true,
      );
    } finally {
      info.picture.dispose();
    }
  }

  /// 外部解码器路径：WIC / ffmpeg / 内嵌预览
  Future<DecodedImage> _decodeExternal(
    String path,
    int bucket,
    int fileBytes,
    SniffResult sniff,
  ) async {
    final maxFrames = sniff.format.animated
        ? math.max(1, settings.animMaxCachedFrames)
        : 1;

    final RawImageData raw;
    try {
      raw = await registry.decode(
        path,
        sniff,
        targetWidth: bucket,
        maxFrames: maxFrames,
      );
    } catch (e) {
      debugPrint('[lime image] $path 解码失败: $e');
      rethrow;
    }

    final orientation = settings.applyExifOrientation ? raw.orientation : 1;

    // 形态一：解码器给的是编码字节（内嵌 JPEG 预览），
    // 直接复用 Skia 的 encoded 路径，白拿降采样。
    if (raw.isEncoded) {
      final buffer = await ui.ImmutableBuffer.fromUint8List(raw.encoded!);
      return _decodeFromBuffer(
        path: path,
        buffer: buffer,
        bucket: bucket,
        fileBytes: fileBytes,
        orientation: orientation,
      );
    }

    // 形态二：已经是目标尺寸的原始像素，不需要再缩
    final pixelFormat = raw.format == RawPixelFormat.bgra8888
        ? ui.PixelFormat.bgra8888
        : ui.PixelFormat.rgba8888;

    final frames = <AnimFrame>[];
    var truncated = false;
    const budget = 256 * 1024 * 1024;
    var used = 0;

    for (var i = 0; i < raw.frames.length; i++) {
      final cost = raw.width * raw.height * 4;
      if (frames.isNotEmpty && used + cost > budget) {
        truncated = true;
        break;
      }
      used += cost;
      final buffer = await ui.ImmutableBuffer.fromUint8List(raw.frames[i]);
      final desc = ui.ImageDescriptor.raw(
        buffer,
        width: raw.width,
        height: raw.height,
        pixelFormat: pixelFormat,
      );
      ui.Codec? codec;
      try {
        codec = await desc.instantiateCodec();
        final f = await codec.getNextFrame();
        final d = raw.delays.length > i ? raw.delays[i] : Duration.zero;
        frames.add(
          AnimFrame(
            f.image,
            d.inMilliseconds <= 10 && raw.frames.length > 1
                ? const Duration(milliseconds: 100)
                : d,
          ),
        );
      } finally {
        codec?.dispose();
        desc.dispose();
        buffer.dispose();
      }
    }

    if (frames.isEmpty) {
      throw DecoderException(raw.decoderId, '解码后没有任何帧');
    }

    return DecodedImage(
      path: path,
      naturalWidth: raw.naturalWidth > 0 ? raw.naturalWidth : raw.width,
      naturalHeight: raw.naturalHeight > 0 ? raw.naturalHeight : raw.height,
      decodedWidth: raw.width,
      frames: frames,
      orientation: orientation,
      fileBytes: fileBytes,
      truncatedFrames: truncated,
    );
  }

  Future<DecodedImage> _decodeNative(
    String path,
    int bucket,
    int fileBytes,
  ) async {
    final orientation = settings.applyExifOrientation
        ? await _readOrientation(File(path))
        : 1;
    final buffer = await ui.ImmutableBuffer.fromFilePath(path);
    return _decodeFromBuffer(
      path: path,
      buffer: buffer,
      bucket: bucket,
      fileBytes: fileBytes,
      orientation: orientation,
    );
  }

  /// 编码字节 -> DecodedImage。原来 _decode 的主体，抽出来给两条路径共用。
  Future<DecodedImage> _decodeFromBuffer({
    required String path,
    required ui.ImmutableBuffer buffer,
    required int bucket,
    required int fileBytes,
    required int orientation,
  }) async {
    ui.ImageDescriptor? desc;
    ui.Codec? codec;
    try {
      desc = await ui.ImageDescriptor.encoded(buffer);
      final natW = desc.width;
      final natH = desc.height;
      final maxDim = settings.maxDecodeDimension;

      var targetW = math.min(natW, bucket);
      // 保证长边不超过纹理上限
      final longSide = natW >= natH ? targetW : (targetW * natH / natW).round();
      if (longSide > maxDim) {
        targetW = natW >= natH
            ? maxDim
            : math.max(1, (maxDim * natW / natH).round());
      }
      if (targetW < 1) targetW = 1;
      final targetH = math.max(1, (natH * targetW / natW).round());

      codec = await desc.instantiateCodec(
        targetWidth: targetW == natW ? null : targetW,
        targetHeight: targetW == natW ? null : targetH,
      );

      final frames = <AnimFrame>[];
      final maxFrames = math.max(1, settings.animMaxCachedFrames);
      final total = codec.frameCount;
      var truncated = false;
      if (total <= 1) {
        final f = await codec.getNextFrame();
        frames.add(AnimFrame(f.image, f.duration));
      } else {
        // 动图：整体像素预算 256MB，超了就只缓存前面的帧
        const budget = 256 * 1024 * 1024;
        var used = 0;
        for (var i = 0; i < math.min(total, maxFrames); i++) {
          final f = await codec.getNextFrame();
          final cost = f.image.width * f.image.height * 4;
          if (used + cost > budget && frames.isNotEmpty) {
            f.image.dispose();
            truncated = true;
            break;
          }
          used += cost;
          frames.add(
            AnimFrame(
              f.image,
              f.duration.inMilliseconds <= 10
                  ? const Duration(milliseconds: 100)
                  : f.duration,
            ),
          );
        }
        if (frames.length < total) truncated = true;
      }

      return DecodedImage(
        path: path,
        naturalWidth: natW,
        naturalHeight: natH,
        decodedWidth: frames.first.image.width,
        frames: frames,
        orientation: orientation,
        fileBytes: fileBytes,
        truncatedFrames: truncated,
      );
    } finally {
      codec?.dispose();
      desc?.dispose();
      buffer.dispose();
    }
  }

  Future<int> _readOrientation(File file) async {
    try {
      final ext = file.path.toLowerCase();
      // 只有这几种容器的 EXIF 能被 exif 包直接读到；
      // HEIC/AVIF/JXL/RAW 的方向由 WIC 在解码时通过元数据查询给出。
      if (!(ext.endsWith('.jpg') ||
          ext.endsWith('.jpeg') ||
          ext.endsWith('.jpe') ||
          ext.endsWith('.jfif') ||
          ext.endsWith('.tif') ||
          ext.endsWith('.tiff') ||
          ext.endsWith('.webp'))) {
        return 1;
      }
      final raf = await file.open();
      final head = await raf.read(math.min(await raf.length(), 512 * 1024));
      await raf.close();
      final tags = await readExifFromBytes(head);
      final o = tags['Image Orientation']?.values.toList().first;
      if (o is int) return o;
      final printable = tags['Image Orientation']?.printable ?? '';
      if (printable.contains('Rotated 90 CW')) return 6;
      if (printable.contains('Rotated 180')) return 3;
      if (printable.contains('Rotated 90 CCW')) return 8;
      if (printable.contains('Mirrored horizontal')) return 2;
      return 1;
    } catch (_) {
      return 1;
    }
  }

  /// 完整 EXIF（状态悬浮窗用）
  Future<Map<String, String>> readExif(String path) async {
    try {
      final file = File(path);
      final raf = await file.open();
      final head = await raf.read(math.min(await raf.length(), 1024 * 1024));
      await raf.close();
      final tags = await readExifFromBytes(head);
      return {
        for (final e in tags.entries)
          if (!e.key.contains('Thumbnail') && e.value.printable.length < 120)
            e.key: e.value.printable,
      };
    } catch (e) {
      debugPrint('[lime image] EXIF 读取失败: $e');
      return {};
    }
  }
}
