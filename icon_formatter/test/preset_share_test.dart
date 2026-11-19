import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:icon_formatter/app/models.dart';
import 'package:icon_formatter/services/preset_share.dart';
import 'package:icon_formatter/src/rust/api/engine.dart';

const d = TranslucentSettings(
  brightness: 0.5,
  frost: 0.2,
  transparency: 0.3,
  tint: 0,
  contrast: 0.4,
  border: 0.5,
  reflection: 0.6,
  depth: 0.7,
  shapeRatio: 0.9,
  exponent: 5,
  seed: 7,
);

Map<String, dynamic> _file(List<Map<String, dynamic>> presets) => {
      'format': presetShareFormat,
      'version': presetShareVersion,
      'presets': presets,
    };

void main() {
  test('round trip keeps name and values', () {
    final p = StylePreset(
      id: 'x',
      name: 'Mio preset',
      params: copyTranslucent(d, brightness: 0.12, tint: -0.5, exponent: 6.5, seed: 42),
    );
    final out = decodePresets(encodePresets([p]), d);
    expect(out, hasLength(1));
    expect(out.first.name, 'Mio preset');
    expect(translucentToJson(out.first.params), translucentToJson(p.params));
  });

  test('malformed JSON throws FormatException', () {
    expect(() => decodePresets('{not json', d), throwsFormatException);
    expect(() => decodePresets('', d), throwsFormatException);
  });

  test('wrong top-level format, version or empty list are rejected', () {
    expect(() => decodePresets('[]', d), throwsFormatException);
    expect(() => decodePresets(jsonEncode({'format': 'altro', 'version': 1, 'presets': []}), d), throwsFormatException);
    expect(() => decodePresets(jsonEncode({'format': presetShareFormat, 'version': 99, 'presets': []}), d), throwsFormatException);
    expect(() => decodePresets(jsonEncode(_file([])), d), throwsFormatException);
  });

  test('wrong value types are rejected without a TypeError', () {
    final bad = [
      {'name': 42, 'params': {}},
      {'name': '  ', 'params': {}},
      {'name': 'ok', 'params': 'no'},
      {'name': 'ok', 'params': {'brightness': 'alto'}},
      {'name': 'ok', 'params': {'seed': true}},
    ];
    for (final b in bad) {
      expect(() => decodePresets(jsonEncode(_file([b])), d), throwsFormatException, reason: '$b');
    }
  });

  test('out-of-range values are clamped and missing ones use the defaults', () {
    final text = jsonEncode(_file([
      {
        'name': 'Fuori',
        'params': {'brightness': 9, 'frost': -3, 'tint': -7, 'shapeRatio': 0.1, 'exponent': 100, 'seed': 1e300},
      },
    ]));
    final t = decodePresets(text, d).single.params;
    expect(t.brightness, 1);
    expect(t.frost, 0);
    expect(t.tint, -1);
    expect(t.shapeRatio, 0.8);
    expect(t.exponent, 8);
    expect(t.seed, 1000000000000000);
    expect(t.contrast, d.contrast);
    expect(t.reflection, d.reflection);
  });

  test('long names are cut', () {
    final text = jsonEncode(_file([
      {'name': 'x' * 100, 'params': {}},
    ]));
    expect(decodePresets(text, d).single.name.length, 40);
  });

  test('name clash gets a suffix, free names stay as they are', () {
    expect(uniqueName('Liquid', ['Minimal']), 'Liquid');
    expect(uniqueName('Liquid', ['Liquid']), 'Liquid (2)');
    expect(uniqueName('Liquid', ['Liquid', 'Liquid (2)']), 'Liquid (3)');
  });
}
