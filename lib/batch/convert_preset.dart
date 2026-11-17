import 'dart:convert';

import '../l10n/strings.dart';

enum RotateBy {
  none('0°'),
  cw90('90°'),
  r180('180°'),
  ccw90('-90°');

  const RotateBy(this.label);
  final String label;
}

enum RotateScope {
  all('全部'),
  landscape('横图'),
  portrait('竖图');

  const RotateScope(this._label);
  final String _label;
  String get label => lt(_label);
}

enum CropMode {
  none('不裁切'),
  ratio('按比例'),
  margin('按边距'),
  fixed('固定尺寸'),
  trim('去除纯色边');

  const CropMode(this._label);
  final String _label;
  String get label => lt(_label);
}

enum MarginUnit { px, percent }

enum ResizeMode {
  none('不缩放'),
  longEdge('长边'),
  shortEdge('短边'),
  width('宽度'),
  height('高度'),
  fit('限定框'),
  percent('百分比'),
  pixels('像素数');

  const ResizeMode(this._label);
  final String _label;
  String get label => lt(_label);
}

enum ResizeFilter {
  quality('高质量'),
  linear('线性'),
  nearest('最近邻');

  const ResizeFilter(this._label);
  final String _label;
  String get label => lt(_label);
}

enum OutputFormat {
  keep('保持原格式', ''),
  jpeg('JPEG', 'jpg'),
  png('PNG', 'png'),
  webp('WebP', 'webp'),
  avif('AVIF', 'avif'),
  tiff('TIFF', 'tif'),
  bmp('BMP', 'bmp');

  const OutputFormat(this._label, this.ext);
  final String _label;
  final String ext;
  String get label => this == keep ? lt(_label) : _label;

  bool get supportsAlpha =>
      this == png || this == webp || this == tiff || this == bmp;
  bool get lossy => this == jpeg || this == webp || this == avif;
}

enum JpegSubsampling {
  s420('4:2:0'),
  s422('4:2:2'),
  s444('4:4:4');

  const JpegSubsampling(this.label);
  final String label;
}

enum TiffCompression {
  none('无压缩'),
  lzw('LZW'),
  zip('ZIP');

  const TiffCompression(this._label);
  final String _label;
  String get label => this == none ? lt(_label) : _label;
}

enum AnimatedPolicy {
  firstFrame('取第一帧'),
  skip('跳过');

  const AnimatedPolicy(this._label);
  final String _label;
  String get label => lt(_label);
}

enum OutputPlace {
  same('原文件夹'),
  subfolder('子文件夹'),
  custom('指定文件夹');

  const OutputPlace(this._label);
  final String _label;
  String get label => lt(_label);
}

enum ConflictPolicy {
  rename('自动编号'),
  overwrite('覆盖'),
  skip('跳过');

  const ConflictPolicy(this._label);
  final String _label;
  String get label => lt(_label);
}

enum MetadataPolicy {
  keep('保留'),
  stripGps('去掉位置信息'),
  strip('全部去掉');

  const MetadataPolicy(this._label);
  final String _label;
  String get label => lt(_label);
}

enum AfterRun {
  nothing('无操作'),
  openFolder('打开输出文件夹'),
  close('关闭窗口');

  const AfterRun(this._label);
  final String _label;
  String get label => lt(_label);
}

T _enum<T extends Enum>(List<T> values, Object? name, T fallback) {
  for (final v in values) {
    if (v.name == name) return v;
  }
  return fallback;
}

/// 一组转换参数。全部是可变字段，界面直接改；存盘用 JSON。
class ConvertPreset {
  ConvertPreset();

  // —— 方向 ——
  bool autoOrient = true;
  RotateBy rotate = RotateBy.none;
  bool flipH = false;
  bool flipV = false;
  RotateScope rotateScope = RotateScope.all;

  // —— 裁切 ——
  CropMode crop = CropMode.none;
  double ratioW = 16;
  double ratioH = 9;
  bool ratioFollowOrientation = true;
  int anchor = 4;
  double marginTop = 0;
  double marginRight = 0;
  double marginBottom = 0;
  double marginLeft = 0;
  MarginUnit marginUnit = MarginUnit.px;
  int fixedW = 1920;
  int fixedH = 1080;
  int trimTolerance = 16;
  int trimPadding = 0;

  /// 裁切后宽高各自向下取整到它的倍数；0 / 1 = 不对齐。固定尺寸模式下不生效。
  int cropAlign = 0;

  // —— 尺寸 ——
  ResizeMode resize = ResizeMode.none;
  double resizeValue = 1920;
  int fitW = 1920;
  int fitH = 1080;

  /// 像素数模式的目标，单位 M，1M = 1024² 像素
  double megapixels = 1;

