import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import '../app/state.dart';

/// Space at the bottom covered by floating glass bars (Android phone
/// layout). Scrollable pages add it as bottom padding so content scrolls
/// under the glass instead of being cut off.
class GlassInsets extends InheritedWidget {
  const GlassInsets({super.key, required this.bottom, required super.child});

  final double bottom;

  static double of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<GlassInsets>()?.bottom ?? 0;

  @override
  bool updateShouldNotify(GlassInsets old) => old.bottom != bottom;
}

/// Glass material from Impostazioni › Liquid Glass, rendered by
/// `liquid_glass_widgets`. [chromatic] scales the configured aberration.
LiquidGlassSettings appGlassSettings({bool dark = false, double chromatic = 0.5}) {
  final g = AppState.I.glass;
  final tint = dark ? Colors.black.withValues(alpha: g.lensDarkness) : Colors.white.withValues(alpha: g.tint);
  return LiquidGlassSettings(
    glassColor: tint,
    blur: g.blur,
    thickness: g.thickness,
    frost: g.frost,
    chromaticAberration: g.chromatic * (0.5 + chromatic),
    lightIntensity: g.lightIntensity,
    lightAngle: g.lightAngle * math.pi / 180,
    refractiveIndex: g.refractiveIndex,
    saturation: g.saturation,
    rimLight: g.rimLight,
  );
}

/// Configurable shadow behind text and icons on glass (legibility).
List<Shadow> glassTextShadows() {
  final g = AppState.I.glass;
  if (g.textShadow <= 0.01) return const [];
  return [
    Shadow(color: Colors.black.withValues(alpha: (g.textShadow * 0.9).clamp(0.0, 1.0)), blurRadius: g.textShadowBlur, offset: const Offset(0, 1)),
    if (g.textShadow > 0.5) Shadow(color: Colors.black.withValues(alpha: (g.textShadow - 0.5) * 0.8), blurRadius: g.textShadowBlur * 2.2),
  ];
}

/// Applies the glass text/icon shadow to a subtree.
Widget withGlassShadows(Widget child) {
  final s = glassTextShadows();
  if (s.isEmpty) return child;
  return DefaultTextStyle.merge(
    style: TextStyle(shadows: s),
    child: IconTheme.merge(data: IconThemeData(shadows: s), child: child),
  );
}

GlassQuality get appGlassQuality => AppState.I.glass.premium ? GlassQuality.premium : GlassQuality.standard;

/// App-wide glass surface (panels, floating bars, lens) backed by
/// `GlassContainer` from liquid_glass_widgets.
class LiquidGlass extends StatelessWidget {
  const LiquidGlass({
    super.key,
    required this.child,
    this.radius = 28,
    this.padding = EdgeInsets.zero,
    this.chromatic = 0.6,
    this.dark = false,
  });

  final Widget child;
  final double radius;
  final EdgeInsetsGeometry padding;

  /// 0..1 intensity of the chromatic refraction.
  final double chromatic;

  /// Darker "lens" variant.
  final bool dark;

  @override
  Widget build(BuildContext context) {
    return GlossOverlay(
      radius: radius,
      child: GlassContainer(
        shape: LiquidRoundedSuperellipse(borderRadius: radius),
        padding: padding,
        settings: appGlassSettings(dark: dark, chromatic: chromatic),
        useOwnLayer: true,
        quality: appGlassQuality,
        clipBehavior: Clip.antiAlias,
        child: withGlassShadows(child),
      ),
    );
  }
}


/// Glossy specular rim over a glass shape (Impostazioni › Liquid Glass ›
/// Lucentezza): bright where the edge faces the light, as on the reference
/// icons, plus a soft sheen on the lit side.
class GlossOverlay extends StatelessWidget {
  const GlossOverlay({super.key, required this.radius, required this.child});

  final double radius;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final g = AppState.I.glass;
    if (!g.gloss || g.glossIntensity <= 0.01) return child;
    return CustomPaint(
      foregroundPainter: GlossPainter(radius: radius, intensity: g.glossIntensity, lightAngle: g.lightAngle),
      child: child,
    );
  }
}

class GlossPainter extends CustomPainter {
  GlossPainter({required this.radius, required this.intensity, required this.lightAngle});

  final double radius;
  final double intensity;

  /// Degrees, same convention as the glass light (135 = top-left).
  final double lightAngle;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final r = math.min(radius, size.shortestSide / 2);
    final rr = RRect.fromRectAndRadius(rect.deflate(0.8), Radius.circular(math.max(0, r - 0.8)));
    final a = lightAngle * math.pi / 180;
    final begin = Alignment(math.cos(a), -math.sin(a));
    final end = Alignment(-math.cos(a), math.sin(a));
    final i = intensity.clamp(0.0, 1.0);
    // crisp rim: brightest on the lit side, faint echo on the opposite side
    canvas.drawRRect(
      rr,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.3
        ..shader = LinearGradient(
          begin: begin,
          end: end,
          colors: [
            Colors.white.withValues(alpha: 0.85 * i),
            Colors.white.withValues(alpha: 0.18 * i),
            Colors.white.withValues(alpha: 0.04 * i),
            Colors.white.withValues(alpha: 0.22 * i),
          ],
          stops: const [0.0, 0.3, 0.7, 1.0],
        ).createShader(rect),
    );
    // soft glow just inside the lit edge
    canvas.drawRRect(
      rr.deflate(1.5),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.5)
        ..shader = LinearGradient(
          begin: begin,
          end: Alignment.center,
          colors: [Colors.white.withValues(alpha: 0.35 * i), Colors.white.withValues(alpha: 0)],
        ).createShader(rect),
    );
    // broad sheen on the lit half
    canvas.save();
    canvas.clipRRect(rr);
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: begin,
          end: Alignment.center,
          colors: [Colors.white.withValues(alpha: 0.10 * i), Colors.white.withValues(alpha: 0)],
        ).createShader(rect),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant GlossPainter old) =>
      old.radius != radius || old.intensity != intensity || old.lightAngle != lightAngle;
}
