import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../batch/batch_state.dart';
import '../../batch/convert_preset.dart';
import '../../batch/engine/convert_engine.dart'
    show ConvertResult, kAlignWarning;
import '../../core/platform_ops.dart';
import '../../core/utils.dart';
import '../../l10n/strings.dart';
import '../../models/enums.dart';
import '../theme.dart';
import '../widgets.dart';

/// 中栏：画布 + 浮层（模式切换、缩放、完成汇总）
class BatchPreview extends StatelessWidget {
  const BatchPreview({
    super.key,
    required this.state,
    required this.background,
  });

  final BatchState state;
  final BackgroundStyle background;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final s = state;
    final pv = s.preview;
    final checker = background == BackgroundStyle.checker;

    return ClipRect(
      child: Stack(
        fit: StackFit.expand,
        children: [
          ColoredBox(color: LimeTheme.canvasColor(background, scheme)),
          if (checker)
            CustomPaint(
              painter: CheckerPainter(scheme.brightness == Brightness.dark),
            ),
          if (pv != null) _Canvas(state: s, data: pv),
          if (pv != null && pv.loading && pv.source == null)
            const Center(
              child: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          Positioned(
            top: 12,
            left: 0,
            right: 0,
            child: Center(child: _ModeBar(state: s)),
          ),
          Positioned(top: 12, right: 12, child: _ZoomButton(state: s)),
          if (s.summary != null)
            Positioned(
              top: 58,
              left: 0,
              right: 0,
              child: Center(child: _SummaryCard(state: s)),
            ),
        ],
      ),
    );
  }
}

/// 浮层统一外观：和状态悬浮窗一样的毛玻璃卡片
class _Glass extends StatelessWidget {
  const _Glass({required this.child, this.padding = EdgeInsets.zero});
  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = scheme.brightness == Brightness.dark;
    final r = BorderRadius.circular(limeRadius(context) + 2);
    return ClipRRect(
      borderRadius: r,
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: (dark ? LimeNeutral.darkOverlay : LimeNeutral.lightOverlay)
                .withValues(alpha: 0.86),
            borderRadius: r,
            border: Border.all(color: dark ? Colors.white12 : Colors.black12),
          ),
          child: child,
        ),
      ),
    );
  }
}

class _ModeBar extends StatelessWidget {
  const _ModeBar({required this.state});
  final BatchState state;

  @override
  Widget build(BuildContext context) => _Glass(
    padding: const EdgeInsets.all(3),
    child: SizedBox(
      width: 230,
      child: LimeSegmented<PreviewMode>(
        value: state.previewMode,
        items: PreviewMode.values,
        labelOf: (m) => switch (m) {
          PreviewMode.original => lt('原图'),
          PreviewMode.result => lt('结果'),
          PreviewMode.sideBySide => lt('对比'),
        },
        onChanged: state.setPreviewMode,
      ),
    ),
  );
}

class _ZoomButton extends StatelessWidget {
  const _ZoomButton({required this.state});
  final BatchState state;

  @override
  Widget build(BuildContext context) => _Glass(
    padding: const EdgeInsets.all(3),
    child: LimeSegmented<bool>(
      value: state.zoomActual,
      items: const [false, true],
      expand: false,
      labelOf: (v) => v ? '1:1' : lt('适应'),
      onChanged: (_) => state.toggleZoom(),
    ),
  );
}

// ---------------------------------------------------------------------------
// 画布
// ---------------------------------------------------------------------------

class _Canvas extends StatelessWidget {
  const _Canvas({required this.state, required this.data});
  final BatchState state;
  final PreviewData data;

