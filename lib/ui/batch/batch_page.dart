import 'dart:async';
import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

import '../../batch/batch_state.dart';
import '../../batch/convert_preset.dart';
import '../../core/platform_ops.dart';
import '../../l10n/strings.dart';
import '../../models/settings.dart';
import '../../services/image_service.dart';
import '../title_bar.dart';
import 'batch_file_list.dart';
import 'batch_options.dart';
import 'batch_preview.dart';

/// 批量转换窗口：左文件列表 / 中预览 / 右参数，底部操作栏
class BatchPage extends StatefulWidget {
  const BatchPage({
    super.key,
    required this.state,
    required this.images,
    required this.settings,
  });

  final BatchState state;
  final ImageService images;
  final Settings settings;

  @override
  State<BatchPage> createState() => _BatchPageState();
}

class _BatchPageState extends State<BatchPage> {
  final FocusNode _focus = FocusNode();
  bool _dragging = false;
  bool _listOpen = false;
  double _sidebarWidth = 320;

  BatchState get s => widget.state;

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  bool _quitting = false;

  /// 主动退出。不用 windowManager.close()：它只是往窗口投递 SC_CLOSE，
  /// 在关闭按钮「按下即响应」时这条消息会被吞掉，窗口关不掉。
  /// 跟看图主窗口一样：先藏窗、写盘、释放端口，再 destroy + exit。
  Future<void> _quit() async {
    if (_quitting) return;
    _quitting = true;
    // 底线：万一后面哪一步卡住，也保证进程退出
    Timer(const Duration(milliseconds: 1200), () => exit(0));
    try {
      await windowManager.hide();
    } catch (_) {}
    try {
      await s.shutdown();
    } catch (_) {}
    try {
      await SingleInstance.release();
    } catch (_) {}
    try {
      await windowManager.destroy();
    } catch (_) {}
    exit(0);
  }

