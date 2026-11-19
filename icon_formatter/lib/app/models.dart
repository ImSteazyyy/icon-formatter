import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';

import '../src/rust/api/engine.dart';
import '../l10n/strings.dart';

/// JSON helpers for bridge types (bridge classes are plain data).
Map<String, dynamic> translucentToJson(TranslucentSettings t) => {
      'brightness': t.brightness,
      'frost': t.frost,
      'transparency': t.transparency,
      'tint': t.tint,
      'contrast': t.contrast,
      'border': t.border,
      'reflection': t.reflection,
      'depth': t.depth,
      'shapeRatio': t.shapeRatio,
      'exponent': t.exponent,
      'seed': t.seed,
    };

TranslucentSettings translucentFromJson(Map<String, dynamic> j, TranslucentSettings d) =>
    TranslucentSettings(
      brightness: _d(j['brightness'], d.brightness),
      frost: _d(j['frost'], d.frost),
      transparency: _d(j['transparency'], d.transparency),
      tint: _d(j['tint'], d.tint),
      contrast: _d(j['contrast'], d.contrast),
      border: _d(j['border'], d.border),
      reflection: _d(j['reflection'], d.reflection),
      depth: _d(j['depth'], d.depth),
      shapeRatio: _d(j['shapeRatio'], d.shapeRatio),
      exponent: _d(j['exponent'], d.exponent),
      seed: (j['seed'] as num?)?.toInt() ?? d.seed,
    );

TranslucentSettings copyTranslucent(
  TranslucentSettings t, {
  double? brightness,
  double? frost,
  double? transparency,
  double? tint,
  double? contrast,
  double? border,
  double? reflection,
  double? depth,
  double? shapeRatio,
  double? exponent,
  int? seed,
}) =>
    TranslucentSettings(
      brightness: brightness ?? t.brightness,
      frost: frost ?? t.frost,
      transparency: transparency ?? t.transparency,
      tint: tint ?? t.tint,
      contrast: contrast ?? t.contrast,
      border: border ?? t.border,
      reflection: reflection ?? t.reflection,
      depth: depth ?? t.depth,
      shapeRatio: shapeRatio ?? t.shapeRatio,
      exponent: exponent ?? t.exponent,
      seed: seed ?? t.seed,
    );

Map<String, dynamic> placementToJson(PlacementSettings p) => {
      'glyphRatio': p.glyphRatio,
      'areaRatio': p.areaRatio,
      'centerX': p.centerX,
      'centerY': p.centerY,
      'areaFit': p.areaFit,
      'scaleMul': p.scaleMul,
      'offsetX': p.offsetX,
      'offsetY': p.offsetY,
    };

PlacementSettings placementFromJson(Map<String, dynamic> j, PlacementSettings d) => PlacementSettings(
      glyphRatio: _d(j['glyphRatio'], d.glyphRatio),
      areaRatio: _d(j['areaRatio'], d.areaRatio),
      centerX: _d(j['centerX'], d.centerX),
      centerY: _d(j['centerY'], d.centerY),
      areaFit: j['areaFit'] as bool? ?? d.areaFit,
      scaleMul: _d(j['scaleMul'], d.scaleMul),
      offsetX: _d(j['offsetX'], d.offsetX),
      offsetY: _d(j['offsetY'], d.offsetY),
    );

PlacementSettings copyPlacement(
  PlacementSettings p, {
  double? glyphRatio,
  double? areaRatio,
  double? centerX,
  double? centerY,
  bool? areaFit,
  double? scaleMul,
  double? offsetX,
  double? offsetY,
  bool? opticalCentre,
}) =>
    PlacementSettings(
      glyphRatio: glyphRatio ?? p.glyphRatio,
      areaRatio: areaRatio ?? p.areaRatio,
      centerX: centerX ?? p.centerX,
      centerY: centerY ?? p.centerY,
      areaFit: areaFit ?? p.areaFit,
      scaleMul: scaleMul ?? p.scaleMul,
      offsetX: offsetX ?? p.offsetX,
      offsetY: offsetY ?? p.offsetY,
      opticalCentre: opticalCentre ?? p.opticalCentre,
    );

Map<String, dynamic> segmentToJson(SegmentSettings s) => {
      'mode': s.mode.name,
      'tolerance': s.tolerance,
      'removeHoles': s.removeHoles,
      'refineEdges': s.refineEdges,
    };

