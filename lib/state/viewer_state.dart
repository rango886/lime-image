import '../l10n/strings.dart';

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:window_manager/window_manager.dart';

import '../core/platform_ops.dart';
import '../core/strip_transform.dart';
import '../core/utils.dart';
import '../models/app_action.dart';
import '../models/enums.dart';
import '../models/settings.dart';
import '../services/folder_service.dart';
import '../services/image_service.dart';
import '../services/metadata_service.dart';
import '../models/image_metadata.dart';
import '../services/settings_service.dart';

/// UI 层需要提供的交互（对话框之类）
abstract class ViewerUiDelegate {
  Future<String?> pickImageFile();
  Future<String?> pickDirectory();
  Future<bool> confirmDelete(String name);
  Future<String?> promptRename(String currentName);
  void openSettings();
  void showHelp();
}

/// 图片变换状态（缩放 / 位移 / 旋转 / 翻转）
class ImageTransform {
  double scale = 1;
  Offset offset = Offset.zero;
  int quarter = 0; // 用户旋转，0..3
  bool flipH = false;
  bool flipV = false;

  void reset() {
    quarter = 0;
    flipH = false;
    flipV = false;
  }
}

class ViewerState extends ChangeNotifier {
  ViewerState({
    required this.settingsService,
    required this.folder,
    required this.images,
    required this.marks,
  }) {
    mode = settings.defaultViewMode;
    folder.addListener(_onFolderChanged);
  }

  final SettingsService settingsService;
  final FolderService folder;
  final ImageService images;
  final MarksService marks;

  Settings get settings => settingsService.settings;
  ViewerUiDelegate? ui;

  // —— 视图状态 ——
  ViewMode mode = ViewMode.autoFit;
  final ImageTransform tr = ImageTransform();
  Size viewport = Size.zero;
  double devicePixelRatio = 1;

  DecodedImage? image; // 当前图
  DecodedImage? secondImage; // 双页模式的第二张
  Object? error;
  bool loading = false;
  int _generation = 0;

  // 锁定缩放（模式 2 / 5）
  // 位置不存绝对像素偏移，而存「落在视口中心的那个内容点」的归一化坐标，
  // 这样换图（同分辨率必然一致）、改窗口大小、进出全屏都能还原同一处画面。
  double? _lockedScale;
  Offset? _lockedAnchor;

  // 动图
  int frameIndex = 0;
  bool animPlaying = true;
  Timer? _animTimer;

  // 界面开关
  bool showExif = false;
  bool showGrid = false;
  bool showFilmstrip = false;
  bool showStatusPanel = false;
  bool closing = false;
  bool isFullscreen = false;
  bool alwaysOnTop = false;
  bool markedOnly = false;
  bool interacting = false; // 交互中（降低插值质量）
  Timer? _interactTimer;
  Timer? _qualityTimer;

  // 幻灯片
  Timer? _slideshowTimer;
  bool get slideshowActive => _slideshowTimer != null;

  // HUD
  String? hudMessage;
  Timer? _hudTimer;

  // 滚动模式
  final StripTransform stripTransform = StripTransform();
  double get stripZoom => stripTransform.scale;
  set stripZoom(double value) => stripTransform.scale = value;
  void Function(Offset delta)? stripWheelPan;

  void panStripBy(Offset delta) {
    stripTransform.offset += delta;
    markInteracting();
    _bump();
  }

  int comicJumpTick = 0;
  int stripFitTick = 0;

  void resetStripView() {
    stripWheelPan?.call(Offset.zero);
    stripTransform.reset();
    stripFitTick++;
    _bump();
    notifyListeners();
  }

  // 过渡动画用：每次换图 +1
  int transitionKey = 0;

  /// 只影响绘制的变换变化（平移/缩放）走这个通道，避免整棵树重建
  final ValueNotifier<int> transformTick = ValueNotifier<int>(0);
  void _bump() => transformTick.value++;

  ImageMetadata? exifData;
  final metadata = MetadataService();
  bool _metadataDisposed = false;

  // ---------------------------------------------------------------------------
  // 生命周期
  // ---------------------------------------------------------------------------
  Future<void> initialize(List<String> args) async {
    showFilmstrip = settings.showFilmstrip;
    showStatusPanel = settings.showStatusPanel;
    alwaysOnTop = settings.alwaysOnTop;
    _primeViewport();
    final first = args.firstWhere(
      (a) =>
          !a.startsWith('-') &&
          (File(a).existsSync() || Directory(a).existsSync()),
      orElse: () => '',
    );
    if (first.isNotEmpty) {
      await open(first);
    } else if (settings.restoreLastImage && settings.lastImagePath != null) {
      if (File(settings.lastImagePath!).existsSync()) {
        await open(settings.lastImagePath!);
      }
    }
  }

  /// 首帧前先拿窗口尺寸当 viewport。
  ///
  /// 否则 [targetDecodeWidth] 会退化到 640 的兜底值，冷启动先解一张小图，
  /// 紧接着 _maybeUpgradeQuality() 又按真实尺寸重解一遍 —— 白干一次解码。
  void _primeViewport() {
    if (!viewport.isEmpty) return;
    final views = WidgetsBinding.instance.platformDispatcher.views;
    if (views.isNotEmpty) {
      final view = views.first;
      final dpr = view.devicePixelRatio;
      final size = view.physicalSize;
      if (dpr > 0) devicePixelRatio = dpr;
      if (dpr > 0 && !size.isEmpty) {
        viewport = size / dpr;
        return;
      }
    }
    // 窗口还没上报尺寸（首帧之前）：用配置里的窗口大小估一个
    final b = settings.savedBounds;
    viewport = Size(
      b?.width ?? settings.defaultWidth,
      b?.height ?? settings.defaultHeight,
    );
  }

