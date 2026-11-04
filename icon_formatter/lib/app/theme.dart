import 'package:flutter/material.dart';

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

ThemeData buildTheme(Appearance a) {
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
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    visualDensity: density,
    scaffoldBackgroundColor: Palette.bg,
    canvasColor: Palette.bg,
    fontFamily: 'Segoe UI',
    textTheme: const TextTheme(
      headlineSmall: TextStyle(fontWeight: FontWeight.w600, letterSpacing: -0.4, color: Palette.text),
      titleLarge: TextStyle(fontWeight: FontWeight.w600, letterSpacing: -0.3, color: Palette.text),
      titleMedium: TextStyle(fontWeight: FontWeight.w600, color: Palette.text),
      titleSmall: TextStyle(fontWeight: FontWeight.w600, color: Palette.text2, letterSpacing: 0.2),
      bodyMedium: TextStyle(color: Palette.text, height: 1.35),
      bodySmall: TextStyle(color: Palette.text2, height: 1.35),
      labelLarge: TextStyle(fontWeight: FontWeight.w600),
    ),
    dividerColor: Colors.white.withValues(alpha: 0.07),
    sliderTheme: SliderThemeData(
      trackHeight: 3,
      activeTrackColor: accent,
      inactiveTrackColor: Colors.white.withValues(alpha: 0.10),
      thumbColor: accent,
      overlayColor: accent.withValues(alpha: 0.12),
      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(shape: const StadiumBorder(), padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14)),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: Palette.text,
        side: BorderSide(color: Colors.white.withValues(alpha: 0.14)),
        shape: const StadiumBorder(),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      ),
    ),
    textButtonTheme: TextButtonThemeData(style: TextButton.styleFrom(foregroundColor: accent, shape: const StadiumBorder())),
    iconButtonTheme: IconButtonThemeData(style: IconButton.styleFrom(shape: const CircleBorder())),
    chipTheme: const ChipThemeData(shape: StadiumBorder()),
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
        side: WidgetStatePropertyAll(BorderSide(color: Colors.white.withValues(alpha: 0.12))),
      ),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? Colors.white : Palette.text2),
      trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? accent : Colors.white.withValues(alpha: 0.08)),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: const Color(0xFF26252A),
      contentTextStyle: const TextStyle(color: Palette.text),
      shape: RoundedRectangleBorder(borderRadius: r),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: const Color(0xFF1C1C1F),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(a.radius)),
    ),
    bottomSheetTheme: const BottomSheetThemeData(backgroundColor: Color(0xFF1A1A1D), showDragHandle: true),
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
