import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icon_formatter/app/models.dart';
import 'package:icon_formatter/app/state.dart';
import 'package:icon_formatter/l10n/strings.dart';
import 'package:icon_formatter/screens/pack/pb_screen.dart';
import 'package:icon_formatter/screens/settings_screen.dart';
import 'package:icon_formatter/screens/studio_screen.dart';

// Runs on the host (no Android channels). Text at 1.0 and 1.3 scale must not
// overflow the Pack tab, the "Altro" sheet, Settings or the Studio toolbar.
void main() {
  for (final scale in const [1.0, 1.3]) {
    for (final style in UiStyle.values) {
      void setUpView(WidgetTester tester) {
        tester.view.physicalSize = const Size(360, 780);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        AppState.I.setupDone = true;
        AppState.I.appearance.style = style;
      }

      Widget app(Widget home) => MaterialApp(
            home: MediaQuery(
              data: MediaQueryData(textScaler: TextScaler.linear(scale)),
              child: home,
            ),
          );

      testWidgets('Pack tab fits at $scale in $style', (tester) async {
        setUpView(tester);
        await tester.pumpWidget(app(const PackBuilderScreen()));
        await tester.pump(const Duration(milliseconds: 300));
        expect(tester.takeException(), isNull);
      });

      testWidgets('Altro sheet fits at $scale in $style', (tester) async {
        setUpView(tester);
        await tester.pumpWidget(app(const PackBuilderScreen()));
        await tester.pump(const Duration(milliseconds: 300));
        // the cards are built lazily: scroll down until the button exists
        final altro = find.byKey(const ValueKey('pb-altro'));
        final list = find.byType(CustomScrollView).first;
        for (var i = 0; i < 30 && altro.evaluate().isEmpty; i++) {
          await tester.drag(list, const Offset(0, -300));
          await tester.pump();
        }
        expect(altro, findsOneWidget);
        await tester.ensureVisible(altro);
        await tester.pump();
        await tester.tap(altro);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.text(S.altro), findsWidgets);
      });

      testWidgets('Settings fits at $scale in $style', (tester) async {
        setUpView(tester);
        await tester.pumpWidget(app(const SettingsScreen()));
        await tester.pump(const Duration(milliseconds: 300));
        expect(tester.takeException(), isNull);
      });

      testWidgets('Studio toolbar fits at $scale in $style', (tester) async {
        setUpView(tester);
        await tester.pumpWidget(app(StudioScreen(onOpenBases: () {})));
        await tester.pump(const Duration(milliseconds: 300));
        expect(tester.takeException(), isNull);
      });
    }
  }
}