SegmentSettings segmentFromJson(Map<String, dynamic> j, SegmentSettings d) => SegmentSettings(
      mode: SegMode.values.firstWhere((m) => m.name == j['mode'], orElse: () => d.mode),
      tolerance: _d(j['tolerance'], d.tolerance),
      removeHoles: j['removeHoles'] as bool? ?? d.removeHoles,
      refineEdges: j['refineEdges'] as bool? ?? d.refineEdges,
    );

SegmentSettings copySegment(SegmentSettings s, {SegMode? mode, double? tolerance, bool? removeHoles, bool? refineEdges}) =>
    SegmentSettings(
      mode: mode ?? s.mode,
      tolerance: tolerance ?? s.tolerance,
      removeHoles: removeHoles ?? s.removeHoles,
      refineEdges: refineEdges ?? s.refineEdges,
    );

double _d(Object? v, double d) => (v as num?)?.toDouble() ?? d;

String segModeLabel(SegMode m) => switch (m) {
      SegMode.auto => S.automatica,
      SegMode.keepAlpha => S.usaTrasparenzaEsistente,
      SegMode.removeBackground => S.rimuoviSempreSfondo,
      SegMode.none => S.nessunaImmagineIntera,
    };

/// Style preset (procedural translucent background parameters).
class StylePreset {
  StylePreset({required this.id, required this.name, required this.params, this.builtIn = false});

  final String id;
  String name;
  TranslucentSettings params;
  final bool builtIn;

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'builtIn': builtIn, 'params': translucentToJson(params)};

  static StylePreset fromJson(Map<String, dynamic> j, TranslucentSettings d) => StylePreset(
        id: j['id'] as String,
        name: j['name'] as String,
        builtIn: j['builtIn'] as bool? ?? false,
        params: translucentFromJson((j['params'] as Map).cast<String, dynamic>(), d),
      );
}

/// Built-in presets. Values tuned on the reference pack.
List<StylePreset> builtInPresets(TranslucentSettings d) => [
      StylePreset(id: 'nothing', name: S.traslucido, builtIn: true, params: d),
      StylePreset(
        id: 'liquid',
        name: S.liquidGlass,
        builtIn: true,
        params: copyTranslucent(d, brightness: 0.62, frost: 0.35, reflection: 0.85, border: 0.85, depth: 0.35, contrast: 0.7),
      ),
      StylePreset(
        id: 'minimal',
        name: S.minimal,
        builtIn: true,
        params: copyTranslucent(d, brightness: 0.55, frost: 0.0, reflection: 0.0, border: 0.25, depth: 0.0, contrast: 0.15),
      ),
      StylePreset(
        id: 'darkflat',
        name: S.darkFlat,
        builtIn: true,
        params: copyTranslucent(d, brightness: 0.25, frost: 0.0, reflection: 0.0, border: 0.0, depth: 0.0, contrast: 0.0),
      ),
      StylePreset(id: 'custom', name: S.custom, builtIn: true, params: d),
    ];

/// User base icon (stored as PNG in the app data folder).
class BaseIcon {
  BaseIcon({
    required this.id,
    required this.name,
    required this.path,
    required this.width,
    required this.height,
    this.calibration,
    this.calibrationInfo,
  });

  final String id;
  String name;
  final String path;
  final int width;
  final int height;

  /// Built-in bases (circle, squircle) are named in the app language.
  bool get builtIn => id == 'squircle' || id == 'circle';
  String get label => switch (id) {
        'squircle' => S.baseSquircle,
        'circle' => S.baseCerchio,
        _ => name,
      };
  PlacementSettings? calibration;

  /// Summary of the last calibration (samples, inliers, MAD, margins).
  Map<String, dynamic>? calibrationInfo;

  int get size => width > height ? width : height;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'path': path,
        'width': width,
        'height': height,
        if (calibration != null) 'calibration': placementToJson(calibration!),
        if (calibrationInfo != null) 'calibrationInfo': calibrationInfo,
      };

  static BaseIcon fromJson(Map<String, dynamic> j, PlacementSettings d) => BaseIcon(
        id: j['id'] as String,
        name: j['name'] as String,
        path: j['path'] as String,
        width: (j['width'] as num).toInt(),
        height: (j['height'] as num).toInt(),
        calibration: j['calibration'] == null ? null : placementFromJson((j['calibration'] as Map).cast(), d),
        calibrationInfo: (j['calibrationInfo'] as Map?)?.cast<String, dynamic>(),
      );
}

