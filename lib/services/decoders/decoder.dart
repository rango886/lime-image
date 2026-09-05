import 'dart:typed_data';

import 'format_sniffer.dart';

/// 原始像素排布。刻意不用 dart:ui 的 PixelFormat，
/// 这样整个 decoders/ 目录是纯 Dart，可以脱离 Flutter 用 `dart run` 单独测。
enum RawPixelFormat {
  /// B,G,R,A 顺序，alpha 已预乘（WIC 的 32bppPBGRA）
  bgra8888,

  /// R,G,B,A 顺序，alpha 已预乘（ffmpeg 的 rgba + 我们自己预乘）
  rgba8888,
}

/// 解码结果。两种形态二选一：
///  - [encoded]  非空：这是一段编码后的字节（例如 PSD 里抠出来的 JPEG 预览），
///               交给 Skia 走现有 `ImageDescriptor.encoded` 路径，白拿降采样能力。
///  - [frames]   非空：已经是目标尺寸的原始像素。
class RawImageData {
  RawImageData.encoded({
    required this.encoded,
    required this.naturalWidth,
    required this.naturalHeight,
    required this.decoderId,
    this.width = 0,
    this.height = 0,
    this.orientation = 1,
    this.previewOnly = false,
  }) : frames = const [],
       delays = const [],
       format = RawPixelFormat.bgra8888;

  RawImageData.pixels({
    required this.frames,
    required this.width,
    required this.height,
    required this.format,
    required this.naturalWidth,
    required this.naturalHeight,
    required this.decoderId,
    List<Duration>? delays,
    this.orientation = 1,
    this.previewOnly = false,
  }) : encoded = null,
       delays = delays ?? List<Duration>.filled(frames.length, Duration.zero);

  final Uint8List? encoded;
  final List<Uint8List> frames;
  final List<Duration> delays;
  final RawPixelFormat format;

  /// 像素帧的实际尺寸（已降采样后的）
  final int width;
  final int height;

  /// 文件里记录的原始尺寸，供上层判断是否还需要更高清版本
  final int naturalWidth;
  final int naturalHeight;

  /// EXIF 1..8，解码器拿不到就填 1
  final int orientation;

  /// true 表示这只是个内嵌预览图，清晰度不代表文件真实内容
  final bool previewOnly;

  final String decoderId;

  bool get isEncoded => encoded != null;
  int get frameCount => isEncoded ? 1 : frames.length;

  /// 有效宽度：像素形态用 width，编码形态用原始宽（Skia 解完才知道实际尺寸）
  int get effectiveWidth =>
      isEncoded ? (width > 0 ? width : naturalWidth) : width;
}

/// 一个解码器后端
abstract class RawDecoder {
  /// 稳定标识，用于日志、黑名单、设置页展示
  String get id;

  /// 数字越小越优先
  int get priority;

  /// 本机是否可用（例如 ffmpeg 是否装了、是否 Windows）
  Future<bool> isAvailable();

  /// 声称能处理哪些格式（乐观声明，真不真要靠实际解码验证）
  bool supports(ImageFormat fmt);

  /// [targetWidth] 是期望宽度（调用方已按 bucket / maxDecodeDimension 夹好）。
  /// 做不到就返回原尺寸，由上层再缩。
  Future<RawImageData> decode(
    String path, {
    required int targetWidth,
    int maxFrames = 1,
  });

  /// 释放常驻资源（COM 对象、缓存句柄等）
  void dispose() {}
}

class DecoderException implements Exception {
  DecoderException(this.decoderId, this.message, [this.cause]);
  final String decoderId;
  final String message;
  final Object? cause;
  @override
  String toString() =>
      'DecoderException($decoderId): $message${cause == null ? '' : ' <- $cause'}';
}

class UnsupportedFormatException implements Exception {
  UnsupportedFormatException(this.format, this.tried);
  final ImageFormat format;
  final List<String> tried;
  @override
  String toString() =>
      '没有可用解码器处理 ${format.label}（已尝试: ${tried.isEmpty ? '无' : tried.join(', ')}）';
}
