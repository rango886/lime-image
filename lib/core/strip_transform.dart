import 'package:flutter/painting.dart';

/// Unbounded scene transform. Layout dimensions never change during zoom.
class StripTransform {
  double scale = 1;
  Offset offset = Offset.zero;

  Offset toScene(Offset point) => (point - offset) / scale;

  bool zoomAt(double next, Offset focal) {
    // Only reject invalid floating point values; no UX zoom/boundary limits.
    if (!next.isFinite || next <= 0 || next == scale) return false;
    final position = focal - toScene(focal) * next;
    if (!position.dx.isFinite || !position.dy.isFinite) return false;
    offset = position;
    scale = next;
    return true;
  }

  void reset() {
    scale = 1;
    offset = Offset.zero;
  }
}