/// UI appearance settings.
/// Look of the whole app: "Stile Nothing" (default) or "Vetro".
enum UiStyle { nothing, glass }

/// Theme: follow the phone, or fixed light / dark.
enum ThemeChoice { system, light, dark }

/// Light mode for a choice; `system` follows the platform brightness.
bool effectiveLight(ThemeChoice c, ui.Brightness platform) => switch (c) {
      ThemeChoice.light => true,
      ThemeChoice.dark => false,
      ThemeChoice.system => platform == ui.Brightness.light,
    };

/// Choice from a saved state: the new field, else the old `light` bool
/// (true = light, false = dark); a fresh state follows the phone.
ThemeChoice themeChoiceFrom(Map<String, dynamic> j) {
  final saved = ThemeChoice.values.where((v) => v.name == j['themeChoice']);
  if (saved.isNotEmpty) return saved.first;
  if (j['light'] is bool) return (j['light'] as bool) ? ThemeChoice.light : ThemeChoice.dark;
  return ThemeChoice.system;
}

/// Backup reminder: after this many changes since the last backup.
const kBackupReminderChanges = 40;

/// Whether the backup banner shows: enough changes, no backup or an old one, not snoozed.
bool backupReminderDue({required int changes, required int lastBackupMs, required int snoozeUntilMs, required int nowMs}) {
  if (changes < kBackupReminderChanges || nowMs < snoozeUntilMs) return false;
  return lastBackupMs == 0 || nowMs - lastBackupMs > const Duration(days: 30).inMilliseconds;
}

class Appearance {
  double radius = 18;

  UiStyle style = UiStyle.nothing;

  /// Theme choice; [light] is the resolved value the whole app reads.
  ThemeChoice themeChoice = ThemeChoice.system;
  bool light = false;

  /// Power saving: glass fast and no animations. The values replaced are kept
  /// here and put back when it goes off.
  bool powerSaving = false;
  String? savedGlassQuality;
  bool savedAnimations = true;

  /// App language code ('' = the phone's language, English when not available).
  String language = '';

  /// The language actually used.
  String get languageCode {
    if (language.isNotEmpty && appLanguages.containsKey(language)) return language;
    final sys = ui.PlatformDispatcher.instance.locale.languageCode;
    return appLanguages.containsKey(sys) ? sys : 'en';
  }

  /// Red of the Nothing style (fixed: the accent picker belongs to "Vetro").
  static const nothingRed = 0xFFEC232B;
  /// Default accent: pink sampled from the user's Windows Start icon.
  static const defaultAccent = 0xFFBA4CD4;
  static const legacyAccent = 0xFFB9A96E;
  int accent = defaultAccent;
  bool animations = true;
  bool compact = false;

  Color get accentColor => Color(style == UiStyle.nothing ? nothingRed : accent);

  Map<String, dynamic> toJson() => {
        'radius': radius,
        'accent': accent,
        'animations': animations,
        'compact': compact,
        'style': style.name,
        'themeChoice': themeChoice.name,
        'light': light,
        'language': language,
        'powerSaving': powerSaving,
        'savedGlassQuality': savedGlassQuality,
        'savedAnimations': savedAnimations,
      };

  void load(Map<String, dynamic> j) {
    radius = _d(j['radius'], radius);
    accent = (j['accent'] as num?)?.toInt() ?? accent;
    animations = j['animations'] as bool? ?? animations;
    compact = j['compact'] as bool? ?? compact;
    style = UiStyle.values.firstWhere((v) => v.name == j['style'], orElse: () => style);
    language = j['language'] as String? ?? language;
    themeChoice = themeChoiceFrom(j);
    powerSaving = j['powerSaving'] as bool? ?? powerSaving;
    savedGlassQuality = j['savedGlassQuality'] as String? ?? savedGlassQuality;
    savedAnimations = j['savedAnimations'] as bool? ?? savedAnimations;
    syncLight();
  }

  /// Resolves [light] from the choice and the phone's brightness; true if it changed.
  bool syncLight() {
    final v = effectiveLight(themeChoice, ui.PlatformDispatcher.instance.platformBrightness);
    final changed = v != light;
    light = v;
    return changed;
  }
}

enum ExportNaming { original, withSize, prefixed }

class ExportSettings {
  bool customSize = false;
  int size = 512;
  ExportNaming naming = ExportNaming.original;
  String prefix = 'ic_';
  bool zip = false;
  String? destination;

  /// Own name and colour for the pack (launcher picker and pack viewer).
  String packName = '';
  int? packAccent;