  @override
  Widget build(BuildContext context) {
    final s = state;
    final src = data.source;
    final out = data.output;
    final err = data.result?.error;

    if (err != null && out == null && s.previewMode != PreviewMode.original) {
      return Center(
        child: _Message(icon: Icons.error_outline, text: lt(err)),
      );
    }

    switch (s.previewMode) {
      case PreviewMode.original:
        if (src == null) return const SizedBox.shrink();
        if (s.zoomActual) return _Actual(image: src);
        return _CropView(state: s, data: data, image: src);
      case PreviewMode.result:
        if (out == null) return _loadingOr(context);
        return s.zoomActual ? _Actual(image: out) : _Fitted(image: out);
      case PreviewMode.sideBySide:
        if (src == null) return const SizedBox.shrink();
        return Row(
          children: [
            Expanded(
              child: s.zoomActual ? _Actual(image: src) : _Fitted(image: src),
            ),
            VerticalDivider(
              width: 1,
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
            Expanded(
              child: out == null
                  ? _loadingOr(context)
                  : s.zoomActual
                  ? _Actual(image: out)
                  : _Fitted(image: out),
            ),
          ],
        );
    }
  }

  Widget _loadingOr(BuildContext context) {
    final skipped = data.result?.skipped;
    if (skipped != null && !data.loading) {
      return Center(
        child: _Message(
          icon: Icons.remove_circle_outline,
          text: lt('跳过：{0}', [lt(skipped)]),
        ),
      );
    }
    return const Center(
      child: SizedBox(
        width: 22,
        height: 22,
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 420),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 26, color: scheme.outline),
          const SizedBox(height: 8),
          Text(
            text,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium
                ?.copyWith(color: scheme.outline),
          ),
        ],
      ),
    );
  }
}

const _pad = EdgeInsets.fromLTRB(24, 56, 24, 24);

class _Fitted extends StatelessWidget {
  const _Fitted({required this.image});
  final ui.Image image;

  @override
  Widget build(BuildContext context) => Padding(
    padding: _pad,
    child: Center(
      child: RawImage(
        image: image,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.medium,
      ),
    ),
  );
}

/// 1:1：可拖动查看
class _Actual extends StatelessWidget {
  const _Actual({required this.image});
  final ui.Image image;

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final w = image.width / dpr, h = image.height / dpr;
    return LayoutBuilder(
      builder: (context, c) => InteractiveViewer(
        constrained: false,
        minScale: 1,
        maxScale: 1,
        scaleEnabled: false,
        boundaryMargin: EdgeInsets.symmetric(
          horizontal: math.max(0, (c.maxWidth - w) / 2),
          vertical: math.max(0, (c.maxHeight - h) / 2),
        ),
        child: SizedBox(
          width: math.max(w, c.maxWidth),
          height: math.max(h, c.maxHeight),
          child: Center(
            child: RawImage(
              image: image,
              width: w,
              height: h,
              filterQuality: FilterQuality.none,
            ),
          ),
        ),
      ),
    );
  }
}

/// 原图 + 裁切框。框可以拖动 / 拉角，松手后只对这一张生效。
class _CropView extends StatefulWidget {
  const _CropView({
    required this.state,
    required this.data,
    required this.image,
  });
  final BatchState state;
  final PreviewData data;
  final ui.Image image;

  @override
  State<_CropView> createState() => _CropViewState();
}

enum _Drag { move, tl, tr, bl, br }

class _CropViewState extends State<_CropView> {
  Rect? _live; // 拖动中的归一化框
  _Drag? _drag;

