import '../l10n/strings.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

import '../core/platform_ops.dart';
import '../models/app_action.dart';
import '../models/enums.dart';
import '../models/key_chord.dart';
import '../models/settings.dart';
import '../services/decoders/decoder_registry.dart';
import '../services/decoders/format_sniffer.dart';
import '../state/viewer_state.dart';
import 'title_bar.dart';
import 'widgets.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({
    super.key,
    required this.state,
    required this.onClose,
    this.embedded = true,
  });
  final ViewerState state;
  final VoidCallback onClose;

  /// true = 嵌在主窗口里（降级方案），false = 独立设置窗口进程
  final bool embedded;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  int _tab = 0;
  TextEditingController? _ffmpegCtl;

  @override
  void dispose() {
    _ffmpegCtl?.dispose();
    super.dispose();
  }

  ViewMode? _scope; // null = 全局

  ViewerState get s => widget.state;
  Settings get cfg => s.settings;

  void _set(void Function() fn) {
    setState(() {
      fn();
      s.settingsService.update((_) {});
    });
  }

  List<(String, IconData)> get _tabs => [
    (lt("窗口与启动"), Icons.web_asset),
    (lt("外观"), Icons.palette_outlined),
    (lt("查看"), Icons.image_outlined),
    (lt("拼页与滚动"), Icons.view_agenda_outlined),
    (lt("动画与过渡"), Icons.animation),
    (lt("鼠标"), Icons.mouse_outlined),
    (lt("快捷键"), Icons.keyboard_outlined),
    (lt("性能"), Icons.speed),
    (lt("文件"), Icons.folder_outlined),
    (lt("解码器"), Icons.extension_outlined),
    (lt("关于"), Icons.info_outline),
  ];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      color: scheme.surface,
      child: Column(
        children: [
          _titleBar(context),
          Expanded(
            child: Row(
              children: [
                Container(
                  width: 190,
                  decoration: BoxDecoration(
                    border: Border(
                      right: BorderSide(color: scheme.outlineVariant),
                    ),
                  ),
                  child: ListView(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    children: [
                      for (var i = 0; i < _tabs.length; i++)
                        _NavItem(
                          label: _tabs[i].$1,
                          icon: _tabs[i].$2,
                          selected: _tab == i,
                          onTap: () => setState(() => _tab = i),
                        ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(18, 14, 18, 30),
                    children: _content(),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 标题栏：独立窗口时自绘（不用系统原生标题栏），风格跟主窗口一致
  Widget _titleBar(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = scheme.brightness == Brightness.dark;
    final h = cfg.titleBarHeight;

    Widget title = Row(
      children: [
        const SizedBox(width: 12),
        Icon(Icons.settings, size: 16, color: scheme.primary),
        const SizedBox(width: 8),
        Text(lt("设置"), style: Theme.of(context).textTheme.titleSmall),
        if (!widget.embedded) ...[
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              lt("改动会自动同步到看图窗口"),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall
                  ?.copyWith(color: scheme.outline),
            ),
          ),
        ],
        const Spacer(),
      ],
    );

    // 独立窗口：标题区可拖动 + 双击最大化
    if (!widget.embedded) {
      title = GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanStart: (_) => windowManager.startDragging(),
        onDoubleTap: _toggleMaximize,
        child: title,
      );
    }

    return SizedBox(
      height: h,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest.withValues(
            alpha: dark ? 0.55 : 0.75,
          ),
          border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
        ),
        child: Row(
          children: [
            Expanded(child: title),
            if (widget.embedded)
              WinButton(
                icon: Icons.close,
                tooltip: lt("关闭 (Esc)"),
                danger: true,
                onTap: widget.onClose,
              )
            else ...[
              WinButton(
                icon: Icons.remove,
                tooltip: lt("最小化"),
                onTap: windowManager.minimize,
              ),
              WinButton(
                icon: Icons.crop_square,
                tooltip: lt("最大化 / 还原"),
                onTap: _toggleMaximize,
              ),
              WinButton(
                icon: Icons.close,
                tooltip: lt("关闭窗口 (Esc)"),
                danger: true,
                onTap: widget.onClose,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _toggleMaximize() async {
    if (await windowManager.isMaximized()) {
      await windowManager.unmaximize();
    } else {
      await windowManager.maximize();
    }
  }

  List<Widget> _content() {
    switch (_tab) {
      case 0:
        return _windowSection();
      case 1:
        return _appearanceSection();
      case 2:
        return _viewSection();
      case 3:
        return _layoutSection();
      case 4:
        return _animSection();
      case 5:
        return _mouseSection();
      case 6:
        return _shortcutSection();
      case 7:
        return _perfSection();
      case 8:
        return _fileSection();
      case 9:
        return _decoderSection();
      default:
        return _aboutSection();
    }
  }

  // ---------------------------------------------------------------------------
  List<Widget> _windowSection() => [
    _header(lt('语言')),
    _dropdown<AppLanguage>(
      lt('语言'),
      cfg.language ?? AppLanguage.simplifiedChinese,
      AppLanguage.values,
      (v) => v.nativeName,
      (v) => _set(() => cfg.language = v),
    ),
    _header(lt("启动位置")),
    _dropdown<StartupPlacement>(
      lt("窗口启动方式"),
      cfg.startupPlacement,
      StartupPlacement.values,
      (v) => v.label,
      (v) => _set(() => cfg.startupPlacement = v),
    ),
    _slider(
      lt("默认宽度"),
      cfg.defaultWidth,
      480,
      3840,
      (v) => _set(() => cfg.defaultWidth = v),
      unit: 'px',
    ),
    _slider(
      lt("默认高度"),
      cfg.defaultHeight,
      360,
      2160,
      (v) => _set(() => cfg.defaultHeight = v),
      unit: 'px',
    ),
    _switch(
      lt("启动时全屏"),
      cfg.startFullscreen,
      (v) => _set(() => cfg.startFullscreen = v),
    ),
    _switch(lt("窗口置顶"), cfg.alwaysOnTop, (v) {
      _set(() => cfg.alwaysOnTop = v);
      if (widget.embedded) s.toggleAlwaysOnTop();
    }),
    _header(lt("多开行为")),
    _dropdown<InstanceMode>(
      lt("从文件管理器打开图片时"),
      cfg.instanceMode,
      InstanceMode.values,
      (v) => v.label,
      (v) => _set(() => cfg.instanceMode = v),
      hint: lt("复用已有窗口时直接切换图片；新窗口模式会为每次打开启动独立进程。"),
    ),
    _header(lt("恢复上次")),
    _switch(
      lt("记住上次打开的文件夹"),
      cfg.rememberLastFolder,
      (v) => _set(() => cfg.rememberLastFolder = v),
    ),
    _switch(
      lt("启动时恢复上次的图片"),
      cfg.restoreLastImage,
      (v) => _set(() => cfg.restoreLastImage = v),
    ),
  ];

  List<Widget> _appearanceSection() => [
    _header(lt("主题")),
    _dropdown<ThemePref>(
      lt("主题模式"),
      cfg.theme,
      ThemePref.values,
      (v) => v.label,
      (v) => _set(() => cfg.theme = v),
    ),
    _colorRow(),
    _dropdown<BackgroundStyle>(
      lt("画布背景"),
      cfg.background,
      BackgroundStyle.values,
      (v) => v.label,
      (v) => _set(() => cfg.background = v),
    ),
    _slider(
      lt("界面圆角"),
      cfg.cornerRadius,
      0,
      20,
      (v) => _set(() => cfg.cornerRadius = v),
      unit: 'px',
    ),
    _slider(
      lt("字体大小"),
      cfg.uiFontScale,
      0.8,
      1.4,
      (v) => _set(() => cfg.uiFontScale = v),
      digits: 2,
      unit: 'x',
    ),
    _header(lt("标题栏")),
    _switch(
      lt("自动隐藏标题栏（靠近顶部显示）"),
      cfg.titleBarAutoHide,
      (v) => _set(() => cfg.titleBarAutoHide = v),
    ),
    _slider(
      lt("标题栏高度"),
      cfg.titleBarHeight,
      26,
      56,
      (v) => _set(() => cfg.titleBarHeight = v),
      unit: 'px',
    ),
    _slider(
      lt("离开后多久隐藏"),
      cfg.titleBarHideDelayMs.toDouble(),
      200,
      6000,
      (v) => _set(() => cfg.titleBarHideDelayMs = v.round()),
      unit: 'ms',
    ),
    _header(lt("状态悬浮窗")),
    _switch(lt("显示状态悬浮窗"), cfg.showStatusPanel, (v) {
      _set(() => cfg.showStatusPanel = v);
      if (widget.embedded) s.showStatusPanel = v;
    }),
    _dropdown<PanelCorner>(
      lt("悬浮窗位置"),
      cfg.statusPanelCorner,
      PanelCorner.values,
      (v) => v.label,
      (v) => _set(() => cfg.statusPanelCorner = v),
    ),
    _slider(
      lt("悬浮窗不透明度"),
      cfg.statusPanelOpacity,
      0.3,
      1,
      (v) => _set(() => cfg.statusPanelOpacity = v),
      digits: 2,
    ),
    _header(lt("其他界面")),
    _switch(lt("显示缩略图栏"), cfg.showFilmstrip, (v) {
      _set(() => cfg.showFilmstrip = v);
      if (widget.embedded) s.showFilmstrip = v;
    }),
    _slider(
      lt("缩略图栏高度"),
      cfg.filmstripHeight,
      60,
      200,
      (v) => _set(() => cfg.filmstripHeight = v),
      unit: 'px',
    ),
    _slider(
      lt("网格缩略图大小"),
      cfg.thumbSize,
      80,
      320,
      (v) => _set(() => cfg.thumbSize = v),
      unit: 'px',
    ),
    _switch(
      lt("显示中部浮层提示 (HUD)"),
      cfg.showHud,
      (v) => _set(() => cfg.showHud = v),
    ),
    _slider(
      lt("提示显示时长"),
      cfg.hudDurationMs.toDouble(),
      400,
      4000,
      (v) => _set(() => cfg.hudDurationMs = v.round()),
      unit: 'ms',
    ),
    _switch(
      lt("全屏时自动隐藏鼠标"),
      cfg.autoHideCursorInFullscreen,
      (v) => _set(() => cfg.autoHideCursorInFullscreen = v),
    ),
    _switch(
      lt("右键菜单显示图标"),
      cfg.contextMenuIcons,
      (v) => _set(() => cfg.contextMenuIcons = v),
    ),
  ];

  List<Widget> _viewSection() => [
    _header(lt("默认查看方式")),
    _dropdown<ViewMode>(
      lt("打开图片时使用"),
      cfg.defaultViewMode,
      ViewMode.values,
      (v) => '${v.hint}. ${v.label}',
      (v) => _set(() => cfg.defaultViewMode = v),
    ),
    _switch(
      lt("记住最后使用的查看方式"),
      cfg.rememberViewMode,
      (v) => _set(() => cfg.rememberViewMode = v),
    ),
    _header(lt("缩放")),
    _dropdown<Interpolation>(
      lt("缩放插值"),
      cfg.interpolation,
      Interpolation.values,
      (v) => v.label,
      (v) => _set(() => cfg.interpolation = v),
    ),
    _slider(
      lt("每次缩放倍率"),
      cfg.zoomStep,
      1.02,
      2.0,
      (v) => _set(() => cfg.zoomStep = v),
      digits: 2,
    ),
    _slider(
      lt("最小缩放"),
      cfg.minZoom,
      0.01,
      1,
      (v) => _set(() => cfg.minZoom = v),
      digits: 2,
    ),
    _slider(
      lt("最大缩放"),
      cfg.maxZoom,
      2,
      64,
      (v) => _set(() => cfg.maxZoom = v),
      digits: 0,
    ),
    _switch(
      lt("放大小于窗口的图片"),
      cfg.upscaleSmallImages,
      (v) => _set(() => cfg.upscaleSmallImages = v),
    ),
    _switch(
      lt("图片小于窗口时居中"),
      cfg.centerSmallImages,
      (v) => _set(() => cfg.centerSmallImages = v),
    ),
    _header(lt("平移")),
    _switch(lt("拖动惯性"), cfg.panInertia, (v) => _set(() => cfg.panInertia = v)),
    _slider(
      lt("键盘平移步长"),
      cfg.keyPanStep,
      20,
      500,
      (v) => _set(() => cfg.keyPanStep = v),
      unit: 'px',
    ),
    _dropdown<DoubleClickAction>(
      lt("双击动作"),
      cfg.doubleClickAction,
      DoubleClickAction.values,
      (v) => v.label,
      (v) => _set(() => cfg.doubleClickAction = v),
    ),
    _header(lt("浏览")),
    _switch(
      lt("到头后循环到另一端"),
      cfg.wrapAround,
      (v) => _set(() => cfg.wrapAround = v),
    ),
    _switch(
      lt("应用 EXIF 方向（手机照片自动转正）"),
      cfg.applyExifOrientation,
      (v) => _set(() => cfg.applyExifOrientation = v),
    ),
  ];

  List<Widget> _layoutSection() => [
    _header(lt("双页模式")),
    _dropdown<ReadingDirection>(
      lt("阅读方向"),
      cfg.readingDirection,
      ReadingDirection.values,
      (v) => v.label,
      (v) => _set(() => cfg.readingDirection = v),
    ),
    _switch(
      lt("首页单独显示（封面）"),
      cfg.doublePageFirstAlone,
      (v) => _set(() => cfg.doublePageFirstAlone = v),
    ),
    _slider(
      lt("双页间距"),
      cfg.pageGap,
      0,
      60,
      (v) => _set(() => cfg.pageGap = v),
      unit: 'px',
    ),
    _header(lt("漫画 / 长图模式")),
    _slider(
      lt("图片间距"),
      cfg.comicGap,
      0,
      60,
      (v) => _set(() => cfg.comicGap = v),
      unit: 'px',
    ),
    _slider(
      lt("滚轮滚动步长"),
      cfg.scrollStep,
      40,
      600,
      (v) => _set(() => cfg.scrollStep = v),
      unit: 'px',
    ),
    _switch(
      lt("平滑滚动（键盘 / 菜单）"),
      cfg.smoothScroll,
      (v) => _set(() => cfg.smoothScroll = v),
    ),
    _switch(
      lt("鼠标滚轮平滑滚动"),
      cfg.smoothWheelScroll,
      (v) => _set(() => cfg.smoothWheelScroll = v),
    ),
    if (cfg.smoothWheelScroll)
      _slider(
        lt("滚轮平滑时长"),
        cfg.smoothWheelScrollMs.toDouble(),
        60,
        500,
        (v) => _set(() => cfg.smoothWheelScrollMs = v.round()),
        unit: 'ms',
        digits: 0,
      ),
    _slider(
      lt("预加载屏数"),
      cfg.comicPreload.toDouble(),
      0,
      8,
      (v) => _set(() => cfg.comicPreload = v.round()),
      digits: 0,
    ),
  ];

  List<Widget> _animSection() => [
    _header(lt("切换图片过渡动画")),
    _dropdown<TransitionType>(
      lt("动画类型"),
      cfg.transition,
      TransitionType.values,
      (v) => v.label,
      (v) => _set(() => cfg.transition = v),
    ),
    _slider(
      lt("动画时长"),
      cfg.transitionMs.toDouble(),
      0,
      600,
      (v) => _set(() => cfg.transitionMs = v.round()),
      unit: 'ms',
    ),
    _header(lt("动图 (GIF / APNG / 动画 WebP)")),
    _switch(
      lt("打开后自动播放"),
      cfg.animAutoPlay,
      (v) => _set(() => cfg.animAutoPlay = v),
    ),
    _slider(
      lt("播放速度"),
      cfg.animSpeed,
      0.1,
      4,
      (v) => _set(() => cfg.animSpeed = v),
      digits: 2,
      unit: 'x',
    ),
    _slider(
      lt("最多缓存帧数"),
      cfg.animMaxCachedFrames.toDouble(),
      20,
      2000,
      (v) => _set(() => cfg.animMaxCachedFrames = v.round()),
      digits: 0,
    ),
  ];

  List<Widget> _mouseSection() {
    return [
      _header(lt("鼠标与滚轮（每种查看方式独立设置）")),
      for (final m in ViewMode.values) ...[
        Padding(
          padding: const EdgeInsets.only(top: 14, bottom: 4),
          child: Text(
            '${m.hint}. ${m.label}',
            style: Theme.of(context).textTheme.titleSmall
                ?.copyWith(color: Theme.of(context).colorScheme.primary),
          ),
        ),
        _wheelRow(lt("滚轮"), m, (b) => b.wheel, (b, v) => b.wheel = v),
        _wheelRow(
          lt("Ctrl + 滚轮"),
          m,
          (b) => b.ctrlWheel,
          (b, v) => b.ctrlWheel = v,
        ),
        _wheelRow(
          lt("Shift + 滚轮"),
          m,
          (b) => b.shiftWheel,
          (b, v) => b.shiftWheel = v,
        ),
        _wheelRow(
          lt("Alt + 滚轮"),
          m,
          (b) => b.altWheel,
          (b, v) => b.altWheel = v,
        ),
        _dropdown<DragButton>(
          lt("拖动图片使用"),
          cfg.mouseFor(m).panButton,
          DragButton.values,
          (v) => v.label,
          (v) => _set(() => cfg.mouseFor(m).panButton = v),
        ),
        _switch(
          lt("反转滚轮方向"),
          cfg.mouseFor(m).invertWheel,
          (v) => _set(() => cfg.mouseFor(m).invertWheel = v),
        ),
      ],
    ];
  }

  Widget _wheelRow(
    String label,
    ViewMode m,
    WheelAction Function(MouseBindings) get,
    void Function(MouseBindings, WheelAction) set,
  ) {
    return _dropdown<WheelAction>(
      label,
      get(cfg.mouseFor(m)),
      WheelAction.values,
      (v) => v.label,
      (v) => _set(() => set(cfg.mouseFor(m), v)),
    );
  }

  List<Widget> _shortcutSection() {
    final groups = <ActionGroup, List<AppAction>>{};
    for (final a in AppAction.values) {
      groups.putIfAbsent(a.group, () => []).add(a);
    }
    return [
      _header(lt("快捷键")),
      Row(
        children: [
          Text(lt("作用范围"), style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(width: 12),
          LimeDropdown<ViewMode?>(
            width: 240,
            value: _scope,
            items: <ViewMode?>[null, ...ViewMode.values],
            labelOf: (v) =>
                v == null ? lt("全局（所有查看方式）") : '${v.hint}. ${v.label}',
            onChanged: (v) => setState(() => _scope = v),
          ),
          const Spacer(),
          TextButton.icon(
            onPressed: () => _set(() => cfg.resetShortcuts()),
            icon: const Icon(Icons.restart_alt, size: 16),
            label: Text(lt("全部恢复默认")),
          ),
        ],
      ),
      if (_scope != null)
        Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 6),
          child: Text(
            lt("在此查看方式下覆盖全局设置；未覆盖的项显示为组继承值。"),
            style: Theme.of(context).textTheme.labelSmall
                ?.copyWith(color: Theme.of(context).colorScheme.outline),
          ),
        ),
      for (final g in groups.entries) ...[
        Padding(
          padding: const EdgeInsets.only(top: 14, bottom: 2),
          child: Text(
            g.key.label,
            style: Theme.of(context).textTheme.titleSmall
                ?.copyWith(color: Theme.of(context).colorScheme.primary),
          ),
        ),
        for (final a in g.value) _shortcutRow(a),
      ],
      const SizedBox(height: 20),
    ];
  }

  Widget _shortcutRow(AppAction a) {
    final scheme = Theme.of(context).colorScheme;
    final overridden =
        _scope != null && (cfg.modeShortcuts[_scope!.name]?[a.name] != null);
    final chords = cfg.chordsFor(a, _scope);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(
            child: Text(a.label, style: Theme.of(context).textTheme.bodyMedium),
          ),
          for (final c in chords)
            Padding(
              padding: const EdgeInsets.only(left: 4),
              child: _Chip(
                label: c.label,
                dim: _scope != null && !overridden,
                onTap: () => _recordChord(a, replace: c),
              ),
            ),
          if (chords.isEmpty)
            _Chip(label: lt("未设置"), dim: true, onTap: () => _recordChord(a)),
          IconButton(
            iconSize: 15,
            visualDensity: VisualDensity.compact,
            tooltip: lt("添加按键"),
            onPressed: () => _recordChord(a, add: true),
            icon: const Icon(Icons.add),
          ),
          IconButton(
            iconSize: 15,
            visualDensity: VisualDensity.compact,
            tooltip: _scope == null ? lt("恢复默认") : lt("取消覆盖"),
            onPressed: () => _set(() {
              if (_scope == null) {
                cfg.shortcuts.remove(a.name);
              } else {
                cfg.clearModeOverride(a, _scope!);
              }
              cfg.invalidateKeymap();
            }),
            icon: Icon(Icons.undo, color: scheme.outline),
          ),
        ],
      ),
    );
  }

  Future<void> _recordChord(
    AppAction a, {
    KeyChord? replace,
    bool add = false,
  }) async {
    final chord = await showDialog<KeyChord>(
      context: context,
      builder: (_) => const _ChordRecorder(),
    );
    if (chord == null) return;
    if (!mounted) return;
    final conflict = cfg.conflictOf(chord, a, _scope);
    if (conflict != null) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(lt("快捷键冲突")),
          content: Text(
            lt("{0} 已被「{1}」占用，是否抢占？", [chord.label, conflict.label]),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(lt("取消")),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(lt("抢占")),
            ),
          ],
        ),
      );
      if (ok != true) return;
      final list = cfg
          .chordsFor(conflict, _scope)
          .where((c) => c != chord)
          .toList();
      cfg.setChords(conflict, list, mode: _scope);
    }
    final current = cfg.chordsFor(a, _scope).toList();
    if (add) {
      current.add(chord);
    } else if (replace != null) {
      final i = current.indexOf(replace);
      if (i >= 0) {
        current[i] = chord;
      } else {
        current.add(chord);
      }
    } else {
      current
        ..clear()
        ..add(chord);
    }
    _set(() => cfg.setChords(a, current, mode: _scope));
  }

  List<Widget> _perfSection() => [
    _header(lt("缓存与预取")),
    _slider(
      lt("图片缓存上限"),
      cfg.maxCacheMB.toDouble(),
      128,
      4096,
      (v) => _set(() => cfg.maxCacheMB = v.round()),
      unit: 'MB',
      digits: 0,
    ),
    _slider(
      lt("预取前后张数"),
      cfg.prefetchCount.toDouble(),
      0,
      10,
      (v) => _set(() => cfg.prefetchCount = v.round()),
      digits: 0,
    ),
    _header(lt("解码")),
    _slider(
      lt("单张最大解码边长"),
      cfg.maxDecodeDimension.toDouble(),
      2048,
      16384,
      (v) => _set(() => cfg.maxDecodeDimension = v.round()),
      unit: 'px',
      digits: 0,
    ),
    _switch(
      lt("放大时渐进加载更高清版本"),
      cfg.progressiveQuality,
      (v) => _set(() => cfg.progressiveQuality = v),
    ),
    _slider(
      lt("停止交互后提升画质延迟"),
      cfg.highQualityDelayMs.toDouble(),
      0,
      800,
      (v) => _set(() => cfg.highQualityDelayMs = v.round()),
      unit: 'ms',
    ),
    const SizedBox(height: 12),
    _infoBox(
      lt("当前缓存：{0} 项 / {1} MB\n超大图（>16k 像素）受 GPU 纹理上限限制会自动降采样。", [
        s.images.cacheCount,
        (s.images.cacheBytes / 1024 / 1024).toStringAsFixed(1),
      ]),
    ),
    Align(
      alignment: Alignment.centerLeft,
      child: TextButton.icon(
        onPressed: () => setState(s.images.clear),
        icon: const Icon(Icons.cleaning_services_outlined, size: 16),
        label: Text(lt("清空缓存")),
      ),
    ),
  ];

  List<Widget> _fileSection() => [
    _header(lt("排序")),
    _dropdown<SortField>(
      lt("默认排序字段"),
      cfg.sortField,
      SortField.values,
      (v) => v.label,
      (v) => _set(() => cfg.sortField = v),
    ),
    _switch(
      lt("正序"),
      cfg.sortAscending,
      (v) => _set(() => cfg.sortAscending = v),
    ),
    _switch(
      lt("自然排序（img2 在 img10 之前）"),
      cfg.naturalSort,
      (v) => _set(() => cfg.naturalSort = v),
    ),
    _switch(
      lt("显示隐藏文件"),
      cfg.includeHidden,
      (v) => _set(() => cfg.includeHidden = v),
    ),
    _switch(
      lt("只列出本机能解码的文件"),
      cfg.hideUndecodableFiles,
      (v) => _set(() {
        cfg.hideUndecodableFiles = v;
        s.folder.refresh();
      }),
      hint: lt("默认关：认得出是图片就列出来，不会因为解不了而让浏览断档"),
    ),
    _header(lt("文件操作")),
    _switch(
      lt("删除到回收站"),
      cfg.deleteToTrash,
      (v) => _set(() => cfg.deleteToTrash = v),
    ),
    _switch(
      lt("删除前确认"),
      cfg.confirmDelete,
      (v) => _set(() => cfg.confirmDelete = v),
    ),
    _switch(
      lt("监听文件夹变化自动刷新"),
      cfg.watchFolder,
      (v) => _set(() => cfg.watchFolder = v),
    ),
    _switch(
      lt("支持打开压缩包 (zip / cbz)"),
      cfg.openArchives,
      (v) => _set(() => cfg.openArchives = v),
    ),
    _header(lt("幻灯片")),
    _slider(
      lt("间隔"),
      cfg.slideshowIntervalMs.toDouble(),
      500,
      30000,
      (v) => _set(() => cfg.slideshowIntervalMs = v.round()),
      unit: 'ms',
    ),
    _switch(
      lt("随机顺序"),
      cfg.slideshowRandom,
      (v) => _set(() => cfg.slideshowRandom = v),
    ),
    _switch(
      lt("循环播放"),
      cfg.slideshowLoop,
      (v) => _set(() => cfg.slideshowLoop = v),
    ),
  ];

  // ---------------------------------------------------------------------------
  // 关于
  // ---------------------------------------------------------------------------
  static const _appVersion = '1.0.0';

  List<Widget> _aboutSection() {
    final scheme = Theme.of(context).colorScheme;
    return [
      _header('lime image'),
      Text(
        lt("lime image 是一款面向桌面的轻量图片查看器，支持常见图片、动图、矢量图、相机 RAW 和漫画浏览。"),
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(height: 1.6),
      ),
      const SizedBox(height: 6),
      Text(
        lt("版本 {0}", [_appVersion]),
        style: Theme.of(context).textTheme.labelMedium
            ?.copyWith(color: scheme.onSurfaceVariant),
      ),
      const SizedBox(height: 22),
      _header(lt("配置文件")),
      SelectableText(
        s.settingsService.filePath,
        style: Theme.of(context).textTheme.bodySmall
            ?.copyWith(color: scheme.onSurfaceVariant),
      ),
      const SizedBox(height: 10),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          OutlinedButton.icon(
            onPressed: () =>
                PlatformOps.revealInFileManager(s.settingsService.filePath),
            icon: const Icon(Icons.folder_outlined, size: 16),
            label: Text(lt("在文件管理器中显示")),
          ),
          TextButton.icon(
            onPressed: () async {
              await s.settingsService.resetAll();
              if (mounted) setState(() {});
            },
            icon: const Icon(Icons.restart_alt, size: 16),
            label: Text(lt("恢复默认设置")),
          ),
        ],
      ),
    ];
  }

  // ---------------------------------------------------------------------------
  // 解码器
  // ---------------------------------------------------------------------------
  List<Widget> _decoderSection() {
    final reg = s.images.registry;
    final scheme = Theme.of(context).colorScheme;
    final report = reg.report();

    void reprobe() {
      reg.reprobeNow().then((_) {
        if (mounted) setState(() {});
      });
    }

    return [
      _header(lt("后端与格式")),
      _supportLegend(),
      const SizedBox(height: 8),
      _decoderBackend('Flutter / Skia', true, const [
        ImageFormat.png,
        ImageFormat.jpeg,
        ImageFormat.gif,
        ImageFormat.webp,
        ImageFormat.bmp,
        ImageFormat.ico,
      ], report),
      _decoderBackend(lt("系统图像组件 (WIC)"), reg.wicAvailable, const [
        ImageFormat.tiff,
        ImageFormat.raw,
        ImageFormat.jxl,
        ImageFormat.heif,
        ImageFormat.avif,
        ImageFormat.dds,
      ], report),
      _decoderBackend(lt("内嵌预览"), true, const [
        ImageFormat.psd,
        ImageFormat.raw,
      ], report),
      _decoderBackend('ffmpeg', reg.ffmpegAvailable, const [
        ImageFormat.psd,
        ImageFormat.tga,
        ImageFormat.exr,
        ImageFormat.hdr,
        ImageFormat.jp2,
        ImageFormat.pcx,
        ImageFormat.qoi,
        ImageFormat.sgi,
        ImageFormat.pnm,
      ], report),
      _decoderBackend(lt("矢量渲染"), true, const [ImageFormat.svg], report),
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: reprobe,
          icon: const Icon(Icons.refresh, size: 16),
          label: Text(lt("重新检测后端")),
        ),
      ),
      const SizedBox(height: 12),
      _header(lt("后台解码")),
      _switch(
        lt("使用 worker isolate"),
        cfg.decodeInIsolate,
        (v) => _set(() {
          cfg.decodeInIsolate = v;
          s.images.applySettings();
        }),
        hint: lt("避免大图解码阻塞界面"),
      ),
      _slider(
        lt("worker 数量"),
        cfg.decodeIsolateCount.toDouble(),
        0,
        8,
        (v) => _set(() {
          cfg.decodeIsolateCount = v.round();
          s.images.applySettings();
        }),
        digits: 0,
      ),
      Padding(
        padding: const EdgeInsets.only(left: 210, bottom: 8),
        child: Text(
          cfg.decodeIsolateCount == 0
              ? lt("自动分配 · 当前 {0} 个 worker", [reg.isolateCount])
              : lt("当前 {0} 个 worker", [reg.isolateCount]),
          style: Theme.of(context).textTheme.labelSmall
              ?.copyWith(color: scheme.outline),
        ),
      ),
      _header('ffmpeg'),
      TextField(
        controller: _ffmpegCtl ??= TextEditingController(
          text: cfg.ffmpegPath ?? '',
        ),
        decoration: InputDecoration(
          isDense: true,
          hintText: lt("可执行文件路径；留空时从 PATH 查找，按回车应用"),
        ),
        onSubmitted: (v) {
          _set(() => cfg.ffmpegPath = v.trim().isEmpty ? null : v.trim());
          s.images.applySettings();
          reprobe();
        },
      ),
      const SizedBox(height: 18),
      _header(lt("文件列表")),
      _switch(
        lt("只列出本机能解码的文件"),
        cfg.hideUndecodableFiles,
        (v) => _set(() {
          cfg.hideUndecodableFiles = v;
          s.folder.refresh();
        }),
        hint: lt("关闭时会列出所有已知图片格式"),
      ),
    ];
  }

  Widget _supportLegend() {
    return Wrap(
      spacing: 14,
      runSpacing: 6,
      children: [
        _StatusKey(lt("内置"), Color(0xFF3478C5)),
        _StatusKey(lt("已验证"), Color(0xFF2E8B57)),
        _StatusKey(lt("待验证"), Color(0xFFC47A16)),
        _StatusKey(lt("失败"), Color(0xFFC74343)),
        _StatusKey(lt("不可用"), Color(0xFF808080)),
      ],
    );
  }

  Widget _decoderBackend(
    String name,
    bool available,
    List<ImageFormat> formats,
    List<FormatStatus> report,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final byFormat = {for (final item in report) item.format: item};
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 170,
            child: Row(
              children: [
                Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: available ? const Color(0xFF2E8B57) : scheme.error,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(child: Text(name)),
              ],
            ),
          ),
          Expanded(
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final format in formats)
                  _formatTag(
                    format.label,
                    available
                        ? (byFormat[format]?.support ?? FormatSupport.claimed)
                        : FormatSupport.none,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _formatTag(String text, FormatSupport status) {
    final color = switch (status) {
      FormatSupport.native => const Color(0xFF3478C5),
      FormatSupport.verified => const Color(0xFF2E8B57),
      FormatSupport.claimed => const Color(0xFFC47A16),
      FormatSupport.failed => const Color(0xFFC74343),
      FormatSupport.none => const Color(0xFF808080),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        border: Border.all(color: color.withValues(alpha: 0.65)),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(text, style: TextStyle(fontSize: 11, color: color)),
    );
  }

  // ---------------------------------------------------------------------------
  Widget _header(String text) => Padding(
    padding: const EdgeInsets.only(top: 6, bottom: 10),
    child: Row(
      children: [
        Container(
          width: 3,
          height: 13,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primary,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 8),
        Text(text, style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(width: 10),
        Expanded(
          child: Divider(
            height: 1,
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
        ),
      ],
    ),
  );

  Widget _switch(
    String label,
    bool value,
    ValueChanged<bool> onChanged, {
    String? hint,
  }) => _row(
    label,
    Align(
      alignment: Alignment.centerLeft,
      child: SizedBox(
        width: 40,
        height: 24,
        child: FittedBox(
          fit: BoxFit.contain,
          alignment: Alignment.centerLeft,
          child: Switch(value: value, onChanged: onChanged),
        ),
      ),
    ),
    hint: hint,
  );

  /// 统一的一行：左侧标题定宽，右侧控件；说明放在控件下方，避免挤压标题。
  Widget _row(String label, Widget control, {String? hint}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SizedBox(
              width: 210,
              child: Text(label, style: Theme.of(context).textTheme.bodyMedium),
            ),
            Expanded(child: control),
          ],
        ),
        if (hint != null)
          Padding(
            padding: const EdgeInsets.only(left: 210, top: 3, bottom: 3),
            child: Text(
              hint,
              style: Theme.of(context).textTheme.labelSmall
                  ?.copyWith(color: Theme.of(context).colorScheme.outline),
            ),
          ),
      ],
    ),
  );

  Widget _slider(
    String label,
    double value,
    double min,
    double max,
    ValueChanged<double> onChanged, {
    String unit = '',
    int digits = 0,
  }) {
    final v = value.clamp(min, max);
    return _row(
      label,
      Row(
        children: [
          Expanded(
            child: Slider(value: v, min: min, max: max, onChanged: onChanged),
          ),
          SizedBox(
            width: 76,
            child: Text(
              '${v.toStringAsFixed(digits)}$unit',
              textAlign: TextAlign.right,
              style: Theme.of(context).textTheme.labelMedium,
            ),
          ),
        ],
      ),
    );
  }

  Widget _dropdown<T>(
    String label,
    T value,
    List<T> items,
    String Function(T) labelOf,
    ValueChanged<T> onChanged, {
    String? hint,
  }) {
    return _row(
      label,
      Row(
        children: [
          Flexible(
            child: LimeDropdown<T>(
              value: value,
              items: items,
              labelOf: labelOf,
              onChanged: onChanged,
            ),
          ),
          const Spacer(),
        ],
      ),
      hint: hint,
    );
  }

  Widget _colorRow() {
    const colors = [
      0xFF9BCC3C,
      0xFF00897B,
      0xFF1E88E5,
      0xFF5E35B1,
      0xFFD81B60,
      0xFFE53935,
      0xFFFB8C00,
      0xFF546E7A,
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 210, child: Text(lt("强调色"))),
          Expanded(
            child: Wrap(
              spacing: 7,
              runSpacing: 7,
              children: [
                for (final c in colors)
                  GestureDetector(
                    onTap: () => _set(() => cfg.accentColor = c),
                    child: Container(
                      width: 21,
                      height: 21,
                      decoration: BoxDecoration(
                        color: Color(c),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: cfg.accentColor == c
                              ? Theme.of(context).colorScheme.onSurface
                              : Colors.transparent,
                          width: 2,
                        ),
                      ),
                    ),
                  ),
                Tooltip(
                  message: lt("自定义颜色"),
                  child: GestureDetector(
                    onTap: _chooseAccentColor,
                    child: Container(
                      width: 21,
                      height: 21,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Theme.of(context)
                            .colorScheme
                            .surfaceContainerHighest,
                        border: Border.all(
                          color: colors.contains(cfg.accentColor)
                              ? Theme.of(context).colorScheme.outlineVariant
                              : Theme.of(context).colorScheme.onSurface,
                          width: colors.contains(cfg.accentColor) ? 1 : 2,
                        ),
                      ),
                      child: Icon(
                        Icons.colorize,
                        size: 12,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _chooseAccentColor() async {
    var red = Color(cfg.accentColor).r * 255;
    var green = Color(cfg.accentColor).g * 255;
    var blue = Color(cfg.accentColor).b * 255;
    final selected = await showDialog<int>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, update) {
          final color = Color.fromARGB(
            255,
            red.round(),
            green.round(),
            blue.round(),
          );
          Widget channel(
            String label,
            double value,
            ValueChanged<double> set,
          ) => Row(
            children: [
              SizedBox(width: 18, child: Text(label)),
              Expanded(
                child: Slider(
                  value: value,
                  min: 0,
                  max: 255,
                  onChanged: (v) => update(() => set(v)),
                ),
              ),
              SizedBox(
                width: 30,
                child: Text(
                  value.round().toString(),
                  textAlign: TextAlign.right,
                ),
              ),
            ],
          );
          return AlertDialog(
            title: Text(lt("自定义强调色")),
            content: SizedBox(
              width: 340,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    height: 36,
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const SizedBox(height: 10),
                  channel('R', red, (v) => red = v),
                  channel('G', green, (v) => green = v),
                  channel('B', blue, (v) => blue = v),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: Text(lt("取消")),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, color.toARGB32()),
                child: Text(lt("应用")),
              ),
            ],
          );
        },
      ),
    );
    if (selected != null) _set(() => cfg.accentColor = selected);
  }

  Widget _infoBox(String text) => Container(
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerHighest
          .withValues(alpha: 0.6),
      borderRadius: BorderRadius.circular(6),
    ),
    child: Text(
      text,
      style: Theme.of(context).textTheme.labelMedium?.copyWith(height: 1.55),
    ),
  );
}

