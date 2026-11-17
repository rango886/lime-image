import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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

// ---------------------------------------------------------------------------
// 表单类组件：设置页 / 批量转换共用
// ---------------------------------------------------------------------------

/// 分组标题：主题色竖条 + 标题 + 横线。给了 [onToggle] 就能折叠，
/// 折叠时在横线右侧显示 [summary]。
class SectionHeader extends StatelessWidget {
  const SectionHeader(
    this.title, {
    super.key,
    this.collapsed,
    this.onToggle,
    this.summary,
    this.trailing,
  });

  final String title;
  final bool? collapsed;
  final VoidCallback? onToggle;
  final String? summary;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final folded = collapsed ?? false;
    Widget row = Row(
      children: [
        Container(
          width: 3,
          height: 13,
          decoration: BoxDecoration(
            color: scheme.primary,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 8),
        Text(title, style: theme.textTheme.titleSmall),
        const SizedBox(width: 10),
        Expanded(
          child: folded && summary != null && summary!.isNotEmpty
              ? Text(
                  summary!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.right,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: scheme.outline,
                  ),
                )
              : Divider(height: 1, color: scheme.outlineVariant),
        ),
        ?trailing,
        if (onToggle != null) ...[
          const SizedBox(width: 4),
          AnimatedRotation(
            turns: folded ? -0.25 : 0,
            duration: const Duration(milliseconds: 140),
            child: Icon(Icons.expand_more, size: 15, color: scheme.outline),
          ),
        ],
      ],
    );
    if (onToggle != null) {
      row = MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onToggle,
          child: row,
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 10),
      child: row,
    );
  }
}

/// 一行设置：左侧标题定宽，右侧控件；说明放在控件下方。
class SettingRow extends StatelessWidget {
  const SettingRow(
    this.label,
    this.control, {
    super.key,
    this.hint,
    this.labelWidth = 210,
  });

  final String label;
  final Widget control;
  final String? hint;
  final double labelWidth;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(
                width: labelWidth,
                child: Text(label, style: theme.textTheme.bodyMedium),
              ),
              Expanded(child: control),
            ],
          ),
          if (hint != null)
            Padding(
              padding: EdgeInsets.only(left: labelWidth, top: 3, bottom: 3),
              child: Text(
                hint!,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.outline,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 缩小过的开关（左对齐）
class LimeSwitch extends StatelessWidget {
  const LimeSwitch({super.key, required this.value, required this.onChanged});
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) => Align(
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
  );
}

/// 滑块 + 右侧数值
class LimeSlider extends StatelessWidget {
  const LimeSlider({
    super.key,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.unit = '',
    this.digits = 0,
    this.divisions,
    this.valueWidth = 76,
    this.onChangeEnd,
  });

  final double value;
  final double min;
  final double max;
  final ValueChanged<double>? onChanged;
  final ValueChanged<double>? onChangeEnd;
  final String unit;
  final int digits;
  final int? divisions;
  final double valueWidth;

  @override
  Widget build(BuildContext context) {
    final v = value.clamp(min, max).toDouble();
    return Row(
      children: [
        Expanded(
          child: Slider(
            value: v,
            min: min,
            max: max,
            divisions: divisions,
            onChanged: onChanged,
            onChangeEnd: onChangeEnd,
          ),
        ),
        SizedBox(
          width: valueWidth,
          child: Text(
            '${v.toStringAsFixed(digits)}$unit',
            textAlign: TextAlign.right,
            style: Theme.of(context).textTheme.labelMedium
                ?.copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
          ),
        ),
      ],
    );
  }
}

/// 小标签按钮（变量、常用值）
class LimeChip extends StatelessWidget {
  const LimeChip({
    super.key,
    required this.label,
    required this.onTap,
    this.dim = false,
    this.selected = false,
  });
  final String label;
  final VoidCallback? onTap;
  final bool dim;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          border: Border.all(
            color: selected ? scheme.primary : scheme.outlineVariant,
          ),
          borderRadius: BorderRadius.circular(4),
          color: selected
              ? scheme.primary.withValues(alpha: 0.16)
              : dim
              ? null
              : scheme.primary.withValues(alpha: 0.10),
        ),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
            color: selected
                ? scheme.primary
                : dim
                ? scheme.outline
                : scheme.onSurface,
          ),
        ),
      ),
    );
  }
}

