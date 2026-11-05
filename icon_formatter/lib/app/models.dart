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
      StylePreset(id: 'nothing', name: S.nothingTranslucent, builtIn: true, params: d),
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
class Appearance {
  double radius = 18;
  /// Default accent: pink sampled from the user's Windows Start icon.
  static const defaultAccent = 0xFFBA4CD4;
  static const legacyAccent = 0xFFB9A96E;
  int accent = defaultAccent;
  bool animations = true;
  bool compact = false;

  Color get accentColor => Color(accent);

  Map<String, dynamic> toJson() => {
        'radius': radius,
        'accent': accent,
        'animations': animations,
        'compact': compact,
      };

  void load(Map<String, dynamic> j) {
    radius = _d(j['radius'], radius);
    accent = (j['accent'] as num?)?.toInt() ?? accent;
    animations = j['animations'] as bool? ?? animations;
    compact = j['compact'] as bool? ?? compact;
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

  Map<String, dynamic> toJson() => {
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
  }

  /// Output file name for a source name (without extension handling).
  String fileName(String stem, int size) => switch (naming) {
        ExportNaming.original => '$stem.png',
        ExportNaming.withSize => S.png(stem, size),
        ExportNaming.prefixed => '$prefix$stem.png',
      };
}

enum AiProviderKind { openai, gemini, openaiCompatible }

class AiConfig {
  AiProviderKind provider = AiProviderKind.openai;
  String model = 'gpt-image-1';
  String baseUrl = 'https://api.openai.com';
  String quality = 'medium';

  Map<String, dynamic> toJson() => {'provider': provider.name, 'model': model, 'baseUrl': baseUrl, 'quality': quality};

  void load(Map<String, dynamic> j) {
    provider = AiProviderKind.values.firstWhere((p) => p.name == j['provider'], orElse: () => provider);
    model = j['model'] as String? ?? model;
    baseUrl = j['baseUrl'] as String? ?? baseUrl;
    quality = j['quality'] as String? ?? quality;
  }
}


/// Liquid glass material (liquid_glass_widgets) used by bars, panels and lens.
class GlassConfig {
  double blur = 8;
  double thickness = 28;
  double chromatic = 0.012;
  double lightIntensity = 0.55;
  double lightAngle = 135;
  double refractiveIndex = 1.2;
  double saturation = 1.45;
  double frost = 0.2;
  double tint = 0.08;
  double rimLight = 0.3;
  double lensDarkness = 0.32;
  bool premium = false;

  /// Text/icon shadow on glass for legibility (0 = off).
  double textShadow = 0.6;

  /// Glossy specular rim like the reference icons (brightest facing the light).
  bool gloss = true;
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
        'premium': premium,
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
    premium = j['premium'] as bool? ?? premium;
    textShadow = _d(j['textShadow'], textShadow);
    gloss = j['gloss'] as bool? ?? gloss;
    glossIntensity = _d(j['glossIntensity'], glossIntensity);
    textShadowBlur = _d(j['textShadowBlur'], textShadowBlur);
  }

  void reset() => load(GlassConfig().toJson());
}


/// Lucent (Nothing OS 5.0) plate settings, ported from Nothing IconGen.
/// The glyph keeps its own colours unless [monochrome] is on.
class LucentConfig {
  bool dark = true;
  LucentShape shape = LucentShape.squircle;
  bool monochrome = false;
  bool keepComposition = true;
  double glyphScale = 1.0;
  double rim = 0.0;
  bool launcherShadow = false;
  bool nothingEncode = false;

  /// Backdrop alpha (Nothing OS: 0x66 = 0.4).
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
      launcherShadow: launcherShadow && !nothingEncode,
      nothingEncode: nothingEncode,
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
    nothingEncode = j['nothingEncode'] as bool? ?? nothingEncode;
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
        'nothingEncode': nothingEncode,
        'backdropAlpha': backdropAlpha,
      };

  void reset() => load(LucentConfig().toJson());
}

/// Local AI background removal model catalogue (optional downloads).
class AiModelInfo {
  const AiModelInfo(this.id, this.kind, this.label, this.bytes, this.ramMb, this.note);
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
const aiModels = [
  AiModelInfo('u2netp', AiModelKind.u2Netp, 'U²-Net-p', 4574861, 350, S.aiModelU2netpNote),
];

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
