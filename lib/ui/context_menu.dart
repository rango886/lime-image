import '../l10n/strings.dart';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../models/app_action.dart';
import '../models/enums.dart';
import '../state/viewer_state.dart';

/// 右键菜单：任意位置右键弹出，左侧功能名，右侧快捷键
class ContextMenuRegion extends StatefulWidget {
  const ContextMenuRegion({
    super.key,
    required this.state,
    required this.child,
  });
  final ViewerState state;
  final Widget child;

  /// 当前活的右键菜单（方便 Esc 等全局逻辑关菜单）
  static bool get menuOpen => _current?.isOpen ?? false;

  static void closeMenu() => _current?.close();

  @override
  State<ContextMenuRegion> createState() => _ContextMenuRegionState();
}

/// 当前挂载的菜单（库内部）
_ContextMenuRegionState? _current;

class _ContextMenuRegionState extends State<ContextMenuRegion> {
  final MenuController _controller = MenuController();
  Offset _position = Offset.zero;

  ViewerState get s => widget.state;

  bool get isOpen => _controller.isOpen;

  void close() {
    if (_controller.isOpen) _controller.close();
  }

  @override
  void initState() {
    super.initState();
    _current = this;
  }

  @override
  void dispose() {
    if (_current == this) _current = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 子内容故意放在 MenuAnchor 外面：否则整个画布都算“菜单内部”，
    // 在画布上点击就关不掉菜单。
    return Stack(
      children: [
        Positioned.fill(
          child: Listener(
            behavior: HitTestBehavior.translucent,
            onPointerDown: (e) {
              // 左键 / 中键点其他地方：先关菜单
              if (_controller.isOpen && e.buttons != kSecondaryMouseButton) {
                _controller.close();
              }
            },
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onSecondaryTapDown: (d) {
                _position = d.localPosition;
                if (_controller.isOpen) _controller.close();
                _controller.open(position: _position);
              },
              child: widget.child,
            ),
          ),
        ),
        Positioned(
          left: 0,
          top: 0,
          child: MenuAnchor(
            controller: _controller,
            consumeOutsideTap: true,
            menuChildren: _buildMenu(context),
            child: const SizedBox.shrink(),
          ),
        ),
      ],
    );
  }

  bool get _icons => s.settings.contextMenuIcons;

  Widget _item(AppAction action, {bool checked = false, IconData? icon}) {
    final label = s.settings.chordLabel(action, s.mode);
    return MenuItemButton(
      leadingIcon: _icons
          ? Icon(icon ?? (checked ? Icons.check : null), size: 15)
          // 关图标时不留空位，只在选中时显示对勾
          : (checked ? const Icon(Icons.check, size: 15) : null),
      trailingIcon: label.isEmpty
          ? null
          : Padding(
              padding: const EdgeInsets.only(left: 18),
              child: Text(
                label,
                style: Theme.of(context).textTheme.labelSmall
                    ?.copyWith(color: Theme.of(context).colorScheme.outline),
              ),
            ),
      onPressed: () {
        _controller.close();
        s.invoke(action);
      },
      child: Text(action.label),
    );
  }

  Widget _sub(String label, IconData icon, List<Widget> children) {
    return SubmenuButton(
      leadingIcon: _icons ? Icon(icon, size: 15) : null,
      menuChildren: children,
      child: Text(label),
    );
  }

  Widget get _divider => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
    child: Divider(
      height: 1,
      color: Theme.of(context).colorScheme.outlineVariant,
    ),
  );

  List<Widget> _buildMenu(BuildContext context) {
    final modeActions = <AppAction>[
      AppAction.mode1,
      AppAction.mode2,
      AppAction.mode3,
      AppAction.mode4,
      AppAction.mode5,
      AppAction.mode6,
      AppAction.mode7,
      AppAction.mode8,
    ];
    return [
      _item(AppAction.openFile, icon: Icons.folder_open),
      _item(AppAction.openFolder, icon: Icons.folder_copy_outlined),
      _item(AppAction.revealInFolder, icon: Icons.launch),
      _divider,
      _sub(lt("查看方式"), Icons.view_carousel_outlined, [
        for (var i = 0; i < modeActions.length; i++)
          _item(modeActions[i], checked: s.mode == ViewMode.values[i]),
      ]),
      _sub(lt("缩放"), Icons.zoom_in, [
        _item(AppAction.zoomIn),
        _item(AppAction.zoomOut),
        _item(AppAction.zoomOriginal),
        _item(AppAction.zoomFit),
      ]),
      _sub(lt("图像"), Icons.rotate_right, [
        _item(AppAction.rotateCW),
        _item(AppAction.rotateCCW),
        _item(AppAction.flipHorizontal),
        _item(AppAction.flipVertical),
        _item(AppAction.resetTransform),
      ]),
      _sub(lt("排序"), Icons.sort, [
        _item(
          AppAction.sortNameAsc,
          checked:
              s.settings.sortField == SortField.name &&
              s.settings.sortAscending,
        ),
        _item(
          AppAction.sortNameDesc,
          checked:
              s.settings.sortField == SortField.name &&
              !s.settings.sortAscending,
        ),
        _item(
          AppAction.sortTimeAsc,
          checked:
              s.settings.sortField == SortField.time &&
              s.settings.sortAscending,
        ),
        _item(
          AppAction.sortTimeDesc,
          checked:
              s.settings.sortField == SortField.time &&
              !s.settings.sortAscending,
        ),
        _item(
          AppAction.sortSizeAsc,
          checked:
              s.settings.sortField == SortField.size &&
              s.settings.sortAscending,
        ),
        _item(
          AppAction.sortSizeDesc,
          checked:
              s.settings.sortField == SortField.size &&
              !s.settings.sortAscending,
        ),
        _item(
          AppAction.sortRandom,
          checked: s.settings.sortField == SortField.random,
        ),
      ]),
      _sub(lt("浏览"), Icons.navigate_next, [
        _item(AppAction.nextImage),
        _item(AppAction.prevImage),
        _item(AppAction.nextSingle),
        _item(AppAction.prevSingle),
        _item(AppAction.firstImage),
        _item(AppAction.lastImage),
        _item(AppAction.reload),
      ]),
      if (s.image?.animated ?? false)
        _sub(lt("动图"), Icons.gif_box_outlined, [
          _item(AppAction.animTogglePlay, checked: s.animPlaying),
          _item(AppAction.animNextFrame),
          _item(AppAction.animPrevFrame),
          _item(AppAction.animSlower),
          _item(AppAction.animFaster),
        ]),
      _divider,
      _item(
        AppAction.toggleMark,
        // 关图标时回退到对勾表示已标记
        checked:
            s.folder.currentPath != null &&
            s.marks.isMarked(s.folder.currentPath!),
        icon:
            s.folder.currentPath != null &&
                s.marks.isMarked(s.folder.currentPath!)
            ? Icons.star_rounded
            : Icons.star_border_rounded,
      ),
      _sub(lt("文件操作"), Icons.description_outlined, [
        _item(AppAction.copyImage, icon: Icons.copy_all_outlined),
        _item(AppAction.copyPath, icon: Icons.link),
        _item(AppAction.pasteOpen, icon: Icons.content_paste_go),
        _item(AppAction.renameFile, icon: Icons.drive_file_rename_outline),
        _item(AppAction.deleteFile, icon: Icons.delete_outline),
        _item(AppAction.openWithSystem, icon: Icons.open_in_new),
        _divider,
        _item(
          AppAction.showMarked,
          checked: s.markedOnly,
          icon: s.markedOnly ? Icons.filter_alt : Icons.filter_alt_outlined,
        ),
        _item(AppAction.copyMarked, icon: Icons.file_copy_outlined),
        _item(AppAction.moveMarked, icon: Icons.drive_file_move_outlined),
      ]),
      _sub(lt("界面"), Icons.dashboard_outlined, [
        _item(AppAction.toggleStatusPanel, checked: s.showStatusPanel),
        _item(AppAction.toggleFilmstrip, checked: s.showFilmstrip),
        _item(AppAction.toggleGrid, checked: s.showGrid),
        _item(AppAction.toggleSlideshow, checked: s.slideshowActive),
        _item(AppAction.toggleTheme),
      ]),
      _sub(lt("窗口"), Icons.web_asset, [
        _item(AppAction.toggleFullscreen, checked: s.isFullscreen),
        _item(AppAction.toggleMaximize),
        _item(AppAction.minimizeWindow),
        _item(AppAction.toggleAlwaysOnTop, checked: s.alwaysOnTop),
        _item(AppAction.fitWindowToImage),
        _item(AppAction.closeWindow),
      ]),
      _divider,
      _item(AppAction.openSettings, icon: Icons.settings_outlined),
      _item(AppAction.showHelp, icon: Icons.help_outline),
    ];
  }
}