  String packNameOr(String fallback) => packName.trim().isNotEmpty ? packName.trim() : fallback;
  int packAccentOr(int fallback) => packAccent ?? fallback;

  Map<String, dynamic> toJson() => {
        'packName': packName,
        'packAccent': packAccent,
        'customSize': customSize,
        'size': size,
        'naming': naming.name,
        'prefix': prefix,
        'zip': zip,
        'destination': destination,
      };

  void load(Map<String, dynamic> j) {
    customSize = j['customSize'] as bool? ?? customSize;
    size = (j['size'] as num?)?.toInt() ?? size;
    naming = ExportNaming.values.firstWhere((n) => n.name == j['naming'], orElse: () => naming);
    prefix = j['prefix'] as String? ?? prefix;
    zip = j['zip'] as bool? ?? zip;
    destination = j['destination'] as String?;
    packName = j['packName'] as String? ?? '';
    packAccent = (j['packAccent'] as num?)?.toInt();
  }

  /// Output file name for a source name (without extension handling).
  String fileName(String stem, int size) => switch (naming) {
        ExportNaming.original => '$stem.png',
        ExportNaming.withSize => S.png(stem, size),
        ExportNaming.prefixed => '$prefix$stem.png',
      };
}

enum GlassQualityLevel { fast, balanced, quality }

/// Liquid glass material (liquid_glass_widgets) used by bars, panels and lens.
/// One instance (AppState.I.glass) drives every glass surface of the app.
class GlassConfig {
  // defaults = the look chosen by the user on their phone
  double blur = 22.6;
  double thickness = 0;
  double chromatic = 0.012;
  double lightIntensity = 0;
  double lightAngle = 74;
  double refractiveIndex = 1.0;
  double saturation = 2.5;
  double frost = 0.61;
  double tint = 0.08;
  double rimLight = 0;
  double lensDarkness = 0.32;

  /// Render tier: fast (blur only, no shader), balanced (light shader),
  /// quality (full shader with refraction and chromatic aberration).
  GlassQualityLevel quality = GlassQualityLevel.balanced;

  /// Native dark material (the glass package preset, premium renderer):
  /// replaces the sliders of Materiale, Bordo e Luce where supported.
  bool native = true;

  // "Vetro nativo" controls (Materiale, Colore, Bordi)
  bool nFrostOn = true;
  double nFrost = 2;
  double nColour = 0.6;
  double nFilm = 0.5;
  double nActiveTab = 0.26;
  double nEdgeLight = 0.55;
  double nEdgeDepth = 19;
  double nBend = 29;
  bool nSplit = false;

  /// Native style: cards are solid like the rest of the page and the glass
  /// stays on what floats (bar, buttons); on = glass cards too.
  bool nPanels = true;

  /// Glass tint colour (ARGB without alpha meaning); 0 = neutral (white/black).
  int tintColor = 0;

  /// Soft drop shadow under glass surfaces.
  bool depth = true;

  /// Where the glass material is used (off = solid anthracite surface).
  bool useNav = true;
  bool usePanels = true;
  bool useButtons = true;
  bool useDialogs = true;

  bool get premium => quality == GlassQualityLevel.quality;

  /// Text/icon shadow on glass for legibility (0 = off).
  double textShadow = 0.6;

  /// Glossy specular rim like the reference icons (brightest facing the light).
  bool gloss = false;
  double glossIntensity = 0.6;
  double textShadowBlur = 6;

  Map<String, dynamic> toJson() => {
        'blur': blur,
        'thickness': thickness,
        'chromatic': chromatic,
        'lightIntensity': lightIntensity,
        'lightAngle': lightAngle,
        'refractiveIndex': refractiveIndex,
        'saturation': saturation,
        'frost': frost,
        'tint': tint,
        'rimLight': rimLight,
        'lensDarkness': lensDarkness,
        'quality': quality.name,
        'native': native,
        'nFrostOn': nFrostOn,
        'nFrost': nFrost,
        'nColour': nColour,
        'nFilm': nFilm,
        'nActiveTab': nActiveTab,
        'nEdgeLight': nEdgeLight,
        'nEdgeDepth': nEdgeDepth,
        'nBend': nBend,
        'nSplit': nSplit,
        'nPanels': nPanels,
        'tintColor': tintColor,
        'depth': depth,
        'useNav': useNav,
        'usePanels': usePanels,
        'useButtons': useButtons,
        'useDialogs': useDialogs,
        'textShadow': textShadow,
        'gloss': gloss,
        'glossIntensity': glossIntensity,
        'textShadowBlur': textShadowBlur,
      };

