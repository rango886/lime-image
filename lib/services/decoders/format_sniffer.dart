import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

/// 识别出的容器格式。注意这里是「容器/编码」而不是「扩展名」，
/// 因为用户改错后缀（.jpg 实际是 HEIC）在手机照片里极其常见。
enum ImageFormat {
  png('PNG', skiaNative: true, animated: true),
  jpeg('JPEG', skiaNative: true),
  gif('GIF', skiaNative: true, animated: true),
  webp('WebP', skiaNative: true, animated: true),
  bmp('BMP', skiaNative: true),
  ico('ICO', skiaNative: true),

  tiff('TIFF'),
  raw('RAW'),
  psd('PSD'),
  jxl('JPEG XL'),
  heif('HEIF/HEIC'),
  avif('AVIF', animated: true),
  dds('DDS'),
  tga('TGA'),
  exr('OpenEXR'),
  hdr('Radiance HDR'),
  jp2('JPEG 2000'),
  pcx('PCX'),
  qoi('QOI'),
  sgi('SGI'),
  pnm('PNM'),
  svg('SVG'),

  unknown('未知');

  const ImageFormat(
    this.label, {
    this.skiaNative = false,
    this.animated = false,
  });

  final String label;

  /// Flutter/Skia 内置就能解，走现有路径，不需要任何外部解码器
  final bool skiaNative;

  /// 可能是多帧
  final bool animated;
}

class SniffResult {
  const SniffResult(this.format, {this.brand, this.detail});
  final ImageFormat format;

  /// ISOBMFF 的 ftyp brand（heic / avif / crx ...）
  final String? brand;

  /// 附加说明，展示在信息面板 / 日志里
  final String? detail;

  @override
  String toString() =>
      '${format.label}${brand == null ? '' : '($brand)'}${detail == null ? '' : ' $detail'}';
}

/// TIFF 派生的 RAW 扩展名。这些文件魔术字节就是 TIFF，
/// 只能靠扩展名区分「真 TIFF」和「相机 RAW」。
const kRawExtensions = <String>{
  '.cr2',
  '.cr3',
  '.crw',
  '.nef',
  '.nrw',
  '.arw',
  '.sr2',
  '.srf',
  '.srw',
  '.dng',
  '.raf',
  '.orf',
  '.ori',
  '.rw2',
  '.rwl',
  '.pef',
  '.ptx',
  '.x3f',
  '.mrw',
  '.kdc',
  '.dcr',
  '.erf',
  '.mef',
  '.mos',
  '.iiq',
  '.3fr',
  '.ari',
  '.bay',
  '.cap',
  '.dcs',
  '.drf',
  '.eip',
  '.fff',
  '.k25',
  '.pxn',
  '.raw',
};

/// 每种格式常见的扩展名。给「运行时可解码扩展名集合」用（roadmap 第 3 项），
/// 也给设置页展示用。RAW 单独取 [kRawExtensions]。
const kFormatExtensions = <ImageFormat, Set<String>>{
  ImageFormat.png: {'.png', '.apng'},
  ImageFormat.jpeg: {'.jpg', '.jpeg', '.jpe', '.jfif'},
  ImageFormat.gif: {'.gif'},
  ImageFormat.webp: {'.webp'},
  ImageFormat.bmp: {'.bmp', '.dib', '.wbmp'},
  ImageFormat.ico: {'.ico', '.cur'},
  ImageFormat.tiff: {'.tif', '.tiff'},
  ImageFormat.psd: {'.psd', '.psb'},
  ImageFormat.jxl: {'.jxl'},
  ImageFormat.heif: {'.heic', '.heif', '.hif'},
  ImageFormat.avif: {'.avif'},
  ImageFormat.dds: {'.dds'},
  ImageFormat.tga: {'.tga', '.icb', '.vda', '.vst'},
  ImageFormat.exr: {'.exr'},
  ImageFormat.hdr: {'.hdr'},
  ImageFormat.jp2: {'.jp2', '.j2k', '.jpf', '.jpx'},
  ImageFormat.pcx: {'.pcx'},
  ImageFormat.qoi: {'.qoi'},
  ImageFormat.sgi: {'.sgi', '.rgb'},
  ImageFormat.pnm: {'.pnm', '.ppm', '.pgm', '.pbm', '.pam'},
  ImageFormat.svg: {'.svg', '.svgz'},
  ImageFormat.raw: kRawExtensions,
};

/// [fmt] 对应的扩展名集合（未知格式返回空集）
Set<String> extensionsOf(ImageFormat fmt) =>
    kFormatExtensions[fmt] ?? const <String>{};

