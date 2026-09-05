import 'dart:ui';

import '../l10n/strings.dart';

import 'app_action.dart';
import 'enums.dart';
import 'key_chord.dart';

/// 鼠标 / 滚轮绑定（每种查看方式可独立设置）
class MouseBindings {
  MouseBindings({
    required this.wheel,
    required this.ctrlWheel,
    required this.shiftWheel,
    required this.altWheel,
    this.panButton = DragButton.left,
    this.invertWheel = false,
  });

  WheelAction wheel;
  WheelAction ctrlWheel;
  WheelAction shiftWheel;
  WheelAction altWheel;
  DragButton panButton;
  bool invertWheel;

  MouseBindings clone() => MouseBindings(
    wheel: wheel,
    ctrlWheel: ctrlWheel,
    shiftWheel: shiftWheel,
    altWheel: altWheel,
    panButton: panButton,
    invertWheel: invertWheel,
  );

  Map<String, dynamic> toJson() => {
    'wheel': wheel.name,
    'ctrlWheel': ctrlWheel.name,
    'shiftWheel': shiftWheel.name,
    'altWheel': altWheel.name,
    'panButton': panButton.name,
    'invertWheel': invertWheel,
  };

  static MouseBindings fromJson(
    Map<String, dynamic> j,
    MouseBindings base,
  ) => MouseBindings(
    wheel: enumFromName(WheelAction.values, j['wheel'], base.wheel),
    ctrlWheel: enumFromName(WheelAction.values, j['ctrlWheel'], base.ctrlWheel),
    shiftWheel: enumFromName(
      WheelAction.values,
      j['shiftWheel'],
      base.shiftWheel,
    ),
    altWheel: enumFromName(WheelAction.values, j['altWheel'], base.altWheel),
    panButton: enumFromName(DragButton.values, j['panButton'], base.panButton),
    invertWheel: j['invertWheel'] as bool? ?? base.invertWheel,
  );

  static MouseBindings defaultsFor(ViewMode mode) {
    switch (mode) {
      case ViewMode.doublePage:
        return MouseBindings(
          wheel: WheelAction.switchImage,
          ctrlWheel: WheelAction.zoom,
          shiftWheel: WheelAction.switchSingle,
          altWheel: WheelAction.scrollVertical,
        );
      case ViewMode.comic:
      case ViewMode.longStrip:
        return MouseBindings(
          wheel: WheelAction.scrollVertical,
          ctrlWheel: WheelAction.zoom,
          shiftWheel: WheelAction.switchImage,
          altWheel: WheelAction.scrollHorizontal,
        );
      default:
        return MouseBindings(
          wheel: WheelAction.switchImage,
          ctrlWheel: WheelAction.zoom,
          shiftWheel: WheelAction.scrollVertical,
          altWheel: WheelAction.scrollHorizontal,
        );
    }
  }
}

/// 全部设置。可变对象，改完调用 SettingsService.save()
class Settings {
  /// null means first-run language selection has not been completed.
  AppLanguage? language;
  // —— 窗口 ——
  StartupPlacement startupPlacement = StartupPlacement.center;
  double defaultWidth = 1280;
  double defaultHeight = 820;
  double? savedX;
  double? savedY;
  double? savedWidth;
  double? savedHeight;
  bool savedMaximized = false;
  bool alwaysOnTop = false;
  bool startFullscreen = false;
  InstanceMode instanceMode = InstanceMode.reuse;

  // —— 外观 ——
  ThemePref theme = ThemePref.dark;
  int accentColor = 0xFF1E88E5;
  BackgroundStyle background = BackgroundStyle.theme;
  bool titleBarAutoHide = true;
  double titleBarHeight = 34;
  int titleBarHideDelayMs = 1500;
  bool titleBarShowOnlyName = true;
  double cornerRadius = 5;
  double uiFontScale = 1.0;
  bool showHud = true;
  int hudDurationMs = 1400;
  bool showStatusBar = false;

  /// H 键切换的状态悬浮窗。默认关掉：多数人开图就是想干净看图
  bool showStatusPanel = false;
  PanelCorner statusPanelCorner = PanelCorner.bottomLeft;
  double statusPanelOpacity = 0.82;
  bool showFilmstrip = false;
  bool contextMenuIcons = false; // 右键菜单是否显示图标
  double filmstripHeight = 96;
  bool autoHideCursorInFullscreen = true;

