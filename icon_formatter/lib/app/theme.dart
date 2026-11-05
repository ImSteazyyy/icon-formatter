import 'package:flutter/material.dart';

import '../widgets/common.dart' show kButtonHeight;
import '../widgets/liquid_glass.dart';

import 'models.dart';

/// Charcoal palette; accent is user-configurable (default pink #BA4CD4).
class Palette {
  static const bg = Color(0xFF0E0E0F);
  static const bg2 = Color(0xFF141416);
  static const surface = Color(0xFF1A1A1C);
  static const text = Color(0xFFE9E7E2);
  static const text2 = Color(0xFF9E9B94);
  static const text3 = Color(0xFF6E6C67);
  static const danger = Color(0xFFD07A6A);
  static const ok = Color(0xFF8FB07A);
  static const warn = Color(0xFFD6B25E);
}

ThemeData buildTheme(Appearance a, [GlassConfig? glass]) {
  final g = glass ?? GlassConfig();
  // dialogs, sheets and menus: translucent anthracite when glass is on for
  // them (the screen behind is blurred by showAppDialog), solid otherwise
  final tintCol = g.tintColor != 0 ? Color(g.tintColor | 0xFF000000) : const Color(0xFF2A2930);
  final overlay = g.useDialogs
      ? Color.alphaBlend(tintCol.withValues(alpha: (g.tint * 0.9).clamp(0.0, 0.3)), const Color(0xFF1C1C1F)).withValues(alpha: (0.94 - g.frost * 0.12).clamp(0.72, 0.96))
      : const Color(0xFF1C1C1F);
  final overlayShape = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(a.radius + 10),
    side: BorderSide(color: Colors.white.withValues(alpha: g.useDialogs ? 0.10 : 0.05)),
  );
  final accent = a.accentColor;
  final scheme = ColorScheme.fromSeed(
    seedColor: accent,
    brightness: Brightness.dark,
  ).copyWith(
    primary: accent,
    onPrimary: accent.computeLuminance() > 0.35 ? const Color(0xFF17150F) : Colors.white,
    secondary: accent,
    surface: Palette.surface,
    onSurface: Palette.text,
    error: Palette.danger,
  );
  final r = BorderRadius.circular(a.radius * 0.6);
  final density = a.compact ? VisualDensity.compact : VisualDensity.standard;
  // "Ombra testo" on every label and icon of the app, buttons included, so
  // no text has it and the next one not (drawn without blur, see
  // glassTextShadows: cheap enough for the whole UI)
  final shadows = glassTextShadowsFor(g);
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    visualDensity: density,
    scaffoldBackgroundColor: Palette.bg,
    canvasColor: Palette.bg,
    fontFamily: 'Segoe UI',
    textTheme: _withShadows(Typography.material2021(platform: TargetPlatform.android).white.merge(const TextTheme(
      // page titles (Studio, AI, Pack, App, ...): large, like Impostazioni
      headlineSmall: TextStyle(fontSize: 32, fontWeight: FontWeight.w700, letterSpacing: -0.8, color: Palette.text),
      titleLarge: TextStyle(fontSize: 30, fontWeight: FontWeight.w700, letterSpacing: -0.7, color: Palette.text),
      titleMedium: TextStyle(fontWeight: FontWeight.w600, color: Palette.text),
      titleSmall: TextStyle(fontWeight: FontWeight.w600, color: Palette.text2, letterSpacing: 0.2),
      bodyMedium: TextStyle(color: Palette.text, height: 1.35),
      bodySmall: TextStyle(color: Palette.text2, height: 1.35),
      labelLarge: TextStyle(fontWeight: FontWeight.w600),
    )), shadows),
    iconTheme: IconThemeData(color: Palette.text, shadows: shadows),
    primaryTextTheme: _withShadows(Typography.material2021(platform: TargetPlatform.android).white, shadows),
    dividerColor: Colors.white.withValues(alpha: 0.07),
    sliderTheme: SliderThemeData(
      trackHeight: 6,
      activeTrackColor: accent,
      inactiveTrackColor: Colors.white.withValues(alpha: 0.12),
      thumbColor: Colors.white,
      overlayColor: accent.withValues(alpha: 0.14),
      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 10, elevation: 2),
      trackShape: const RoundedRectSliderTrackShape(),
      showValueIndicator: ShowValueIndicator.never,
    ),
    filledButtonTheme: FilledButtonThemeData(
      // disabled ("Seleziona delle app", busy steps): white label on a dim
      // pill, readable instead of grey on grey
      style: FilledButton.styleFrom(
        shape: const StadiumBorder(),
        minimumSize: const Size(64, kButtonHeight),
        padding: const EdgeInsets.symmetric(horizontal: 20),
        disabledForegroundColor: Colors.white.withValues(alpha: 0.92),
        disabledBackgroundColor: Colors.white.withValues(alpha: 0.10),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: Palette.text,
        side: BorderSide(color: Colors.white.withValues(alpha: 0.14)),
        shape: const StadiumBorder(),
        minimumSize: const Size(64, kButtonHeight),
        padding: const EdgeInsets.symmetric(horizontal: 18),
      ),
    ),
    textButtonTheme: TextButtonThemeData(style: TextButton.styleFrom(foregroundColor: accent, shape: const StadiumBorder(), minimumSize: const Size(48, kButtonHeight), padding: const EdgeInsets.symmetric(horizontal: 16))),
    iconButtonTheme: IconButtonThemeData(style: IconButton.styleFrom(shape: const CircleBorder())),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white.withValues(alpha: 0.04),
      border: OutlineInputBorder(borderRadius: r, borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.10))),
      enabledBorder: OutlineInputBorder(borderRadius: r, borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.10))),
      focusedBorder: OutlineInputBorder(borderRadius: r, borderSide: BorderSide(color: accent.withValues(alpha: 0.7))),
      isDense: true,
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        shape: const WidgetStatePropertyAll(StadiumBorder()),
        minimumSize: const WidgetStatePropertyAll(Size(48, kButtonHeight)),
        side: WidgetStatePropertyAll(BorderSide(color: Colors.white.withValues(alpha: 0.12))),
      ),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? Colors.white : Palette.text2),
      trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? accent : Colors.white.withValues(alpha: 0.10)),
      trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: const Color(0xFF26252A),
      contentTextStyle: const TextStyle(color: Palette.text),
      shape: RoundedRectangleBorder(borderRadius: r),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: overlay,
      surfaceTintColor: Colors.transparent,
      shape: overlayShape,
      titleTextStyle: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, letterSpacing: -0.4, color: Palette.text),
      contentTextStyle: const TextStyle(fontSize: 14.5, height: 1.45, color: Palette.text2),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: overlay,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(a.radius + 10))),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: overlay,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(a.radius * 0.8)),
      textStyle: const TextStyle(color: Palette.text, fontSize: 14),
    ),
    menuTheme: MenuThemeData(
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(overlay),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
        shape: WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: BorderRadius.circular(a.radius * 0.8))),
      ),
    ),
    dropdownMenuTheme: DropdownMenuThemeData(
      menuStyle: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(overlay),
        shape: WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: BorderRadius.circular(a.radius * 0.8))),
      ),
    ),
    listTileTheme: const ListTileThemeData(
      contentPadding: EdgeInsets.zero,
      titleTextStyle: TextStyle(fontSize: 15, color: Palette.text),
      subtitleTextStyle: TextStyle(fontSize: 12, color: Palette.text2),
      iconColor: Palette.text2,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      titleTextStyle: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, letterSpacing: -0.4, color: Palette.text),
    ),
    chipTheme: ChipThemeData(
      shape: const StadiumBorder(),
      side: BorderSide(color: Colors.white.withValues(alpha: 0.10)),
      backgroundColor: Colors.white.withValues(alpha: 0.04),
      selectedColor: accent.withValues(alpha: 0.22),
      labelStyle: const TextStyle(color: Palette.text, fontSize: 13),
    ),
    pageTransitionsTheme: PageTransitionsTheme(
      builders: {
        for (final p in TargetPlatform.values)
          p: a.animations ? const FadeForwardsPageTransitionsBuilder() : const _NoTransition(),
      },
    ),
  );
}

class _NoTransition extends PageTransitionsBuilder {
  const _NoTransition();

  @override
  Widget buildTransitions<T>(PageRoute<T> route, BuildContext context, Animation<double> animation,
          Animation<double> secondaryAnimation, Widget child) =>
      child;
}


TextTheme _withShadows(TextTheme t, List<Shadow> s) {
  if (s.isEmpty) return t;
  TextStyle? f(TextStyle? x) => x?.copyWith(shadows: s);
  return t.copyWith(
    displayLarge: f(t.displayLarge),
    displayMedium: f(t.displayMedium),
    displaySmall: f(t.displaySmall),
    headlineLarge: f(t.headlineLarge),
    headlineMedium: f(t.headlineMedium),
    headlineSmall: f(t.headlineSmall),
    titleLarge: f(t.titleLarge),
    titleMedium: f(t.titleMedium),
    titleSmall: f(t.titleSmall),
    bodyLarge: f(t.bodyLarge),
    bodyMedium: f(t.bodyMedium),
    bodySmall: f(t.bodySmall),
    labelLarge: f(t.labelLarge),
    labelMedium: f(t.labelMedium),
    labelSmall: f(t.labelSmall),
  );
}