class FormatSniffer {
  /// 读文件头做嗅探。[ext] 传扩展名（含点，小写）仅作为辅助判据。
  static Future<SniffResult> sniffFile(String path) async {
    RandomAccessFile? f;
    try {
      f = await File(path).open();
      final len = await f.length();
      final head = await f.read(math.min(len, 512));
      return sniff(head, ext: _extOf(path));
    } catch (_) {
      return SniffResult(_fromExtension(_extOf(path)));
    } finally {
      await f?.close();
    }
  }

  static String _extOf(String path) {
    final i = path.lastIndexOf('.');
    if (i < 0) return '';
    return path.substring(i).toLowerCase();
  }

  static bool _has(Uint8List b, int off, List<int> sig) {
    if (b.length < off + sig.length) return false;
    for (var i = 0; i < sig.length; i++) {
      if (b[off + i] != sig[i]) return false;
    }
    return true;
  }

  static String _ascii(Uint8List b, int off, int len) {
    if (b.length < off + len) return '';
    return String.fromCharCodes(b.sublist(off, off + len));
  }

  static SniffResult sniff(Uint8List b, {String ext = ''}) {
    if (b.length < 4) return SniffResult(_fromExtension(ext));

    // ---- 无歧义的固定签名 ----
    if (_has(b, 0, [0x89, 0x50, 0x4E, 0x47])) {
      return const SniffResult(ImageFormat.png);
    }
    if (_has(b, 0, [0xFF, 0xD8, 0xFF])) {
      return const SniffResult(ImageFormat.jpeg);
    }
    if (_has(b, 0, [0x47, 0x49, 0x46, 0x38])) {
      return const SniffResult(ImageFormat.gif);
    }
    if (_has(b, 0, [0x42, 0x4D])) return const SniffResult(ImageFormat.bmp);
    if (_has(b, 0, [0x38, 0x42, 0x50, 0x53])) {
      return const SniffResult(ImageFormat.psd);
    }
    if (_has(b, 0, [0x44, 0x44, 0x53, 0x20])) {
      return const SniffResult(ImageFormat.dds);
    }
    if (_has(b, 0, [0x76, 0x2F, 0x31, 0x01])) {
      return const SniffResult(ImageFormat.exr);
    }
    if (_has(b, 0, [0x71, 0x6F, 0x69, 0x66])) {
      return const SniffResult(ImageFormat.qoi);
    }
    if (_has(b, 0, [0x01, 0xDA])) return const SniffResult(ImageFormat.sgi);
    if (_has(b, 0, [0x0A]) && b.length > 2 && b[1] <= 0x05) {
      // PCX: manufacturer=0x0A, version<=5
      if (ext == '.pcx') return const SniffResult(ImageFormat.pcx);
    }
    if (_ascii(b, 0, 10) == '#?RADIANCE' || _ascii(b, 0, 6) == '#?RGBE') {
      return const SniffResult(ImageFormat.hdr);
    }
    if (_has(b, 0, [0x00, 0x00, 0x01, 0x00])) {
      return const SniffResult(ImageFormat.ico);
    }
    if (_has(b, 0, [0x00, 0x00, 0x02, 0x00])) {
      return const SniffResult(ImageFormat.ico, detail: 'CUR');
    }
    // PNM: P1..P7
    if (b[0] == 0x50 && b[1] >= 0x31 && b[1] <= 0x37) {
      return const SniffResult(ImageFormat.pnm);
    }
    // JPEG 2000: 裸码流 FF4FFF51 / JP2 容器
    if (_has(b, 0, [0xFF, 0x4F, 0xFF, 0x51]) ||
        _has(b, 4, [0x6A, 0x50, 0x20, 0x20])) {
      return const SniffResult(ImageFormat.jp2);
    }

    // ---- JXL：两种签名都要认，这是踩过的坑 ----
    // 裸码流
    if (_has(b, 0, [0xFF, 0x0A])) {
      return const SniffResult(ImageFormat.jxl, detail: 'codestream');
    }
    // ISOBMFF 封装
    if (_has(b, 0, [
      0x00,
      0x00,
      0x00,
      0x0C,
      0x4A,
      0x58,
      0x4C,
      0x20,
      0x0D,
      0x0A,
      0x87,
      0x0A,
    ])) {
      return const SniffResult(ImageFormat.jxl, detail: 'ISOBMFF');
    }

    // ---- RIFF: WebP ----
    if (_ascii(b, 0, 4) == 'RIFF' && _ascii(b, 8, 4) == 'WEBP') {
      return const SniffResult(ImageFormat.webp);
    }

    // ---- ISOBMFF: HEIF / AVIF / CR3 ----
    if (_ascii(b, 4, 4) == 'ftyp') {
      final brand = _ascii(b, 8, 4);
      switch (brand) {
        case 'avif':
        case 'avis':
          return SniffResult(ImageFormat.avif, brand: brand);
        case 'heic':
        case 'heix':
        case 'heim':
        case 'heis':
        case 'hevc':
        case 'hevx':
        case 'mif1':
        case 'msf1':
          return SniffResult(ImageFormat.heif, brand: brand);
        case 'crx ':
          return SniffResult(ImageFormat.raw, brand: brand, detail: 'CR3');
        case 'jxl ':
          return SniffResult(ImageFormat.jxl, brand: brand);
      }
      // 未知 brand：如果扩展名是 heic/avif 就信扩展名
      if (ext == '.heic' || ext == '.heif') {
        return SniffResult(ImageFormat.heif, brand: brand);
      }
      if (ext == '.avif') return SniffResult(ImageFormat.avif, brand: brand);
    }

    // ---- TIFF 家族（含大部分 RAW）----
    final isTiffLE = _has(b, 0, [0x49, 0x49, 0x2A, 0x00]);
    final isTiffBE = _has(b, 0, [0x4D, 0x4D, 0x00, 0x2A]);
    final isBigTiff =
        _has(b, 0, [0x49, 0x49, 0x2B, 0x00]) ||
        _has(b, 0, [0x4D, 0x4D, 0x00, 0x2B]);
    if (isTiffLE || isTiffBE || isBigTiff) {
      if (kRawExtensions.contains(ext)) {
        return SniffResult(ImageFormat.raw, detail: 'TIFF 派生');
      }
      return const SniffResult(ImageFormat.tiff);
    }

    // ---- 各家 RAW 私有签名 ----
    if (_ascii(b, 0, 8) == 'FUJIFILM') {
      return const SniffResult(ImageFormat.raw, detail: 'RAF');
    }
    if (_has(b, 0, [0x00, 0x4D, 0x52, 0x4D])) {
      return const SniffResult(ImageFormat.raw, detail: 'MRW');
    }
    if (_ascii(b, 0, 4) == 'FOVb') {
      return const SniffResult(ImageFormat.raw, detail: 'X3F');
    }
    if (_has(b, 0, [0x49, 0x49, 0x52, 0x4F]) ||
        _has(b, 0, [0x49, 0x49, 0x52, 0x53]) ||
        _has(b, 0, [0x4D, 0x4D, 0x4F, 0x52]) ||
        _has(b, 0, [0x4D, 0x4D, 0x53, 0x52])) {
      return const SniffResult(ImageFormat.raw, detail: 'ORF');
    }
    if (_has(b, 0, [0x49, 0x49, 0x55, 0x00])) {
      return const SniffResult(ImageFormat.raw, detail: 'RW2');
    }

    // ---- SVG：文本格式，前 512 字节里找标签 ----
    final text = String.fromCharCodes(
      b.take(math.min(b.length, 512)).where((c) => c < 0x80),
    ).toLowerCase();
    if (text.contains('<svg') || (text.contains('<?xml') && ext == '.svg')) {
      return const SniffResult(ImageFormat.svg);
    }

    // ---- TGA 没有头部魔术字节，只能靠扩展名 + 尾部签名 ----
    if (ext == '.tga' || ext == '.icb' || ext == '.vda' || ext == '.vst') {
      return const SniffResult(ImageFormat.tga, detail: '按扩展名判定');
    }

    return SniffResult(_fromExtension(ext));
  }

