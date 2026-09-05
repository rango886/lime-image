import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../core/smooth_scroll.dart';
import '../models/enums.dart';
import '../services/image_service.dart';
import '../state/viewer_state.dart';

class ComicView extends StatelessWidget {
  const ComicView({super.key, required this.state});
  final ViewerState state;

  @override
  Widget build(BuildContext context) => _StripCanvas(state: state, comic: true);
}

class LongStripView extends StatelessWidget {
  const LongStripView({super.key, required this.state});
  final ViewerState state;

  @override
  Widget build(BuildContext context) =>
      _StripCanvas(state: state, comic: false);
}

class _PageLayout {
  const _PageLayout(this.path, this.top, this.height);
  final String path;
  final double top;
  final double height;
}

/// A virtual image: immutable page geometry + one unbounded scene transform.
/// Only visible/preloaded pages have widgets and decoded images.
class _StripCanvas extends StatefulWidget {
  const _StripCanvas({required this.state, required this.comic});
  final ViewerState state;
  final bool comic;

  @override
  State<_StripCanvas> createState() => _StripCanvasState();
}

class _StripCanvasState extends State<_StripCanvas> {
  ViewerState get s => widget.state;
  List<String> _paths = [];
  List<_PageLayout> _pages = [];
  double _baseWidth = 0;
  int _generation = 0;
  int _jumpTick = -1;
  int _fitTick = -1;
  int _reported = -1;
  bool _dragging = false;
  Timer? _syncTimer;
  late final Ticker _ticker;
  Offset _remaining = Offset.zero;
  Duration _lastTick = Duration.zero;

  @override
  void initState() {
    super.initState();
    _ticker = Ticker(_tick);
    s.stripWheelPan = _wheelPan;
    _jumpTick = s.comicJumpTick;
    _fitTick = s.stripFitTick;
  }

  void _stopMotion() {
    _ticker.stop();
    _remaining = Offset.zero;
    _lastTick = Duration.zero;
  }

  void _wheelPan(Offset delta) {
    if (delta == Offset.zero) {
      _stopMotion();
    } else if (!s.settings.smoothWheelScroll ||
        s.settings.smoothWheelScrollMs <= 0) {
      _stopMotion();
      s.panStripBy(delta);
    } else {
      _remaining += delta;
      if (!_ticker.isActive) _ticker.start();
    }
  }

  void _tick(Duration elapsed) {
    final dt = _lastTick == Duration.zero
        ? 1000 / 60
        : (elapsed - _lastTick).inMicroseconds / 1000;
    _lastTick = elapsed;
    final tau = math.max(20.0, s.settings.smoothWheelScrollMs / 3);
    final step = _remaining * (1 - math.exp(-dt / tau));
    _remaining -= step;
    if (_remaining.distance < 0.1) {
      final rest = _remaining;
      _stopMotion();
      s.panStripBy(step + rest);
    } else {
      s.panStripBy(step);
    }
  }

  @override
  void dispose() {
    _generation++;
    _syncTimer?.cancel();
    if (s.stripWheelPan == _wheelPan) s.stripWheelPan = null;
    _ticker.dispose();
    super.dispose();
  }

  // Resolve dimensions before publishing the layout. Decoding upgrades must
  // never move page origins or change the scene point under the pointer.
  Future<void> _prepare(List<String> paths, double width) async {
    final generation = ++_generation;
    // Even a fully cached directory must not setState during build.
    await Future<void>.delayed(Duration.zero);
    final pages = <_PageLayout>[];
    var top = 0.0;
    final gap = widget.comic ? s.settings.comicGap : 0.0;
    for (final path in paths) {
      if (!mounted || generation != _generation) return;
      var aspect = 0.7;
      try {
        final cached = s.images.cached(path);
        if (cached != null && !cached.disposed) {
          aspect = cached.displayWidth / math.max(1, cached.displayHeight);
        } else {
          final size = await s.images.size(path);
          if (size != null) {
            aspect = size.aspect;
          } else {
            final decoded = await s.images.load(
              path,
              targetWidth: width.round(),
            );
            aspect = decoded.displayWidth / math.max(1, decoded.displayHeight);
          }
        }
      } catch (_) {
        // An unreadable page gets a fixed placeholder, not a shifting layout.
      }
      if (!aspect.isFinite || aspect <= 0) aspect = 0.7;
      final height = width / aspect;
      pages.add(_PageLayout(path, top, height));
      top += height + gap;
    }
    if (!mounted || generation != _generation) return;
    setState(() => _pages = pages);
  }

  void _jumpTo(int index) {
    if (index < 0 || index >= _pages.length) return;
    _stopMotion();
    _syncTimer?.cancel();
    s.stripTransform.offset = Offset(0, -_pages[index].top * s.stripZoom);
    _reported = index;
  }

  // Binary search works even far into a large comic, without sliver estimates.
  int _pageAt(double y) {
    var low = 0;
    var high = _pages.length;
    while (low < high) {
      final mid = (low + high) ~/ 2;
      if (_pages[mid].top + _pages[mid].height < y) {
        low = mid + 1;
      } else {
        high = mid;
      }
    }
    return low;
  }

  void _reportCurrent(Size size) {
    if (!widget.comic || _pages.isEmpty) return;
    final transform = s.stripTransform;
    final top = transform.toScene(Offset.zero).dy;
    final bottom = transform.toScene(Offset(0, size.height)).dy;
    final index = _pageAt(math.max(0, top));
    if (index >= _pages.length || _pages[index].top > bottom) return;
    if (_reported == index) return;
    _reported = index;
    _syncTimer?.cancel();
    _syncTimer = Timer(const Duration(milliseconds: 180), () {
      if (!mounted || index >= s.folder.count) return;
      s.folder.goTo(index);
      s.syncStripCurrent();
    });
  }

