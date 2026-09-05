import '../l10n/strings.dart';

import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:window_manager/window_manager.dart';

import '../core/utils.dart';
import '../models/app_action.dart';
import '../state/viewer_state.dart';
import 'theme.dart';
import 'metadata_panel.dart';

/// 自绘标题栏：自动隐藏、可拖动，只显示文件名
class TitleBar extends StatelessWidget {
  const TitleBar({super.key, required this.state, required this.visible});

  final ViewerState state;
  final bool visible;

  @override
  Widget build(BuildContext context) {
    final s = state;
    final scheme = Theme.of(context).colorScheme;
    final dark = scheme.brightness == Brightness.dark;
    final h = s.settings.titleBarHeight;
    final path = s.folder.currentPath;
    final title = path == null ? 'lime image' : p.basename(path);
    final full = s.isFullscreen;

    return IgnorePointer(
      ignoring: !visible,
      child: AnimatedSlide(
        duration: const Duration(milliseconds: 170),
        curve: Curves.easeOutCubic,
        offset: Offset(0, visible ? 0 : -1),
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 150),
          opacity: visible ? 1 : 0,
          child: SizedBox(
            height: h,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: LimeTheme.overlaySurface(scheme, alpha: 0.92),
                border: Border(
                  bottom: BorderSide(
                    color: dark ? Colors.white10 : Colors.black12,
                  ),
                ),
              ),
              child: Row(
                children: [
                  const SizedBox(width: 11),
                  Icon(Icons.crop_original, size: 14, color: scheme.primary),
                  const SizedBox(width: 9),
                  Expanded(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      // 全屏时拖动标题栏没有意义，也会把窗口拖出全屏
                      onPanStart: full
                          ? null
                          : (_) => windowManager.startDragging(),
                      onDoubleTap: s.toggleMaximize,
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(
                                color: scheme.onSurface.withValues(alpha: 0.92),
                              ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (full)
                    WinButton(
                      icon: Icons.fullscreen_exit,
                      tooltip: lt("退出全屏 (Esc)"),
                      onTap: () => s.setFullscreen(false),
                    )
                  else ...[
                    WinButton(
                      icon: Icons.remove,
                      tooltip: lt("最小化"),
                      onTap: s.minimizeWindow,
                    ),
                    WinButton(
                      icon: Icons.crop_square,
                      tooltip: lt("最大化 / 还原"),
                      onTap: s.toggleMaximize,
                    ),
                  ],
                  WinButton(
                    icon: Icons.close,
                    tooltip: lt("关闭"),
                    danger: true,
                    onTap: s.requestClose,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 标题栏右侧的窗口按钮（主窗口 / 设置窗口共用）
class WinButton extends StatefulWidget {
  const WinButton({
    super.key,
    required this.icon,
    required this.onTap,
    required this.tooltip,
    this.danger = false,
  });

  final IconData icon;
  final VoidCallback onTap;
  final String tooltip;
  final bool danger;

  @override
  State<WinButton> createState() => _WinButtonState();
}

class _WinButtonState extends State<WinButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bg = widget.danger
        ? const Color(0xFFE81123)
        : scheme.onSurface.withValues(alpha: 0.09);
    return Tooltip(
      message: widget.tooltip,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          // 关窗仍然按下即响应；最小化/最大化等到点击完成，避免和窗口状态切换竞争。
          onTap: widget.danger ? null : widget.onTap,
          onTapDown: widget.danger ? (_) => widget.onTap() : null,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 110),
            width: 42,
            height: double.infinity,
            color: _hover ? bg : Colors.transparent,
            child: Center(
              child: Icon(
                widget.icon,
                size: 14,
                color: _hover && widget.danger
                    ? Colors.white
                    : scheme.onSurface.withValues(alpha: 0.72),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 悬浮状态小窗（H 键开关）：毛玻璃卡片，只讲信息，不再列快捷键
class StatusPanel extends StatelessWidget {
  const StatusPanel({super.key, required this.state});
  final ViewerState state;

  @override
  Widget build(BuildContext context) {
    final s = state;
    final cfg = s.settings;
    final scheme = Theme.of(context).colorScheme;
    final dark = scheme.brightness == Brightness.dark;
    final img = s.image;
    final entry = s.folder.current;
    if (entry == null) return const SizedBox.shrink();

    final radius = BorderRadius.circular(cfg.cornerRadius + 2);
    final surface = (dark ? const Color(0xFF1A1C20) : Colors.white).withValues(
      alpha: cfg.statusPanelOpacity,
    );

    final progress = s.folder.count <= 1
        ? 1.0
        : (s.folder.index + 1) / s.folder.count;

    return ClipRRect(
      borderRadius: radius,
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          width: 320,
          decoration: BoxDecoration(
            color: surface,
            borderRadius: radius,
            border: Border.all(color: dark ? Colors.white12 : Colors.black12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: dark ? 0.5 : 0.16),
                blurRadius: 22,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // —— 标题行 ——
              Padding(
                padding: const EdgeInsets.fromLTRB(13, 11, 8, 0),
                child: Row(
                  children: [
                    Icon(Icons.image_outlined, size: 14, color: scheme.primary),
                    const SizedBox(width: 7),
                    Expanded(
                      child: Text(
                        p.basename(entry.path),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleSmall
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                    ),
                    if (s.marks.isMarked(entry.path))
                      const Padding(
                        padding: EdgeInsets.only(left: 4),
                        child: Icon(
                          Icons.star_rounded,
                          size: 15,
                          color: Color(0xFFFFC53D),
                        ),
                      ),
                    _MiniIconButton(
                      icon: Icons.close_rounded,
                      tooltip: lt("隐藏状态窗"),
                      onTap: () => s.invoke(AppAction.toggleStatusPanel),
                    ),
                  ],
                ),
              ),
              // —— 查看方式 + 排序 ——
              Padding(
                padding: const EdgeInsets.fromLTRB(13, 8, 13, 0),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: scheme.primary.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(5),
                      ),
                      child: Text(
                        s.mode.label,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: scheme.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 7),
                    Icon(
                      cfg.sortAscending
                          ? Icons.arrow_upward_rounded
                          : Icons.arrow_downward_rounded,
                      size: 11,
                      color: scheme.outline,
                    ),
                    const SizedBox(width: 2),
                    Text(
                      cfg.sortField.label,
                      style: Theme.of(context).textTheme.labelSmall
                          ?.copyWith(color: scheme.outline),
                    ),
                    const Spacer(),
                    // EXIF 展开 / 收起（默认折叠，展开才去读）
                    _ExifToggle(state: s),
                    if (s.slideshowActive)
                      Padding(
                        padding: const EdgeInsets.only(left: 6),
                        child: Icon(
                          Icons.slideshow_rounded,
                          size: 13,
                          color: scheme.primary,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              // —— 信息表 ——
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 13),
                child: Column(
                  children: [
                    if (img != null)
                      _line(
                        context,
                        lt("尺寸"),
                        '${img.displayWidth} × ${img.displayHeight}',
                      ),
                    if (img != null &&
                        (img.naturalWidth != img.displayWidth ||
                            img.naturalHeight != img.displayHeight))
                      _line(
                        context,
                        lt("原始"),
                        '${img.naturalWidth} × ${img.naturalHeight}',
                      ),
                    _line(
                      context,
                      lt("缩放"),
                      s.mode.isScrollMode
                          ? lt("宽度 {0}%", [(s.stripZoom * 100).round()])
                          : '${(s.tr.scale * 100).round()}%',
                    ),
                    _line(context, lt("大小"), formatBytes(entry.size)),
                    _line(context, lt("修改"), formatDate(entry.modified)),
                    if (img != null && img.animated)
                      _line(
                        context,
                        s.animPlaying ? lt("播放中") : lt("已暂停"),
                        lt("第 {0} / {1}{2} 帧", [
                          s.frameIndex + 1,
                          img.frameCount,
                          img.truncatedFrames ? '+' : '',
                        ]),
                        highlight: true,
                      ),
                    _line(
                      context,
                      lt("缓存"),
                      '${formatBytes(s.images.cacheBytes)}'
                      '${img != null ? lt('  ·  解码 {0}px', [img.decodedWidth]) : ''}',
                    ),
                    if (s.showExif && img != null)
                      _line(context, lt("方向"), 'EXIF ${img.orientation}'),
                  ],
                ),
              ),
              // —— EXIF 详情（点 EXIF 按钮展开）——
              if (s.showExif) _exifSection(context),
              const SizedBox(height: 9),
              // —— 目录 + 进度 ——
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 13),
                child: Text(
                  s.folder.directory ?? '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelSmall
                      ?.copyWith(color: scheme.outline.withValues(alpha: 0.8)),
                ),
              ),
              const SizedBox(height: 9),
              Padding(
                padding: const EdgeInsets.fromLTRB(13, 0, 13, 11),
                child: Row(
                  children: [
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(2),
                        child: SizedBox(
                          height: 3,
                          child: LinearProgressIndicator(
                            value: progress,
                            backgroundColor: scheme.onSurface.withValues(
                              alpha: 0.09,
                            ),
                            valueColor: AlwaysStoppedAnimation<Color>(
                              scheme.primary,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 9),
                    Text(
                      '${s.folder.index + 1} / ${s.folder.count}',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                        fontFeatures: const [ui.FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _exifSection(BuildContext context) => MetadataPanel(
    key: ValueKey(state.folder.currentPath),
    data: state.exifData,
  );

  Widget _line(
    BuildContext context,
    String k,
    String v, {
    bool highlight = false,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 52,
            child: Text(
              k,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: highlight ? scheme.primary : scheme.outline,
              ),
            ),
          ),
          Expanded(
            child: Text(
              v,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: highlight ? scheme.primary : scheme.onSurface,
                fontFeatures: const [ui.FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ExifToggle extends StatelessWidget {
  const _ExifToggle({required this.state});
  final ViewerState state;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final on = state.showExif;
    return Tooltip(
      message: on ? lt("收起元数据") : lt("展开元数据"),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: state.toggleExif,
          child: Container(
            padding: const EdgeInsets.fromLTRB(6, 2, 3, 2),
            decoration: BoxDecoration(
              color: on
                  ? scheme.primary.withValues(alpha: 0.16)
                  : scheme.onSurface.withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(5),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'EXIF / XMP',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: on ? scheme.primary : scheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Icon(
                  on ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                  size: 14,
                  color: on ? scheme.primary : scheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MiniIconButton extends StatefulWidget {
  const _MiniIconButton({
    required this.icon,
    required this.onTap,
    required this.tooltip,
  });
  final IconData icon;
  final VoidCallback onTap;
  final String tooltip;

  @override
  State<_MiniIconButton> createState() => _MiniIconButtonState();
}

class _MiniIconButtonState extends State<_MiniIconButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: widget.tooltip,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(
              color: _hover
                  ? scheme.onSurface.withValues(alpha: 0.09)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(5),
            ),
            child: Icon(
              widget.icon,
              size: 13,
              color: scheme.onSurface.withValues(alpha: 0.7),
            ),
          ),
        ),
      ),
    );
  }
}
