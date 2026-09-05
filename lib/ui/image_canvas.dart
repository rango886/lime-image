import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../core/utils.dart';
import '../models/enums.dart';
import '../services/image_service.dart';
import '../state/viewer_state.dart';

/// 图片绘制：一次 drawImageRect，变换全靠 canvas，缩放平移不触发重新光栅化
class ImagePainter extends CustomPainter {
  ImagePainter({
    required this.image,
    required this.second,
    required this.scale,
    required this.offset,
    required this.quarter,
    required this.flipH,
    required this.flipV,
    required this.quality,
    required this.frameIndex,
    required this.gap,
    required this.rtl,
  });

  final DecodedImage image;
  final DecodedImage? second;
  final double scale;
  final Offset offset;
  final int quarter;
  final bool flipH;
  final bool flipV;
  final FilterQuality quality;
  final int frameIndex;
  final double gap;
  final bool rtl;

  @override
  void paint(Canvas canvas, Size size) {
    if (image.disposed) return;
    final w1 = image.naturalWidth.toDouble();
    final h1 = image.naturalHeight.toDouble();
    final s = second;
    final hasSecond = s != null && !s.disposed;
    final w2 = hasSecond ? s.naturalWidth.toDouble() : 0.0;
    final h2 = hasSecond ? s.naturalHeight.toDouble() : 0.0;

    // 双页：先把两张缩到同一高度，避免一大一小时高度不齐
    final layout = hasSecond ? doublePageLayout(w1, h1, w2, h2, gap) : null;
    final cw = layout?.width ?? w1;
    final ch = layout?.height ?? h1;
    final rotated = quarter.isOdd ? Size(ch, cw) : Size(cw, ch);

    final paint = Paint()
      ..filterQuality = quality
      ..isAntiAlias = quality != FilterQuality.none;

    canvas.save();
    canvas.translate(offset.dx, offset.dy);
    canvas.scale(scale);
    canvas.translate(rotated.width / 2, rotated.height / 2);
    if (quarter != 0) canvas.rotate(quarter * math.pi / 2);
    if (flipH || flipV) canvas.scale(flipH ? -1 : 1, flipV ? -1 : 1);
    canvas.translate(-cw / 2, -ch / 2);

    void draw(DecodedImage img, double x, double w, double h) {
      final frame = img.frames[frameIndex % img.frameCount].image;
      final src = Rect.fromLTWH(
        0,
        0,
        frame.width.toDouble(),
        frame.height.toDouble(),
      );
      final dst = Rect.fromLTWH(x, (ch - h) / 2, w, h);
      canvas.drawImageRect(frame, src, dst, paint);
    }

    if (!hasSecond) {
      draw(image, 0, w1, h1);
    } else if (rtl) {
      draw(s, 0, layout!.w2, layout.height);
      draw(image, layout.w2 + gap, layout.w1, layout.height);
    } else {
      draw(image, 0, layout!.w1, layout.height);
      draw(s, layout.w1 + gap, layout.w2, layout.height);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(ImagePainter old) =>
      old.image != image ||
      old.second != second ||
      old.scale != scale ||
      old.offset != offset ||
      old.quarter != quarter ||
      old.flipH != flipH ||
      old.flipV != flipV ||
      old.quality != quality ||
      old.frameIndex != frameIndex ||
      old.gap != gap ||
      old.rtl != rtl;
}

class _CanvasSnapshot {
  const _CanvasSnapshot({
    required this.image,
    required this.second,
    required this.scale,
    required this.offset,
    required this.quarter,
    required this.flipH,
    required this.flipV,
    required this.quality,
    required this.frameIndex,
    required this.gap,
    required this.rtl,
  });

  factory _CanvasSnapshot.fromState(ViewerState s, FilterQuality quality) =>
      _CanvasSnapshot(
        image: s.image!,
        second: s.mode == ViewMode.doublePage ? s.secondImage : null,
        scale: s.tr.scale,
        offset: s.tr.offset,
        quarter: s.totalQuarter,
        flipH: s.totalFlipH,
        flipV: s.totalFlipV,
        quality: quality,
        frameIndex: s.frameIndex,
        gap: s.settings.pageGap,
        rtl: s.settings.readingDirection == ReadingDirection.rtl,
      );

  final DecodedImage image;
  final DecodedImage? second;
  final double scale;
  final Offset offset;
  final int quarter;
  final bool flipH;
  final bool flipV;
  final FilterQuality quality;
  final int frameIndex;
  final double gap;
  final bool rtl;
}

/// 模式 1~6 的画布：滚轮 / 拖动 / 惯性 / 触控板 / 双击
class ImageCanvas extends StatefulWidget {
  const ImageCanvas({super.key, required this.state});
  final ViewerState state;

  @override
  State<ImageCanvas> createState() => _ImageCanvasState();
}

class _ImageCanvasState extends State<ImageCanvas>
    with TickerProviderStateMixin {
  ViewerState get s => widget.state;

  Ticker? _inertia;
  Offset _velocity = Offset.zero;
  Duration _lastTick = Duration.zero;

  // 滚轮平移的平滑动画：剩余位移按指数逼近 0，多次滚动自然累加
  Ticker? _wheelPan;
  Offset _wheelRemain = Offset.zero;
  Duration _lastWheelTick = Duration.zero;

  late final AnimationController _enter = AnimationController(
    vsync: this,
    duration: Duration(milliseconds: s.settings.transitionMs),
  );
  int _lastTransitionKey = -1;
  _CanvasSnapshot? _previous;
  _CanvasSnapshot? _lastRendered;

  bool _dragging = false;
  Offset _lastPointer = Offset.zero;

  @override
  void initState() {
    super.initState();
    _enter.value = 1;
  }

  @override
  void dispose() {
    _inertia?.dispose();
    _wheelPan?.dispose();
    _enter.dispose();
    super.dispose();
  }

  void _syncTransition() {
    if (s.transitionKey == _lastTransitionKey) return;
    final first = _lastTransitionKey < 0;
    _lastTransitionKey = s.transitionKey;
    final t = s.settings.transition;
    if (t == TransitionType.none || s.settings.transitionMs <= 0 || first) {
      _previous = null;
      _enter.value = 1;
      return;
    }
    _previous = _lastRendered;
    _enter.duration = Duration(milliseconds: s.settings.transitionMs);
    _enter.forward(from: 0).whenComplete(() => _previous = null);
  }

  // —— 惯性 ——
  void _startInertia(Offset velocity) {
    _stopInertia();
    if (!s.settings.panInertia || velocity.distance < 60) return;
    _velocity = velocity;
    _lastTick = Duration.zero;
    _inertia = createTicker((elapsed) {
      final dt = _lastTick == Duration.zero
          ? 1 / 60
          : (elapsed - _lastTick).inMicroseconds / 1e6;
      _lastTick = elapsed;
      final decay = math.pow(0.0025, dt).toDouble(); // 每秒衰减到 0.25%
      _velocity *= decay;
      s.panBy(_velocity * dt);
      if (_velocity.distance < 40) _stopInertia();
    })..start();
  }

  void _stopInertia() {
    _inertia?.dispose();
    _inertia = null;
    _velocity = Offset.zero;
  }

  // —— 滚轮平移（平滑可关） ——
  void _wheelPanBy(Offset delta) {
    if (!s.settings.smoothWheelScroll || s.settings.smoothWheelScrollMs <= 0) {
      _stopWheelPan();
      s.panBy(delta);
      return;
    }
    _wheelRemain += delta;
    if (_wheelPan == null) {
      _lastWheelTick = Duration.zero;
      _wheelPan = createTicker(_tickWheelPan)..start();
    }
  }

  void _tickWheelPan(Duration elapsed) {
    final dt = _lastWheelTick == Duration.zero
        ? 1 / 60
        : (elapsed - _lastWheelTick).inMicroseconds / 1e6;
    _lastWheelTick = elapsed;
    // 时长越短逼近越快：一个动画时长内走完约 95%
    final ms = math.max(30, s.settings.smoothWheelScrollMs);
    final k = math.pow(0.05, dt * 1000 / ms).toDouble();
    final step = _wheelRemain * (1 - k);
    _wheelRemain -= step;
    s.markInteracting();
    s.panBy(step);
    if (_wheelRemain.distance < 0.5) {
      final rest = _wheelRemain;
      _stopWheelPan();
      if (rest != Offset.zero) s.panBy(rest);
    }
  }

  void _stopWheelPan() {
    _wheelPan?.dispose();
    _wheelPan = null;
    _wheelRemain = Offset.zero;
  }

  // —— 滚轮 ——
  void _onSignal(PointerSignalEvent e) {
    if (e is! PointerScrollEvent) return;
    final keys = HardwareKeyboard.instance;
    final b = s.settings.mouseFor(s.mode);
    var action = b.wheel;
    if (keys.isControlPressed) {
      action = b.ctrlWheel;
    } else if (keys.isShiftPressed) {
      action = b.shiftWheel;
    } else if (keys.isAltPressed) {
      action = b.altWheel;
    }
    var dy = e.scrollDelta.dy;
    if (dy == 0) dy = e.scrollDelta.dx;
    if (b.invertWheel) dy = -dy;
    if (dy == 0) return;
    _handleWheel(action, dy, e.localPosition);
  }

  void _handleWheel(WheelAction action, double dy, Offset local) {
    switch (action) {
      case WheelAction.none:
        return;
      case WheelAction.switchImage:
        s.navigate(dy > 0 ? 1 : -1);
      case WheelAction.switchSingle:
        s.navigateSingle(dy > 0 ? 1 : -1);
      case WheelAction.zoom:
        _stopInertia();
        _stopWheelPan();
        final step = s.settings.zoomStep;
        s.zoomAt(local, dy > 0 ? 1 / step : step);
        s.showToast('${(s.tr.scale * 100).round()}%');
      case WheelAction.scrollVertical:
        _stopInertia();
        _wheelPanBy(Offset(0, -dy.sign * s.settings.scrollStep));
      case WheelAction.scrollHorizontal:
        _stopInertia();
        _wheelPanBy(Offset(-dy.sign * s.settings.scrollStep, 0));
    }
  }

  int _buttonMask(DragButton b) => switch (b) {
    DragButton.left => kPrimaryMouseButton,
    DragButton.middle => kMiddleMouseButton,
    DragButton.right => kSecondaryMouseButton,
  };

  VelocityTracker? _tracker;

  void _onDown(PointerDownEvent e) {
    _stopInertia();
    _stopWheelPan();
    final mask = _buttonMask(s.settings.mouseFor(s.mode).panButton);
    if (e.buttons & mask != 0) {
      _dragging = true;
      _lastPointer = e.localPosition;
      _tracker = VelocityTracker.withKind(e.kind)
        ..addPosition(e.timeStamp, e.position);
    }
  }

  void _onMove(PointerMoveEvent e) {
    if (!_dragging) return;
    final delta = e.localPosition - _lastPointer;
    _lastPointer = e.localPosition;
    _tracker?.addPosition(e.timeStamp, e.position);
    s.markInteracting();
    s.panBy(delta);
  }

  void _onUp(PointerUpEvent e) {
    if (_dragging) {
      _dragging = false;
      final v = _tracker?.getVelocity().pixelsPerSecond ?? Offset.zero;
      _tracker = null;
      _startInertia(v);
    }
  }

  @override
  Widget build(BuildContext context) {
    _syncTransition();
    final img = s.image;
    if (img == null) return const SizedBox.expand();
    if (img.disposed) {
      // 缓存把当前图回收了（以前表现为“有时候不显示图片”），重新解码
      WidgetsBinding.instance.addPostFrameCallback((_) => s.ensureImageAlive());
      return const SizedBox.expand();
    }

    final quality = _quality();
    _lastRendered = _CanvasSnapshot.fromState(s, quality);

    return Listener(
      onPointerSignal: _onSignal,
      onPointerDown: _onDown,
      onPointerMove: _onMove,
      onPointerUp: _onUp,
      onPointerPanZoomStart: (_) {
        _stopInertia();
        _stopWheelPan();
      },
      onPointerPanZoomUpdate: (e) {
        // 触控板：双指平移 + 捏合缩放
        if (e.scale != 1.0) {
          s.zoomAt(e.localPosition, 1 + (e.scale - 1) * 0.35);
        }
        if (e.panDelta != Offset.zero) {
          s.panBy(e.panDelta);
        }
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onDoubleTapDown: (d) => _doubleTap(d.localPosition),
        child: AnimatedBuilder(
          animation: _enter,
          builder: (context, _) {
            final t = Curves.easeOutCubic.transform(_enter.value);
            final canvas = _liveCanvas(quality);
            final previous = _previous;
            if (previous == null || previous.image.disposed) {
              return canvas;
            }
            return Stack(
              fit: StackFit.expand,
              children: [
                _transitionOut(_snapshotCanvas(previous), t),
                _transitionIn(canvas, t),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _liveCanvas(FilterQuality quality) => RepaintBoundary(
    child: ValueListenableBuilder<int>(
      valueListenable: s.transformTick,
      builder: (context, _, _) => CustomPaint(
        painter: ImagePainter(
          image: s.image!,
          second: s.mode == ViewMode.doublePage ? s.secondImage : null,
          scale: s.tr.scale,
          offset: s.tr.offset,
          quarter: s.totalQuarter,
          flipH: s.totalFlipH,
          flipV: s.totalFlipV,
          quality: quality,
          frameIndex: s.frameIndex,
          gap: s.settings.pageGap,
          rtl: s.settings.readingDirection == ReadingDirection.rtl,
        ),
        size: Size.infinite,
      ),
    ),
  );

  Widget _snapshotCanvas(_CanvasSnapshot snap) => RepaintBoundary(
    child: CustomPaint(
      painter: ImagePainter(
        image: snap.image,
        second: snap.second,
        scale: snap.scale,
        offset: snap.offset,
        quarter: snap.quarter,
        flipH: snap.flipH,
        flipV: snap.flipV,
        quality: snap.quality,
        frameIndex: snap.frameIndex,
        gap: snap.gap,
        rtl: snap.rtl,
      ),
      size: Size.infinite,
    ),
  );

  Widget _transitionIn(Widget child, double t) {
    switch (s.settings.transition) {
      case TransitionType.none:
        return child;
      case TransitionType.fade:
        return Opacity(opacity: t, child: child);
      case TransitionType.slide:
        return Opacity(
          opacity: t,
          child: Transform.translate(
            offset: Offset((1 - t) * 36, 0),
            child: child,
          ),
        );
      case TransitionType.slideVertical:
        return Opacity(
          opacity: t,
          child: Transform.translate(
            offset: Offset(0, (1 - t) * 36),
            child: child,
          ),
        );
      case TransitionType.scale:
        return Opacity(
          opacity: t,
          child: Transform.scale(scale: 0.985 + 0.015 * t, child: child),
        );
    }
  }

  Widget _transitionOut(Widget child, double t) {
    switch (s.settings.transition) {
      case TransitionType.none:
        return const SizedBox.shrink();
      case TransitionType.fade:
        return Opacity(opacity: 1 - t, child: child);
      case TransitionType.slide:
        return Opacity(
          opacity: 1 - t,
          child: Transform.translate(offset: Offset(-20 * t, 0), child: child),
        );
      case TransitionType.slideVertical:
        return Opacity(
          opacity: 1 - t,
          child: Transform.translate(offset: Offset(0, -20 * t), child: child),
        );
      case TransitionType.scale:
        return Opacity(
          opacity: 1 - t,
          child: Transform.scale(scale: 1.0 + 0.01 * t, child: child),
        );
    }
  }

  FilterQuality _quality() {
    switch (s.settings.interpolation) {
      case Interpolation.none:
        return FilterQuality.none;
      case Interpolation.low:
        return FilterQuality.low;
      case Interpolation.medium:
        return FilterQuality.medium;
      case Interpolation.high:
        return FilterQuality.high;
      case Interpolation.auto:
        if (s.interacting) return FilterQuality.low;
        // 放大超过 1:1 时用 low（避免 medium 的模糊 + 开销）
        return s.tr.scale > 1.05 ? FilterQuality.low : FilterQuality.medium;
    }
  }

  void _doubleTap(Offset pos) {
    switch (s.settings.doubleClickAction) {
      case DoubleClickAction.toggleFullscreen:
        s.toggleFullscreen();
      case DoubleClickAction.toggleZoom:
        final fit = s.fitScale(s.mode);
        if ((s.tr.scale - fit).abs() < 0.01) {
          s.setZoom(1, focal: pos);
        } else {
          s.applyFitForMode();
        }
      case DoubleClickAction.maximize:
        s.toggleMaximize();
      case DoubleClickAction.nextImage:
        s.navigate(1);
      case DoubleClickAction.none:
        break;
    }
  }
}

/// 空白状态：只显示图标，不显示拖入提示和打开按钮。
class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.onOpen});
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Icon(
        Icons.image_outlined,
        size: 60,
        color: scheme.outline.withValues(alpha: 0.7),
      ),
    );
  }
}

/// 供外部使用的图片帧（缩略图等）
class RawFrame extends StatelessWidget {
  const RawFrame({super.key, required this.image, this.fit = BoxFit.cover});
  final ui.Image image;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) =>
      RawImage(image: image, fit: fit, filterQuality: FilterQuality.low);
}