  /// 缩放后宽高各自向下取整到它的倍数（居中裁掉多余），0 / 1 = 不对齐
  int resizeAlign = 0;
  bool noUpscale = true;
  ResizeFilter filter = ResizeFilter.quality;

  // —— 格式 ——
  OutputFormat format = OutputFormat.jpeg;
  int jpegQuality = 88;
  JpegSubsampling jpegSubsampling = JpegSubsampling.s420;
  int webpQuality = 82;
  bool webpLossless = false;
  int webpEffort = 4;
  int avifQuality = 60;
  int avifSpeed = 6;
  TiffCompression tiffCompression = TiffCompression.lzw;
  bool limitSize = false;
  int maxKb = 500;
  int background = 0xFFFFFFFF;
  AnimatedPolicy animated = AnimatedPolicy.firstFrame;
  bool keepIfLarger = false;

  // —— 输出 ——
  OutputPlace place = OutputPlace.subfolder;
  String subfolder = 'converted';
  String customDir = '';
  bool keepStructure = true;
  ConflictPolicy conflict = ConflictPolicy.rename;
  AfterRun afterRun = AfterRun.nothing;

  // —— 文件名 ——
  String nameTemplate = '{name}';
  int seqStart = 1;
  int seqDigits = 3;
  bool jpegLongExt = false;

  // —— 元数据 ——
  MetadataPolicy metadata = MetadataPolicy.keep;
  bool keepTimestamps = true;

  ConvertPreset copy() => ConvertPreset.fromJson(toJson());

  /// 方向是否会改变像素（不算 EXIF 摆正）
  bool get hasUserTransform => rotate != RotateBy.none || flipH || flipV;

  /// 固定尺寸是用户明确填的数字，不再对齐
  bool get cropAlignActive => cropAlign > 1 && crop != CropMode.fixed;

  /// 不缩放时尺寸对齐和裁切对齐重复，不生效
  bool get resizeAlignActive => resizeAlign > 1 && resize != ResizeMode.none;

  String extFor(OutputFormat f) =>
      f == OutputFormat.jpeg ? (jpegLongExt ? 'jpeg' : 'jpg') : f.ext;

  Map<String, dynamic> toJson() => {
    'autoOrient': autoOrient,
    'rotate': rotate.name,
    'flipH': flipH,
    'flipV': flipV,
    'rotateScope': rotateScope.name,
    'crop': crop.name,
    'ratioW': ratioW,
    'ratioH': ratioH,
    'ratioFollowOrientation': ratioFollowOrientation,
    'anchor': anchor,
    'marginTop': marginTop,
    'marginRight': marginRight,
    'marginBottom': marginBottom,
    'marginLeft': marginLeft,
    'marginUnit': marginUnit.name,
    'fixedW': fixedW,
    'fixedH': fixedH,
    'trimTolerance': trimTolerance,
    'trimPadding': trimPadding,
    'cropAlign': cropAlign,
    'resize': resize.name,
    'resizeValue': resizeValue,
    'fitW': fitW,
    'fitH': fitH,
    'megapixels': megapixels,
    'resizeAlign': resizeAlign,
    'noUpscale': noUpscale,
    'filter': filter.name,
    'format': format.name,
    'jpegQuality': jpegQuality,
    'jpegSubsampling': jpegSubsampling.name,
    'webpQuality': webpQuality,
    'webpLossless': webpLossless,
    'webpEffort': webpEffort,
    'avifQuality': avifQuality,
    'avifSpeed': avifSpeed,
    'tiffCompression': tiffCompression.name,
    'limitSize': limitSize,
    'maxKb': maxKb,
    'background': background,
    'animated': animated.name,
    'keepIfLarger': keepIfLarger,
    'place': place.name,
    'subfolder': subfolder,
    'customDir': customDir,
    'keepStructure': keepStructure,
    'conflict': conflict.name,
    'afterRun': afterRun.name,
    'nameTemplate': nameTemplate,
    'seqStart': seqStart,
    'seqDigits': seqDigits,
    'jpegLongExt': jpegLongExt,
    'metadata': metadata.name,
    'keepTimestamps': keepTimestamps,
  };

