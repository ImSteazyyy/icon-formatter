import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import '../app/models.dart';
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

/// Glass material from Impostazioni › Vetro, rendered by
/// `liquid_glass_widgets`. [chromatic] scales the configured aberration.
/// Every glass surface of the app reads it, so a change in the settings is
/// visible everywhere at once (no restart, no per-screen copies).
LiquidGlassSettings appGlassSettings({bool dark = false, double chromatic = 0.5}) {
  final g = AppState.I.glass;
  // Frost is applied as extra diffusion + milky tint so it is visible in
  // every quality mode (the package's own frost/aberration exist only in the
  // Premium Impeller pipeline). Aberration is also drawn by GlossOverlay.
  final Color tint;
  if (dark) {
    tint = Colors.black.withValues(alpha: g.lensDarkness);
  } else if (g.tintColor != 0) {
    // coloured glass: "Tinta" + "Colore" (amount)
    tint = Color(g.tintColor | 0xFF000000).withValues(alpha: (g.tint * 1.4 + g.frost * 0.10).clamp(0.0, 0.85));
  } else {
    tint = Colors.white.withValues(alpha: (g.tint + g.frost * 0.14).clamp(0.0, 0.8));
  }
  return LiquidGlassSettings(
    glassColor: tint,
    blur: g.blur + g.frost * 12,
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

/// Bottom bar material: glass, or a solid anthracite pill when
/// "Vetro nella barra in basso" is off.
LiquidGlassSettings navGlassSettings() {
  if (AppState.I.glass.useNav) return appGlassSettings(chromatic: 0.6);
  return const LiquidGlassSettings(glassColor: Color(0xF21C1C1F), blur: 0, thickness: 0, chromaticAberration: 0, lightIntensity: 0, saturation: 1);
}

/// Where a glass surface sits; each role can be switched to a solid
/// surface in Impostazioni › Vetro › Dove usarlo.
enum GlassRole { panel, button, nav, lens }

bool glassEnabled(GlassRole r) {
  final g = AppState.I.glass;
  return switch (r) {
    GlassRole.panel => g.usePanels,
    GlassRole.button => g.useButtons,
    GlassRole.nav => g.useNav,
    GlassRole.lens => g.useNav,
  };
}

/// Solid anthracite used where glass is switched off (and by plain cards).
const solidSurface = Color(0xFF1C1C1F);

/// Drop shadow of glass surfaces ("Profondità").
List<BoxShadow> glassDepthShadows(double radius) {
  if (!AppState.I.glass.depth) return const [];
  return [
    BoxShadow(color: Colors.black.withValues(alpha: 0.38), blurRadius: 18, offset: const Offset(0, 8)),
    BoxShadow(color: Colors.black.withValues(alpha: 0.22), blurRadius: 4, offset: const Offset(0, 1)),
  ];
}

/// Configurable shadow behind text and icons on glass (legibility).
///
/// Drawn without blur. On Impeller a blurred text shadow is an offscreen
/// blur pass per text run per frame: with the default 60 / 6.0 the glass
/// labels cost dozens of blur passes per frame and page swipes dropped to
/// 30-60 fps on the Phone (2a) Plus. The soft edge is rebuilt from a few
/// crisp copies placed on rings as wide as the blur, each faint; a crisp
/// glyph copy costs about as much as the text itself.
List<Shadow> glassTextShadows() => glassTextShadowsFor(AppState.I.glass);

List<Shadow> glassTextShadowsFor(GlassConfig g) {
  if (g.textShadow <= 0.01) return const [];
  final key = Object.hash(g.textShadow, g.textShadowBlur);
  if (key == _shadowKey) return _shadowCache;
  _shadowKey = key;
  final strength = g.textShadow.clamp(0.0, 1.0);
  final soft = g.textShadowBlur.clamp(0.0, 20.0);
  final out = <Shadow>[Shadow(color: Colors.black.withValues(alpha: strength * 0.55), offset: const Offset(0, 1))];
  void ring(double radius, double alpha, int n, double phase) {
    if (radius < 0.5 || alpha <= 0.004) return;
    for (var i = 0; i < n; i++) {
      final a = phase + i * 2 * math.pi / n;
      out.add(Shadow(color: Colors.black.withValues(alpha: alpha), offset: Offset(math.cos(a) * radius, 1 + math.sin(a) * radius)));
    }
  }
  ring(soft * 0.30, strength * 0.22, 6, 0);
  if (g.textShadow > 0.5) ring(soft * 0.65, (g.textShadow - 0.5) * 0.30, 6, math.pi / 6);
  return _shadowCache = out;
}

Object? _shadowKey;
List<Shadow> _shadowCache = const [];

/// Applies the glass text/icon shadow to a subtree.
Widget withGlassShadows(Widget child) {
  final s = glassTextShadows();
  if (s.isEmpty) return child;
  return DefaultTextStyle.merge(
    style: TextStyle(shadows: s),
    child: IconTheme.merge(data: IconThemeData(shadows: s), child: child),
  );
}

/// The premium shader path needs Impeller on Vulkan/Metal: on Windows and
/// Linux (Impeller on OpenGL ES) it leaves the window blank, so "Qualità"
/// falls back to the standard glass there.
bool get premiumGlassSupported => Platform.isAndroid || Platform.isIOS || Platform.isMacOS;

GlassQuality get appGlassQuality => switch (AppState.I.glass.quality) {
      GlassQualityLevel.fast => GlassQuality.minimal,
      GlassQualityLevel.balanced => GlassQuality.standard,
      GlassQualityLevel.quality => premiumGlassSupported ? GlassQuality.premium : GlassQuality.standard,
    };

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
    this.role = GlassRole.panel,
    this.live = false,
  });

  final Widget child;

  /// True for glass that floats over content that moves (bottom action bar,
  /// pop-up menus, the settings preview): it blurs what is behind it every
  /// frame. Everything else sits on the fixed app background, where a live
  /// blur looks the same as none but costs a full-screen copy and a blur pass
  /// per surface per frame on Impeller; that glass keeps its tint, rim and
  /// light but skips the backdrop read (the same idea as a frozen backdrop).
  final bool live;
  final double radius;
  final EdgeInsetsGeometry padding;

  /// 0..1 intensity of the chromatic refraction.
  final double chromatic;

  /// Darker "lens" variant.
  final bool dark;

  final GlassRole role;

  @override
  Widget build(BuildContext context) {
    // Listens to the settings itself: glass redraws live even when created
    // as a const widget inside a parent that does not rebuild.
    return ListenableBuilder(
      listenable: AppState.I,
      builder: (context, _) {
        final shadows = glassDepthShadows(radius);
        Widget body;
        if (!glassEnabled(role)) {
          body = Container(
            padding: padding,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: dark ? const Color(0xFF26252B) : solidSurface,
              borderRadius: BorderRadius.circular(radius),
              border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
            ),
            child: child,
          );
        } else {
          final settings = appGlassSettings(dark: dark, chromatic: chromatic);
          Widget glass = GlassContainer(
            shape: LiquidRoundedSuperellipse(borderRadius: radius),
            padding: padding,
            settings: settings,
            useOwnLayer: true,
            quality: appGlassQuality,
            clipBehavior: Clip.antiAlias,
            child: withGlassShadows(child),
          );
          if (!live) {
            // tells the lightweight renderer the blur is already there, so it
            // pushes no BackdropFilterLayer for this surface
            glass = InheritedLiquidGlass(settings: settings, quality: appGlassQuality, isBlurProvidedByAncestor: true, child: glass);
          }
          body = GlossOverlay(radius: radius, child: glass);
        }
        if (shadows.isEmpty) return body;
        return DecoratedBox(
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(radius), boxShadow: shadows),
          child: body,
        );
      },
    );
  }
}

