import 'dart:math' as math;
import 'dart:typed_data';

/// 一张位图：B,G,R,A 顺序，alpha 预乘（和 WIC 的 32bppPBGRA 一致）。
class Pix {
  Pix(this.width, this.height, this.data)
    : assert(data.length >= width * height * 4);

  factory Pix.blank(int w, int h) => Pix(w, h, Uint8List(w * h * 4));

  final int width;
  final int height;
  final Uint8List data;

  Uint32List get words =>
      data.buffer.asUint32List(data.offsetInBytes, width * height);

  bool get hasAlpha {
    final d = data;
    for (var i = 3; i < d.length; i += 4) {
      if (d[i] != 255) return true;
    }
    return false;
  }
}

/// ffmpeg 给的 RGBA（已预乘）换成 BGRA
void rgbaToBgraInPlace(Uint8List p) {
  for (var i = 0; i < p.length; i += 4) {
    final r = p[i];
    p[i] = p[i + 2];
    p[i + 2] = r;
  }
}

/// 按 EXIF 方向码（1..8）重排像素。用户的旋转 / 翻转也映射成同一套码：
/// 顺时针 90 = 6，180 = 3，逆时针 90 = 8，水平翻转 = 2，垂直翻转 = 4。
Pix orient(Pix src, int code) {
  if (code <= 1 || code > 8) return src;
  final w = src.width, h = src.height;
  final swap = code >= 5;
  final ow = swap ? h : w, oh = swap ? w : h;
  final s = src.words;
  final out = Pix.blank(ow, oh);
  final d = out.words;
  var o = 0;
  for (var y = 0; y < oh; y++) {
    for (var x = 0; x < ow; x++) {
      int sx, sy;
      switch (code) {
        case 2:
          sx = w - 1 - x;
          sy = y;
        case 3:
          sx = w - 1 - x;
          sy = h - 1 - y;
        case 4:
          sx = x;
          sy = h - 1 - y;
        case 5:
          sx = y;
          sy = x;
        case 6:
          sx = y;
          sy = h - 1 - x;
        case 7:
          sx = w - 1 - y;
          sy = h - 1 - x;
        default: // 8
          sx = w - 1 - y;
          sy = x;
      }
      d[o++] = s[sy * w + sx];
    }
  }
  return out;
}

/// 整数矩形，左上角 + 宽高
class IRect {
  const IRect(this.x, this.y, this.w, this.h);
  final int x, y, w, h;

  bool covers(int width, int height) =>
      x <= 0 && y <= 0 && w >= width && h >= height;

  @override
  String toString() => 'IRect($x,$y ${w}x$h)';
}

Pix crop(Pix src, IRect r) {
  final x = r.x.clamp(0, src.width - 1);
  final y = r.y.clamp(0, src.height - 1);
  final w = math.max(1, math.min(r.w, src.width - x));
  final h = math.max(1, math.min(r.h, src.height - y));
  if (x == 0 && y == 0 && w == src.width && h == src.height) return src;
  final out = Pix.blank(w, h);
  final rowBytes = w * 4;
  for (var row = 0; row < h; row++) {
    final so = ((y + row) * src.width + x) * 4;
    out.data.setRange(row * rowBytes, row * rowBytes + rowBytes, src.data, so);
  }
  return out;
}

/// 找出四周和左上角颜色相近的纯色边，返回内容区域
IRect trimBounds(Pix p, int tolerance, int padding) {
  final w = p.width, h = p.height;
  final d = p.data;
  final b0 = d[0], g0 = d[1], r0 = d[2], a0 = d[3];
  bool same(int i) =>
      (d[i] - b0).abs() <= tolerance &&
      (d[i + 1] - g0).abs() <= tolerance &&
      (d[i + 2] - r0).abs() <= tolerance &&
      (d[i + 3] - a0).abs() <= tolerance;
  bool rowSame(int y) {
    var i = y * w * 4;
    for (var x = 0; x < w; x++, i += 4) {
      if (!same(i)) return false;
    }
    return true;
  }

  bool colSame(int x, int top, int bottom) {
    for (var y = top; y <= bottom; y++) {
      if (!same((y * w + x) * 4)) return false;
    }
    return true;
  }

  var top = 0;
  while (top < h - 1 && rowSame(top)) {
    top++;
  }
  var bottom = h - 1;
  while (bottom > top && rowSame(bottom)) {
    bottom--;
  }
  var left = 0;
  while (left < w - 1 && colSame(left, top, bottom)) {
    left++;
  }
  var right = w - 1;
  while (right > left && colSame(right, top, bottom)) {
    right--;
  }
  if (top == 0 && left == 0 && bottom == h - 1 && right == w - 1) {
    return IRect(0, 0, w, h);
  }
  final x0 = math.max(0, left - padding);
  final y0 = math.max(0, top - padding);
  final x1 = math.min(w, right + 1 + padding);
  final y1 = math.min(h, bottom + 1 + padding);
  return IRect(x0, y0, x1 - x0, y1 - y0);
}