  factory ConvertPreset.fromJson(Map<String, dynamic> j) {
    final d = ConvertPreset();
    bool b(String k, bool def) => j[k] is bool ? j[k] as bool : def;
    int i(String k, int def) => j[k] is num ? (j[k] as num).round() : def;
    double n(String k, double def) =>
        j[k] is num ? (j[k] as num).toDouble() : def;
    String s(String k, String def) => j[k] is String ? j[k] as String : def;

    return d
      ..autoOrient = b('autoOrient', d.autoOrient)
      ..rotate = _enum(RotateBy.values, j['rotate'], d.rotate)
      ..flipH = b('flipH', d.flipH)
      ..flipV = b('flipV', d.flipV)
      ..rotateScope = _enum(RotateScope.values, j['rotateScope'], d.rotateScope)
      ..crop = _enum(CropMode.values, j['crop'], d.crop)
      ..ratioW = n('ratioW', d.ratioW)
      ..ratioH = n('ratioH', d.ratioH)
      ..ratioFollowOrientation = b(
        'ratioFollowOrientation',
        d.ratioFollowOrientation,
      )
      ..anchor = i('anchor', d.anchor).clamp(0, 8)
      ..marginTop = n('marginTop', d.marginTop)
      ..marginRight = n('marginRight', d.marginRight)
      ..marginBottom = n('marginBottom', d.marginBottom)
      ..marginLeft = n('marginLeft', d.marginLeft)
      ..marginUnit = _enum(MarginUnit.values, j['marginUnit'], d.marginUnit)
      ..fixedW = i('fixedW', d.fixedW)
      ..fixedH = i('fixedH', d.fixedH)
      ..trimTolerance = i('trimTolerance', d.trimTolerance)
      ..trimPadding = i('trimPadding', d.trimPadding)
      ..cropAlign = i('cropAlign', d.cropAlign).clamp(0, 4096)
      ..resize = _enum(ResizeMode.values, j['resize'], d.resize)
      ..resizeValue = n('resizeValue', d.resizeValue)
      ..fitW = i('fitW', d.fitW)
      ..fitH = i('fitH', d.fitH)
      ..megapixels = n('megapixels', d.megapixels)
      ..resizeAlign = i('resizeAlign', d.resizeAlign).clamp(0, 4096)
      ..noUpscale = b('noUpscale', d.noUpscale)
      ..filter = _enum(ResizeFilter.values, j['filter'], d.filter)
      ..format = _enum(OutputFormat.values, j['format'], d.format)
      ..jpegQuality = i('jpegQuality', d.jpegQuality).clamp(1, 100)
      ..jpegSubsampling = _enum(
        JpegSubsampling.values,
        j['jpegSubsampling'],
        d.jpegSubsampling,
      )
      ..webpQuality = i('webpQuality', d.webpQuality).clamp(1, 100)
      ..webpLossless = b('webpLossless', d.webpLossless)
      ..webpEffort = i('webpEffort', d.webpEffort).clamp(0, 6)
      ..avifQuality = i('avifQuality', d.avifQuality).clamp(1, 100)
      ..avifSpeed = i('avifSpeed', d.avifSpeed).clamp(0, 10)
      ..tiffCompression = _enum(
        TiffCompression.values,
        j['tiffCompression'],
        d.tiffCompression,
      )
      ..limitSize = b('limitSize', d.limitSize)
      ..maxKb = i('maxKb', d.maxKb)
      ..background = i('background', d.background)
      ..animated = _enum(AnimatedPolicy.values, j['animated'], d.animated)
      ..keepIfLarger = b('keepIfLarger', d.keepIfLarger)
      ..place = _enum(OutputPlace.values, j['place'], d.place)
      ..subfolder = s('subfolder', d.subfolder)
      ..customDir = s('customDir', d.customDir)
      ..keepStructure = b('keepStructure', d.keepStructure)
      ..conflict = _enum(ConflictPolicy.values, j['conflict'], d.conflict)
      ..afterRun = _enum(AfterRun.values, j['afterRun'], d.afterRun)
      ..nameTemplate = s('nameTemplate', d.nameTemplate)
      ..seqStart = i('seqStart', d.seqStart)
      ..seqDigits = i('seqDigits', d.seqDigits).clamp(1, 8)
      ..jpegLongExt = b('jpegLongExt', d.jpegLongExt)
      ..metadata = _enum(MetadataPolicy.values, j['metadata'], d.metadata)
      ..keepTimestamps = b('keepTimestamps', d.keepTimestamps);
  }

  String encode() => jsonEncode(toJson());

  @override
  bool operator ==(Object other) =>
      other is ConvertPreset && other.encode() == encode();

  @override
  int get hashCode => encode().hashCode;

  /// 第一次打开时生成的几个预设
  static List<(String, ConvertPreset)> builtIns() => [
    (
      lt('网页 JPEG'),
      ConvertPreset()
        ..format = OutputFormat.jpeg
        ..jpegQuality = 85
        ..resize = ResizeMode.longEdge
        ..resizeValue = 2048
        ..metadata = MetadataPolicy.stripGps,
    ),
    (
      'WebP',
      ConvertPreset()
        ..format = OutputFormat.webp
        ..webpQuality = 82,
    ),
    ('PNG', ConvertPreset()..format = OutputFormat.png),
    (
      lt('缩略图'),
      ConvertPreset()
        ..format = OutputFormat.jpeg
        ..jpegQuality = 82
        ..resize = ResizeMode.fit
        ..fitW = 512
        ..fitH = 512
        ..subfolder = 'thumbs'
        ..metadata = MetadataPolicy.strip,
    ),
  ];
}
