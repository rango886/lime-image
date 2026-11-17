import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../batch/batch_state.dart';
import '../../batch/engine/convert_engine.dart' show kAlignWarning;
import '../../core/platform_ops.dart';
import '../../core/utils.dart';
import '../../l10n/strings.dart';
import '../../services/image_service.dart';
import '../widgets.dart';

Future<void> pickFilesInto(BatchState s) async {
  final files = await openFiles(
    acceptedTypeGroups: [
      XTypeGroup(
        label: lt('图片'),
        extensions: kKnownImageExtensions.map((e) => e.substring(1)).toList(),
      ),
    ],
  );
  if (files.isNotEmpty) await s.addPaths(files.map((f) => f.path).toList());
}

Future<void> pickFolderInto(BatchState s) async {
  final dir = await getDirectoryPath();
  if (dir != null) await s.addPaths([dir]);
}

/// 左栏：待转换的文件
class BatchFileList extends StatefulWidget {
  const BatchFileList({super.key, required this.state, required this.images});
  final BatchState state;
  final ImageService images;

  @override
  State<BatchFileList> createState() => _BatchFileListState();
}

class _BatchFileListState extends State<BatchFileList> {
  final ScrollController _scroll = ScrollController();
  static const double _rowH = 34;
  int _lastSelected = -1;

  BatchState get s => widget.state;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _ensureVisible(List<BatchItem> list) {
    final cur = s.current;
    if (cur == null || !_scroll.hasClients) return;
    if (s.selected == _lastSelected) return;
    _lastSelected = s.selected;
    final i = list.indexOf(cur);
    if (i < 0) return;
    final top = i * _rowH;
    final view = _scroll.position.viewportDimension;
    final off = _scroll.offset;
    if (top < off) {
      _scroll.jumpTo(top);
    } else if (top + _rowH > off + view) {
      _scroll.jumpTo(top + _rowH - view);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final list = s.visibleItems;
    WidgetsBinding.instance.addPostFrameCallback((_) => _ensureVisible(list));

    return Column(
      children: [
        SizedBox(
          height: 40,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Row(
              children: [
                IconButton(
                  tooltip: lt('添加图片'),
                  iconSize: 18,
                  icon: const Icon(Icons.add_photo_alternate_outlined),
                  onPressed: s.running ? null : () => pickFilesInto(s),
                ),
                IconButton(
                  tooltip: lt('添加文件夹'),
                  iconSize: 18,
                  icon: const Icon(Icons.create_new_folder_outlined),
                  onPressed: s.running ? null : () => pickFolderInto(s),
                ),
                const Spacer(),
                if (s.failedCount > 0 || s.onlyFailed)
                  Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: LimeChip(
                      label: lt('失败 {0}', [s.failedCount]),
                      selected: s.onlyFailed,
                      dim: !s.onlyFailed,
                      onTap: () => s.setOnlyFailed(!s.onlyFailed),
                    ),
                  ),
                _ListMenu(state: s),
              ],
            ),
          ),
        ),
        Divider(height: 1, color: scheme.outlineVariant),
        Expanded(
          child: list.isEmpty
              ? _Empty(state: s)
              : Scrollbar(
                  controller: _scroll,
                  child: ListView.builder(
                    controller: _scroll,
                    itemExtent: _rowH,
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    itemCount: list.length,
                    itemBuilder: (context, i) => _Row(
                      state: s,
                      item: list[i],
                      images: widget.images,
                      selected: identical(list[i], s.current),
                    ),
                  ),
                ),
        ),
        Divider(height: 1, color: scheme.outlineVariant),
        SizedBox(
          height: 30,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                Text(
                  s.checkedCount == s.items.length
                      ? lt('{0} 张', [s.items.length])
                      : lt('{0} / {1} 张', [s.checkedCount, s.items.length]),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: scheme.outline,
                  ),
                ),
                const Spacer(),
                Text(
                  formatBytes(s.totalBytes),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: scheme.outline,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.state});
  final BatchState state;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.photo_library_outlined, size: 30, color: scheme.outline),
          const SizedBox(height: 10),
          Text(
            state.onlyFailed ? lt('没有失败的文件') : lt('拖入图片或文件夹'),
            style: Theme.of(context).textTheme.bodyMedium
                ?.copyWith(color: scheme.outline),
          ),
        ],
      ),
    );
  }
}