/// 纯 Dart 的可分离重采样（非 Windows 时的兜底）。
/// 缩小时用按比例放宽的三角核，等价于带抗锯齿的双线性；[nearest] 用于像素画。
Pix resizeDart(Pix src, int ow, int oh, {bool nearest = false}) {
  if (ow == src.width && oh == src.height) return src;
  if (nearest) {
    final out = Pix.blank(ow, oh);
    final s = src.words, d = out.words;
    for (var y = 0; y < oh; y++) {
      final sy = math.min(src.height - 1, (y + 0.5) * src.height ~/ oh);
      for (var x = 0; x < ow; x++) {
        final sx = math.min(src.width - 1, (x + 0.5) * src.width ~/ ow);
        d[y * ow + x] = s[sy * src.width + sx];
      }
    }
    return out;
  }
  final tmp = _resample1d(src.data, src.width, src.height, ow, true);
  final out = _resample1d(tmp, ow, src.height, oh, false);
  return Pix(ow, oh, out);
}

Uint8List _resample1d(Uint8List s, int w, int h, int target, bool horizontal) {
  final srcLen = horizontal ? w : h;
  final scale = target / srcLen;
  final support = scale < 1 ? 1 / scale : 1.0;
  final ow = horizontal ? target : w;
  final oh = horizontal ? h : target;
  final out = Uint8List(ow * oh * 4);

  // 预算每个输出位置的权重
  final starts = Int32List(target);
  final counts = Int32List(target);
  final weights = <Float32List>[];
  for (var i = 0; i < target; i++) {
    final center = (i + 0.5) / scale;
    final lo = math.max(0, (center - support).floor());
    final hi = math.min(srcLen - 1, (center + support).ceil());
    final ws = Float32List(hi - lo + 1);
    var sum = 0.0;
    for (var j = lo; j <= hi; j++) {
      final wgt = math.max(0.0, 1 - ((j + 0.5 - center).abs() / support));
      ws[j - lo] = wgt;
      sum += wgt;
    }
    if (sum <= 0) {
      ws[(center - lo).floor().clamp(0, ws.length - 1)] = 1;
      sum = 1;
    }
    for (var k = 0; k < ws.length; k++) {
      ws[k] /= sum;
    }
    starts[i] = lo;
    counts[i] = ws.length;
    weights.add(ws);
  }

  final lines = horizontal ? h : w;
  for (var line = 0; line < lines; line++) {
    for (var i = 0; i < target; i++) {
      final ws = weights[i];
      final lo = starts[i];
      var b = 0.0, g = 0.0, r = 0.0, a = 0.0;
      for (var k = 0; k < counts[i]; k++) {
        final j = lo + k;
        final si = horizontal ? (line * w + j) * 4 : (j * w + line) * 4;
        final wk = ws[k];
        b += s[si] * wk;
        g += s[si + 1] * wk;
        r += s[si + 2] * wk;
        a += s[si + 3] * wk;
      }
      final di = horizontal ? (line * ow + i) * 4 : (i * ow + line) * 4;
      out[di] = b.round().clamp(0, 255);
      out[di + 1] = g.round().clamp(0, 255);
      out[di + 2] = r.round().clamp(0, 255);
      out[di + 3] = a.round().clamp(0, 255);
    }
  }
  return out;
}

/// 预乘像素铺到不透明背景上（[argb] 是 0xAARRGGBB），结果 alpha 全 255
Pix flatten(Pix src, int argb) {
  final br = (argb >> 16) & 0xFF, bg = (argb >> 8) & 0xFF, bb = argb & 0xFF;
  final s = src.data;
  final out = Uint8List(s.length);
  for (var i = 0; i < s.length; i += 4) {
    final a = s[i + 3];
    if (a == 255) {
      out[i] = s[i];
      out[i + 1] = s[i + 1];
      out[i + 2] = s[i + 2];
    } else {
      final inv = 255 - a;
      out[i] = math.min(255, s[i] + (bb * inv + 127) ~/ 255);
      out[i + 1] = math.min(255, s[i + 1] + (bg * inv + 127) ~/ 255);
      out[i + 2] = math.min(255, s[i + 2] + (br * inv + 127) ~/ 255);
    }
    out[i + 3] = 255;
  }
  return Pix(src.width, src.height, out);
}

/// 预乘 -> 直通 alpha（编码器要的是直通）
Uint8List unpremultiplied(Pix src) {
  final s = src.data;
  final out = Uint8List.fromList(s);
  for (var i = 0; i < out.length; i += 4) {
    final a = out[i + 3];
    if (a == 255 || a == 0) continue;
    out[i] = math.min(255, (out[i] * 255 + a ~/ 2) ~/ a);
    out[i + 1] = math.min(255, (out[i + 1] * 255 + a ~/ 2) ~/ a);
    out[i + 2] = math.min(255, (out[i + 2] * 255 + a ~/ 2) ~/ a);
  }
  return out;
}

/// 九宫格锚点 -> 在剩余空间里的位置比例
(double, double) anchorFactor(int anchor) =>
    ((anchor % 3) / 2.0, (anchor ~/ 3) / 2.0);