/// Dialogs and sheets: the screen behind is blurred with the glass blur
/// (Impostazioni › Vetro › Dove usarlo › Finestre di dialogo).
Future<T?> showAppDialog<T>({required BuildContext context, required WidgetBuilder builder, bool barrierDismissible = true}) {
  return showDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    barrierColor: Colors.black.withValues(alpha: AppState.I.glass.useDialogs ? 0.35 : 0.6),
    builder: (ctx) {
      final g = AppState.I.glass;
      final child = builder(ctx);
      if (!g.useDialogs) return child;
      final sigma = (g.blur + g.frost * 12).clamp(0.0, 40.0) * 0.6;
      return BackdropFilter(filter: ui.ImageFilter.blur(sigmaX: sigma, sigmaY: sigma), child: child);
    },
  );
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
    return ListenableBuilder(
      listenable: AppState.I,
      child: child,
      builder: (context, child) {
        final g = AppState.I.glass;
        final gloss = g.gloss ? g.glossIntensity : 0.0;
        final chroma = (g.chromatic / 0.05).clamp(0.0, 1.0);
        if (gloss <= 0.01 && chroma <= 0.01) return child!;
        return CustomPaint(
          foregroundPainter: GlossPainter(radius: radius, intensity: gloss, lightAngle: g.lightAngle, chroma: chroma),
          child: child,
        );
      },
    );
  }
}

class GlossPainter extends CustomPainter {
  GlossPainter({required this.radius, required this.intensity, required this.lightAngle, this.chroma = 0});

  final double radius;
  final double intensity;

  /// 0..1 chromatic fringes along the edge (aberration).
  final double chroma;

  /// Degrees, same convention as the glass light (135 = top-left).
  final double lightAngle;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final r = math.min(radius, size.shortestSide / 2);
    final rr = RRect.fromRectAndRadius(rect.deflate(0.8), Radius.circular(math.max(0, r - 0.8)));
    final a = lightAngle * math.pi / 180;
    final a0 = a;
    final begin = Alignment(math.cos(a), -math.sin(a));
    final end = Alignment(-math.cos(a), math.sin(a));
    final i = intensity.clamp(0.0, 1.0);
    if (chroma > 0.01) {
      // dispersion: cool fringe on the lit side, warm/magenta on the far side.
      // A wide faint stroke under a narrow one reads as the soft fringe that a
      // mask blur gave, without an offscreen blur pass every frame.
      final c = chroma.clamp(0.0, 1.0);
      Shader fringe(double a) => SweepGradient(
            colors: [
              const Color(0xFF3FD5FF).withValues(alpha: 0.75 * c * a),
              const Color(0xFFFF4FD8).withValues(alpha: 0.55 * c * a),
              const Color(0xFFFFA43A).withValues(alpha: 0.70 * c * a),
              const Color(0xFF7A5CFF).withValues(alpha: 0.55 * c * a),
              const Color(0xFF3FD5FF).withValues(alpha: 0.75 * c * a),
            ],
            transform: GradientRotation(a0 + math.pi),
          ).createShader(rect);
      canvas.drawRRect(
        rr.deflate(1.0),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5 + 4.5 * c
          ..shader = fringe(0.30),
      );
      canvas.drawRRect(
        rr.deflate(1.0),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.0 + 1.5 * c
          ..shader = fringe(0.55),
      );
    }
    if (i <= 0.01) return;
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
        ..strokeWidth = 4
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
      old.radius != radius || old.intensity != intensity || old.lightAngle != lightAngle || old.chroma != chroma;
}