/// 分段按钮：一排连在一起的单选，高度和 [LimeDropdown] 一致
class LimeSegmented<T> extends StatelessWidget {
  const LimeSegmented({
    super.key,
    required this.value,
    required this.items,
    required this.onChanged,
    this.labelOf,
    this.iconOf,
    this.tooltipOf,
    this.expand = true,
    this.enabled = true,
  });

  final T value;
  final List<T> items;
  final ValueChanged<T> onChanged;
  final String Function(T)? labelOf;
  final IconData Function(T)? iconOf;
  final String Function(T)? tooltipOf;
  final bool expand;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = scheme.brightness == Brightness.dark;
    final children = <Widget>[];
    for (var i = 0; i < items.length; i++) {
      final item = items[i];
      final selected = item == value;
      Widget cell = _SegmentCell(
        selected: selected,
        enabled: enabled,
        onTap: () {
          if (!selected) onChanged(item);
        },
        divider: i > 0,
        child: iconOf != null
            ? Icon(
                iconOf!(item),
                size: 15,
                color: selected ? scheme.primary : scheme.onSurfaceVariant,
              )
            : Text(
                labelOf?.call(item) ?? '$item',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: selected ? scheme.primary : scheme.onSurface,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
      );
      if (tooltipOf != null) {
        cell = Tooltip(message: tooltipOf!(item), child: cell);
      }
      children.add(expand ? Expanded(child: cell) : cell);
    }
    return Opacity(
      opacity: enabled ? 1 : 0.5,
      child: Container(
        height: 28,
        decoration: BoxDecoration(
          color: dark
              ? Colors.white.withValues(alpha: 0.04)
              : Colors.black.withValues(alpha: 0.025),
          border: Border.all(color: scheme.outlineVariant),
          borderRadius: BorderRadius.circular(6),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(5),
          child: Row(
            mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
            children: children,
          ),
        ),
      ),
    );
  }
}

class _SegmentCell extends StatefulWidget {
  const _SegmentCell({
    required this.selected,
    required this.enabled,
    required this.onTap,
    required this.divider,
    required this.child,
  });
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;
  final bool divider;
  final Widget child;

  @override
  State<_SegmentCell> createState() => _SegmentCellState();
}

class _SegmentCellState extends State<_SegmentCell> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return MouseRegion(
      cursor: widget.enabled
          ? SystemMouseCursors.click
          : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.enabled ? widget.onTap : null,
        child: Container(
          constraints: const BoxConstraints(minWidth: 32),
          padding: const EdgeInsets.symmetric(horizontal: 8),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: widget.selected
                ? scheme.primary.withValues(alpha: 0.14)
                : _hover && widget.enabled
                ? scheme.onSurface.withValues(alpha: 0.06)
                : null,
            border: widget.divider
                ? Border(left: BorderSide(color: scheme.outlineVariant))
                : null,
          ),
          child: widget.child,
        ),
      ),
    );
  }
}

