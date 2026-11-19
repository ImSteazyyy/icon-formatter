import 'package:flutter/material.dart';

import '../widgets/common.dart' show kButtonHeight;
import '../widgets/liquid_glass.dart';

import 'models.dart';
import 'state.dart';

/// Charcoal palette; accent is user-configurable (default pink #BA4CD4).
class Palette {
  static bool get _light => AppState.I.appearance.light;
  static Color get bg => _light ? const Color(0xFFF2F2F2) : const Color(0xFF0B0B0D);
  static Color get bg2 => _light ? const Color(0xFFE9E9E9) : const Color(0xFF141416);
  static Color get surface => _light ? const Color(0xFFFCFCFC) : const Color(0xFF1A1A1C);
  static Color get text => _light ? const Color(0xFF1C1C1C) : const Color(0xFFF2F2F2);
  static Color get text2 => _light ? const Color(0xFF484848) : const Color(0xFFC8C8C8);
  static Color get text3 => _light ? const Color(0xFF777777) : const Color(0xFF929292);

  /// Foreground: white on dark, near black on light (icons, overlays, primary button).
  static Color get fg => _light ? const Color(0xFF111114) : Colors.white;

  /// The opposite of [fg]: label of the primary (fg-filled) button.
  static Color get onFg => _light ? Colors.white : const Color(0xFF111114);

  /// Cells and solid cards of the Glass style.
  static Color get card => _light ? const Color(0xFFFFFFFF) : const Color(0xFF1C1B20);

  /// Raised controls (tool buttons, chips, snack bars).
  static Color get raised => _light ? const Color(0xFFE6E6EA) : const Color(0xFF26262B);

  /// Dialogs, sheets and menus.
  static Color get overlayBase => _light ? const Color(0xFFF7F7F9) : const Color(0xFF1C1C1F);

  /// Notices and toasts.
  static Color get toast => _light ? const Color(0xF2FFFFFF) : const Color(0xF2242329);

  /// Checkerboard behind transparent icons.
  static Color get checkA => _light ? const Color(0xFFD9D9DE) : const Color(0xFF55555C);
  static Color get checkB => _light ? const Color(0xFFF1F1F3) : const Color(0xFF3E3E44);
  static const danger = Color(0xFFD07A6A);
  static const ok = Color(0xFF8FB07A);
  static const warn = Color(0xFFD6B25E);
}