  int get _panMask => switch (s.settings.mouseFor(s.mode).panButton) {
    DragButton.left => kPrimaryMouseButton,
    DragButton.middle => kMiddleMouseButton,
    DragButton.right => kSecondaryMouseButton,
  };

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        final paths = widget.comic
            ? s.folder.entries.map((e) => e.path).toList()
            : [if (s.folder.currentPath != null) s.folder.currentPath!];
        if (_baseWidth == 0 || !listEquals(paths, _paths)) {
          _paths = paths;
          _baseWidth = size.width;
          _pages = [];
          _reported = -1;
          _syncTimer?.cancel();
          _stopMotion();
          s.stripTransform.reset();
          unawaited(_prepare(paths, _baseWidth));
        }
        return ListenableBuilder(
          listenable: s.transformTick,
          builder: (context, _) {
            if (_fitTick != s.stripFitTick) {
              _fitTick = s.stripFitTick;
              final ratio = size.width / _baseWidth;
              _baseWidth = size.width;
              if (_pages.isEmpty) {
                unawaited(_prepare(_paths, _baseWidth));
              } else {
                _pages = [
                  for (final page in _pages)
                    _PageLayout(
                      page.path,
                      page.top * ratio,
                      page.height * ratio,
                    ),
                ];
              }
            }
            if (_pages.isNotEmpty && _jumpTick != s.comicJumpTick) {
              _jumpTick = s.comicJumpTick;
              _jumpTo(s.folder.index);
            }
            _reportCurrent(size);
            final transform = s.stripTransform;
            final margin = size.height * (1 + s.settings.comicPreload);
            final first = _pageAt(transform.toScene(Offset(0, -margin)).dy);
            final bottom = transform
                .toScene(Offset(0, size.height + margin))
                .dy;
            final children = <Widget>[];
            for (var i = first; i < _pages.length; i++) {
              final page = _pages[i];
              if (page.top > bottom) break;
              final width = _baseWidth * transform.scale;
              // Position visible pages directly in screen coordinates. This is
              // the same affine transform for every page, without a huge widget.
              children.add(
                Positioned(
                  key: ValueKey(page.path),
                  left: transform.offset.dx,
                  top: transform.offset.dy + page.top * transform.scale,
                  width: width,
                  height: page.height * transform.scale,
                  child: _PageImage(
                    state: s,
                    path: page.path,
                    width: width,
                    animated: !widget.comic,
                  ),
                ),
              );
            }
            return Listener(
              behavior: HitTestBehavior.opaque,
              onPointerDown: (e) {
                _stopMotion();
                _dragging = e.buttons & _panMask != 0;
              },
              onPointerMove: (e) {
                if (_dragging) s.panStripBy(e.localDelta);
              },
              onPointerUp: (_) => _dragging = false,
              onPointerCancel: (_) => _dragging = false,
              onPointerPanZoomStart: (_) {
                _stopMotion();
                _gestureScale = 1;
              },
              onPointerPanZoomUpdate: _panZoom,
              child: WheelInterceptor(
                onWheel: (e) => s.handleStripWheel(e, focal: e.localPosition),
                child: ClipRect(
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (_pages.isEmpty && paths.isNotEmpty)
                        const Center(child: CircularProgressIndicator()),
                      ...children,
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  double _gestureScale = 1;
  void _panZoom(PointerPanZoomUpdateEvent e) {
    s.setStripZoom(
      s.stripZoom * e.scale / _gestureScale,
      focal: e.localPosition + e.pan - e.panDelta,
    );
    _gestureScale = e.scale;
    s.panStripBy(e.panDelta);
  }
}

class _PageImage extends StatefulWidget {
  const _PageImage({
    required this.state,
    required this.path,
    required this.width,
    required this.animated,
  });
  final ViewerState state;
  final String path;
  final double width;
  final bool animated;

  @override
  State<_PageImage> createState() => _PageImageState();
}

class _PageImageState extends State<_PageImage> {
  DecodedImage? _image;
  Timer? _upgrade;
  Object? _error;
  int _request = 0;
  ViewerState get s => widget.state;

  @override
  void initState() {
    super.initState();
    s.images.keepAlive.add(widget.path);
    _image = s.images.cached(widget.path);
    unawaited(_load());
  }

  int get _targetWidth => (widget.width * s.devicePixelRatio)
      .clamp(1, s.settings.maxDecodeDimension)
      .round();

  Future<void> _load() async {
    final request = ++_request;
    try {
      final image = await s.images.load(widget.path, targetWidth: _targetWidth);
      if (mounted && request == _request) {
        setState(() {
          _image = image;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted && request == _request) setState(() => _error = e);
    }
  }

  @override
  void didUpdateWidget(covariant _PageImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (s.settings.progressiveQuality &&
        _targetWidth > (_image?.decodedWidth ?? 0) * 1.25) {
      _upgrade?.cancel();
      _upgrade = Timer(const Duration(milliseconds: 350), _load);
    }
  }

  @override
  void dispose() {
    _upgrade?.cancel();
    s.images.keepAlive.remove(widget.path);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final image = _image;
    if (image == null || image.disposed) {
      return ColoredBox(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: Center(
          child: _error == null
              ? const CircularProgressIndicator()
              : const Icon(Icons.broken_image_outlined),
        ),
      );
    }
    final frame = widget.animated ? s.frameIndex % image.frameCount : 0;
    return RawImage(
      image: image.frames[frame].image,
      fit: BoxFit.fill,
      filterQuality: s.interacting ? FilterQuality.low : FilterQuality.medium,
    );
  }
}