  static ImageFormat _fromExtension(String ext) {
    switch (ext) {
      case '.png':
      case '.apng':
        return ImageFormat.png;
      case '.jpg':
      case '.jpeg':
      case '.jpe':
      case '.jfif':
        return ImageFormat.jpeg;
      case '.gif':
        return ImageFormat.gif;
      case '.webp':
        return ImageFormat.webp;
      case '.bmp':
      case '.dib':
        return ImageFormat.bmp;
      case '.ico':
      case '.cur':
        return ImageFormat.ico;
      case '.tif':
      case '.tiff':
        return ImageFormat.tiff;
      case '.psd':
      case '.psb':
        return ImageFormat.psd;
      case '.jxl':
        return ImageFormat.jxl;
      case '.heic':
      case '.heif':
      case '.hif':
        return ImageFormat.heif;
      case '.avif':
        return ImageFormat.avif;
      case '.dds':
        return ImageFormat.dds;
      case '.tga':
        return ImageFormat.tga;
      case '.exr':
        return ImageFormat.exr;
      case '.hdr':
        return ImageFormat.hdr;
      case '.jp2':
      case '.j2k':
      case '.jpf':
      case '.jpx':
        return ImageFormat.jp2;
      case '.pcx':
        return ImageFormat.pcx;
      case '.qoi':
        return ImageFormat.qoi;
      case '.sgi':
      case '.rgb':
        return ImageFormat.sgi;
      case '.pnm':
      case '.ppm':
      case '.pgm':
      case '.pbm':
      case '.pam':
        return ImageFormat.pnm;
      case '.svg':
      case '.svgz':
        return ImageFormat.svg;
      default:
        if (kRawExtensions.contains(ext)) return ImageFormat.raw;
        return ImageFormat.unknown;
    }
  }
}