/// 图标开关按钮（翻转之类的独立开关）
class LimeIconToggle extends StatelessWidget {
  const LimeIconToggle({
    super.key,
    required this.icon,
    required this.value,
    required this.onChanged,
    required this.tooltip,
  });
  final IconData icon;
  final bool value;
  final ValueChanged<bool> onChanged;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: () => onChanged(!value),
        borderRadius: BorderRadius.circular(6),
        child: Container(
          width: 32,
          height: 28,
          decoration: BoxDecoration(
            color: value ? scheme.primary.withValues(alpha: 0.14) : null,
            border: Border.all(
              color: value ? scheme.primary : scheme.outlineVariant,
            ),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Icon(
            icon,
            size: 15,
            color: value ? scheme.primary : scheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

/// 数字输入框：可带单位，滚轮调值（Shift ×10）
class LimeNumberField extends StatefulWidget {
  const LimeNumberField({
    super.key,
    required this.value,
    required this.onChanged,
    this.min = 0,
    this.max = 100000,
    this.step = 1,
    this.digits = 0,
    this.unit,
    this.width = 84,
  });

  final double value;
  final ValueChanged<double> onChanged;
  final double min;
  final double max;
  final double step;
  final int digits;
  final String? unit;
  final double width;

  @override
  State<LimeNumberField> createState() => _LimeNumberFieldState();
}

class _LimeNumberFieldState extends State<LimeNumberField> {
  late final TextEditingController _ctl = TextEditingController(
    text: _fmt(widget.value),
  );
  final FocusNode _focus = FocusNode();

  String _fmt(double v) => v.toStringAsFixed(widget.digits);

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (_focus.hasFocus) {
        PlatformOps.acquireIme();
      } else {
        PlatformOps.releaseIme();
        _commit();
      }
    });
  }

  @override
  void didUpdateWidget(LimeNumberField old) {
    super.didUpdateWidget(old);
    if (!_focus.hasFocus && _fmt(widget.value) != _ctl.text) {
      _ctl.text = _fmt(widget.value);
    }
  }

  @override
  void dispose() {
    if (_focus.hasFocus) PlatformOps.releaseIme();
    _ctl.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _commit() {
    final v = double.tryParse(_ctl.text.trim());
    if (v == null) {
      _ctl.text = _fmt(widget.value);
      return;
    }
    final c = v.clamp(widget.min, widget.max).toDouble();
    _ctl.text = _fmt(c);
    if (c != widget.value) widget.onChanged(c);
  }

  void _nudge(double delta) {
    final c = (widget.value + delta).clamp(widget.min, widget.max).toDouble();
    _ctl.text = _fmt(c);
    if (c != widget.value) widget.onChanged(c);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: widget.width,
      child: Listener(
        onPointerSignal: (e) {
          if (e is! PointerScrollEvent) return;
          final shift = HardwareKeyboard.instance.isShiftPressed;
          final dir = e.scrollDelta.dy < 0 ? 1 : -1;
          _nudge(dir * widget.step * (shift ? 10 : 1));
        },
        child: TextField(
          controller: _ctl,
          focusNode: _focus,
          style: Theme.of(context).textTheme.bodyMedium
              ?.copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
          onSubmitted: (_) => _commit(),
          decoration: InputDecoration(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 8,
              vertical: 6,
            ),
            suffixText: widget.unit,
            suffixStyle: Theme.of(context).textTheme.labelSmall
                ?.copyWith(color: scheme.outline),
          ),
        ),
      ),
    );
  }
}

/// 3×3 锚点选择（0..8，行优先）
class AnchorPicker extends StatelessWidget {
  const AnchorPicker({super.key, required this.value, required this.onChanged});
  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: 62,
      height: 62,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        border: Border.all(color: scheme.outlineVariant),
        borderRadius: BorderRadius.circular(6),
      ),
      child: GridView.count(
        crossAxisCount: 3,
        mainAxisSpacing: 2,
        crossAxisSpacing: 2,
        physics: const NeverScrollableScrollPhysics(),
        padding: EdgeInsets.zero,
        children: [
          for (var i = 0; i < 9; i++)
            MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                onTap: () => onChanged(i),
                child: Container(
                  decoration: BoxDecoration(
                    color: i == value
                        ? scheme.primary
                        : scheme.onSurface.withValues(alpha: 0.07),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 普通单行文本框：聚焦时开输入法，失焦 / 回车时提交
class LimeTextField extends StatefulWidget {
  const LimeTextField({
    super.key,
    required this.value,
    required this.onChanged,
    this.controller,
    this.hintText,
    this.live = false,
  });

  final String value;
  final ValueChanged<String> onChanged;
  final TextEditingController? controller;
  final String? hintText;

  /// true = 每次输入都回调；false = 失焦 / 回车才回调
  final bool live;

  @override
  State<LimeTextField> createState() => _LimeTextFieldState();
}

class _LimeTextFieldState extends State<LimeTextField> {
  late final TextEditingController _ctl =
      widget.controller ?? TextEditingController(text: widget.value);
  final FocusNode _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    if (widget.controller != null && _ctl.text != widget.value) {
      _ctl.text = widget.value;
    }
    _focus.addListener(() {
      if (_focus.hasFocus) {
        PlatformOps.acquireIme();
      } else {
        PlatformOps.releaseIme();
        if (!widget.live && _ctl.text != widget.value) {
          widget.onChanged(_ctl.text);
        }
      }
    });
  }

  @override
  void didUpdateWidget(LimeTextField old) {
    super.didUpdateWidget(old);
    if (!_focus.hasFocus && _ctl.text != widget.value) {
      _ctl.text = widget.value;
    }
  }

  @override
  void dispose() {
    if (_focus.hasFocus) PlatformOps.releaseIme();
    if (widget.controller == null) _ctl.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TextField(
    controller: _ctl,
    focusNode: _focus,
    style: Theme.of(context).textTheme.bodyMedium,
    onChanged: widget.live ? widget.onChanged : null,
    onSubmitted: widget.live ? null : widget.onChanged,
    decoration: InputDecoration(
      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      hintText: widget.hintText,
    ),
  );
}
