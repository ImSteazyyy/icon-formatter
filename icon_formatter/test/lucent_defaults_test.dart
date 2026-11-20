import 'package:flutter_test/flutter_test.dart';
import 'package:icon_formatter/app/models.dart';

void main() {
  test('dark and light plates have their own default alpha', () {
    // toSettings() needs the Rust bridge, so the alpha is read through the getter
    final dark = LucentConfig();
    expect(dark.backdropAlpha, closeTo(0x66 / 255, 1e-9));
    dark.dark = false;
    expect(dark.backdropAlpha, closeTo(0x99 / 255, 1e-9));
  });

  test('the alpha slider edits only the current mode', () {
    final l = LucentConfig()..backdropAlpha = 0.2;
    expect(l.backdropAlphaDark, closeTo(0.2, 1e-9));
    expect(l.backdropAlphaLight, closeTo(0x99 / 255, 1e-9));
    l.dark = false;
    expect(l.backdropAlpha, closeTo(0x99 / 255, 1e-9));
  });

  test('older saves with one backdropAlpha still load', () {
    final l = LucentConfig()..load({'dark': true, 'backdropAlpha': 0.7});
    expect(l.backdropAlphaDark, closeTo(0.7, 1e-9));
    expect(l.backdropAlphaLight, closeTo(0x99 / 255, 1e-9));
  });

  test('round trip keeps both modes', () {
    final l = LucentConfig()
      ..backdropAlphaDark = 0.3
      ..backdropAlphaLight = 0.8;
    final l2 = LucentConfig()..load(l.toJson());
    expect(l2.backdropAlphaDark, closeTo(0.3, 1e-9));
    expect(l2.backdropAlphaLight, closeTo(0.8, 1e-9));
  });
}