ThemeData buildTheme(Appearance a, [GlassConfig? glass]) {
  final g = glass ?? GlassConfig();
  // dialogs, sheets and menus: translucent anthracite when glass is on for
  // them (the screen behind is blurred by showAppDialog), solid otherwise
  final tintCol = g.tintColor != 0 ? Color(g.tintColor | 0xFF000000) : (a.light ? const Color(0xFFE2E2E8) : const Color(0xFF2A2930));
  final overlay = g.useDialogs
      ? Color.alphaBlend(tintCol.withValues(alpha: (g.tint * 0.9).clamp(0.0, 0.3)), Palette.overlayBase).withValues(alpha: (0.94 - g.frost * 0.12).clamp(0.72, 0.96))
      : Palette.overlayBase;
  final overlayShape = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(a.radius + 10),
    side: BorderSide(color: Palette.fg.withValues(alpha: g.useDialogs ? 0.10 : 0.05)),
  );
  final accent = a.accentColor;
  final scheme = ColorScheme.fromSeed(
    seedColor: accent,
    brightness: a.light ? Brightness.light : Brightness.dark,
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
  final nothing = a.style == UiStyle.nothing;
  final shadows = nothing || a.light ? const <Shadow>[] : glassTextShadowsFor(g);
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    visualDensity: density,
    scaffoldBackgroundColor: nothing ? NothingColors.bg : Palette.bg,
    canvasColor: nothing ? NothingColors.bg : Palette.bg,
    fontFamily: nothing ? 'Inter' : 'Segoe UI',
    textTheme: _withShadows((a.light ? Typography.material2021(platform: TargetPlatform.android).black : Typography.material2021(platform: TargetPlatform.android).white).merge(TextTheme(
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
    primaryTextTheme: _withShadows(a.light ? Typography.material2021(platform: TargetPlatform.android).black : Typography.material2021(platform: TargetPlatform.android).white, shadows),
    dividerColor: Palette.fg.withValues(alpha: 0.07),
    sliderTheme: SliderThemeData(
      trackHeight: 6,
      activeTrackColor: nothing ? NothingColors.on : accent,
      inactiveTrackColor: Palette.fg.withValues(alpha: 0.12),
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
        backgroundColor: Palette.fg,
        foregroundColor: Palette.onFg,
        iconColor: Palette.onFg,
        textStyle: const TextStyle(fontWeight: FontWeight.w700, shadows: []),
        minimumSize: const Size(64, kButtonHeight),
        padding: const EdgeInsets.symmetric(horizontal: 20),
        disabledForegroundColor: Palette.fg.withValues(alpha: 0.92),
        disabledBackgroundColor: Palette.fg.withValues(alpha: 0.10),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: Palette.text,
        side: BorderSide(color: Palette.fg.withValues(alpha: 0.14)),
        shape: const StadiumBorder(),
        minimumSize: const Size(64, kButtonHeight),
        padding: const EdgeInsets.symmetric(horizontal: 18),
      ),
    ),
    textButtonTheme: TextButtonThemeData(style: TextButton.styleFrom(foregroundColor: accent, shape: const StadiumBorder(), minimumSize: const Size(48, kButtonHeight), padding: const EdgeInsets.symmetric(horizontal: 16))),
    iconButtonTheme: IconButtonThemeData(style: IconButton.styleFrom(shape: const CircleBorder())),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: nothing ? NothingColors.card : Palette.fg.withValues(alpha: 0.04),
      border: OutlineInputBorder(borderRadius: r, borderSide: BorderSide(color: Palette.fg.withValues(alpha: 0.10))),
      enabledBorder: OutlineInputBorder(borderRadius: r, borderSide: BorderSide(color: Palette.fg.withValues(alpha: 0.10))),
      focusedBorder: OutlineInputBorder(borderRadius: r, borderSide: BorderSide(color: accent.withValues(alpha: 0.7))),
      isDense: true,
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        shape: const WidgetStatePropertyAll(StadiumBorder()),
        minimumSize: const WidgetStatePropertyAll(Size(48, kButtonHeight)),
        side: WidgetStatePropertyAll(BorderSide(color: Palette.fg.withValues(alpha: 0.12))),
      ),
    ),
    switchTheme: SwitchThemeData(
      // Nothing style: white track and black knob when on
      thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? (nothing ? NothingColors.onOn : Colors.white) : Palette.text2),
      trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? (nothing ? NothingColors.on : accent) : (nothing ? NothingColors.tertiary : Palette.fg.withValues(alpha: 0.10))),
      trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: Palette.raised,
      contentTextStyle: TextStyle(color: Palette.text),
      shape: RoundedRectangleBorder(borderRadius: r),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: nothing ? NothingColors.card : overlay,
      surfaceTintColor: Colors.transparent,
      shape: overlayShape,
      titleTextStyle: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, letterSpacing: -0.4, color: Palette.text),
      contentTextStyle: TextStyle(fontSize: 14.5, height: 1.45, color: Palette.text2),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      // solid: a sheet has no backdrop blur, a see-through one showed the bars behind
      backgroundColor: nothing ? NothingColors.card : overlay.withValues(alpha: 1),
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(a.radius + 10))),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: nothing ? NothingColors.raised : overlay,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(a.radius * 0.8)),
      textStyle: TextStyle(color: Palette.text, fontSize: 14),
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
    listTileTheme: ListTileThemeData(
      contentPadding: EdgeInsets.zero,
      titleTextStyle: TextStyle(fontSize: 15, color: Palette.text),
      subtitleTextStyle: TextStyle(fontSize: 12, color: Palette.text2),
      iconColor: Palette.text2,
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      titleTextStyle: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, letterSpacing: -0.4, color: Palette.text),
    ),
    chipTheme: ChipThemeData(
      shape: const StadiumBorder(),
      side: BorderSide(color: Palette.fg.withValues(alpha: 0.07)),
      backgroundColor: nothing ? NothingColors.card : Palette.raised,
      selectedColor: nothing ? NothingColors.tertiary : accent.withValues(alpha: 0.30),
      labelStyle: TextStyle(color: Palette.text, fontSize: 14, fontWeight: FontWeight.w600),
    ),
    pageTransitionsTheme: PageTransitionsTheme(
      builders: {
        for (final p in TargetPlatform.values)
          // the transition paints a backdrop behind the page: the app's own
          // background, not the scheme's lighter surface (it flashed grey)
          p: a.animations ? FadeForwardsPageTransitionsBuilder(backgroundColor: nothing ? NothingColors.bg : Palette.bg) : const _NoTransition(),
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