class _StatusKey extends StatelessWidget {
  const _StatusKey(this.label, this.color);

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 7,
        height: 7,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
      const SizedBox(width: 5),
      Text(label, style: Theme.of(context).textTheme.labelSmall),
    ],
  );
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        color: selected ? scheme.primary.withValues(alpha: 0.12) : null,
        child: Row(
          children: [
            Icon(
              icon,
              size: 15,
              color: selected ? scheme.primary : scheme.onSurfaceVariant,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: selected ? scheme.primary : scheme.onSurface,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.onTap, this.dim = false});
  final String label;
  final VoidCallback onTap;
  final bool dim;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          border: Border.all(color: scheme.outlineVariant),
          borderRadius: BorderRadius.circular(4),
          color: dim ? null : scheme.primary.withValues(alpha: 0.10),
        ),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelMedium
              ?.copyWith(color: dim ? scheme.outline : scheme.onSurface),
        ),
      ),
    );
  }
}

/// 按键录制对话框
class _ChordRecorder extends StatefulWidget {
  const _ChordRecorder();

  @override
  State<_ChordRecorder> createState() => _ChordRecorderState();
}

class _ChordRecorderState extends State<_ChordRecorder> {
  KeyChord? _chord;
  final FocusNode _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  static const _modifiers = {
    'Control Left',
    'Control Right',
    'Shift Left',
    'Shift Right',
    'Alt Left',
    'Alt Right',
    'Meta Left',
    'Meta Right',
  };

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(lt("按下新的快捷键")),
      content: Focus(
        focusNode: _focus,
        autofocus: true,
        onKeyEvent: (node, event) {
          if (event is KeyDownEvent) {
            final label = event.logicalKey.debugName ?? '';
            if (!_modifiers.contains(label)) {
              setState(() => _chord = KeyChord.fromEvent(event));
            }
          }
          return KeyEventResult.handled;
        },
        child: SizedBox(
          width: 320,
          height: 70,
          child: Center(
            child: Text(
              _chord?.label ?? lt("等待按键…"),
              style: Theme.of(context).textTheme.headlineSmall,
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(lt("取消")),
        ),
        FilledButton(
          onPressed: _chord == null
              ? null
              : () => Navigator.pop<KeyChord>(context, _chord),
          child: Text(lt("确定")),
        ),
      ],
    );
  }
}
