import 'package:flutter_test/flutter_test.dart';
import 'package:icon_formatter/app/models.dart';

void main() {
  test('Vetro settings persist (quality, tint, depth, where to use)', () {
    final g = GlassConfig()
      ..quality = GlassQualityLevel.fast
      ..tintColor = 0xFFFF3B30
      ..tint = 0.4
      ..depth = false
      ..useNav = false
      ..usePanels = false
      ..useButtons = true
      ..useDialogs = false;
    final g2 = GlassConfig()..load(g.toJson());
    expect(g2.quality, GlassQualityLevel.fast);
    expect(g2.tintColor, 0xFFFF3B30);
    expect(g2.tint, 0.4);
    expect(g2.depth, isFalse);
    expect(g2.useNav, isFalse);
    expect(g2.usePanels, isFalse);
    expect(g2.useButtons, isTrue);
    expect(g2.useDialogs, isFalse);
  });

  test('old "premium" flag migrates to the Qualità level', () {
    final g = GlassConfig()..load({'premium': true});
    expect(g.quality, GlassQualityLevel.quality);
    expect(g.premium, isTrue);
  });

  test('reset restores defaults', () {
    final g = GlassConfig()
      ..tintColor = 0xFF00FF00
      ..useNav = false
      ..reset();
    expect(g.tintColor, 0);
    expect(g.useNav, isTrue);
    expect(g.quality, GlassQualityLevel.balanced);
  });
}
