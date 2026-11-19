import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import '../app/models.dart';
import '../app/state.dart';
import '../app/theme.dart';
import 'glassfix_premium_gate.dart';

/// "Stile Nothing": solid black and grey surfaces, no glass.
bool get nothingStyle => AppState.I.appearance.style == UiStyle.nothing;

/// Nothing style surfaces (from the darkest to the lightest).
class NothingColors {
  // light: the Nothing light surfaces (#F2F2F2 page, white cards)
  static bool get _light => AppState.I.appearance.light;
  static Color get bg => _light ? const Color(0xFFF2F2F2) : const Color(0xFF000000);
  static Color get card => _light ? const Color(0xFFFCFCFC) : const Color(0xFF141414);
  static Color get raised => _light ? const Color(0xFFE9E9E9) : const Color(0xFF1C1C1C);
  static Color get control => _light ? const Color(0xFFE3E3E3) : const Color(0xFF292929);
  static Color get tertiary => _light ? const Color(0xFFC8C8C8) : const Color(0xFF323232);

  /// The "on" pill (active filter, done step, switch track): white on
  /// black, near black on light.
  static Color get on => _light ? const Color(0xFF1C1C1C) : const Color(0xFFF2F2F2);

  /// Text and icons on [on].
  static Color get onOn => _light ? Colors.white : Colors.black;

  /// Blurred pill of the bottom bar.
  static Color get navPill => _light ? const Color(0xC8FFFFFF) : const Color(0xB8282828);
}

/// Space at the bottom covered by floating glass bars (Android phone
/// layout). Scrollable pages add it as bottom padding so content scrolls
/// under the glass instead of being cut off.
class GlassInsets extends InheritedWidget {
  const GlassInsets({super.key, required this.bottom, this.folded = false, required super.child});

  final double bottom;

  /// The bottom bar is folded into its round button (Glass style).
  final bool folded;

  static double of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<GlassInsets>()?.bottom ?? 0;

  static bool foldedOf(BuildContext context) => context.dependOnInheritedWidgetOfExactType<GlassInsets>()?.folded ?? false;

  @override
  bool updateShouldNotify(GlassInsets old) => old.bottom != bottom || old.folded != folded;
}

/// Where a floating action bar sits over the bottom bar. With the bar open
/// it stands above it; with the bar folded it drops down next to the round
/// button left, at the bottom edge (the bar is out of the way).
class FloatingBarSlot extends StatelessWidget {
  const FloatingBarSlot({super.key, required this.child, this.side = 12});

  final Widget child;

  /// Gap to the screen edges when the bar is open.
  final double side;

  @override
  Widget build(BuildContext context) {
    final under = GlassInsets.of(context);
    final folded = GlassInsets.foldedOf(context);
    final inset = MediaQuery.of(context).viewPadding.bottom;
    // folded button: 50 dp round, 12 dp from the left and bottom edges
    // same start as the tab bar: rising faster than it opens, dropping a bit
    // slower than it folds, so the two never cross
    return AnimatedPositioned(
      duration: Duration(milliseconds: folded ? 340 : 200),
      curve: folded ? Curves.easeInOutCubic : Curves.easeOutCubic,
      left: folded ? 12 + 50 + 8 : side,
      right: side,
      // centred on the folded button (measured on the emulator)
      bottom: folded ? inset + 12 : under - 4, // the nav box includes 12dp of top padding
      child: child,
    );
  }
}

