import 'dart:convert';

import '../app/models.dart';
import '../src/rust/api/engine.dart';

/// File format of shared style presets (.json).
const presetShareFormat = 'icon-formatter-presets';
const presetShareVersion = 1;

/// Slider ranges of the translucent controls (see translucentSliders).
const _ranges = <String, (double, double)>{
  'brightness': (0, 1),
  'frost': (0, 1),
  'transparency': (0, 1),
  'tint': (-1, 1),
  'contrast': (0, 1),
  'border': (0, 1),
  'reflection': (0, 1),
  'depth': (0, 1),
  'shapeRatio': (0.8, 1.0),
  'exponent': (3.0, 8.0),
};

const _maxNameLength = 40;

/// Text of a presets .json file.
String encodePresets(List<StylePreset> presets) => const JsonEncoder.withIndent('  ').convert({
      'format': presetShareFormat,
      'version': presetShareVersion,
      'presets': [
        for (final p in presets) {'name': p.name, 'params': translucentToJson(p.params)},
      ],
    });

/// Reads a presets file. Throws FormatException when the text is not a valid file.
/// Out-of-range numbers are clamped, missing ones take the values of [d].
List<({String name, TranslucentSettings params})> decodePresets(String text, TranslucentSettings d) {
  final root = jsonDecode(text);
  if (root is! Map || root['format'] != presetShareFormat) throw const FormatException('format');
  final version = root['version'];
  if (version is! int || version < 1 || version > presetShareVersion) throw const FormatException('version');
  final list = root['presets'];
  if (list is! List || list.isEmpty) throw const FormatException('presets');
  return [for (final e in list) _decodeOne(e, d)];
}

({String name, TranslucentSettings params}) _decodeOne(Object? e, TranslucentSettings d) {
  if (e is! Map) throw const FormatException('preset');
  final name = e['name'];
  final p = e['params'];
  if (name is! String || name.trim().isEmpty || p is! Map) throw const FormatException('preset');

  double v(String k, double def) {
    final x = p[k];
    if (x == null) return def;
    if (x is! num) throw FormatException(k);
    final r = _ranges[k]!;
    return x.clamp(r.$1, r.$2).toDouble();
  }

  final seed = p['seed'];
  if (seed != null && seed is! num) throw const FormatException('seed');
  final n = name.trim();
  return (
    name: n.length > _maxNameLength ? n.substring(0, _maxNameLength) : n,
    params: TranslucentSettings(
      brightness: v('brightness', d.brightness),
      frost: v('frost', d.frost),
      transparency: v('transparency', d.transparency),
      tint: v('tint', d.tint),
      contrast: v('contrast', d.contrast),
      border: v('border', d.border),
      reflection: v('reflection', d.reflection),
      depth: v('depth', d.depth),
      shapeRatio: v('shapeRatio', d.shapeRatio),
      exponent: v('exponent', d.exponent),
      seed: seed == null ? d.seed : (seed as num).clamp(-1e15, 1e15).toInt(),
    ),
  );
}

/// [name] if free, otherwise "name (2)", "name (3)" ...
String uniqueName(String name, Iterable<String> taken) {
  final set = taken.toSet();
  var n = name;
  for (var i = 2; set.contains(n); i++) {
    n = '$name ($i)';
  }
  return n;
}
