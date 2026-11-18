import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../app/state.dart';

/// Look changes (light / dark, Nothing / Glass) spread out in a circle from
/// the point the user touched: the old look is frozen in a picture and a
/// growing hole in it uncovers the new one.
class ThemeReveal extends StatefulWidget {
  const ThemeReveal({super.key, required this.child});

  final Widget child;

  static final _key = GlobalKey<_ThemeRevealState>();

  /// The app root, wrapped once in main.
  static Widget wrap(Widget child) => ThemeReveal(key: _key, child: child);

  /// Applies [change] with the circular reveal from the last touch.
  static Future<void> run(VoidCallback change) => _key.currentState?._run(change) ?? Future.sync(change);

  @override
  State<ThemeReveal> createState() => _ThemeRevealState();
}

class _ThemeRevealState extends State<ThemeReveal> with SingleTickerProviderStateMixin {
  final _boundary = GlobalKey();
  late final _anim = AnimationController(vsync: this, duration: const Duration(milliseconds: 560));
  ui.Image? _shot;
  Offset _from = Offset.zero;
  Offset _lastTouch = Offset.zero;

  @override
  void dispose() {
    _anim.dispose();
    _shot?.dispose();
    super.dispose();
  }

  /// Applies the change and redraws every screen: pages kept alive in the
  /// background read the palette in build and would keep the old colours.
  void _apply(VoidCallback change) {
    change();
    void mark(Element e) {
      e.markNeedsBuild();
      e.visitChildren(mark);
    }

    (context as Element).visitChildren(mark);
  }

  Future<void> _run(VoidCallback change) async {
    final b = _boundary.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (!AppState.I.appearance.animations || b == null || _shot != null) {
      _apply(change);
      return;
    }
    final dpr = View.of(context).devicePixelRatio;
    final img = await b.toImage(pixelRatio: dpr);
    if (!mounted) {
      img.dispose();
      _apply(change);
      return;
    }
    setState(() {
      _shot = img;
      _from = _lastTouch;
    });
    _apply(change);
    await _anim.forward(from: 0);
    if (!mounted) return;
    setState(() {
      _shot?.dispose();
      _shot = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Listener(
        // remembers where the finger went down: the reveal starts there
        onPointerDown: (e) => _lastTouch = e.position,
        behavior: HitTestBehavior.translucent,
        child: Stack(children: [
          RepaintBoundary(key: _boundary, child: widget.child),
          if (_shot != null)
            Positioned.fill(
              child: IgnorePointer(
                child: AnimatedBuilder(
                  animation: _anim,
                  builder: (context, _) => CustomPaint(
                    painter: _HolePainter(_shot!, _from, Curves.easeInOutCubic.transform(_anim.value)),
                  ),
                ),
              ),
            ),
        ]),
      ),
    );
  }
}

/// The frozen old look with a circular hole of growing radius at [center].
class _HolePainter extends CustomPainter {
  _HolePainter(this.image, this.center, this.t);

  final ui.Image image;
  final Offset center;
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    // farthest corner: the circle covers the whole screen at t = 1
    final far = [Offset.zero, Offset(size.width, 0), Offset(0, size.height), Offset(size.width, size.height)]
        .map((c) => (c - center).distance)
        .reduce(math.max);
    final hole = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size)
      ..addOval(Rect.fromCircle(center: center, radius: far * t));
    canvas.save();
    canvas.clipPath(hole);
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      Offset.zero & size,
      Paint()..filterQuality = FilterQuality.medium,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_HolePainter old) => old.t != t || old.image != image;
}