  // —— 查看 ——
  ViewMode defaultViewMode = ViewMode.autoFit;
  bool rememberViewMode = true;
  Interpolation interpolation = Interpolation.auto;
  double zoomStep = 1.15;
  double minZoom = 0.05;
  double maxZoom = 32;
  int zoomAnimMs = 120;
  bool panInertia = true;
  double inertiaFriction = 0.0000135;
  DoubleClickAction doubleClickAction = DoubleClickAction.toggleFullscreen;
  bool wrapAround = true;
  bool upscaleSmallImages = false;
  bool applyExifOrientation = true;
  bool centerSmallImages = true;
  double keyPanStep = 120;

  // —— 双页 / 漫画 / 长图 ——
  ReadingDirection readingDirection = ReadingDirection.ltr;
  bool doublePageFirstAlone = false;
  double pageGap = 8;
  double comicGap = 8;
  double scrollStep = 140;

  /// 键盘 / 动作触发的滚动是否带动画
  bool smoothScroll = true;

  /// 鼠标滚轮滚动（漫画 / 长图的列表滚动，以及普通模式下的滚轮平移）是否平滑
  bool smoothWheelScroll = true;

  /// 滚轮平滑滚动的动画时长
  int smoothWheelScrollMs = 150;
  int comicPreload = 3;

  // —— 过渡动画 ——
  TransitionType transition = TransitionType.none;
  int transitionMs = 180;

  // —— 性能 ——
  int maxCacheMB = 768;
  int prefetchCount = 3;
  int maxDecodeDimension = 8192;

  /// ffmpeg 可执行文件路径。空 = 从 PATH 自动探测。
  /// 作为长尾格式（PSD/TGA/EXR/HDR/JP2/PCX/QOI/SGI）的兜底解码器。
  String? ffmpegPath;

  /// 外部解码（WIC / ffmpeg / 内嵌预览）放到常驻 worker isolate 池里跑。
  /// 关掉会退回主 isolate 解码，大图会明显卡 UI，只用于排查问题。
  bool decodeInIsolate = true;

  /// worker isolate 数量，0 = 自动（min(4, 核心数/2)）
  int decodeIsolateCount = 0;
  int highQualityDelayMs = 160;
  int animMaxCachedFrames = 400;
  double thumbSize = 140;
  bool progressiveQuality = true;

  // —— 文件 ——
  SortField sortField = SortField.name;
  bool sortAscending = true;
  bool naturalSort = true;
  bool includeHidden = false;

  /// 只列出本机真的能解码的文件（默认关：少列文件会让浏览断档）
  bool hideUndecodableFiles = false;
  bool deleteToTrash = true;
  bool confirmDelete = true;
  bool watchFolder = true;
  bool rememberLastFolder = true;
  bool restoreLastImage = false;
  String? lastImagePath;
  int slideshowIntervalMs = 3000;
  bool slideshowRandom = false;
  bool slideshowLoop = true;
  bool openArchives = true;

  // —— 动图 ——
  bool animAutoPlay = true;
  double animSpeed = 1.0;

  // —— 快捷键 ——
  /// 动作名 -> 组合键文本
  Map<String, List<String>> shortcuts = {};

  /// 查看方式名 -> (动作名 -> 组合键文本)，仅存覆盖项
  Map<String, Map<String, List<String>>> modeShortcuts = {};

  /// 查看方式名 -> 鼠标绑定
  Map<String, MouseBindings> mouse = {
    for (final m in ViewMode.values) m.name: MouseBindings.defaultsFor(m),
  };

  Rect? get savedBounds =>
      (savedX != null &&
          savedY != null &&
          savedWidth != null &&
          savedHeight != null)
      ? Rect.fromLTWH(savedX!, savedY!, savedWidth!, savedHeight!)
      : null;

  MouseBindings mouseFor(ViewMode mode) =>
      mouse[mode.name] ??= MouseBindings.defaultsFor(mode);

  // —— 快捷键解析 ——
  Map<ViewMode, Map<KeyChord, AppAction>> _keymapCache = {};

  void invalidateKeymap() => _keymapCache = {};

  Map<KeyChord, AppAction> keymapFor(ViewMode mode) {
    return _keymapCache[mode] ??= _buildKeymap(mode);
  }

  Map<KeyChord, AppAction> _buildKeymap(ViewMode mode) {
    final map = <KeyChord, AppAction>{};
    for (final action in AppAction.values) {
      for (final chord in chordsFor(action, mode)) {
        map[chord] = action;
      }
    }
    return map;
  }

  /// 某动作在某模式下生效的按键（模式覆盖优先）
  List<KeyChord> chordsFor(AppAction action, ViewMode? mode) {
    List<String>? raw;
    if (mode != null) raw = modeShortcuts[mode.name]?[action.name];
    raw ??= shortcuts[action.name];
    if (raw == null) return action.defaults;
    return raw.map(KeyChord.parse).whereType<KeyChord>().toList();
  }

