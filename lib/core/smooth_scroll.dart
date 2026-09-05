import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

/// 滚轮平滑滚动器。
///
/// 不用 [ScrollController.animateTo]：每来一格滚轮都重启一条带曲线的动画，
/// 速度会被反复归零，看起来就是一顿一顿的。这里改成"待走距离 + 每帧指数逼近"
/// 的模型（和 image_canvas 里的滚轮平移一致）：
/// 连续滚动只是往 `_remain` 里加数，速度自然叠加，永远不重启动画。
class WheelScroller {
  Ticker? _ticker;
  ScrollController? _c;
  double _remain = 0;
  double _tauMs = 60;
  Duration _last = Duration.zero;

  void reset() {
    _ticker?.dispose();
    _ticker = null;
    _remain = 0;
    _last = Duration.zero;
  }

  /// [delta] > 0 表示向下 / 向右滚
  void by(
    ScrollController? c,
    double delta, {
    required bool smooth,
    int durationMs = 150,
  }) {
    if (c == null || !c.hasClients || delta == 0) return;
    final pos = c.position;
    if (pos.maxScrollExtent <= 0) return;

    if (!smooth || durationMs <= 0) {
      reset();
      c.jumpTo((pos.pixels + delta).clamp(0.0, pos.maxScrollExtent));
      return;
    }

    // 一个"时长"内走完约 95% → tau = ms / ln(20)
    _tauMs = math.max(20.0, durationMs / 3.0);

    if (_c != c) {
      reset();
      _c = c;
    }
    _remain = _clampRemain(pos, _remain + delta);
    if (_remain == 0) return;
    if (_ticker == null) {
      _last = Duration.zero;
      _ticker = Ticker(_tick)..start();
    }
  }

  double _clampRemain(ScrollPosition pos, double v) => v.clamp(
    pos.minScrollExtent - pos.pixels,
    pos.maxScrollExtent - pos.pixels,
  );

  void _tick(Duration elapsed) {
    final c = _c;
    if (c == null || !c.hasClients) {
      reset();
      return;
    }
    final pos = c.position;
    final dtMs = _last == Duration.zero
        ? 1000 / 60
        : (elapsed - _last).inMicroseconds / 1000.0;
    _last = elapsed;

    // 长图边界/尺寸随图片加载而变，每帧重新夹一次
    _remain = _clampRemain(pos, _remain);
    if (_remain.abs() < 0.5) {
      final rest = _remain;
      reset();
      if (rest != 0) _scrollBy(pos, rest);
      return;
    }
    final k = math.exp(-dtMs / _tauMs);
    final step = _remain * (1 - k);
    _remain -= step;
    _scrollBy(pos, step);
  }

  void _scrollBy(ScrollPosition pos, double step) {
    if (pos is ScrollPositionWithSingleContext) {
      // 专为滚轮设计：直接改像素，不会新建 activity / 打断惯性
      pos.pointerScroll(step);
    } else {
      pos.jumpTo((pos.pixels + step).clamp(0.0, pos.maxScrollExtent));
    }
  }

  void dispose() => reset();
}

/// 放在滚动视图**内部**：靠 [PointerSignalResolver] 抢在 Scrollable 之前
/// 拿下滚轮事件（信号事件从最深命中者往外派发，先注册者胜），
/// 这样才能用自己的平滑滚动 / 缩放逻辑取代默认的瞬移滚动。
class WheelInterceptor extends StatelessWidget {
  const WheelInterceptor({
    super.key,
    required this.onWheel,
    required this.child,
    this.enabled = true,
  });

  final void Function(PointerScrollEvent event) onWheel;
  final Widget child;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    if (!enabled) return child;
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerSignal: (e) {
        if (e is! PointerScrollEvent) return;
        GestureBinding.instance.pointerSignalResolver.register(
          e,
          (ev) => onWheel(ev as PointerScrollEvent),
        );
      },
      child: child,
    );
  }
}