  void load(Map<String, dynamic> j) {
    blur = _d(j['blur'], blur);
    thickness = _d(j['thickness'], thickness);
    chromatic = _d(j['chromatic'], chromatic);
    lightIntensity = _d(j['lightIntensity'], lightIntensity);
    lightAngle = _d(j['lightAngle'], lightAngle);
    refractiveIndex = _d(j['refractiveIndex'], refractiveIndex);
    saturation = _d(j['saturation'], saturation);
    frost = _d(j['frost'], frost);
    tint = _d(j['tint'], tint);
    rimLight = _d(j['rimLight'], rimLight);
    lensDarkness = _d(j['lensDarkness'], lensDarkness);
    // v1.1: premium flag -> quality level
    if (j['premium'] == true) quality = GlassQualityLevel.quality;
    quality = GlassQualityLevel.values.firstWhere((q) => q.name == j['quality'], orElse: () => quality);
    tintColor = (j['tintColor'] as num?)?.toInt() ?? tintColor;
    native = j['native'] as bool? ?? native;
    nFrostOn = j['nFrostOn'] as bool? ?? nFrostOn;
    nFrost = _d(j['nFrost'], nFrost);
    nColour = _d(j['nColour'], nColour);
    nFilm = _d(j['nFilm'], nFilm);
    nActiveTab = _d(j['nActiveTab'], nActiveTab);
    nEdgeLight = _d(j['nEdgeLight'], nEdgeLight);
    nEdgeDepth = _d(j['nEdgeDepth'], nEdgeDepth);
    nBend = _d(j['nBend'], nBend);
    nSplit = j['nSplit'] as bool? ?? nSplit;
    nPanels = j['nPanels'] as bool? ?? nPanels;
    depth = j['depth'] as bool? ?? depth;
    useNav = j['useNav'] as bool? ?? useNav;
    usePanels = j['usePanels'] as bool? ?? usePanels;
    useButtons = j['useButtons'] as bool? ?? useButtons;
    useDialogs = j['useDialogs'] as bool? ?? useDialogs;
    textShadow = _d(j['textShadow'], textShadow);
    gloss = j['gloss'] as bool? ?? gloss;
    glossIntensity = _d(j['glossIntensity'], glossIntensity);
    textShadowBlur = _d(j['textShadowBlur'], textShadowBlur);
  }

  void reset() => load(GlassConfig().toJson());
}


/// Lucent plate settings (see native/icon_core/src/lucent.rs).
/// The glyph keeps its own colours unless [monochrome] is on.
class LucentConfig {
  bool dark = true;
  LucentShape shape = LucentShape.squircle;
  bool monochrome = false;
  bool keepComposition = true;
  double glyphScale = 1.0;
  double rim = 0.0;
  bool launcherShadow = false;
  bool launcherEncode = false;

  /// Backdrop alpha (0x66 = 0.4).
  double backdropAlpha = 0x66 / 255;

  LucentSettings toSettings() {
    final d = defaultLucentSettings(dark: dark);
    final a = (backdropAlpha.clamp(0.0, 1.0) * 255).round();
    return LucentSettings(
      ink: d.ink,
      backdrop: (a << 24) | (d.backdrop & 0xFFFFFF),
      shape: shape,
      monochrome: monochrome,
      keepComposition: keepComposition,
      glyphScale: glyphScale,
      rim: rim,
      launcherShadow: launcherShadow && !launcherEncode,
      launcherEncode: launcherEncode,
      strategy: LucentStrategy.auto,
    );
  }

  void load(Map<String, dynamic> j) {
    dark = j['dark'] as bool? ?? dark;
    shape = LucentShape.values.firstWhere((e) => e.name == j['shape'], orElse: () => shape);
    monochrome = j['monochrome'] as bool? ?? monochrome;
    keepComposition = j['keepComposition'] as bool? ?? keepComposition;
    glyphScale = (j['glyphScale'] as num?)?.toDouble() ?? glyphScale;
    rim = (j['rim'] as num?)?.toDouble() ?? rim;
    launcherShadow = j['launcherShadow'] as bool? ?? launcherShadow;
    launcherEncode = j['launcherEncode'] as bool? ?? launcherEncode;
    backdropAlpha = (j['backdropAlpha'] as num?)?.toDouble() ?? backdropAlpha;
  }