  String chordLabel(AppAction action, [ViewMode? mode]) {
    final list = chordsFor(action, mode);
    return list.isEmpty ? '' : list.map((c) => c.label).join(' / ');
  }

  void setChords(AppAction action, List<KeyChord> chords, {ViewMode? mode}) {
    final encoded = chords.map((c) => c.encode()).toList();
    if (mode == null) {
      shortcuts[action.name] = encoded;
    } else {
      (modeShortcuts[mode.name] ??= {})[action.name] = encoded;
    }
    invalidateKeymap();
  }

  void clearModeOverride(AppAction action, ViewMode mode) {
    modeShortcuts[mode.name]?.remove(action.name);
    invalidateKeymap();
  }

  void resetShortcuts() {
    shortcuts.clear();
    modeShortcuts.clear();
    invalidateKeymap();
  }

  /// 冲突检测：返回同一模式下与给定组合键冲突的动作
  AppAction? conflictOf(KeyChord chord, AppAction self, ViewMode? mode) {
    for (final a in AppAction.values) {
      if (a == self) continue;
      if (chordsFor(a, mode).contains(chord)) return a;
    }
    return null;
  }

  Map<String, dynamic> toJson() => {
    'language': language?.code,
    'startupPlacement': startupPlacement.name,
    'defaultWidth': defaultWidth,
    'defaultHeight': defaultHeight,
    'savedX': savedX,
    'savedY': savedY,
    'savedWidth': savedWidth,
    'savedHeight': savedHeight,
    'savedMaximized': savedMaximized,
    'alwaysOnTop': alwaysOnTop,
    'startFullscreen': startFullscreen,
    'instanceMode': instanceMode.name,
    'theme': theme.name,
    'accentColor': accentColor,
    'background': background.name,
    'titleBarAutoHide': titleBarAutoHide,
    'titleBarHeight': titleBarHeight,
    'titleBarHideDelayMs': titleBarHideDelayMs,
    'titleBarShowOnlyName': titleBarShowOnlyName,
    'cornerRadius': cornerRadius,
    'uiFontScale': uiFontScale,
    'showHud': showHud,
    'hudDurationMs': hudDurationMs,
    'showStatusBar': showStatusBar,
    'showStatusPanel': showStatusPanel,
    'statusPanelCorner': statusPanelCorner.name,
    'statusPanelOpacity': statusPanelOpacity,
    'showFilmstrip': showFilmstrip,
    'contextMenuIcons': contextMenuIcons,
    'filmstripHeight': filmstripHeight,
    'autoHideCursorInFullscreen': autoHideCursorInFullscreen,
    'defaultViewMode': defaultViewMode.name,
    'rememberViewMode': rememberViewMode,
    'interpolation': interpolation.name,
    'zoomStep': zoomStep,
    'minZoom': minZoom,
    'maxZoom': maxZoom,
    'zoomAnimMs': zoomAnimMs,
    'panInertia': panInertia,
    'inertiaFriction': inertiaFriction,
    'doubleClickAction': doubleClickAction.name,
    'wrapAround': wrapAround,
    'upscaleSmallImages': upscaleSmallImages,
    'applyExifOrientation': applyExifOrientation,
    'centerSmallImages': centerSmallImages,
    'keyPanStep': keyPanStep,
    'readingDirection': readingDirection.name,
    'doublePageFirstAlone': doublePageFirstAlone,
    'pageGap': pageGap,
    'comicGap': comicGap,
    'scrollStep': scrollStep,
    'smoothScroll': smoothScroll,
    'smoothWheelScroll': smoothWheelScroll,
    'smoothWheelScrollMs': smoothWheelScrollMs,
    'comicPreload': comicPreload,
    'transition': transition.name,
    'transitionMs': transitionMs,
    'maxCacheMB': maxCacheMB,
    'prefetchCount': prefetchCount,
    'maxDecodeDimension': maxDecodeDimension,
    'ffmpegPath': ffmpegPath,
    'decodeInIsolate': decodeInIsolate,
    'decodeIsolateCount': decodeIsolateCount,
    'highQualityDelayMs': highQualityDelayMs,
    'animMaxCachedFrames': animMaxCachedFrames,
    'thumbSize': thumbSize,
    'progressiveQuality': progressiveQuality,
    'sortField': sortField.name,
    'sortAscending': sortAscending,
    'naturalSort': naturalSort,
    'includeHidden': includeHidden,
    'hideUndecodableFiles': hideUndecodableFiles,
    'deleteToTrash': deleteToTrash,
    'confirmDelete': confirmDelete,
    'watchFolder': watchFolder,
    'rememberLastFolder': rememberLastFolder,
    'restoreLastImage': restoreLastImage,
    'lastImagePath': lastImagePath,
    'slideshowIntervalMs': slideshowIntervalMs,
    'slideshowRandom': slideshowRandom,
    'slideshowLoop': slideshowLoop,
    'openArchives': openArchives,
    'animAutoPlay': animAutoPlay,
    'animSpeed': animSpeed,
    'shortcuts': shortcuts,
    'modeShortcuts': modeShortcuts,
    'mouse': {for (final e in mouse.entries) e.key: e.value.toJson()},
  };