  Future<void> open(String path) async {
    // 冷启动关键路径：先把要看的那张图塞进列表立即开解，目录扫描并行跑。
    // 原来是 await folder.open() 先把整个目录列完才开始解码，
    // 在几千张图的目录里要多等好几秒才看得到图。
    if (isImageFile(path) && File(path).existsSync()) {
      folder.seedSingle(path);
      final decoding = reload();
      await folder.open(path);
      await decoding;
      _prefetchNeighbors();
      return;
    }
    await folder.open(path);
    await reload();
  }

  void _onFolderChanged() {
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // 加载
  // ---------------------------------------------------------------------------
  int get targetDecodeWidth {
    final vw = math.max(viewport.width, 640) * devicePixelRatio;
    return (vw * 1.25).round().clamp(256, settings.maxDecodeDimension);
  }

  Future<void> reload({bool keepTransform = false}) async {
    final path = folder.currentPath;
    if (path == null) {
      image = null;
      secondImage = null;
      notifyListeners();
      return;
    }
    final gen = ++_generation;
    _exifDebounce?.cancel();
    metadata.cancel();
    exifData = null;
    _exifPath = null;
    loading = true;
    error = null;
    notifyListeners();

    try {
      final img = await images.load(path, targetWidth: targetDecodeWidth);
      if (gen != _generation) return;
      image = img;
      images.pin(path);
      error = null;
      exifData = null;
      _exifPath = null;
      transitionKey++;

      // 双页模式的第二张
      secondImage = null;
      if (mode == ViewMode.doublePage) {
        final second = _secondPagePath();
        if (second != null) {
          try {
            secondImage = await images.load(
              second,
              targetWidth: targetDecodeWidth,
            );
          } catch (_) {}
        }
      }

      _setupAnimation();
      if (!keepTransform) applyFitForMode();
      if (settings.rememberLastFolder) {
        settingsService.update((s) => s.lastImagePath = path, notify: false);
      }
      if (showExif) _loadExif();
    } catch (e) {
      if (gen != _generation) return;
      error = e;
      image = null;
    } finally {
      if (gen == _generation) {
        loading = false;
        notifyListeners();
        _prefetchNeighbors();
      }
    }
  }

  /// 万一当前图被缓存回收了（画面空白），重新解码一次
  bool _recovering = false;
  void ensureImageAlive() {
    final img = image;
    if (img == null || !img.disposed || loading || _recovering) return;
    _recovering = true;
    final path = folder.currentPath;
    if (path != null) images.evict(path);
    reload(keepTransform: true).whenComplete(() => _recovering = false);
  }

  String? _secondPagePath() {
    if (settings.doublePageFirstAlone && folder.index == 0) return null;
    final i = folder.index + 1;
    if (i < 0 || i >= folder.entries.length) return null;
    return folder.entries[i].path;
  }

  void _prefetchNeighbors() {
    if (settings.prefetchCount <= 0) return;
    final list = folder.neighbors(settings.prefetchCount);
    images.prefetch(list, targetDecodeWidth);
  }

  /// 状态窗里展开 / 收起 EXIF（默认折叠，只在展开时才去读）
  void toggleExif() {
    showExif = !showExif;
    if (showExif) {
      _loadExif();
    } else {
      _exifDebounce?.cancel();
      metadata.cancel();
    }
    notifyListeners();
  }

  Future<void> _loadExif() async {
    final path = folder.currentPath;
    _exifDebounce?.cancel();
    metadata.cancel();
    if (path == null || !showExif || !showStatusPanel) return;
    if (_exifPath != path) exifData = null;
    // Only after navigation settles; never await this in the image-open path.
    final gen = _generation;
    _exifDebounce = Timer(const Duration(milliseconds: 250), () async {
      if (_metadataDisposed ||
          !showStatusPanel ||
          !showExif ||
          gen != _generation ||
          folder.currentPath != path) {
        return;
      }
      final data = await metadata.load(path);
      if (data == null ||
          !showStatusPanel ||
          _metadataDisposed ||
          !showExif ||
          gen != _generation ||
          folder.currentPath != path) {
        return;
      }
      _exifPath = path;
      exifData = data;
      notifyListeners();
    });
  }

  String? _exifPath;
  Timer? _exifDebounce;

  // ---------------------------------------------------------------------------
  // 变换 / 适配
  // ---------------------------------------------------------------------------
  /// EXIF 方向 -> (旋转 90° 次数, 水平翻转)
  static (int, bool) exifTransform(int o) {
    switch (o) {
      case 2:
        return (0, true);
      case 3:
        return (2, false);
      case 4:
        return (2, true);
      case 5:
        return (1, true);
      case 6:
        return (1, false);
      case 7:
        return (3, true);
      case 8:
        return (3, false);
      default:
        return (0, false);
    }
  }

  int get totalQuarter {
    final img = image;
    final e = img == null ? 0 : exifTransform(img.orientation).$1;
    return (e + tr.quarter) % 4;
  }

  bool get totalFlipH {
    final img = image;
    final e = img != null && exifTransform(img.orientation).$2;
    return e != tr.flipH;
  }

  bool get totalFlipV => tr.flipV;

  /// 当前内容尺寸（自然像素，已考虑旋转）
  Size get contentSize {
    final img = image;
    if (img == null) return Size.zero;
    var w = img.naturalWidth.toDouble();
    var h = img.naturalHeight.toDouble();
    if (mode == ViewMode.doublePage && secondImage != null) {
      final s = secondImage!;
      // 一大一小的两页先缩到同一高度，再算并排后的整体尺寸
      final l = doublePageLayout(
        w,
        h,
        s.naturalWidth.toDouble(),
        s.naturalHeight.toDouble(),
        settings.pageGap,
      );
      w = l.width;
      h = l.height;
    }
    return totalQuarter.isOdd ? Size(h, w) : Size(w, h);
  }

  /// 当前实际显示倍率（滚动模式用 stripZoom，其余用 tr.scale）
  double get effectiveScale => mode.isScrollMode ? stripZoom : tr.scale;

  double fitScale(ViewMode m) {
    final c = contentSize;
    if (c.isEmpty || viewport.isEmpty) return 1;
    final sw = viewport.width / c.width; // 宽度填满
    final sh = viewport.height / c.height; // 高度填满
    final contain = math.min(sw, sh); // 完整显示
    double s;
    // “填满”模式（1/2/3/7/8）必须真的填满窗口，小图也要放大，
    // 不受“不放大小图”限制；锁定 / 双页模式尊重该设置。
    var fill = false;
    switch (m) {
      case ViewMode.fitWidth:
      case ViewMode.comic:
      case ViewMode.longStrip:
        s = sw;
        fill = true;
      case ViewMode.fitHeight:
        s = sh;
        fill = true;
      case ViewMode.autoFit:
        // 横图以窗口宽为基准、竖图以窗口高为基准（小图也拉大到填满）；
        // 但若基准边缩放后另一边会溢出（例如 4:3 照片放进 16:9 全屏，
        // 或任意图片放进比例相反的小窗），就退到 contain，保证整图不被裁掉。
        s = math.min(c.width >= c.height ? sw : sh, contain);
        fill = true;
      case ViewMode.doublePage:
      case ViewMode.focusLock:
      case ViewMode.centerLock:
        s = contain;
    }
    if (!fill && !settings.upscaleSmallImages && s > 1) s = 1;
    return s.clamp(settings.minZoom, settings.maxZoom);
  }

  void applyFitForMode() {
    if (image == null || viewport.isEmpty) return;
    switch (mode) {
      case ViewMode.focusLock:
        if (_lockedScale == null || _lockedAnchor == null) {
          tr.scale = fitScale(mode);
          _centerContent();
          _captureLock();
        } else {
          _applyLockedView();
        }
      case ViewMode.centerLock:
        // 中心锁定：只记缩放率，始终以图片中心对准视口中心
        _applyLockedView(anchor: const Offset(0.5, 0.5));
        _lockedScale = tr.scale;
      case ViewMode.comic:
      case ViewMode.longStrip:
        tr.scale = fitScale(mode);
        tr.offset = Offset.zero;
      default:
        tr.scale = fitScale(mode);
        _centerContent();
    }
    clampOffset();
    _bump();
    notifyListeners();
  }

  void _centerContent() {
    final c = contentSize * tr.scale;
    tr.offset = Offset(
      (viewport.width - c.width) / 2,
      (viewport.height - c.height) / 2,
    );
    // 溢出的那一边从起始处开始看（宽度优先从顶部，高度优先从左边／日漫从右边）
    if (mode == ViewMode.fitWidth && c.height > viewport.height) {
      tr.offset = Offset(tr.offset.dx, 0);
    }
    if (mode == ViewMode.fitHeight && c.width > viewport.width) {
      final dx = settings.readingDirection == ReadingDirection.rtl
          ? viewport.width - c.width
          : 0.0;
      tr.offset = Offset(dx, tr.offset.dy);
    }
  }

  /// 记下当前画面：缩放率 + 视口中心对应的内容点（归一化）
  void _captureLock() {
    final c = contentSize;
    _lockedScale = tr.scale;
    if (c.isEmpty || viewport.isEmpty || tr.scale <= 0) return;
    final p = (viewport.center(Offset.zero) - tr.offset) / tr.scale;
    _lockedAnchor = Offset(p.dx / c.width, p.dy / c.height);
  }

  /// 还原锁定的画面。anchor 为空时用记下的锚点，默认图片中心。
  void _applyLockedView({Offset? anchor}) {
    final c = contentSize;
    tr.scale = (_lockedScale ?? fitScale(mode)).clamp(
      settings.minZoom,
      settings.maxZoom,
    );
    if (c.isEmpty || viewport.isEmpty) return;
    final a = anchor ?? _lockedAnchor ?? const Offset(0.5, 0.5);
    tr.offset =
        viewport.center(Offset.zero) -
        Offset(a.dx * c.width, a.dy * c.height) * tr.scale;
  }

  void clampOffset() {
    final c = contentSize * tr.scale;
    double dx = tr.offset.dx, dy = tr.offset.dy;
    if (c.width <= viewport.width) {
      if (settings.centerSmallImages) dx = (viewport.width - c.width) / 2;
    } else {
      dx = dx.clamp(viewport.width - c.width, 0);
    }
    if (c.height <= viewport.height) {
      if (settings.centerSmallImages) dy = (viewport.height - c.height) / 2;
    } else {
      dy = dy.clamp(viewport.height - c.height, 0);
    }
    tr.offset = Offset(dx, dy);
  }

  void zoomAt(Offset focal, double factor, {bool notify = true}) {
    final ns = (tr.scale * factor).clamp(settings.minZoom, settings.maxZoom);
    if (ns == tr.scale) return;
    tr.offset = focal - (focal - tr.offset) * (ns / tr.scale);
    tr.scale = ns;
    clampOffset();
    _rememberLock();
    markInteracting();
    if (notify) _bump();
  }

  void zoomBy(double factor) => zoomAt(viewport.center(Offset.zero), factor);

  void panBy(Offset delta, {bool notify = true}) {
    tr.offset += delta;
    clampOffset();
    _rememberLock();
    if (notify) _bump();
  }

  void setZoom(double scale, {Offset? focal}) {
    final f = focal ?? viewport.center(Offset.zero);
    zoomAt(f, scale / tr.scale);
  }

  void _rememberLock() {
    if (mode == ViewMode.focusLock) {
      _captureLock();
    } else if (mode == ViewMode.centerLock) {
      _lockedScale = tr.scale;
    }
  }

  /// 滚动模式（漫画 / 长图）的缩放。
  /// [focal] 是相对滚动视口左上角的坐标（默认视口中心），
  /// 缩放后会把该点下的内容拉回原位，画面不会乱跑。
  void setStripZoom(double z, {Offset? focal}) {
    stripWheelPan?.call(Offset.zero); // Cancel pending wheel motion.
    if (!stripTransform.zoomAt(z, focal ?? viewport.center(Offset.zero))) {
      return;
    }
    markInteracting();
    showToast(lt("宽度 {0}%", [(stripZoom * 100).round()]));
    _bump();
    notifyListeners();
  }

  /// 漫画模式滚到新的一页：只同步“当前页”的展示信息。
  /// 不能走 reload()：重解会换 bucket、pin 会把其他可见页的缓存捣掉，画面会闪。
  void syncStripCurrent() {
    final path = folder.currentPath;
    if (path == null) return;
    final cached = images.cached(path);
    if (cached != null && !cached.disposed) {
      image = cached;
      error = null;
      _setupAnimation();
    }
    if (showExif) _loadExif();
    notifyListeners();
  }

  void markInteracting() {
    interacting = true;
    _qualityTimer?.cancel();
    _qualityTimer = Timer(
      Duration(milliseconds: settings.highQualityDelayMs),
      () {
        interacting = false;
        notifyListeners();
        _maybeUpgradeQuality();
      },
    );
  }

  /// 放大超过已解码分辨率时，后台重解码更清晰的版本
  Future<void> _maybeUpgradeQuality() async {
    if (!settings.progressiveQuality) return;
    final img = image;
    final path = folder.currentPath;
    if (img == null || path == null) return;
    final shownWidth = mode.isScrollMode
        ? viewport.width * stripZoom
        : contentSize.width * tr.scale;
    final neededPx = (shownWidth * devicePixelRatio).round();
    if (neededPx <= img.decodedWidth * 1.2) return;
    final want = math.min(neededPx, settings.maxDecodeDimension);
    // 矢量图（SVG）没有「原尺寸」上限，一直可以栅格得更清晰
    if (!img.vector && img.decodedWidth >= img.naturalWidth) return;
    final gen = _generation;
    try {
      final better = await images.load(path, targetWidth: want);
      if (gen == _generation && better.decodedWidth > img.decodedWidth) {
        image = better;
        images.pin(path);
        notifyListeners();
      }
    } catch (_) {}
  }

  /// 设置被改动（包括独立设置窗口改完写盘后热加载）时同步运行时状态
  void onSettingsChanged() {
    if (closing) return;
    // ffmpeg 路径 / isolate 池配置可能是在独立设置窗口里改的，这里跟上
    images.applySettings();
    final statusChanged = showStatusPanel != settings.showStatusPanel;
    showStatusPanel = settings.showStatusPanel;
    if (statusChanged) _loadExif();
    showFilmstrip = settings.showFilmstrip;
    if (alwaysOnTop != settings.alwaysOnTop) {
      alwaysOnTop = settings.alwaysOnTop;
      windowManager.setAlwaysOnTop(alwaysOnTop);
    }
    if (image != null) applyFitForMode();
  }

  void setViewport(Size size, double dpr) {
    final changed = size != viewport;
    viewport = size;
    devicePixelRatio = dpr;
    if (changed && image != null) {
      applyFitForMode();
    }
  }

  // ---------------------------------------------------------------------------
  // 模式切换
  // ---------------------------------------------------------------------------
  Future<void> setMode(ViewMode m, {bool toast = true}) async {
    if (mode == m) return;
    final wasDouble = mode == ViewMode.doublePage;
    // 锁定模式从当前画面开始锁定，而不是重新适配后才锁定。
    // 滚动模式里 tr.scale 没有意义，用 stripZoom 换算。
    if (m == ViewMode.focusLock || m == ViewMode.centerLock) {
      if (mode.isScrollMode) {
        tr.scale = fitScale(ViewMode.fitWidth) * stripZoom;
        _centerContent();
      }
      _captureLock();
    }
    mode = m;
    if (m.isScrollMode) stripTransform.reset();
    if (settings.rememberViewMode) {
      settingsService.update((s) => s.defaultViewMode = m, notify: false);
    }
    if (m == ViewMode.doublePage || wasDouble) {
      await reload();
    } else {
      applyFitForMode();
    }
    if (m == ViewMode.comic) {
      comicJumpTick++;
    }
    if (toast) showToast(m.label);
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // 动图
  // ---------------------------------------------------------------------------
  void _setupAnimation() {
    _animTimer?.cancel();
    _animTimer = null;
    frameIndex = 0;
    animPlaying = settings.animAutoPlay;
    if (image != null && image!.animated && animPlaying) _scheduleFrame();
  }

  void _scheduleFrame() {
    final img = image;
    if (img == null || !img.animated || !animPlaying) return;
    final d = img.frames[frameIndex % img.frameCount].duration;
    final ms = math.max(10, (d.inMilliseconds / settings.animSpeed).round());
    _animTimer = Timer(Duration(milliseconds: ms), () {
      frameIndex = (frameIndex + 1) % img.frameCount;
      _bump();
      notifyListeners();
      _scheduleFrame();
    });
  }

  void toggleAnimPlay() {
    if (image == null || !image!.animated) return;
    animPlaying = !animPlaying;
    _animTimer?.cancel();
    if (animPlaying) _scheduleFrame();
    showToast(animPlaying ? lt("播放") : lt("暂停"));
    notifyListeners();
  }

  void stepFrame(int delta) {
    final img = image;
    if (img == null || !img.animated) return;
    animPlaying = false;
    _animTimer?.cancel();
    frameIndex = (frameIndex + delta) % img.frameCount;
    if (frameIndex < 0) frameIndex += img.frameCount;
    _bump();
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // 导航
  // ---------------------------------------------------------------------------
  Future<void> navigate(int delta) async {
    if (folder.isEmpty) return;
    final step = mode == ViewMode.doublePage ? delta * 2 : delta;
    if (!folder.step(step)) return;
    // 锁定模式不是“原封不动”，而是重新应用锁定的缩放率 + 锚点，
    // 同分辨率结果完全一致，不同分辨率也不会飞到画面外。
    await reload();
    if (mode == ViewMode.comic) _scrollToCurrentInComic();
    if (mode == ViewMode.longStrip) _resetStripScroll();
  }

  Future<void> navigateSingle(int delta) async {
    if (folder.isEmpty) return;
    if (!folder.step(delta)) return;
    await reload();
    if (mode == ViewMode.comic) _scrollToCurrentInComic();
    if (mode == ViewMode.longStrip) _resetStripScroll();
  }

  Future<void> goToIndex(int i) async {
    if (!folder.goTo(i)) return;
    await reload();
    if (mode == ViewMode.comic) _scrollToCurrentInComic();
    if (mode == ViewMode.longStrip) _resetStripScroll();
  }

  void _scrollToCurrentInComic() {
    comicJumpTick++;
    notifyListeners();
  }

  void _resetStripScroll() {
    stripTransform.offset = Offset.zero;
    stripWheelPan?.call(Offset.zero);
    _bump();
  }

  // ---------------------------------------------------------------------------
  // HUD / 提示
  // ---------------------------------------------------------------------------
  void showToast(String msg) {
    if (!settings.showHud) return;
    hudMessage = msg;
    notifyListeners();
    _hudTimer?.cancel();
    _hudTimer = Timer(Duration(milliseconds: settings.hudDurationMs), () {
      hudMessage = null;
      notifyListeners();
    });
  }

  // ---------------------------------------------------------------------------
  // 幻灯片
  // ---------------------------------------------------------------------------
  void toggleSlideshow() {
    if (_slideshowTimer != null) {
      _slideshowTimer!.cancel();
      _slideshowTimer = null;
      showToast(lt("幻灯片已停止"));
    } else {
      _slideshowTimer = Timer.periodic(
        Duration(milliseconds: settings.slideshowIntervalMs),
        (_) {
          if (settings.slideshowRandom) {
            goToIndex(math.Random().nextInt(math.max(1, folder.count)));
          } else {
            if (!settings.slideshowLoop && folder.index >= folder.count - 1) {
              toggleSlideshow();
              return;
            }
            navigate(1);
          }
        },
      );
      showToast(lt("幻灯片放映中 {0}s", [settings.slideshowIntervalMs ~/ 1000]));
    }
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // 文件操作
  // ---------------------------------------------------------------------------
  Future<void> deleteCurrent() async {
    final path = folder.currentPath;
    if (path == null) return;
    if (settings.confirmDelete) {
      final ok = await ui?.confirmDelete(p.basename(path)) ?? false;
      if (!ok) return;
    }
    images.evict(path);
    var done = false;
    if (settings.deleteToTrash) done = await PlatformOps.moveToTrash(path);
    if (!done) {
      try {
        await File(path).delete();
        done = true;
      } catch (e) {
        showToast(lt("删除失败: {0}", [e]));
        return;
      }
    }
    folder.removeCurrent();
    showToast(lt("已删除 {0}", [p.basename(path)]));
    await reload();
  }

  Future<void> renameCurrent() async {
    final path = folder.currentPath;
    if (path == null) return;
    final name = await ui?.promptRename(p.basename(path));
    if (name == null || name.isEmpty) return;
    final target = p.join(p.dirname(path), name);
    try {
      await File(path).rename(target);
      images.evict(path);
      folder.replaceCurrentPath(target);
      showToast(lt("已重命名"));
      await reload();
    } catch (e) {
      showToast(lt("重命名失败: {0}", [e]));
    }
  }

  Future<void> copyMarkedTo({required bool move}) async {
    if (marks.count == 0) {
      showToast(lt("没有标记的文件"));
      return;
    }
    final dir = await ui?.pickDirectory();
    if (dir == null) return;
    var n = 0;
    for (final path in marks.all.toList()) {
      try {
        final target = p.join(dir, p.basename(path));
        if (move) {
          await File(path).rename(target);
        } else {
          await File(path).copy(target);
        }
        n++;
      } catch (_) {}
    }
    showToast(lt("{0} {1} 个文件", [move ? lt('已移动') : lt('已复制'), n]));
    if (move) await folder.refresh();
  }

  // ---------------------------------------------------------------------------
  // 窗口
  // ---------------------------------------------------------------------------
  bool _maximizedBeforeFullscreen = false;

  /// 进入/退出全屏。
  ///
  /// Windows 上 window_manager 直接对「已最大化」的窗口设全屏是无效的
  /// （窗口仍处于 SW_MAXIMIZE，SetWindowPos 的尺寸会被忽略，任务栏还盖在上面，
  /// 同时 WS_MAXIMIZEBOX 被摘掉导致之后最大化/最小化失灵），
  /// 所以这里先取消最大化再进全屏，退出时再还原。
  Future<void> setFullscreen(bool on) async {
    if (on) {
      _maximizedBeforeFullscreen = await windowManager.isMaximized();
      if (_maximizedBeforeFullscreen) {
        await windowManager.unmaximize();
        // 等一下让 Windows 真正退出 zoomed 状态，否则全屏尺寸不生效
        await Future<void>.delayed(const Duration(milliseconds: 60));
      }
      await windowManager.setFullScreen(true);
    } else {
      await windowManager.setFullScreen(false);
      await _ensureWindowControlsEnabled();
      if (_maximizedBeforeFullscreen) {
        await Future<void>.delayed(const Duration(milliseconds: 60));
        await windowManager.maximize();
      }
      _maximizedBeforeFullscreen = false;
    }
    isFullscreen = on;
    notifyListeners();
  }

  Future<void> toggleFullscreen() async =>
      setFullscreen(!(await windowManager.isFullScreen()));

  /// 系统侧全屏状态发生变化（窗口事件）时同步
  void syncFullscreen(bool on) {
    if (isFullscreen == on) return;
    isFullscreen = on;
    notifyListeners();
  }

  Future<void> _ensureWindowControlsEnabled() async {
    if (!Platform.isWindows && !Platform.isMacOS) return;
    try {
      await windowManager.setResizable(true);
      await windowManager.setMinimizable(true);
      await windowManager.setMaximizable(true);
    } catch (_) {
      // 某些平台/窗口管理器不支持这些 flag，忽略即可。
    }
  }

  /// 全屏时系统不允许最小化（window_manager 会直接忽略），先退出全屏
  Future<void> minimizeWindow() async {
    if (isFullscreen || await windowManager.isFullScreen()) {
      await setFullscreen(false);
    }
    await _ensureWindowControlsEnabled();
    await windowManager.minimize();
  }

  Future<void> toggleMaximize() async {
    // 全屏状态下最大化按钮的语义 = 退出全屏
    if (isFullscreen || await windowManager.isFullScreen()) {
      await setFullscreen(false);
      return;
    }
    await _ensureWindowControlsEnabled();
    if (await windowManager.isMaximized()) {
      await windowManager.unmaximize();
    } else {
      await windowManager.maximize();
    }
  }

  Future<void> toggleAlwaysOnTop() async {
    alwaysOnTop = !alwaysOnTop;
    await windowManager.setAlwaysOnTop(alwaysOnTop);
    settingsService.update((s) => s.alwaysOnTop = alwaysOnTop);
    showToast(alwaysOnTop ? lt("窗口置顶") : lt("取消置顶"));
  }

  Future<void> fitWindowToImage() async {
    final img = image;
    if (img == null) return;
    final display = await windowManager.getBounds();
    var w = img.displayWidth.toDouble();
    var h = img.displayHeight.toDouble();
    const maxW = 2400.0, maxH = 1500.0;
    final k = math.min(1.0, math.min(maxW / w, maxH / h));
    w *= k;
    h *= k;
    await windowManager.setBounds(
      Rect.fromLTWH(display.left, display.top, w, h + settings.titleBarHeight),
    );
    showToast(lt("窗口适应图片"));
  }

  /// 保存窗口位置尺寸
  Future<void> persistBounds() async {
    if (settings.startupPlacement != StartupPlacement.remember) return;
    try {
      if (await windowManager.isMaximized() ||
          await windowManager.isFullScreen()) {
        return;
      }
      final b = await windowManager.getBounds();
      settingsService.update((c) {
        c.savedX = b.left;
        c.savedY = b.top;
        c.savedWidth = b.width;
        c.savedHeight = b.height;
      }, notify: false);
    } catch (_) {}
  }

  /// 安全关窗：先把窗口藏起来（观感上立刻关闭），再存配置、销毁
  Future<void> requestClose() async {
    if (closing) return;
    closing = true;
    _animTimer?.cancel();
    _slideshowTimer?.cancel();
    _hudTimer?.cancel();
    _qualityTimer?.cancel();
    _interactTimer?.cancel();

    // 保险：无论下面哪一步卡住，最多 1.2s 后强制退出
    Timer(const Duration(milliseconds: 1200), () => exit(0));

    // 先采集窗口位置（藏起来之后就拿不到了），再立即隐藏
    try {
      await persistBounds();
    } catch (_) {}
    try {
      await windowManager.hide();
    } catch (_) {}
    try {
      await settingsService.saveNow();
    } catch (_) {}
    try {
      await SingleInstance.release();
    } catch (_) {}
    try {
      await windowManager.destroy();
    } catch (_) {}
    exit(0);
  }

  // ---------------------------------------------------------------------------
  // 动作分发
  // ---------------------------------------------------------------------------
  Future<void> invoke(AppAction action) async {
    switch (action) {
      case AppAction.nextImage:
        await navigate(1);
      case AppAction.prevImage:
        await navigate(-1);
      case AppAction.nextSingle:
        await navigateSingle(1);
      case AppAction.prevSingle:
        await navigateSingle(-1);
      case AppAction.firstImage:
        await goToIndex(0);
      case AppAction.lastImage:
        await goToIndex(folder.count - 1);
      case AppAction.jumpForward:
        await goToIndex(folder.index + 10);
      case AppAction.jumpBackward:
        await goToIndex(folder.index - 10);
      case AppAction.reload:
        final path = folder.currentPath;
        if (path != null) images.evict(path);
        await folder.refresh();
        await reload();

      case AppAction.zoomIn:
        if (mode.isScrollMode) {
          setStripZoom(stripZoom * settings.zoomStep);
        } else {
          zoomBy(settings.zoomStep);
          showToast('${(tr.scale * 100).round()}%');
        }
      case AppAction.zoomOut:
        if (mode.isScrollMode) {
          setStripZoom(stripZoom / settings.zoomStep);
        } else {
          zoomBy(1 / settings.zoomStep);
          showToast('${(tr.scale * 100).round()}%');
        }
      case AppAction.zoomOriginal:
        if (mode.isScrollMode) {
          resetStripView();
        } else {
          setZoom(1);
          showToast('100%');
        }
      case AppAction.zoomFit:
        if (mode.isScrollMode) {
          resetStripView();
        } else {
          applyFitForMode();
        }
        showToast(lt("适应窗口"));
      case AppAction.scrollUp:
        _scrollOrPan(Offset(0, settings.keyPanStep));
      case AppAction.scrollDown:
        _scrollOrPan(Offset(0, -settings.keyPanStep));
      case AppAction.scrollLeft:
        _scrollOrPan(Offset(settings.keyPanStep, 0));
      case AppAction.scrollRight:
        _scrollOrPan(Offset(-settings.keyPanStep, 0));
      case AppAction.pageUp:
        _scrollOrPan(Offset(0, viewport.height * 0.9));
      case AppAction.pageDown:
        _scrollOrPan(Offset(0, -viewport.height * 0.9));

      case AppAction.mode1:
        await setMode(ViewMode.autoFit);
      case AppAction.mode2:
        await setMode(ViewMode.focusLock);
      case AppAction.mode3:
        await setMode(ViewMode.fitWidth);
      case AppAction.mode4:
        await setMode(ViewMode.fitHeight);
      case AppAction.mode5:
        await setMode(ViewMode.centerLock);
      case AppAction.mode6:
        await setMode(ViewMode.doublePage);
      case AppAction.mode7:
        await setMode(ViewMode.comic);
      case AppAction.mode8:
        await setMode(ViewMode.longStrip);

      case AppAction.sortNameAsc:
        _sort(SortField.name, true);
      case AppAction.sortNameDesc:
        _sort(SortField.name, false);
      case AppAction.sortTimeAsc:
        _sort(SortField.time, true);
      case AppAction.sortTimeDesc:
        _sort(SortField.time, false);
      case AppAction.sortSizeAsc:
        _sort(SortField.size, true);
      case AppAction.sortSizeDesc:
        _sort(SortField.size, false);
      case AppAction.sortRandom:
        _sort(SortField.random, true);

      case AppAction.openFile:
        final path = await ui?.pickImageFile();
        if (path != null) await open(path);
      case AppAction.openFolder:
        final dir = await ui?.pickDirectory();
        if (dir != null) await open(dir);
      case AppAction.revealInFolder:
        final path = folder.currentPath;
        if (path != null) await PlatformOps.revealInFileManager(path);
      case AppAction.toggleMark:
        final path = folder.currentPath;
        if (path != null) {
          marks.toggle(path);
          showToast(marks.isMarked(path) ? lt("已标记") : lt("取消标记"));
          notifyListeners();
        }
      case AppAction.showMarked:
        if (folder.markedOnly) {
          folder.clearMarkFilter();
          markedOnly = false;
          showToast(lt("显示全部"));
        } else if (marks.count == 0) {
          showToast(lt("还没有标记任何文件"));
        } else {
          folder.applyMarkFilter(marks.all);
          markedOnly = true;
          showToast(lt("只看标记项（{0}）", [folder.count]));
          await reload();
        }
        notifyListeners();
      case AppAction.copyMarked:
        await copyMarkedTo(move: false);
      case AppAction.moveMarked:
        await copyMarkedTo(move: true);
      case AppAction.deleteFile:
        await deleteCurrent();
      case AppAction.renameFile:
        await renameCurrent();
      case AppAction.copyImage:
        final path = folder.currentPath;
        if (path != null) {
          final ok = await PlatformOps.copyImageToClipboard(path);
          showToast(ok ? lt("已复制图片") : lt("复制失败（缺少系统工具？）"));
        }
      case AppAction.copyPath:
        final path = folder.currentPath;
        if (path != null) {
          await PlatformOps.copyText(path);
          showToast(lt("已复制路径"));
        }
      case AppAction.pasteOpen:
        final path = await PlatformOps.clipboardImagePath();
        if (path != null) {
          await open(path);
        } else {
          showToast(lt("剪贴板里没有可打开的文件"));
        }
      case AppAction.openWithSystem:
        final path = folder.currentPath;
        if (path != null) await PlatformOps.openWithSystem(path);

      case AppAction.rotateCW:
        tr.quarter = (tr.quarter + 1) % 4;
        applyFitForMode();
        showToast(lt("旋转 {0}°", [tr.quarter * 90]));
      case AppAction.rotateCCW:
        tr.quarter = (tr.quarter + 3) % 4;
        applyFitForMode();
        showToast(lt("旋转 {0}°", [tr.quarter * 90]));
      case AppAction.flipHorizontal:
        tr.flipH = !tr.flipH;
        showToast(lt("水平翻转"));
        notifyListeners();
      case AppAction.flipVertical:
        tr.flipV = !tr.flipV;
        showToast(lt("垂直翻转"));
        notifyListeners();
      case AppAction.resetTransform:
        tr.reset();
        _lockedScale = null;
        _lockedAnchor = null;
        if (mode.isScrollMode) resetStripView();
        applyFitForMode();
        showToast(lt("已重置"));

      case AppAction.animTogglePlay:
        toggleAnimPlay();
      case AppAction.animNextFrame:
        stepFrame(1);
      case AppAction.animPrevFrame:
        stepFrame(-1);
      case AppAction.animSlower:
        settingsService.update(
          (s) => s.animSpeed = math.max(0.1, s.animSpeed - 0.25),
        );
        showToast(lt("速度 {0}x", [settings.animSpeed.toStringAsFixed(2)]));
      case AppAction.animFaster:
        settingsService.update(
          (s) => s.animSpeed = math.min(8, s.animSpeed + 0.25),
        );
        showToast(lt("速度 {0}x", [settings.animSpeed.toStringAsFixed(2)]));

      case AppAction.toggleFullscreen:
        await toggleFullscreen();
      case AppAction.closeWindow:
        if (showGrid) {
          showGrid = false;
          notifyListeners();
        } else if (isFullscreen) {
          await setFullscreen(false);
        } else {
          await requestClose();
        }
      case AppAction.minimizeWindow:
        await minimizeWindow();
      case AppAction.toggleMaximize:
        await toggleMaximize();
      case AppAction.toggleAlwaysOnTop:
        await toggleAlwaysOnTop();
      case AppAction.fitWindowToImage:
        await fitWindowToImage();

      case AppAction.toggleFilmstrip:
        showFilmstrip = !showFilmstrip;
        settingsService.update((s) => s.showFilmstrip = showFilmstrip);
      case AppAction.toggleStatusPanel:
        showStatusPanel = !showStatusPanel;
        _loadExif();
        settingsService.update((s) => s.showStatusPanel = showStatusPanel);
      case AppAction.toggleGrid:
        showGrid = !showGrid;
        notifyListeners();
      case AppAction.toggleSlideshow:
        toggleSlideshow();
      case AppAction.toggleTheme:
        final next = switch (settings.theme) {
          ThemePref.system => ThemePref.light,
          ThemePref.light => ThemePref.dark,
          ThemePref.dark => ThemePref.system,
        };
        settingsService.update((s) => s.theme = next);
        showToast(next.label);
      case AppAction.openSettings:
        ui?.openSettings();
      case AppAction.showHelp:
        ui?.showHelp();
    }
  }

  void _sort(SortField f, bool asc) {
    folder.sortBy(f, asc);
    settingsService.update((s) {
      s.sortField = f;
      s.sortAscending = asc;
    });
    showToast('${f.label}${asc ? ' ↑' : ' ↓'}');
  }

  void _scrollOrPan(Offset delta) {
    if (!mode.isScrollMode) {
      panBy(delta);
      return;
    }
    stripWheelPan?.call(Offset.zero);
    panStripBy(delta);
  }

  // ---------------------------------------------------------------------------
  // 滚动模式（漫画 / 长图）的滚轮
  // ---------------------------------------------------------------------------

  /// 漫画 / 长图模式的滚轮分派：走各模式自己的鼠标绑定，
  /// 平移交给虚拟画布，不再受 ScrollPosition 边界限制。
  void handleStripWheel(PointerScrollEvent e, {Offset? focal}) {
    final b = settings.mouseFor(mode);
    final keys = HardwareKeyboard.instance;
    var action = b.wheel;
    if (keys.isControlPressed) {
      action = b.ctrlWheel;
    } else if (keys.isShiftPressed) {
      action = b.shiftWheel;
    } else if (keys.isAltPressed) {
      action = b.altWheel;
    }
    var d = e.scrollDelta.dy;
    if (d == 0) d = e.scrollDelta.dx;
    if (b.invertWheel) d = -d;
    if (d == 0) return;
    switch (action) {
      case WheelAction.none:
        return;
      case WheelAction.switchImage:
        navigate(d > 0 ? 1 : -1);
      case WheelAction.switchSingle:
        navigateSingle(d > 0 ? 1 : -1);
      case WheelAction.zoom:
        setStripZoom(stripZoom * (d > 0 ? 1 / 1.08 : 1.08), focal: focal);
      case WheelAction.scrollVertical:
        wheelScroll(d.sign * settings.scrollStep, horizontal: false);
      case WheelAction.scrollHorizontal:
        wheelScroll(d.sign * settings.scrollStep, horizontal: true);
    }
  }

  void wheelScroll(double delta, {required bool horizontal}) {
    final movement = horizontal ? Offset(-delta, 0) : Offset(0, -delta);
    if (stripWheelPan != null) {
      stripWheelPan!(movement);
    } else {
      panStripBy(movement);
    }
  }

  // ---------------------------------------------------------------------------
  @override
  void dispose() {
    _metadataDisposed = true;
    metadata.cancel();
    folder.removeListener(_onFolderChanged);
    _animTimer?.cancel();
    _hudTimer?.cancel();
    _slideshowTimer?.cancel();
    _interactTimer?.cancel();
    _qualityTimer?.cancel();
    _exifDebounce?.cancel();
    transformTick.dispose();
    super.dispose();
  }
}

/// 让子树拿到 ViewerState
class ViewerScope extends InheritedNotifier<ViewerState> {
  const ViewerScope({
    super.key,
    required ViewerState state,
    required super.child,
  }) : super(notifier: state);

  static ViewerState of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<ViewerScope>();
    assert(scope != null, lt("ViewerScope 未找到"));
    return scope!.notifier!;
  }

  static ViewerState read(BuildContext context) {
    final scope = context.getInheritedWidgetOfExactType<ViewerScope>();
    return scope!.notifier!;
  }
}