class _ListMenu extends StatelessWidget {
  const _ListMenu({required this.state});
  final BatchState state;

  @override
  Widget build(BuildContext context) {
    final s = state;
    Widget item(String label, VoidCallback? onTap, {IconData? icon}) =>
        MenuItemButton(
          onPressed: onTap,
          leadingIcon: Icon(icon, size: 15),
          child: Text(label),
        );
    return MenuAnchor(
      menuChildren: [
        MenuItemButton(
          onPressed: s.running ? null : () => s.setRecursive(!s.recursive),
          leadingIcon: Icon(
            s.recursive ? Icons.check_box : Icons.check_box_outline_blank,
            size: 15,
          ),
          child: Text(lt('包含子文件夹')),
        ),
        const Divider(height: 9),
        item(lt('全选'), () => s.setAllChecked(true), icon: Icons.done_all),
        item(lt('全不选'), () => s.setAllChecked(false), icon: Icons.remove_done),
        const Divider(height: 9),
        item(
          lt('按名称排序'),
          () => s.sortBy((a, b) => naturalCompare(a.path, b.path)),
          icon: Icons.sort_by_alpha,
        ),
        item(
          lt('按大小排序'),
          () => s.sortBy((a, b) => b.size.compareTo(a.size)),
          icon: Icons.sort,
        ),
        const Divider(height: 9),
        item(
          lt('移除已完成'),
          s.running ? null : s.removeFinished,
          icon: Icons.playlist_remove,
        ),
        item(
          lt('清空列表'),
          s.running ? null : s.clear,
          icon: Icons.delete_sweep_outlined,
        ),
      ],
      builder: (context, controller, _) => IconButton(
        iconSize: 18,
        icon: const Icon(Icons.more_horiz),
        onPressed: () =>
            controller.isOpen ? controller.close() : controller.open(),
      ),
    );
  }
}

class _Row extends StatefulWidget {
  const _Row({
    required this.state,
    required this.item,
    required this.images,
    required this.selected,
  });
  final BatchState state;
  final BatchItem item;
  final ImageService images;
  final bool selected;

  @override
  State<_Row> createState() => _RowState();
}

class _RowState extends State<_Row> {
  bool _hover = false;
  final MenuController _menu = MenuController();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final s = widget.state;
    final it = widget.item;
    final sel = widget.selected;