  Future<void> _start() async {
    if (s.running || s.checkedCount == 0) return;
    if (s.preset.place == OutputPlace.custom &&
        s.preset.customDir.trim().isEmpty) {
      s.update((p) => p.place = OutputPlace.subfolder);
    }
    final sum = await s.start();
    if (sum == null || sum.cancelled) return;
    switch (s.preset.afterRun) {
      case AfterRun.nothing:
        break;
      case AfterRun.openFolder:
        if (sum.lastDir != null) await openFolder(sum.lastDir!);
      case AfterRun.close:
        if (sum.failed == 0) await _quit();
    }
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    // 文本框里打字时不抢键
    final primary = FocusManager.instance.primaryFocus;
    if (primary != null &&
        primary != _focus &&
        primary.context?.findAncestorWidgetOfExactType<EditableText>() !=
            null) {
      return KeyEventResult.ignored;
    }
    final k = e.logicalKey;
    final ctrl = HardwareKeyboard.instance.isControlPressed;
    if (k == LogicalKeyboardKey.arrowDown) {
      s.selectRelative(1);
    } else if (k == LogicalKeyboardKey.arrowUp) {
      s.selectRelative(-1);
    } else if (e is KeyRepeatEvent) {
      return KeyEventResult.ignored;
    } else if (k == LogicalKeyboardKey.space && s.current != null) {
      if (!s.running) s.toggleChecked(s.current!);
    } else if (k == LogicalKeyboardKey.delete && s.current != null) {
      s.remove(s.current!);
    } else if (k == LogicalKeyboardKey.digit1) {
      s.setPreviewMode(PreviewMode.original);
    } else if (k == LogicalKeyboardKey.digit2) {
      s.setPreviewMode(PreviewMode.result);
    } else if (k == LogicalKeyboardKey.digit3) {
      s.setPreviewMode(PreviewMode.sideBySide);
    } else if (k == LogicalKeyboardKey.keyZ) {
      s.toggleZoom();
    } else if (ctrl && k == LogicalKeyboardKey.enter) {
      unawaited(_start());
    } else if (ctrl && k == LogicalKeyboardKey.keyS) {
      if (s.presetName != null && s.dirty) s.savePreset();
    } else if (k == LogicalKeyboardKey.escape) {
      if (s.running) {
        s.cancel();
      } else if (s.summary != null) {
        s.dismissSummary();
      } else {
        _quit();
      }
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Focus(
      focusNode: _focus,
      autofocus: true,
      onKeyEvent: _onKey,
      child: DropTarget(
        onDragEntered: (_) => setState(() => _dragging = true),
        onDragExited: (_) => setState(() => _dragging = false),
        onDragDone: (d) async {
          setState(() => _dragging = false);
          if (s.running) return;
          await s.addPaths(d.files.map((f) => f.path).toList());
          _focus.requestFocus();
        },
        child: ListenableBuilder(
          listenable: s,
          builder: (context, _) => Stack(
            children: [
              Container(
                color: scheme.surface,
                child: Column(
                  children: [
                    _titleBar(context),
                    Expanded(child: _body(context)),
                    _BottomBar(state: s, onStart: _start),
                  ],
                ),
              ),
              if (_dragging)
                Positioned.fill(
                  child: IgnorePointer(
                    child: Container(
                      margin: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: scheme.primary.withValues(alpha: 0.06),
                        border: Border.all(color: scheme.primary, width: 2),
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _body(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final border = BorderSide(color: scheme.outlineVariant);
    return LayoutBuilder(
      builder: (context, c) {
        final narrow = c.maxWidth < 1200;
        const dividerWidth = 8.0;
        final maxSidebarWidth =
            (c.maxWidth - 340 - dividerWidth - (narrow ? 0 : 480)).clamp(
              280.0,
              560.0,
            );
        final sidebarWidth = _sidebarWidth.clamp(280.0, maxSidebarWidth);
        final list = SizedBox(
          width: sidebarWidth,
          child: BatchFileList(state: s, images: widget.images),
        );
        final sidebar = ColoredBox(
          color: scheme.surface,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              list,
              MouseRegion(
                cursor: SystemMouseCursors.resizeLeftRight,
                child: GestureDetector(
                  key: const ValueKey('batch-sidebar-resizer'),
                  behavior: HitTestBehavior.opaque,
                  onDoubleTap: () => setState(() => _sidebarWidth = 320),
                  onHorizontalDragUpdate: (d) => setState(() {
                    _sidebarWidth = (sidebarWidth + d.delta.dx).clamp(
                      280.0,
                      maxSidebarWidth,
                    );
                  }),
                  child: SizedBox(
                    width: dividerWidth,
                    height: double.infinity,
                    child: Center(
                      child: Container(width: 1, color: scheme.outlineVariant),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
        final center = Column(
          children: [
            Expanded(
              child: BatchPreview(
                state: s,
                background: widget.settings.background,
              ),
            ),
            if (s.preview != null)
              ConstrainedBox(
                constraints: BoxConstraints(maxHeight: c.maxHeight * 0.45),
                child: SingleChildScrollView(child: BatchInfoPanel(state: s)),
              ),
          ],
        );
        final options = Container(
          width: 340,
          decoration: BoxDecoration(border: Border(left: border)),
          child: BatchOptions(state: s),
        );
        if (!narrow) {
          return Row(
            children: [
              sidebar,
              Expanded(child: center),
              options,
            ],
          );
        }
        return Row(
          children: [
            Expanded(
              child: Stack(
                children: [
                  Positioned.fill(child: center),
                  if (_listOpen)
                    Positioned(
                      left: 0,
                      top: 0,
                      bottom: 0,
                      child: Material(elevation: 8, child: sidebar),
                    ),
                ],
              ),
            ),
            options,
          ],
        );
      },
    );
  }

  Widget _titleBar(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = scheme.brightness == Brightness.dark;
    final h = widget.settings.titleBarHeight;
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
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onPanStart: (_) => windowManager.startDragging(),
                onDoubleTap: _toggleMaximize,
                child: Row(
                  children: [
                    const SizedBox(width: 12),
                    Icon(Icons.transform, size: 16, color: scheme.primary),
                    const SizedBox(width: 8),
                    Text(
                      lt('批量转换'),
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const Spacer(),
                  ],
                ),
              ),
            ),
            LayoutBuilder(
              builder: (context, c) => MediaQuery.sizeOf(context).width < 1200
                  ? WinButton(
                      icon: _listOpen ? Icons.menu_open : Icons.menu,
                      tooltip: lt('文件列表'),
                      onTap: () => setState(() => _listOpen = !_listOpen),
                    )
                  : const SizedBox.shrink(),
            ),
            WinButton(
              icon: Icons.remove,
              tooltip: lt('最小化'),
              onTap: windowManager.minimize,
            ),
            WinButton(
              icon: Icons.crop_square,
              tooltip: lt('最大化 / 还原'),
              onTap: _toggleMaximize,
            ),
            WinButton(
              icon: Icons.close,
              tooltip: lt('关闭'),
              danger: true,
              onTap: _quit,
            ),
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
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({required this.state, required this.onStart});
  final BatchState state;
  final VoidCallback onStart;

  String _fmt(Duration d) {
    final m = d.inMinutes;
    final sec = d.inSeconds % 60;
    return '$m:${sec.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final s = state;
    Widget left;
    if (s.running) {
      final eta = s.eta;
      left = Row(
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: s.runTotal == 0 ? 0 : s.runDone / s.runTotal,
                minHeight: 5,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            '${s.runDone} / ${s.runTotal}'
            '${eta == null ? '' : '   ${_fmt(eta)}'}',
            style: theme.textTheme.labelMedium?.copyWith(
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      );
    } else {
      left = const SizedBox.shrink();
    }

    return Container(
      key: const ValueKey('batch-action-bar'),
      height: 46,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: scheme.outlineVariant)),
      ),
      child: Row(
        children: [
          Expanded(child: left),
          const SizedBox(width: 16),
          if (s.running)
            OutlinedButton(
              onPressed: s.cancelRequested ? null : s.cancel,
              child: Text(lt('取消')),
            )
          else
            FilledButton.icon(
              onPressed: s.checkedCount == 0 ? null : onStart,
              icon: const Icon(Icons.play_arrow_rounded, size: 18),
              label: Text(
                s.checkedCount == 0
                    ? lt('开始转换')
                    : lt('开始转换（{0}）', [s.checkedCount]),
              ),
            ),
        ],
      ),
    );
  }
}
