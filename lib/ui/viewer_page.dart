import '../l10n/strings.dart';

import 'dart:async';
import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

import '../core/platform_ops.dart';
import '../core/utils.dart';
import '../models/app_action.dart';
import '../models/enums.dart';
import '../models/key_chord.dart';
import '../state/viewer_state.dart';
import 'comic_view.dart';
import 'context_menu.dart';
import 'image_canvas.dart';
import 'panels.dart';
import 'settings_page.dart';
import 'theme.dart';
import 'title_bar.dart';
import 'widgets.dart';

class ViewerPage extends StatefulWidget {
  const ViewerPage({super.key, required this.state});
  final ViewerState state;

  @override
  State<ViewerPage> createState() => _ViewerPageState();
}

class _ViewerPageState extends State<ViewerPage>
    with WindowListener
    implements ViewerUiDelegate {
  ViewerState get s => widget.state;

  bool _titleVisible = false;
  bool _cursorHidden = false;
  bool _showSettings = false;
  bool _dragging = false;
  bool _dialogOpen = false;
  Timer? _titleTimer;
  Timer? _cursorTimer;
  StreamSubscription<List<String>>? _openSub;
  final FocusNode _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    s.ui = this;
    windowManager.addListener(this);
    // 全局键盘钩子：不依赖焦点，中文输入法开启时也能触发
    HardwareKeyboard.instance.addHandler(_handleGlobalKey);
    _openSub = PlatformOps.openFileEvents.listen((paths) async {
      if (paths.isEmpty) return;
      await windowManager.show();
      await windowManager.focus();
      await s.open(paths.first);
    });
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    HardwareKeyboard.instance.removeHandler(_handleGlobalKey);
    _openSub?.cancel();
    _titleTimer?.cancel();
    _cursorTimer?.cancel();
    _focus.dispose();
    super.dispose();
  }

  // —— 窗口事件 ——
  @override
  void onWindowMoved() => s.persistBounds();

  @override
  void onWindowResized() => s.persistBounds();

  @override
  void onWindowMaximize() {
    s.settingsService.update((c) => c.savedMaximized = true, notify: false);
  }

  @override
  void onWindowUnmaximize() {
    s.settingsService.update((c) => c.savedMaximized = false, notify: false);
  }

  @override
  void onWindowEnterFullScreen() {
    if (!mounted) return;
    s.syncFullscreen(true);
    // 全屏后马上开始数隐藏鼠标的秒，不用等用户动鼠标
    _scheduleCursorHide();
    if (s.settings.titleBarAutoHide) _scheduleTitleHide();
  }

  @override
  void onWindowLeaveFullScreen() {
    if (!mounted) return;
    s.syncFullscreen(false);
    _cursorTimer?.cancel();
    if (_cursorHidden) setState(() => _cursorHidden = false);
  }

  @override
  void onWindowClose() {
    // 不要在这里 await，交给 requestClose 自己排队销毁，否则会卡住
    s.requestClose();
  }

  // —— 键盘（全局钩子，绕过输入法与焦点）——
  bool _handleGlobalKey(KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return false;

    final isEscape =
        event.logicalKey == LogicalKeyboardKey.escape ||
        event.physicalKey == PhysicalKeyboardKey.escape;

    // Esc 优先关掉右键菜单 / 内嵌设置面板
    if (isEscape && ContextMenuRegion.menuOpen) {
      ContextMenuRegion.closeMenu();
      return true;
    }
    if (isEscape && _showSettings) {
      setState(() => _showSettings = false);
      _focus.requestFocus();
      return true;
    }

    if (_showSettings || _dialogOpen) return false;
    // 正在输入文字（重命名框等）时不抢按键
    final primary = FocusManager.instance.primaryFocus;
    if (primary?.context?.widget is EditableText) return false;

    // 菜单开着时任何快捷键先把菜单关掉
    if (ContextMenuRegion.menuOpen) ContextMenuRegion.closeMenu();

    final keymap = s.settings.keymapFor(s.mode);
    var action = keymap[KeyChord.fromEvent(event)];
    // 中文输入法会改写 logicalKey，退回物理按键再匹配一次
    action ??= keymap[KeyChord.fromPhysical(event)];
    if (action == null) return false;
    s.invoke(action);
    return true;
  }

  // —— 标题栏 / 光标自动隐藏 ——
  void _onMouseMove(PointerHoverEvent e) {
    final zone = s.settings.titleBarHeight + 8;
    final nearTop = e.localPosition.dy <= zone;
    if (nearTop) {
      _titleTimer?.cancel();
      if (!_titleVisible) setState(() => _titleVisible = true);
    } else if (_titleVisible && s.settings.titleBarAutoHide) {
      _scheduleTitleHide();
    }
    if (_cursorHidden) setState(() => _cursorHidden = false);
    _scheduleCursorHide();
  }

  void _scheduleTitleHide() {
    if (!s.settings.titleBarAutoHide) {
      if (!_titleVisible) setState(() => _titleVisible = true);
      return;
    }
    if (_titleTimer?.isActive ?? false) return; // 已经在倒计时，不重置
    _titleTimer = Timer(
      Duration(milliseconds: s.settings.titleBarHideDelayMs),
      () {
        if (mounted && !_showSettings && !_dialogOpen) {
          setState(() => _titleVisible = false);
        }
      },
    );
  }

  void _scheduleCursorHide() {
    _cursorTimer?.cancel();
    if (!s.settings.autoHideCursorInFullscreen || !s.isFullscreen) {
      if (_cursorHidden && mounted) setState(() => _cursorHidden = false);
      return;
    }
    _cursorTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _cursorHidden = true);
    });
  }

  // —— ViewerUiDelegate ——
  @override
  Future<String?> pickImageFile() async {
    final group = XTypeGroup(
      label: lt("图片"),
      extensions: kKnownImageExtensions
          .map((e) => e.substring(1))
          .followedBy(kArchiveExtensions.map((e) => e.substring(1)))
          .toList(),
    );
    final file = await openFile(acceptedTypeGroups: [group]);
    return file?.path;
  }

  @override
  Future<String?> pickDirectory() => getDirectoryPath();

  @override
  Future<bool> confirmDelete(String name) async {
    _dialogOpen = true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(lt("删除文件")),
        content: Text(
          s.settings.deleteToTrash
              ? lt("把「{0}」移到回收站？", [name])
              : lt("永久删除「{0}」？此操作不可撤销。", [name]),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(lt("取消")),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(lt("删除")),
          ),
        ],
      ),
    );
    _dialogOpen = false;
    return ok ?? false;
  }

  @override
  Future<String?> promptRename(String currentName) async {
    final controller = TextEditingController(text: currentName);
    _dialogOpen = true;
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => ImeScope(
        child: AlertDialog(
          title: Text(lt("重命名")),
          content: TextField(
            controller: controller,
            autofocus: true,
            onSubmitted: (v) => Navigator.pop(ctx, v),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(lt("取消")),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, controller.text),
              child: Text(lt("确定")),
            ),
          ],
        ),
      ),
    );
    _dialogOpen = false;
    return result;
  }

  @override
  void openSettings() {
    if (!mounted) return;
    setState(() {
      _showSettings = true;
      _titleVisible = true;
    });
  }

  @override
  void showHelp() async {
    _dialogOpen = true;
    await showDialog(
      context: context,
      builder: (_) => HelpSheet(state: s),
    );
    _dialogOpen = false;
  }

  // —— 构建 ——
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bg = LimeTheme.canvasColor(s.settings.background, scheme);
    final hasImage = s.image != null;

    return Focus(
      focusNode: _focus,
      autofocus: true,
      child: MouseRegion(
        cursor: _cursorHidden
            ? SystemMouseCursors.none
            : SystemMouseCursors.basic,
        onHover: _onMouseMove,
        child: DropTarget(
          onDragEntered: (_) => setState(() => _dragging = true),
          onDragExited: (_) => setState(() => _dragging = false),
          onDragDone: (detail) async {
            setState(() => _dragging = false);
            if (detail.files.isEmpty) return;
            await s.open(detail.files.first.path);
            _focus.requestFocus();
          },
          child: Stack(
            children: [
              Column(
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        Expanded(
                          child: ClipRect(
                            child: Stack(
                              children: [
                                Positioned.fill(child: _background(bg)),
                                Positioned.fill(child: _content()),
                                if (s.loading)
                                  const Positioned(
                                    right: 12,
                                    bottom: 12,
                                    child: SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    ),
                                  ),
                                if (s.error != null) _errorBox(),
                                if (s.showStatusPanel &&
                                    hasImage &&
                                    !_showSettings &&
                                    !s.showGrid)
                                  _statusPanelSlot(),
                                Positioned.fill(
                                  child: Hud(message: s.hudMessage),
                                ),
                                if (_dragging)
                                  Positioned.fill(
                                    child: IgnorePointer(
                                      child: Container(
                                        color: scheme.primary.withValues(
                                          alpha: 0.12,
                                        ),
                                        child: Center(
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 18,
                                              vertical: 10,
                                            ),
                                            decoration: BoxDecoration(
                                              color: scheme.primary,
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                            ),
                                            child: Text(
                                              lt("松手打开图片"),
                                              style: TextStyle(
                                                color: scheme.onPrimary,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                if (s.showGrid)
                                  Positioned.fill(
                                    child: GridOverview(state: s),
                                  ),
                                if (_showSettings)
                                  Positioned.fill(
                                    child: ColoredBox(
                                      color: Colors.black.withValues(
                                        alpha: 0.45,
                                      ),
                                      child: Center(
                                        child: Padding(
                                          padding: EdgeInsets.fromLTRB(
                                            20,
                                            s.settings.titleBarHeight + 14,
                                            20,
                                            20,
                                          ),
                                          child: ConstrainedBox(
                                            constraints: const BoxConstraints(
                                              maxWidth: 760,
                                              maxHeight: 650,
                                            ),
                                            child: DecoratedBox(
                                              decoration: BoxDecoration(
                                                borderRadius:
                                                    BorderRadius.circular(
                                                      s.settings.cornerRadius +
                                                          2,
                                                    ),
                                                border: Border.all(
                                                  color: scheme.outlineVariant,
                                                ),
                                                boxShadow: [
                                                  BoxShadow(
                                                    color: Colors.black
                                                        .withValues(
                                                          alpha: 0.35,
                                                        ),
                                                    blurRadius: 28,
                                                    offset: const Offset(0, 10),
                                                  ),
                                                ],
                                              ),
                                              child: ClipRRect(
                                                borderRadius:
                                                    BorderRadius.circular(
                                                      s.settings.cornerRadius +
                                                          2,
                                                    ),
                                                child: SettingsPage(
                                                  state: s,
                                                  onClose: () {
                                                    setState(
                                                      () =>
                                                          _showSettings = false,
                                                    );
                                                    _focus.requestFocus();
                                                  },
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (s.showFilmstrip && s.folder.count > 0 && !_showSettings)
                    Filmstrip(state: s),
                ],
              ),
              // 标题栏浮在最上层，横跨整个窗口宽度
              Positioned(
                left: 0,
                right: 0,
                top: 0,
                child: TitleBar(
                  state: s,
                  visible: !s.settings.titleBarAutoHide || _titleVisible,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 悬浮状态窗按设置摆到四个角
  Widget _statusPanelSlot() {
    const m = 12.0;
    final corner = s.settings.statusPanelCorner;
    final top = corner == PanelCorner.topLeft || corner == PanelCorner.topRight;
    final left =
        corner == PanelCorner.topLeft || corner == PanelCorner.bottomLeft;
    return Positioned(
      top: top ? s.settings.titleBarHeight + m : null,
      bottom: top ? null : m,
      left: left ? m : null,
      right: left ? null : m,
      child: StatusPanel(state: s),
    );
  }

  Widget _background(Color bg) {
    if (s.settings.background == BackgroundStyle.checker) {
      return CustomPaint(
        painter: CheckerPainter(
          Theme.of(context).colorScheme.brightness == Brightness.dark,
        ),
      );
    }
    return ColoredBox(color: bg);
  }

  Widget _content() {
    // 常显的标题栏是不透明的，会盖住画面顶部；
    // 这时把那一条让出来，“填满窗口”才是填满真正看得见的区域。
    final reserved = s.settings.titleBarAutoHide
        ? 0.0
        : s.settings.titleBarHeight;
    return Padding(
      padding: EdgeInsets.only(top: reserved),
      child: ContextMenuRegion(
        state: s,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final size = Size(constraints.maxWidth, constraints.maxHeight);
            final dpr = MediaQuery.of(context).devicePixelRatio;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) s.setViewport(size, dpr);
            });
            if (s.image == null) {
              return EmptyState(onOpen: () => s.invoke(AppAction.openFile));
            }
            switch (s.mode) {
              case ViewMode.comic:
                return ComicView(state: s);
              case ViewMode.longStrip:
                return LongStripView(state: s);
              default:
                return ImageCanvas(state: s);
            }
          },
        ),
      ),
    );
  }

  Widget _errorBox() {
    final path = s.folder.currentPath ?? '';
    final name = path.isEmpty ? '' : path.split(Platform.pathSeparator).last;
    // 不能再用 isNativeImageFile 判定“没有解码器”：
    // 现在 WIC / ffmpeg / 内嵌预览都能接非原生格式。
    // 真正的信息在 s.error 里（UnsupportedFormatException 会列出试过哪些）。
    final err = s.error?.toString() ?? '';
    final noDecoder = err.contains('没有可用解码器');
    return Center(
      child: Container(
        margin: const EdgeInsets.all(30),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              noDecoder
                  ? Icons.extension_off_outlined
                  : Icons.broken_image_outlined,
              color: Colors.white70,
              size: 34,
            ),
            const SizedBox(height: 10),
            Text(
              noDecoder
                  ? lt("这个格式本机没有可用解码器\n{0}", [name])
                  : lt("无法打开这张图片\n{0}", [err]),
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}