    return MenuAnchor(
      controller: _menu,
      menuChildren: [
        MenuItemButton(
          onPressed: () => PlatformOps.revealInFileManager(it.path),
          leadingIcon: const Icon(Icons.folder_open_outlined, size: 15),
          child: Text(lt('打开所在文件夹')),
        ),
        if (it.outPath != null)
          MenuItemButton(
            onPressed: () => PlatformOps.revealInFileManager(it.outPath!),
            leadingIcon: const Icon(Icons.drive_file_move_outlined, size: 15),
            child: Text(lt('打开输出文件')),
          ),
        if (s.cropOverrideFor(it.path) != null)
          MenuItemButton(
            onPressed: () => s.clearCropOverride(it.path),
            leadingIcon: const Icon(Icons.crop_free, size: 15),
            child: Text(lt('恢复默认裁切')),
          ),
        MenuItemButton(
          onPressed: s.running ? null : () => s.remove(it),
          leadingIcon: const Icon(Icons.close, size: 15),
          child: Text(lt('从列表移除')),
        ),
      ],
      child: MouseRegion(
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => s.select(s.items.indexOf(it)),
          onSecondaryTapDown: (d) {
            s.select(s.items.indexOf(it));
            _menu.open(position: d.localPosition);
          },
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 4),
            padding: const EdgeInsets.only(left: 2, right: 8),
            decoration: BoxDecoration(
              color: sel
                  ? scheme.primary.withValues(alpha: 0.12)
                  : _hover
                  ? scheme.onSurface.withValues(alpha: 0.04)
                  : null,
              borderRadius: BorderRadius.circular(5),
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 28,
                  child: Transform.scale(
                    scale: 0.78,
                    child: Checkbox(
                      value: it.checked,
                      visualDensity: VisualDensity.compact,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      onChanged: s.running
                          ? null
                          : (v) => s.toggleChecked(it, v),
                    ),
                  ),
                ),
                _Thumb(path: it.path, images: widget.images),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    it.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: !it.checked
                          ? scheme.outline
                          : sel
                          ? scheme.primary
                          : scheme.onSurface,
                      fontWeight: sel ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                ),
                if (s.cropOverrideFor(it.path) != null)
                  Padding(
                    padding: const EdgeInsets.only(left: 4),
                    child: Icon(Icons.crop, size: 12, color: scheme.primary),
                  ),
                const SizedBox(width: 6),
                _Trailing(item: it),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Trailing extends StatelessWidget {
  const _Trailing({required this.item});
  final BatchItem item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final small = theme.textTheme.labelSmall?.copyWith(
      color: scheme.outline,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    switch (item.status) {
      case ItemStatus.pending:
        return Text(formatBytes(item.size), style: small);
      case ItemStatus.running:
        return SizedBox(
          width: 12,
          height: 12,
          child: CircularProgressIndicator(
            strokeWidth: 1.6,
            color: scheme.primary,
          ),
        );
      case ItemStatus.done:
        final warn = item.message == kAlignWarning;
        return Tooltip(
          message: item.outPath == null
              ? ''
              : '${p.basename(item.outPath!)}\n'
                    '${formatBytes(item.size)} → ${formatBytes(item.outSize)}'
                    '${item.message == null ? '' : '\n${lt(item.message!)}'}',
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(formatBytes(item.outSize), style: small),
              const SizedBox(width: 4),
              warn
                  ? Icon(
                      Icons.warning_amber_rounded,
                      size: 13,
                      color: Colors.orange.shade700,
                    )
                  : Icon(Icons.check_circle, size: 13, color: scheme.primary),
            ],
          ),
        );
      case ItemStatus.skipped:
        return Tooltip(
          message: lt(item.message ?? '已跳过'),
          child: Icon(
            Icons.remove_circle_outline,
            size: 13,
            color: scheme.outline,
          ),
        );
      case ItemStatus.failed:
        return Tooltip(
          message: lt(item.message ?? ''),
          child: Icon(Icons.error_outline, size: 14, color: scheme.error),
        );
    }
  }
}

class _Thumb extends StatefulWidget {
  const _Thumb({required this.path, required this.images});
  final String path;
  final ImageService images;

  @override
  State<_Thumb> createState() => _ThumbState();
}

class _ThumbState extends State<_Thumb> {
  DecodedImage? _img;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(_Thumb old) {
    super.didUpdateWidget(old);
    if (old.path != widget.path) {
      _img = null;
      _load();
    }
  }

  Future<void> _load() async {
    final path = widget.path;
    _img = widget.images.cached(path);
    if (_img != null) return;
    try {
      final img = await widget.images.load(path, targetWidth: 64);
      if (mounted && widget.path == path) setState(() => _img = img);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final img = _img;
    Widget child;
    if (img == null || img.disposed) {
      child = ColoredBox(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
      );
    } else {
      child = RotatedBox(
        quarterTurns: switch (img.orientation) {
          6 || 5 => 1,
          3 || 4 => 2,
          8 || 7 => 3,
          _ => 0,
        },
        child: RawImage(
          image: img.image,
          fit: BoxFit.cover,
          filterQuality: FilterQuality.low,
        ),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(3),
      child: SizedBox(width: 24, height: 24, child: child),
    );
  }
}
