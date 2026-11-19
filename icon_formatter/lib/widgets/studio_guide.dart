import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app/theme.dart';

/// Preview-only guide: the squircle plate edge (size 0.93, exponent 4.25, as
/// the Lucent plate of the engine) and a centre cross. Never written to the
/// output files.
class StudioGuidePainter extends CustomPainter {
  const StudioGuidePainter();

  static const _size = 0.93;
  static const _exp = 4.25;

  @override
  void paint(Canvas canvas, Size size) {
    final side = math.min(size.width, size.height);
    if (side <= 0) return;
    final c = Offset(size.width / 2, size.height / 2);
    final half = side * _size / 2;
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = Palette.fg.withValues(alpha: 0.55);
    // |x|^n + |y|^n = 1, sampled around the circle parameter
    final path = Path();
    const steps = 180;
    for (var k = 0; k <= steps; k++) {
      final t = 2 * math.pi * k / steps;
      final cs = math.cos(t);
      final sn = math.sin(t);
      final x = c.dx + half * _sgn(cs) * math.pow(cs.abs(), 2 / _exp);
      final y = c.dy + half * _sgn(sn) * math.pow(sn.abs(), 2 / _exp);
      if (k == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x.toDouble(), y.toDouble());
      }
    }
    path.close();
    canvas.drawPath(path, line);
    canvas.drawLine(Offset(c.dx, 0), Offset(c.dx, size.height), line..color = Palette.fg.withValues(alpha: 0.3));
    canvas.drawLine(Offset(0, c.dy), Offset(size.width, c.dy), line);
  }

  static double _sgn(double v) => v < 0 ? -1 : 1;

  @override
  bool shouldRepaint(covariant StudioGuidePainter oldDelegate) => false;
}