  Rect? _currentRect() {
    if (_live != null) return _live;
    final s = widget.state;
    final o = s.cropOverrideFor(widget.data.path);
    if (o != null) return Rect.fromLTWH(o[0], o[1], o[2], o[3]);
    final r = widget.data.result?.cropRect;
    if (r != null) return Rect.fromLTWH(r[0], r[1], r[2], r[3]);
    if (s.preset.crop != CropMode.none) return const Rect.fromLTWH(0, 0, 1, 1);
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final img = widget.image;
    return Padding(
      padding: _pad,
      child: LayoutBuilder(
        builder: (context, c) {
          final box = Size(c.maxWidth, c.maxHeight);
          final fitted = applyBoxFit(
            BoxFit.contain,
            Size(img.width.toDouble(), img.height.toDouble()),
            box,
          ).destination;
          final dst = Alignment.center.inscribe(fitted, Offset.zero & box);
          final norm = _currentRect();
          final crop = norm == null
              ? null
              : Rect.fromLTWH(
                  dst.left + norm.left * dst.width,
                  dst.top + norm.top * dst.height,
                  norm.width * dst.width,
                  norm.height * dst.height,
                );

          return Stack(
            children: [
              Positioned.fromRect(
                rect: dst,
                child: RawImage(
                  image: img,
                  fit: BoxFit.fill,
                  filterQuality: FilterQuality.medium,
                ),
              ),
              if (crop != null) ...[
                Positioned.fill(
                  child: IgnorePointer(
                    child: CustomPaint(
                      painter: _CropPainter(
                        image: dst,
                        crop: crop,
                        color: scheme.primary,
                      ),
                    ),
                  ),
                ),
                Positioned.fill(
                  child: GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onPanStart: (d) => _start(d.localPosition, crop),
                    onPanUpdate: (d) => _update(d.delta, dst),
                    onPanEnd: (_) => _end(),
                    child: MouseRegion(
                      cursor: SystemMouseCursors.move,
                      child: const SizedBox.expand(),
                    ),
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }

  void _start(Offset pos, Rect crop) {
    const grab = 14.0;
    _Drag? d;
    if ((pos - crop.topLeft).distance < grab) {
      d = _Drag.tl;
    } else if ((pos - crop.topRight).distance < grab) {
      d = _Drag.tr;
    } else if ((pos - crop.bottomLeft).distance < grab) {
      d = _Drag.bl;
    } else if ((pos - crop.bottomRight).distance < grab) {
      d = _Drag.br;
    } else if (crop.contains(pos)) {
      d = _Drag.move;
    }
    _drag = d;
    if (d != null) _live = _currentRect();
  }

  void _update(Offset delta, Rect dst) {
    final d = _drag;
    var r = _live;
    if (d == null || r == null) return;
    final dx = delta.dx / dst.width, dy = delta.dy / dst.height;
    const minSize = 0.02;
    final preset = widget.state.preset;
    final keepRatio = preset.crop == CropMode.ratio;
    final aspect = r.width / r.height; // 归一化空间里的宽高比

    switch (d) {
      case _Drag.move:
        final nx = (r.left + dx).clamp(0.0, 1 - r.width);
        final ny = (r.top + dy).clamp(0.0, 1 - r.height);
        r = Rect.fromLTWH(nx, ny, r.width, r.height);
      case _Drag.tl || _Drag.tr || _Drag.bl || _Drag.br:
        var l = r.left, t = r.top, rr = r.right, b = r.bottom;
        if (d == _Drag.tl || d == _Drag.bl) {
          l = (l + dx).clamp(0.0, rr - minSize);
        }
        if (d == _Drag.tr || d == _Drag.br) {
          rr = (rr + dx).clamp(l + minSize, 1.0);
        }
        if (keepRatio) {
          final w = rr - l;
          final h = w / aspect;
          if (d == _Drag.tl || d == _Drag.tr) {
            t = b - h;
          } else {
            b = t + h;
          }
          if (t < 0 || b > 1) return;
        } else {
          if (d == _Drag.tl || d == _Drag.tr) {
            t = (t + dy).clamp(0.0, b - minSize);
          }
          if (d == _Drag.bl || d == _Drag.br) {
            b = (b + dy).clamp(t + minSize, 1.0);
          }
        }
        r = Rect.fromLTRB(l, t, rr, b);
    }
    setState(() => _live = r);
  }

  void _end() {
    final r = _live;
    _drag = null;
    if (r != null) {
      widget.state.setCropOverride(widget.data.path, [
        r.left,
        r.top,
        r.width,
        r.height,
      ]);
    }
    setState(() => _live = null);
  }
}

class _CropPainter extends CustomPainter {
  _CropPainter({required this.image, required this.crop, required this.color});
  final Rect image;
  final Rect crop;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final shade = Paint()..color = Colors.black.withValues(alpha: 0.5);
    final path = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(image)
      ..addRect(crop);
    canvas.drawPath(path, shade);

    final line = Paint()
      ..color = Colors.white.withValues(alpha: 0.35)
      ..strokeWidth = 1;
    for (var i = 1; i < 3; i++) {
      final x = crop.left + crop.width * i / 3;
      final y = crop.top + crop.height * i / 3;
      canvas.drawLine(Offset(x, crop.top), Offset(x, crop.bottom), line);
      canvas.drawLine(Offset(crop.left, y), Offset(crop.right, y), line);
    }
    canvas.drawRect(
      crop,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
    final handle = Paint()..color = color;
    for (final c in [
      crop.topLeft,
      crop.topRight,
      crop.bottomLeft,
      crop.bottomRight,
    ]) {
      canvas.drawRect(Rect.fromCenter(center: c, width: 8, height: 8), handle);
    }
  }

  @override
  bool shouldRepaint(_CropPainter old) =>
      old.crop != crop || old.image != image || old.color != color;
}

// ---------------------------------------------------------------------------
// 前后信息
// ---------------------------------------------------------------------------

/// 预览下方的属性对比和双行完整路径，不遮挡预览画布。
class BatchInfoPanel extends StatefulWidget {
  const BatchInfoPanel({super.key, required this.state});
  final BatchState state;

  @override
  State<BatchInfoPanel> createState() => _BatchInfoPanelState();
}

class _BatchInfoPanelState extends State<BatchInfoPanel> {
  static const double _labelColWidth = 84;

  ConvertResult? _lastResult;
  String? _lastTargetPath;
  int _lastOutBytes = 0;
  Timer? _dimTimer;
  bool _dimmed = false;

  @override
  void initState() {
    super.initState();
    _syncFromPreview();
  }

  @override
  void didUpdateWidget(covariant BatchInfoPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncFromPreview();
  }

  @override
  void dispose() {
    _dimTimer?.cancel();
    super.dispose();
  }

  void _syncFromPreview() {
    final pv = widget.state.preview;
    if (pv == null) {
      _dimTimer?.cancel();
      _dimTimer = null;
      _lastResult = null;
      _lastTargetPath = null;
      _lastOutBytes = 0;
      _dimmed = false;
      return;
    }
    if (pv.result != null) {
      _dimTimer?.cancel();
      _dimTimer = null;
      _lastResult = pv.result;
      _lastTargetPath = pv.targetPath;
      _lastOutBytes = pv.outBytes;
      _dimmed = false;
      return;
    }
    if (_lastResult != null && _dimTimer == null && !_dimmed) {
      // 小图几十毫秒内就能算完，不闪白也不变灰；只有耗时较久时才温和淡化提示更新中。
      _dimTimer = Timer(const Duration(milliseconds: 180), () {
        if (!mounted) return;
        if (widget.state.preview?.result == null) {
          setState(() => _dimmed = true);
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final pv = widget.state.preview!;
    final r = pv.result ?? _lastResult;
    final outBytes = pv.result != null ? pv.outBytes : _lastOutBytes;
    final targetPath = pv.result != null ? pv.targetPath : _lastTargetPath;
    final labelSize = (theme.textTheme.labelSmall?.fontSize ?? 11) - 0.5;
    final valueSize = (theme.textTheme.bodySmall?.fontSize ?? 11.5) - 1.0;
    final label = theme.textTheme.labelSmall?.copyWith(
      fontSize: labelSize,
      color: scheme.onSurfaceVariant,
    );
    final value = theme.textTheme.bodySmall?.copyWith(
      fontSize: valueSize,
      color: scheme.onSurface,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final before = value;
    final after = value;

    final ok = r?.ok ?? false;
    String meta(bool exif, bool gps) =>
        exif ? (gps ? 'EXIF · GPS' : 'EXIF') : lt('无');
    final keepGps =
        r != null &&
        widget.state.preset.metadata == MetadataPolicy.keep &&
        r.srcHasGps;
    final outSize = r == null ? 0 : (r.keepOriginal ? r.srcSize : outBytes);
    final pct = r == null || r.srcSize == 0
        ? 0
        : (outSize - r.srcSize) * 100 / r.srcSize;
    final deltaColor = pct <= 0 ? scheme.primary : scheme.error;
    final alignBadge = r != null && ok && r.warning == kAlignWarning
        ? Tooltip(
            message: lt(kAlignWarning),
            child: Icon(
              Icons.warning_amber_rounded,
              size: 14,
              color: Colors.orange.shade700,
            ),
          )
        : null;
    final sizeBadge = r != null && ok && r.srcSize > 0 && pct.round() != 0
        ? Tooltip(
            message:
                '${pct < 0 ? lt('节省') : lt('增加')} '
                '${formatBytes((outSize - r.srcSize).abs())}',
            child: Container(
              key: const ValueKey('batch-size-delta'),
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: deltaColor.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                '${pct > 0 ? '+' : ''}${pct.round()}%',
                style: label?.copyWith(
                  color: deltaColor,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          )
        : null;
    final fmtAfter = r == null || !ok
        ? '—'
        : r.keepOriginal
        ? lt('保留原图')
        : r.format.lossy && r.quality > 0
        ? '${r.format.label} · ${r.quality}'
        : r.format.label;

    final fields = r == null
        ? [
            (lt('格式'), '—', '—'),
            (lt('尺寸'), '—', '—'),
            (lt('大小'), '—', '—'),
            (lt('透明'), '—', '—'),
            (lt('元数据'), '—', '—'),
          ]
        : [
            (lt('格式'), r.srcFormat, fmtAfter),
            (
              lt('尺寸'),
              '${r.srcW} × ${r.srcH}',
              ok ? '${r.outW} × ${r.outH}' : '—',
            ),
            (lt('大小'), formatBytes(r.srcSize), ok ? formatBytes(outSize) : '—'),
            (
              lt('透明'),
              r.srcAlpha ? lt('有') : lt('无'),
              ok ? (r.outAlpha ? lt('有') : lt('无')) : '—',
            ),
            (
              lt('元数据'),
              meta(r.srcHasExif, r.srcHasGps),
              ok ? meta(r.exifKept, r.exifKept && keepGps) : '—',
            ),
          ];
    Widget cell(
      String text,
      TextStyle? style, {
      Widget? trailing,
      double vertical = 3.5,
    }) => Padding(
      padding: EdgeInsets.symmetric(vertical: vertical, horizontal: 10),
      child: Wrap(
        spacing: 6,
        runSpacing: 2,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(text, style: style),
          ?trailing,
        ],
      ),
    );
    Widget rowLabel(bool result, {double horizontal = 14}) => Padding(
      padding: EdgeInsets.symmetric(vertical: 3.5, horizontal: horizontal),
      child: Text(result ? lt('转换后') : lt('转换前'), style: label),
    );
    final body = LayoutBuilder(
      builder: (context, c) {
        if (c.maxWidth >= 560) {
          // 中栏够宽时横排属性，用三行代替六行，给图片留出更多高度。
          return Table(
            columnWidths: const {
              0: FixedColumnWidth(_labelColWidth),
              1: FlexColumnWidth(1.05),
              2: FlexColumnWidth(1.25),
              3: FlexColumnWidth(1.45),
              4: FlexColumnWidth(1.0),
              5: FlexColumnWidth(1.05),
            },
            defaultVerticalAlignment: TableCellVerticalAlignment.middle,
            children: [
              TableRow(
                children: [
                  const SizedBox.shrink(),
                  for (final f in fields) cell(f.$1, label, vertical: 3.5),
                ],
              ),
              TableRow(
                children: [
                  rowLabel(false),
                  for (final f in fields) cell(f.$2, before),
                ],
              ),
              TableRow(
                children: [
                  rowLabel(true),
                  for (var i = 0; i < fields.length; i++)
                    cell(
                      fields[i].$3,
                      after,
                      trailing: i == 2
                          ? sizeBadge
                          : i == 1
                          ? alignBadge
                          : null,
                    ),
                ],
              ),
            ],
          );
        }
        return Table(
          columnWidths: const {
            0: FixedColumnWidth(_labelColWidth),
            1: FlexColumnWidth(),
            2: FlexColumnWidth(),
          },
          defaultVerticalAlignment: TableCellVerticalAlignment.middle,
          children: [
            TableRow(
              children: [
                const SizedBox.shrink(),
                rowLabel(false, horizontal: 10),
                rowLabel(true, horizontal: 10),
              ],
            ),
            for (var i = 0; i < fields.length; i++)
              TableRow(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 3.5, 8, 3.5),
                    child: Text(fields[i].$1, style: label),
                  ),
                  cell(fields[i].$2, before, vertical: 3.5),
                  cell(
                    fields[i].$3,
                    after,
                    vertical: 3.5,
                    trailing: i == 2
                        ? sizeBadge
                        : i == 1
                        ? alignBadge
                        : null,
                  ),
                ],
              ),
          ],
        );
      },
    );

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(top: BorderSide(color: scheme.outlineVariant)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            key: const ValueKey('batch-comparison-card'),
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedOpacity(
                opacity: _dimmed ? 0.55 : 1.0,
                duration: const Duration(milliseconds: 150),
                child: body,
              ),
              const SizedBox(height: 2),
              _InfoPathRow(
                path: pv.path,
                label: lt('输入路径'),
                textKey: const ValueKey('batch-source-path'),
                labelWidth: _labelColWidth,
                labelSize: labelSize,
                valueSize: valueSize - 1.0,
              ),
              _InfoPathRow(
                path: targetPath,
                label: lt('输出路径'),
                textKey: const ValueKey('batch-target-path'),
                labelWidth: _labelColWidth,
                labelSize: labelSize,
                valueSize: valueSize - 1.0,
              ),
            ],
          ),
          if (pv.result?.error != null) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 4, 14, 6),
              child: Text(
                lt(pv.result!.error!),
                style: label?.copyWith(color: scheme.error),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// 路径标签固定，只有完整路径横向滚动，复制按钮不随路径移走。
class _InfoPathRow extends StatelessWidget {
  const _InfoPathRow({
    required this.path,
    required this.label,
    required this.textKey,
    required this.labelWidth,
    required this.labelSize,
    required this.valueSize,
  });

  final String? path;
  final String label;
  final Key textKey;
  final double labelWidth;
  final double labelSize;
  final double valueSize;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final muted = scheme.onSurfaceVariant;
    return SizedBox(
      height: 24,
      child: Row(
        children: [
          SizedBox(
            width: labelWidth,
            child: Padding(
              padding: const EdgeInsets.only(left: 14, right: 8),
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall?.copyWith(
                  fontSize: labelSize,
                  color: muted,
                ),
              ),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(left: 10),
              child: Tooltip(
                message: path ?? '',
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Text(
                    path ?? '—',
                    key: textKey,
                    softWrap: false,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontSize: valueSize,
                      color: muted,
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),
          Padding(
            padding: const EdgeInsets.only(right: 10),
            child: IconButton(
              tooltip: lt('复制路径'),
              onPressed: path == null
                  ? null
                  : () => Clipboard.setData(ClipboardData(text: path!)),
              icon: const Icon(Icons.copy_outlined, size: 12.5),
              color: muted,
              padding: const EdgeInsets.all(4),
              constraints: const BoxConstraints.tightFor(width: 22, height: 22),
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.state});
  final BatchState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final sum = state.summary!;
    final saved = sum.inBytes - sum.outBytes;

    Widget stat(String n, String label, [Color? color]) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Column(
        children: [
          Text(
            n,
            style: theme.textTheme.titleLarge?.copyWith(
              color: color,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(color: scheme.outline),
          ),
        ],
      ),
    );

    return _Glass(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            sum.cancelled
                ? Icons.stop_circle_outlined
                : sum.failed > 0
                ? Icons.error_outline
                : Icons.check_circle_outline,
            color: sum.failed > 0 ? scheme.error : scheme.primary,
            size: 22,
          ),
          const SizedBox(width: 6),
          stat('${sum.done}', lt('完成')),
          if (sum.skipped > 0) stat('${sum.skipped}', lt('已跳过')),
          if (sum.failed > 0) stat('${sum.failed}', lt('失败'), scheme.error),
          if (sum.done > 0)
            stat(
              saved >= 0 ? formatBytes(saved) : '+${formatBytes(-saved)}',
              saved >= 0 ? lt('节省') : lt('增加'),
            ),
          const SizedBox(width: 8),
          if (sum.lastDir != null)
            TextButton(
              onPressed: () => openFolder(sum.lastDir!),
              child: Text(lt('打开输出文件夹')),
            ),
          if (sum.failed > 0)
            TextButton(onPressed: state.retryFailed, child: Text(lt('重试失败项'))),
          IconButton(
            iconSize: 16,
            tooltip: lt('关闭'),
            icon: const Icon(Icons.close),
            onPressed: state.dismissSummary,
          ),
        ],
      ),
    );
  }
}

Future<void> openFolder(String dir) async {
  try {
    if (Platform.isWindows) {
      await Process.run('explorer.exe', [dir]);
    } else {
      await PlatformOps.openWithSystem(dir);
    }
  } catch (_) {}
}