  Map<String, dynamic> toJson() => {
        'dark': dark,
        'shape': shape.name,
        'monochrome': monochrome,
        'keepComposition': keepComposition,
        'glyphScale': glyphScale,
        'rim': rim,
        'launcherShadow': launcherShadow,
        'launcherEncode': launcherEncode,
        'backdropAlpha': backdropAlpha,
      };

  void reset() => load(LucentConfig().toJson());
}

/// Global colour and look options, applied to the whole batch and the preview.
/// Neutral values give null effects, so the engine skips the pass.
class LookConfig {
  double brightness = 0;
  double saturation = 0;
  double hue = 0;
  bool recolorOn = false;

  /// Symbol colour (ARGB) used when [recolorOn].
  int recolor = 0xFFFFFFFF;
  double plateTint = 0;
  double sharpen = 0;

  /// Optical centring of the symbol (placement, all icons).
  bool opticalCentre = false;

  EffectSettings? get effects {
    if (brightness == 0 && saturation == 0 && hue == 0 && !recolorOn && plateTint == 0 && sharpen == 0) return null;
    return EffectSettings(brightness: brightness, saturation: saturation, hue: hue, recolor: recolorOn ? recolor : null, plateTint: plateTint, sharpen: sharpen);
  }

  void resetColor() {
    brightness = 0;
    saturation = 0;
    hue = 0;
    recolorOn = false;
    plateTint = 0;
    sharpen = 0;
  }

  void load(Map<String, dynamic> j) {
    brightness = (j['brightness'] as num?)?.toDouble() ?? brightness;
    saturation = (j['saturation'] as num?)?.toDouble() ?? saturation;
    hue = (j['hue'] as num?)?.toDouble() ?? hue;
    recolorOn = j['recolorOn'] as bool? ?? recolorOn;
    recolor = (j['recolor'] as num?)?.toInt() ?? recolor;
    plateTint = (j['plateTint'] as num?)?.toDouble() ?? plateTint;
    sharpen = (j['sharpen'] as num?)?.toDouble() ?? sharpen;
    opticalCentre = j['opticalCentre'] as bool? ?? opticalCentre;
  }

  Map<String, dynamic> toJson() => {
        'brightness': brightness,
        'saturation': saturation,
        'hue': hue,
        'recolorOn': recolorOn,
        'recolor': recolor,
        'plateTint': plateTint,
        'sharpen': sharpen,
        'opticalCentre': opticalCentre,
      };
}

/// Local AI background removal model catalogue (optional downloads).
class AiModelInfo {
  const AiModelInfo(this.id, this.kind, this.label, this.bytes, this.ramMb, this.note, {this.phone = true, this.desktop = true});

  /// Runs smoothly on a phone (mid-range class) / on Windows.
  final bool phone;
  final bool desktop;
  final String id;
  final AiModelKind kind;
  final String label;
  final int bytes;
  final int ramMb;
  final String note;

  String get url => 'https://github.com/danielgatis/rembg/releases/download/v0.0.0/$id.onnx';
}

/// Only models measured as usable on CPU with tract are offered: U²-Net-p
/// runs in ~0.8 s per icon; Silueta took ~93 s per icon (tract, i5-13500H),
/// so it is not listed.
final aiModels = [
  AiModelInfo('u2netp', AiModelKind.u2Netp, 'U²-Net-p', 4574861, 350, S.aiModelU2netpNote),
  // 1024 px input: ~7,5 s/icona su un PC (misurato), decine di secondi su telefono
  AiModelInfo('isnet-general-use', AiModelKind.isnetGeneral, 'ISNet General', 178648008, 1400, S.aiModelIsnetNote, phone: false),
];

/// Models offered on this device (phone-friendly ones only on Android).
List<AiModelInfo> get aiModelsHere => [for (final m in aiModels) if (Platform.isAndroid ? m.phone : m.desktop) m];

class LocalAiConfig {
  String modelId = 'u2netp';
  double low = 0.15;
  double high = 0.85;

  AiModelInfo get model => aiModels.firstWhere((m) => m.id == modelId, orElse: () => aiModels.first);

  void load(Map<String, dynamic> j) {
    modelId = j['modelId'] as String? ?? modelId;
    low = (j['low'] as num?)?.toDouble() ?? low;
    high = (j['high'] as num?)?.toDouble() ?? high;
  }

  Map<String, dynamic> toJson() => {'modelId': modelId, 'low': low, 'high': high};
}
