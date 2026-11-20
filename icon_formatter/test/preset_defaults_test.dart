import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:icon_formatter/app/models.dart';
import 'package:icon_formatter/src/rust/api/engine.dart';

// The rendering of each look (squircle/circle corners, plate alpha, mono hue,
// colour hue) runs on the host Rust library: native/icon_core/tests/lucent_presets.rs.
// Dart checks the built-in definitions, the JSON round trip and the migration.

const _dummy = TranslucentSettings(
  brightness: 0,
  frost: 0,
  transparency: 0,
  tint: 0,
  contrast: 0,
  border: 0,
  reflection: 0,
  depth: 0,
  shapeRatio: 0,
  exponent: 0,
  seed: 0,
);

void main() {
  group('built-in looks', () {
    test('exactly four built-ins: squircle and circle, colour and mono', () {
      final list = builtInPresets(_dummy);
      expect(list.map((p) => p.id), ['sqColour', 'sqMono', 'ciColour', 'ciMono']);
      expect(list.every((p) => p.builtIn && p.lucent != null), isTrue);

      final shapes = {for (final p in list) p.id: p.lucent!.shape};
      expect(shapes['sqColour'], LucentShape.squircle);
      expect(shapes['sqMono'], LucentShape.squircle);
      expect(shapes['ciColour'], LucentShape.circle);
      expect(shapes['ciMono'], LucentShape.circle);

      final mono = {for (final p in list) p.id: p.lucent!.monochrome};
      expect(mono, {'sqColour': false, 'sqMono': true, 'ciColour': false, 'ciMono': true});
    });

    test('every built-in is a transparent dark plate at the widget alpha', () {
      for (final p in builtInPresets(_dummy)) {
        expect(p.lucent!.dark, isTrue, reason: p.id);
        expect(p.lucent!.backdropAlphaDark, closeTo(0x66 / 255, 1e-9), reason: p.id);
        expect(p.lucent!.rim, 0, reason: p.id);
      }
    });

    test('default active look is the squircle colour preset', () {
      expect(kDefaultPresetId, 'sqColour');
      expect(builtInPresets(_dummy).first.id, kDefaultPresetId);
    });
  });

  group('json and migration', () {
    test('a Lucent preset survives a JSON round trip', () {
      final src = builtInPresets(_dummy)[1];
      final back = StylePreset.fromJson((jsonDecode(jsonEncode(src.toJson())) as Map).cast(), _dummy);
      expect(back.id, 'sqMono');
      expect(back.lucent!.shape, LucentShape.squircle);
      expect(back.lucent!.monochrome, isTrue);
      expect(jsonEncode(back.values), jsonEncode(src.values));
    });

    test('a procedural user preset keeps no Lucent look', () {
      final user = StylePreset(id: 'u1', name: 'Mine', params: _dummy);
      final back = StylePreset.fromJson((jsonDecode(jsonEncode(user.toJson())) as Map).cast(), _dummy);
      expect(back.lucent, isNull);
    });

    test('old built-in ids fall back to the default look', () {
      final known = builtInPresets(_dummy).map((p) => p.id);
      for (final old in ['nothing', 'liquid', 'minimal', 'darkflat', 'custom', null]) {
        expect(migratePresetId(old, known), kDefaultPresetId, reason: '$old');
      }
    });

    test('ids that still exist are kept', () {
      final known = [...builtInPresets(_dummy).map((p) => p.id), 'u123'];
      expect(migratePresetId('ciMono', known), 'ciMono');
      expect(migratePresetId('u123', known), 'u123');
    });

    test('older LucentConfig saves load into a preset', () {
      final l = LucentConfig()..load({'shape': 'circle', 'monochrome': true, 'backdropAlpha': 0.5});
      expect(l.shape, LucentShape.circle);
      expect(l.monochrome, isTrue);
      expect(l.backdropAlphaDark, closeTo(0.5, 1e-9));
    });
  });
}
