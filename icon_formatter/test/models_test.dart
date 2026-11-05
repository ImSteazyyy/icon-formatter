import 'package:flutter_test/flutter_test.dart';
import 'package:icon_formatter/app/models.dart';
import 'package:icon_formatter/src/rust/api/engine.dart';

const t0 = TranslucentSettings(
  brightness: 0.5,
  frost: 0.5,
  transparency: 0,
  tint: 0,
  contrast: 0.5,
  border: 0.6,
  reflection: 0.45,
  depth: 0.5,
  shapeRatio: 0.93,
  exponent: 4.25,
  seed: 7,
);

void main() {
  test('translucent settings JSON round trip', () {
    final t = copyTranslucent(t0, brightness: 0.8, tint: -0.3);
    final back = translucentFromJson(translucentToJson(t), t0);
    expect(back.brightness, 0.8);
    expect(back.tint, -0.3);
    expect(back.exponent, 4.25);
  });

  test('built-in presets exist and are editable copies', () {
    final ps = builtInPresets(t0);
    expect(ps.map((e) => e.name), containsAll(['Liquid Glass', 'Nothing Translucent', 'Minimale', 'Scuro piatto', 'Personalizzato']));
    final pr = StylePreset.fromJson(ps[1].toJson(), t0);
    expect(pr.params.reflection, ps[1].params.reflection);
  });

  test('export naming', () {
    final e = ExportSettings();
    expect(e.fileName('whatsapp', 512), 'whatsapp.png');
    e.naming = ExportNaming.withSize;
    expect(e.fileName('whatsapp', 512), 'whatsapp_512.png');
    e.naming = ExportNaming.prefixed;
    expect(e.fileName('whatsapp', 512), 'ic_whatsapp.png');
  });

  test('appearance persistence', () {
    final a = Appearance()
      ..radius = 7
      ..accent = 0xFF112233
      ..compact = true;
    final b = Appearance()..load(a.toJson());
    expect(b.radius, 7);
    expect(b.accent, 0xFF112233);
    expect(b.compact, true);
  });

  test('liquid glass settings persistence and reset', () {
    final g = GlassConfig()
      ..blur = 21
      ..gloss = false
      ..textShadow = 0.2;
    final h = GlassConfig()..load(g.toJson());
    expect(h.blur, 21);
    expect(h.gloss, false);
    expect(h.textShadow, 0.2);
    h.reset();
    expect(h.blur, GlassConfig().blur);
    expect(h.gloss, true);
  });
}
