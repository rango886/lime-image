import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/platform_ops.dart';

/// 桌面风格下拉框：一行高度的按钮 + 贴着按钮弹出的紧凑菜单（不是手机端的居中转盘）
class LimeDropdown<T> extends StatefulWidget {
  const LimeDropdown({
    super.key,
    required this.value,
    required this.items,
    required this.labelOf,
    required this.onChanged,
    this.width,
    this.iconOf,
    this.enabled = true,
  });

  final T value;
  final List<T> items;
  final String Function(T) labelOf;
  final ValueChanged<T> onChanged;
  final double? width;
  final IconData? Function(T)? iconOf;
  final bool enabled;

  @override
  State<LimeDropdown<T>> createState() => _LimeDropdownState<T>();
}

class _LimeDropdownState<T> extends State<LimeDropdown<T>> {
  final MenuController _menu = MenuController();
  bool _hover = false;

  static const double _rowHeight = 28;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = scheme.brightness == Brightness.dark;

    return LayoutBuilder(
      builder: (context, constraints) {
        final avail = constraints.hasBoundedWidth
            ? constraints.maxWidth
            : double.infinity;
        var w = widget.width ?? 260.0;
        if (avail.isFinite) w = math.min(w, avail);
        final menuWidth = math.max(w, 180.0);

        return SizedBox(
          width: w,
          child: MenuAnchor(
            controller: _menu,
            consumeOutsideTap: true,
            alignmentOffset: const Offset(0, 2),
            style: MenuStyle(
              minimumSize: WidgetStatePropertyAll(Size(menuWidth, 0)),
              maximumSize: WidgetStatePropertyAll(
                Size(math.max(menuWidth, 420), 460),
              ),
              padding: const WidgetStatePropertyAll(EdgeInsets.zero),
            ),
            menuChildren: [
              for (final item in widget.items)
                _MenuRow<T>(
                  label: widget.labelOf(item),
                  icon: widget.iconOf?.call(item),
                  selected: item == widget.value,
                  width: menuWidth,
                  onTap: () {
                    _menu.close();
                    if (item != widget.value) widget.onChanged(item);
                  },
                ),
            ],
            builder: (context, controller, _) {
              final open = controller.isOpen;
              return MouseRegion(
                cursor: widget.enabled
                    ? SystemMouseCursors.click
                    : SystemMouseCursors.basic,
                onEnter: (_) => setState(() => _hover = true),
                onExit: (_) => setState(() => _hover = false),
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: !widget.enabled
                      ? null
                      : () => open ? controller.close() : controller.open(),
                  child: Container(
                    height: _rowHeight,
                    padding: const EdgeInsets.only(left: 9, right: 5),
                    decoration: BoxDecoration(
                      color: open || _hover
                          ? (dark
                                ? Colors.white.withValues(alpha: 0.09)
                                : Colors.black.withValues(alpha: 0.05))
                          : (dark
                                ? Colors.white.withValues(alpha: 0.04)
                                : Colors.black.withValues(alpha: 0.025)),
                      border: Border.all(
                        color: open
                            ? scheme.primary.withValues(alpha: 0.75)
                            : scheme.outlineVariant,
                      ),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            widget.labelOf(widget.value),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ),
                        Icon(
                          Icons.unfold_more,
                          size: 14,
                          color: scheme.outline,
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }
}

class _MenuRow<T> extends StatelessWidget {
  const _MenuRow({
    required this.label,
    required this.selected,
    required this.onTap,
    required this.width,
    this.icon,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final double width;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return MenuItemButton(
      onPressed: onTap,
      style: ButtonStyle(
        minimumSize: WidgetStatePropertyAll(Size(width - 8, 28)),
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: 8),
        ),
        backgroundColor: WidgetStateProperty.resolveWith(
          (states) => selected ? scheme.primary.withValues(alpha: 0.12) : null,
        ),
      ),
      leadingIcon: Icon(
        icon ?? (selected ? Icons.check : null),
        size: 14,
        color: selected ? scheme.primary : scheme.onSurfaceVariant,
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: selected ? scheme.primary : scheme.onSurface,
          fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
        ),
      ),
    );
  }
}

/// 需要打字的地方套一层：进入时打开系统输入法，离开时关掉，
/// 这样看图时的单键快捷键不会被中文输入法吃掉。
class ImeScope extends StatefulWidget {
  const ImeScope({super.key, required this.child});
  final Widget child;

  @override
  State<ImeScope> createState() => _ImeScopeState();
}

class _ImeScopeState extends State<ImeScope> {
  @override
  void initState() {
    super.initState();
    PlatformOps.acquireIme();
  }

  @override
  void dispose() {
    PlatformOps.releaseIme();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// 小徽章：显示快捷键
class KeyCapLabel extends StatelessWidget {
  const KeyCapLabel(this.label, {super.key});
  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: scheme.onSurface.withValues(alpha: 0.05),
        border: Border.all(color: scheme.outlineVariant),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          fontFeatures: const [FontFeature.tabularFigures()],
          color: scheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// 设置页里的分组卡片
class LimeCard extends StatelessWidget {
  const LimeCard({super.key, required this.title, required this.children});
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final radius = _radiusOf(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: scheme.brightness == Brightness.dark
            ? Colors.white.withValues(alpha: 0.035)
            : Colors.white,
        border: Border.all(color: scheme.outlineVariant),
        borderRadius: BorderRadius.circular(radius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 11, 14, 7),
            child: Text(
              title,
              style: Theme.of(context).textTheme.titleSmall
                  ?.copyWith(color: scheme.primary),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: children,
            ),
          ),
        ],
      ),
    );
  }
}

double _radiusOf(BuildContext context) {
  final shape = Theme.of(context).dialogTheme.shape;
  if (shape is RoundedRectangleBorder) {
    final r = shape.borderRadius.resolve(TextDirection.ltr).topLeft.x;
    return (r - 2).clamp(0, 24);
  }
  return 10;
}

double limeRadius(BuildContext context) => _radiusOf(context);
