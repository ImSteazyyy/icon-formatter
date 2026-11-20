import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icon_formatter/app/models.dart';
import 'package:icon_formatter/app/state.dart';
import 'package:icon_formatter/l10n/strings.dart';
import 'package:icon_formatter/screens/settings_screen.dart';
import 'package:icon_formatter/widgets/liquid_glass.dart';

void main() {
  test('the Nothing style is the only style', () {
    expect(UiStyle.values, [UiStyle.nothing]);
    expect(nothingStyle, isTrue);
  });

  test('a saved glass style loads as Nothing, and the backup keeps the key', () {
    final a = Appearance()..load({'style': 'glass', 'accent': 0xFF112233});
    expect(a.style, UiStyle.nothing);
    expect(a.accentColor, const Color(Appearance.nothingRed));
    expect(a.toJson()['style'], 'nothing');
  });

  testWidgets('Settings > Appearance has no style selector', (tester) async {
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    AppState.I.setupDone = true;
    await tester.pumpWidget(MaterialApp(home: SettingsScreen(initial: SettingsCat.appearance)));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text(S.stileVetro), findsNothing);
    expect(find.text(S.stileNothing), findsNothing);
    expect(find.text(S.comodoTemaScuro), findsOneWidget);
  });
}