  static Settings fromJson(Map<String, dynamic> j) {
    final s = Settings();
    // Existing pre-localization configurations retain their Chinese interface.
    s.language = j.containsKey('language')
        ? AppLanguage.fromCode(j['language'])
        : AppLanguage.simplifiedChinese;
    double? d(String k) => (j[k] as num?)?.toDouble();
    int i(String k, int f) => (j[k] as num?)?.toInt() ?? f;
    bool b(String k, bool f) => j[k] as bool? ?? f;

    s.startupPlacement = enumFromName(
      StartupPlacement.values,
      j['startupPlacement'],
      s.startupPlacement,
    );
    s.defaultWidth = d('defaultWidth') ?? s.defaultWidth;
    s.defaultHeight = d('defaultHeight') ?? s.defaultHeight;
    s.savedX = d('savedX');
    s.savedY = d('savedY');
    s.savedWidth = d('savedWidth');
    s.savedHeight = d('savedHeight');
    s.savedMaximized = b('savedMaximized', s.savedMaximized);
    s.alwaysOnTop = b('alwaysOnTop', s.alwaysOnTop);
    s.startFullscreen = b('startFullscreen', s.startFullscreen);
    s.instanceMode = enumFromName(
      InstanceMode.values,
      j['instanceMode'],
      s.instanceMode,
    );
    s.theme = enumFromName(ThemePref.values, j['theme'], s.theme);
    s.accentColor = i('accentColor', s.accentColor);
    s.background = enumFromName(
      BackgroundStyle.values,
      j['background'],
      s.background,
    );
    s.titleBarAutoHide = b('titleBarAutoHide', s.titleBarAutoHide);
    s.titleBarHeight = d('titleBarHeight') ?? s.titleBarHeight;
    s.titleBarHideDelayMs = i('titleBarHideDelayMs', s.titleBarHideDelayMs);
    s.titleBarShowOnlyName = b('titleBarShowOnlyName', s.titleBarShowOnlyName);
    s.cornerRadius = d('cornerRadius') ?? s.cornerRadius;
    s.uiFontScale = d('uiFontScale') ?? s.uiFontScale;
    s.showHud = b('showHud', s.showHud);
    s.hudDurationMs = i('hudDurationMs', s.hudDurationMs);
    s.showStatusBar = b('showStatusBar', s.showStatusBar);
    s.showStatusPanel = b('showStatusPanel', s.showStatusPanel);
    s.statusPanelCorner = enumFromName(
      PanelCorner.values,
      j['statusPanelCorner'],
      s.statusPanelCorner,
    );
    s.statusPanelOpacity = d('statusPanelOpacity') ?? s.statusPanelOpacity;
    s.showFilmstrip = b('showFilmstrip', s.showFilmstrip);
    s.contextMenuIcons = b('contextMenuIcons', s.contextMenuIcons);
    s.filmstripHeight = d('filmstripHeight') ?? s.filmstripHeight;
    s.autoHideCursorInFullscreen = b(
      'autoHideCursorInFullscreen',
      s.autoHideCursorInFullscreen,
    );
    s.defaultViewMode = enumFromName(
      ViewMode.values,
      j['defaultViewMode'],
      s.defaultViewMode,
    );
    s.rememberViewMode = b('rememberViewMode', s.rememberViewMode);
    s.interpolation = enumFromName(
      Interpolation.values,
      j['interpolation'],
      s.interpolation,
    );
    s.zoomStep = d('zoomStep') ?? s.zoomStep;
    s.minZoom = d('minZoom') ?? s.minZoom;
    s.maxZoom = d('maxZoom') ?? s.maxZoom;
    s.zoomAnimMs = i('zoomAnimMs', s.zoomAnimMs);
    s.panInertia = b('panInertia', s.panInertia);
    s.inertiaFriction = d('inertiaFriction') ?? s.inertiaFriction;
    s.doubleClickAction = enumFromName(
      DoubleClickAction.values,
      j['doubleClickAction'],
      s.doubleClickAction,
    );
    s.wrapAround = b('wrapAround', s.wrapAround);
    s.upscaleSmallImages = b('upscaleSmallImages', s.upscaleSmallImages);
    s.applyExifOrientation = b('applyExifOrientation', s.applyExifOrientation);
    s.centerSmallImages = b('centerSmallImages', s.centerSmallImages);
    s.keyPanStep = d('keyPanStep') ?? s.keyPanStep;
    s.readingDirection = enumFromName(
      ReadingDirection.values,
      j['readingDirection'],
      s.readingDirection,
    );
    s.doublePageFirstAlone = b('doublePageFirstAlone', s.doublePageFirstAlone);
    s.pageGap = d('pageGap') ?? s.pageGap;
    s.comicGap = d('comicGap') ?? s.comicGap;
    s.scrollStep = d('scrollStep') ?? s.scrollStep;
    s.smoothScroll = b('smoothScroll', s.smoothScroll);
    s.smoothWheelScroll = b('smoothWheelScroll', s.smoothWheelScroll);
    s.smoothWheelScrollMs = i('smoothWheelScrollMs', s.smoothWheelScrollMs);
    s.comicPreload = i('comicPreload', s.comicPreload);
    s.transition = enumFromName(
      TransitionType.values,
      j['transition'],
      s.transition,
    );
    s.transitionMs = i('transitionMs', s.transitionMs);
    s.maxCacheMB = i('maxCacheMB', s.maxCacheMB);
    s.prefetchCount = i('prefetchCount', s.prefetchCount);
    s.maxDecodeDimension = i('maxDecodeDimension', s.maxDecodeDimension);
    s.ffmpegPath = j['ffmpegPath'] as String?;
    s.decodeInIsolate = b('decodeInIsolate', s.decodeInIsolate);
    s.decodeIsolateCount = i('decodeIsolateCount', s.decodeIsolateCount);
    s.highQualityDelayMs = i('highQualityDelayMs', s.highQualityDelayMs);
    s.animMaxCachedFrames = i('animMaxCachedFrames', s.animMaxCachedFrames);
    s.thumbSize = d('thumbSize') ?? s.thumbSize;
    s.progressiveQuality = b('progressiveQuality', s.progressiveQuality);
    s.sortField = enumFromName(SortField.values, j['sortField'], s.sortField);
    s.sortAscending = b('sortAscending', s.sortAscending);
    s.naturalSort = b('naturalSort', s.naturalSort);
    s.includeHidden = b('includeHidden', s.includeHidden);
    s.hideUndecodableFiles = b('hideUndecodableFiles', s.hideUndecodableFiles);
    s.deleteToTrash = b('deleteToTrash', s.deleteToTrash);
    s.confirmDelete = b('confirmDelete', s.confirmDelete);
    s.watchFolder = b('watchFolder', s.watchFolder);
    s.rememberLastFolder = b('rememberLastFolder', s.rememberLastFolder);
    s.restoreLastImage = b('restoreLastImage', s.restoreLastImage);
    s.lastImagePath = j['lastImagePath'] as String?;
    s.slideshowIntervalMs = i('slideshowIntervalMs', s.slideshowIntervalMs);
    s.slideshowRandom = b('slideshowRandom', s.slideshowRandom);
    s.slideshowLoop = b('slideshowLoop', s.slideshowLoop);
    s.openArchives = b('openArchives', s.openArchives);
    s.animAutoPlay = b('animAutoPlay', s.animAutoPlay);
    s.animSpeed = d('animSpeed') ?? s.animSpeed;

    final sc = j['shortcuts'];
    if (sc is Map) {
      s.shortcuts = {
        for (final e in sc.entries)
          e.key.toString():
              (e.value as List?)?.map((v) => v.toString()).toList() ?? [],
      };
    }
    final msc = j['modeShortcuts'];
    if (msc is Map) {
      s.modeShortcuts = {
        for (final e in msc.entries)
          e.key.toString(): {
            for (final f in (e.value as Map).entries)
              f.key.toString():
                  (f.value as List?)?.map((v) => v.toString()).toList() ?? [],
          },
      };
    }
    final mo = j['mouse'];
    if (mo is Map) {
      for (final m in ViewMode.values) {
        final raw = mo[m.name];
        if (raw is Map) {
          s.mouse[m.name] = MouseBindings.fromJson(
            raw.cast<String, dynamic>(),
            MouseBindings.defaultsFor(m),
          );
        }
      }
    }
    return s;
  }
}
