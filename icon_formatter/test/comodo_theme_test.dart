import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:icon_formatter/app/models.dart';

void main() {
  group('theme choice migration', () {
    test('a fresh state follows the phone', () {
      expect(themeChoiceFrom({}), ThemeChoice.system);
    });

    test('old saved light flag maps to light or dark', () {
      expect(themeChoiceFrom({'light': true}), ThemeChoice.light);
      expect(themeChoiceFrom({'light': false}), ThemeChoice.dark);
    });

    test('the new field wins over the old flag', () {
      expect(themeChoiceFrom({'light': true, 'themeChoice': 'system'}), ThemeChoice.system);
      expect(themeChoiceFrom({'light': false, 'themeChoice': 'light'}), ThemeChoice.light);
    });

    test('an unknown field value falls back to the old flag', () {
      expect(themeChoiceFrom({'light': true, 'themeChoice': 'purple'}), ThemeChoice.light);
      expect(themeChoiceFrom({'themeChoice': 'purple'}), ThemeChoice.system);
    });
  });

  test('effective light follows the choice and the phone only for system', () {
    expect(effectiveLight(ThemeChoice.light, ui.Brightness.dark), isTrue);
    expect(effectiveLight(ThemeChoice.dark, ui.Brightness.light), isFalse);
    expect(effectiveLight(ThemeChoice.system, ui.Brightness.light), isTrue);
    expect(effectiveLight(ThemeChoice.system, ui.Brightness.dark), isFalse);
  });
}
