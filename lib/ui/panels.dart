import '../l10n/strings.dart';

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/app_action.dart';
import '../services/image_service.dart';
import '../state/viewer_state.dart';
import 'widgets.dart';

/// 缩略图（列表 / 网格共用）
class Thumb extends StatefulWidget {
  const Thumb({
    super.key,
    required this.state,
    required this.path,
    required this.size,
  });
  final ViewerState state;
  final String path;
  final double size;

  @override
  State<Thumb> createState() => _ThumbState();
}

class _ThumbState extends State<Thumb> {
  DecodedImage? _img;

  @override
  void initState() {
    super.initState();
    _img = widget.state.images.cached(widget.path);
    if (_img == null) _load();
  }

  Future<void> _load() async {
    try {
      final img = await widget.state.images.load(
        widget.path,
        targetWidth: (widget.size * widget.state.devicePixelRatio).round(),
      );
      if (mounted) setState(() => _img = img);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final img = _img;
    if (img == null || img.disposed) {
      if (img != null && img.disposed) {
        _img = null;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _load();
        });
      }
      return Container(
        color: Theme.of(context).colorScheme.surfaceContainerHighest
            .withValues(alpha: 0.4),
      );
    }
    return RawImage(
      image: img.frames.first.image,
      fit: BoxFit.cover,
      filterQuality: FilterQuality.low,
    );
  }
}

/// 底部缩略图栏
class Filmstrip extends StatefulWidget {
  const Filmstrip({super.key, required this.state});
  final ViewerState state;

  @override
  State<Filmstrip> createState() => _FilmstripState();
}

class _FilmstripState extends State<Filmstrip> {
  final ScrollController _controller = ScrollController();
  int _lastIndex = -1;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _ensureVisible() {
    final s = widget.state;
    if (s.folder.index == _lastIndex || !_controller.hasClients) return;
    _lastIndex = s.folder.index;
    final itemW = s.settings.filmstripHeight * 0.9;
    final target = (_lastIndex * itemW) - (s.viewport.width / 2) + itemW / 2;
    _controller.animateTo(
      target.clamp(0, math.max(0, _controller.position.maxScrollExtent)),
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.state;
    final scheme = Theme.of(context).colorScheme;
    final h = s.settings.filmstripHeight;
    WidgetsBinding.instance.addPostFrameCallback((_) => _ensureVisible());
    return Container(
      height: h,
      decoration: BoxDecoration(
        color:
            (scheme.brightness == Brightness.dark
                    ? const Color(0xFF17181B)
                    : Colors.white)
                .withValues(alpha: 0.9),
        border: Border(top: BorderSide(color: scheme.outlineVariant)),
      ),
      child: ListView.builder(
        controller: _controller,
        scrollDirection: Axis.horizontal,
        itemCount: s.folder.count,
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        itemBuilder: (context, i) {
          final e = s.folder.entries[i];
          final selected = i == s.folder.index;
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3),
            child: GestureDetector(
              onTap: () => s.goToIndex(i),
              child: Container(
                width: h * 0.9,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                    color: selected ? scheme.primary : Colors.transparent,
                    width: 2,
                  ),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Thumb(state: s, path: e.path, size: h * 1.4),
                      if (s.marks.isMarked(e.path))
                        const Positioned(
                          right: 2,
                          top: 2,
                          child: Icon(
                            Icons.star,
                            size: 12,
                            color: Colors.amber,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// 网格总览
class GridOverview extends StatelessWidget {
  const GridOverview({super.key, required this.state});
  final ViewerState state;

  @override
  Widget build(BuildContext context) {
    final s = state;
    final scheme = Theme.of(context).colorScheme;
    return Container(
      color: scheme.surface.withValues(alpha: 0.97),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                Text(
                  lt("{0} 张图片", [s.folder.count]),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const Spacer(),
                IconButton(
                  iconSize: 18,
                  onPressed: () => s.invoke(AppAction.toggleGrid),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),
          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.all(8),
              gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: s.settings.thumbSize,
                mainAxisSpacing: 6,
                crossAxisSpacing: 6,
              ),
              itemCount: s.folder.count,
              itemBuilder: (context, i) {
                final e = s.folder.entries[i];
                final selected = i == s.folder.index;
                return GestureDetector(
                  onTap: () {
                    s.goToIndex(i);
                    s.invoke(AppAction.toggleGrid);
                  },
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: selected
                            ? scheme.primary
                            : scheme.outlineVariant,
                        width: selected ? 2 : 1,
                      ),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(5),
                      child: Thumb(
                        state: s,
                        path: e.path,
                        size: s.settings.thumbSize * 1.5,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// 中间浮层提示
class Hud extends StatelessWidget {
  const Hud({super.key, required this.message});
  final String? message;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 140),
        opacity: message == null ? 0 : 1,
        child: Align(
          alignment: const Alignment(0, 0.82),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.72),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              message ?? '',
              style: const TextStyle(color: Colors.white, fontSize: 12.5),
            ),
          ),
        ),
      ),
    );
  }
}

/// 快捷键帮助
class HelpSheet extends StatelessWidget {
  const HelpSheet({super.key, required this.state});
  final ViewerState state;

  @override
  Widget build(BuildContext context) {
    final s = state;
    final scheme = Theme.of(context).colorScheme;
    final groups = <ActionGroup, List<AppAction>>{};
    for (final a in AppAction.values) {
      groups.putIfAbsent(a.group, () => []).add(a);
    }
    return Dialog(
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: 760,
        height: 580,
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(16, 13, 10, 13),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: scheme.outlineVariant),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.keyboard_outlined,
                    size: 17,
                    color: scheme.primary,
                  ),
                  const SizedBox(width: 9),
                  Text(
                    lt("快捷键"),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(width: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: scheme.primary.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(5),
                    ),
                    child: Text(
                      s.mode.label,
                      style: Theme.of(context).textTheme.labelSmall
                          ?.copyWith(color: scheme.primary),
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    iconSize: 18,
                    tooltip: lt("关闭"),
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Scrollbar(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 18),
                  children: [
                    for (final g in groups.entries)
                      _group(context, g.key, g.value, s),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _group(
    BuildContext context,
    ActionGroup group,
    List<AppAction> actions,
    ViewerState s,
  ) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: scheme.onSurface.withValues(alpha: 0.03),
        border: Border.all(color: scheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            group.label,
            style: Theme.of(context).textTheme.titleSmall
                ?.copyWith(color: scheme.primary),
          ),
          const SizedBox(height: 8),
          // 两列排版，不再是一条条拉得很长
          Wrap(
            spacing: 18,
            runSpacing: 4,
            children: [
              for (final a in actions)
                SizedBox(
                  width: 330,
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          a.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ),
                      const SizedBox(width: 8),
                      if (s.settings.chordLabel(a, s.mode).isEmpty)
                        Text(
                          '—',
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(color: scheme.outline),
                        )
                      else
                        KeyCapLabel(s.settings.chordLabel(a, s.mode)),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
