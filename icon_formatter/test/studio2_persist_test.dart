import 'package:flutter_test/flutter_test.dart';
import 'package:icon_formatter/app/models.dart';
import 'package:icon_formatter/src/rust/api/engine.dart';

void main() {
  test('an old state file without look settings is neutral', () {
    final l = LookConfig()..load({});
    expect(l.effects, isNull);
    expect(l.opticalCentre, isFalse);
  });

  test('look settings survive a JSON round trip', () {
    final a = LookConfig()
      ..brightness = 0.25
      ..saturation = -0.5
      ..hue = 120
      ..recolorOn = true
      ..recolor = 0xFF2196F3
      ..plateTint = 0.4
      ..sharpen = 0.3
      ..opticalCentre = true;
    final b = LookConfig()..load(a.toJson());
    expect(b.toJson(), a.toJson());
    final fx = b.effects!;
    expect(fx.brightness, 0.25);
    expect(fx.saturation, -0.5);
    expect(fx.hue, 120);
    expect(fx.recolor, 0xFF2196F3);
    expect(fx.plateTint, 0.4);
    expect(fx.sharpen, 0.3);
  });

  test('a single non-neutral value turns the effects on', () {
    expect((LookConfig()..hue = 1).effects, isNotNull);
    expect((LookConfig()..recolorOn = true).effects!.recolor, 0xFFFFFFFF);
    expect((LookConfig()..recolorOn = false).effects, isNull);
  });

  test('resetColor keeps the optical centring', () {
    final l = LookConfig()
      ..brightness = 0.5
      ..recolorOn = true
      ..sharpen = 0.2
      ..opticalCentre = true
      ..resetColor();
    expect(l.effects, isNull);
    expect(l.opticalCentre, isTrue);
  });

  test(
    'copyPlacement keeps the optical centring unless asked to change it',
    () {
      final base = PlacementSettings(
        glyphRatio: 0.6,
        areaRatio: 0.8,
        centerX: 0.5,
        centerY: 0.5,
        areaFit: false,
        scaleMul: 1,
        offsetX: 0,
        offsetY: 0,
        opticalCentre: true,
      );
      expect(copyPlacement(base, scaleMul: 1.2).opticalCentre, isTrue);
      expect(copyPlacement(base, opticalCentre: false).opticalCentre, isFalse);
    },
  );
}