/// Glass material from Impostazioni › Vetro, rendered by
/// `liquid_glass_widgets`. [chromatic] scales the configured aberration.
/// Every glass surface of the app reads it, so a change in the settings is
/// visible everywhere at once (no restart, no per-screen copies).
LiquidGlassSettings appGlassSettings({bool dark = false, double chromatic = 0.5}) {
  final g = AppState.I.glass;
  if (nativeGlass) {
    // native dark material; each control scales the preset value it stands
    // for, so the defaults reproduce the preset exactly
    // every control is a ratio to its default applied to the preset value,
    // so the defaults give the preset unchanged
    final base = AppState.I.appearance.light ? _nativeLight : _nativeDark;
    double ratio(double v, double def) => (v / def).clamp(0.0, double.infinity);
    // Film: opacity of the body colour
    final alpha = (ratio(g.nFilm, 0.5) * base.glassColor.a).clamp(0.0, 1.0);
    final Color color;
    if (dark) {
      color = Colors.black.withValues(alpha: (g.lensDarkness * 0.7).clamp(0.0, 0.6));
    } else if (g.tintColor != 0) {
      // Tint: the hue of the chosen colour, light and pastel, same opacity
      final hsv = HSVColor.fromColor(Color(g.tintColor | 0xFF000000));
      color = HSVColor.fromAHSV(alpha, hsv.hue, 0.33, 1).toColor();
    } else {
      color = Colors.white.withValues(alpha: alpha);
    }
    // Frost (dp) sets how much frost; with Frost off the body is clear and
    // only a light blur is left
    final frost = base.frost * ratio(g.nFrost, 2);
    return base.copyWith(
      glassColor: color,
      frost: g.nFrostOn ? frost : 0,
      blur: g.nFrostOn ? base.blur : math.max(base.blur, frost * 0.25),
      // Colour: scales the saturation boost above neutral
      saturation: 1 + ratio(g.nColour, 0.6) * (base.saturation - 1),
      rimLight: base.rimLight * ratio(g.nEdgeLight, 0.55),
      thickness: math.max(1.0, base.thickness * ratio(g.nEdgeDepth, 19.2)),
      refractiveIndex: 1 + ratio(g.nBend, 28.8) * (base.refractiveIndex - 1),
      chromaticAberration: g.nSplit ? 0.4 : 0,
      // Depth: a deeper, darker edge
      edgeAbsorption: base.edgeAbsorption * (g.depth ? 2 : 1),
    );
  }
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

/// Light appearance: the package's iOS 27 light values.
const _nativeLight = LiquidGlassSettings(
  glassColor: Color(0x87F8F8F8),
  saturation: 2.1,
  blur: 0.6,
  blurWeight: 0.8,
  frost: 14,
  frostOpacity: 0.73,
  frostClamp: 0.4,
  frostWeight: 2.0,
  thickness: 32,
  refractiveIndex: 1.24,
  lensModel: GlassLensModel.paraxial,
  lightAngle: 1.5707963267948966,
  lightIntensity: 0,
  fresnelStrength: 0,
  chromaticAberration: 0,
  edgeAbsorption: 0.035,
  rimShade: 1,
  rimLight: 1,
);

/// Base of "Vetro nativo": dark frosted body, thin outline, light on the rim.
const _nativeDark = LiquidGlassSettings(
  glassColor: Color(0x1FFFFFFF),
  saturation: 1.4,
  blur: 0.6,
  blurWeight: 2.5,
  frost: 14,
  frostOpacity: 0.85,
  frostClamp: -0.45,
  frostWeight: 0.5,
  thickness: 32,
  refractiveIndex: 1.24,
  lensModel: GlassLensModel.paraxial,
  lightAngle: -1.5707963267948966,
  lightIntensity: 0,
  fresnelStrength: 0,
  chromaticAberration: 0,
  edgeAbsorption: 0.035,
  rimShade: 1,
  rimShadeEnds: 0,
  rimLight: 1.15,
  bodyShade: 0.28,
  shadowElevation: 0,
);

/// Bottom bar material: glass, or a solid anthracite pill when
/// "Vetro nella barra in basso" is off.
LiquidGlassSettings navGlassSettings() {
  if (AppState.I.glass.useNav) return appGlassSettings(chromatic: 0.6);
  return LiquidGlassSettings(glassColor: Palette.overlayBase.withValues(alpha: 0.95), blur: 0, thickness: 0, chromaticAberration: 0, lightIntensity: 0, saturation: 1);
}

/// The bottom tab bar of the Glass style; the settings preview draws the
/// same widget, so what the preview shows is what the bar does.
Widget appGlassTabBar({
  Key? key,
  required List<IconData> icons,
  required List<String> labels,
  required int index,
  required ValueChanged<int> onSelect,
  bool minimized = false,
  VoidCallback? onExpand,
}) {
  final g = AppState.I.glass;
  final accent = AppState.I.appearance.accentColor;
  final bar = navGlassSettings();
  return GlassTabBar.minimizable(
    key: key,
    // icons only; the names stay for screen readers
    tabs: [for (var i = 0; i < icons.length; i++) GlassTab(icon: Icon(icons[i]), semanticLabel: labels[i])],
    // the active tab is white on its puck, the others carry the accent
    selectedIconColor: Palette.fg,
    unselectedIconColor: Color.lerp(accent, Palette.fg, 0.55),
    iconSize: 26,
    selectedIndex: index,
    onTabSelected: onSelect,
    minimized: minimized,
    onMinimizedTabTap: onExpand,
    horizontalPadding: 12,
    verticalPadding: 12,
    settings: bar,
    quality: glassQualityFor(live: true),
    // Scheda attiva: from no puck to solid white
    indicatorColor: g.native ? Palette.fg.withValues(alpha: g.nActiveTab.clamp(0.0, 1.0)) : null,
    // while dragging, a clear round lens that lifts above the bar and
    // magnifies the icon under it
    indicatorSettings: bar.copyWith(frost: 0, blur: 0, glassColor: Colors.white.withValues(alpha: 0.03)),
    indicatorExpansion: const EdgeInsets.symmetric(horizontal: 6, vertical: 14),
    magnification: 1.25,
  );
}

/// Where a glass surface sits; each role can be switched to a solid
/// surface in Impostazioni › Vetro › Dove usarlo.
enum GlassRole { panel, button, nav, lens }

bool glassEnabled(GlassRole r) {
  final g = AppState.I.glass;
  return switch (r) {
    GlassRole.panel => g.native ? g.nPanels : g.usePanels,
    GlassRole.button => g.useButtons,
    GlassRole.nav => g.useNav,
    GlassRole.lens => g.useNav,
  };
}

/// Solid anthracite used where glass is switched off (and by plain cards).
Color get solidSurface => Palette.overlayBase;

/// Drop shadow of glass surfaces ("Profondità").
List<BoxShadow> glassDepthShadows(double radius) {
  // native glass: Depth deepens the edge instead (see appGlassSettings)
  if (nothingStyle || nativeGlass || !AppState.I.glass.depth) return const [];
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
/// 30-60 fps on the test phone. The soft edge is rebuilt from a few
/// crisp copies placed on rings as wide as the blur, each faint; a crisp
/// glyph copy costs about as much as the text itself.
List<Shadow> glassTextShadows() => nothingStyle || AppState.I.appearance.light ? const [] : glassTextShadowsFor(AppState.I.glass);

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

/// Render tier of one surface. With the native material, Materiale chooses
/// it for everything: Qualità = premium, Bilanciato = standard, Più veloce =
/// minimal, on bars and cards alike.
GlassQuality glassQualityFor({required bool live}) {
  if (!nativeGlass) return appGlassQuality;
  return switch (AppState.I.glass.quality) {
    // one tier for bars and cards alike, so they always look the same
    GlassQualityLevel.quality => premiumGlassSupported ? GlassQuality.premium : GlassQuality.standard,
    GlassQualityLevel.balanced => GlassQuality.standard,
    GlassQualityLevel.fast => GlassQuality.minimal,
  };
}

/// "Vetro nativo": the native dark material. Its outline, frost and shading are
/// drawn in full by "Qualità", approximated by the lighter levels.
bool get nativeGlass => AppState.I.glass.native;

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
        if (nothingStyle) {
          // floating chrome (action bar, menus, jump buttons): the same frosted
          // pill as the tab bar, so the content shows through, blurred
          if (live) {
            return ClipRRect(
              borderRadius: BorderRadius.circular(radius),
              child: BackdropFilter(
                filter: ui.ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                child: Container(padding: padding, color: NothingColors.navPill, child: child),
              ),
            );
          }
          return Container(
            padding: padding,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(color: dark ? NothingColors.control : NothingColors.card, borderRadius: BorderRadius.circular(radius)),
            child: child,
          );
        }
        Widget body;
        // native style: cards are solid, but a panel floating over the
        // content (action bars, menus) is glass like the bottom bar
        final floating = live && role == GlassRole.panel && AppState.I.glass.native && AppState.I.glass.useNav;
        if (!glassEnabled(role) && !floating) {
          body = Container(
            padding: padding,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: dark ? Palette.raised : (AppState.I.glass.native ? Palette.card : solidSurface),
              borderRadius: BorderRadius.circular(radius),
              border: Border.all(color: Palette.fg.withValues(alpha: 0.06)),
            ),
            child: child,
          );
        } else {
          // cards in scrolling pages: the bar's colour, rim and light without
          // the frost, and no backdrop read (a scrolling list made the frost
          // lag and turn black); floating chrome keeps the full material
          final full = appGlassSettings(dark: dark, chromatic: chromatic);
          final settings = nativeGlass && !live ? full.copyWith(frost: 0, blur: 0) : full;
          final quality = live ? glassQualityFor(live: true) : (nativeGlass ? GlassQuality.standard : appGlassQuality);
          // premium surfaces join in batches (GlassPremiumGate), not all at once
          final Widget glass = GlassStagedQuality(
            quality: quality,
            builder: (q) {
              final container = GlassContainer(
                shape: LiquidRoundedSuperellipse(borderRadius: radius),
                padding: padding,
                settings: settings,
                useOwnLayer: true,
                quality: q,
                clipBehavior: Clip.antiAlias,
                child: withGlassShadows(child),
              );
              // native material: the lightweight renderer needs its own backdrop
              // read, or the card comes out black. Not live: the blur is already
              // there, so the renderer pushes no BackdropFilterLayer for this surface.
              if (live) return container;
              return InheritedLiquidGlass(settings: settings, quality: q, isBlurProvidedByAncestor: true, child: container);
            },
          );
          // native glass: the rim light is in the material already, as on
          // the bottom bar; the extra gloss would set the two apart
          body = nativeGlass ? glass : GlossOverlay(radius: radius, child: glass);
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

/// Bottom sheet that floats like the bars: away from the screen edges,
/// every corner rounded, a solid body and its own grab handle.
Future<T?> showAppSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool isScrollControlled = false,
  bool showDragHandle = true,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: isScrollControlled,
    backgroundColor: Colors.transparent,
    elevation: 0,
    showDragHandle: false,
    builder: (ctx) {
      final theme = Theme.of(ctx).bottomSheetTheme;
      final r = AppState.I.appearance.radius + 12;
      final bottom = MediaQuery.of(ctx).viewPadding.bottom;
      return Padding(
        padding: EdgeInsets.fromLTRB(12, 0, 12, 12 + bottom),
        child: Material(
          color: theme.backgroundColor,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(r),
            side: nothingStyle ? BorderSide.none : BorderSide(color: Colors.white.withValues(alpha: 0.08)),
          ),
          clipBehavior: Clip.antiAlias,
          child: MediaQuery.removePadding(
            context: ctx,
            removeBottom: true,
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              if (showDragHandle)
                Center(
                  child: Container(
                    margin: const EdgeInsets.symmetric(vertical: 10),
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.35), borderRadius: BorderRadius.circular(2)),
                  ),
                ),
              Flexible(child: builder(ctx)),
            ]),
          ),
        ),
      );
    },
  );
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

/// Glossy specular rim over a glass shape (Impostazioni › Vetro ›
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
        // the native material draws its own rim line and light
        if (nativeGlass || (gloss <= 0.01 && chroma <= 0.01)) return child!;
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
