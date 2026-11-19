import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icon_formatter/app/models.dart';
import 'package:icon_formatter/app/state.dart';
import 'package:icon_formatter/l10n/strings.dart';
import 'package:icon_formatter/screens/setup_screen.dart';
import 'package:icon_formatter/widgets/tour2_visibility.dart';

// Runs on the host (no Android channels): the permissions page is skipped.
void main() {
  for (final size in const [Size(360, 640), Size(412, 915)]) {
    for (final style in UiStyle.values) {
      testWidgets('tour fits ${size.width}x${size.height} in $style', (
        tester,
      ) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);

        final st = AppState.I;
        st.setupDone = false;
        st.appearance.style = style;

        await tester.pumpWidget(const MaterialApp(home: OnboardingScreen()));
        await tester.pumpAndSettle();

        // walk every page: no overflow, the primary button stays on screen
        for (var i = 0; i < 4; i++) {
          expect(tester.takeException(), isNull, reason: 'page $i');
          final button = find.byKey(const ValueKey('tour-next'));
          expect(button, findsOneWidget);
          final rect = tester.getRect(button);
          expect(
            rect.bottom,
            lessThanOrEqualTo(size.height),
            reason: 'page $i',
          );
          expect(rect.left, greaterThanOrEqualTo(0));
          expect(rect.right, lessThanOrEqualTo(size.width));
          await tester.tap(button);
          await tester.pumpAndSettle();
        }
        expect(tester.takeException(), isNull);
        expect(find.text(S.tourInizia), findsOneWidget);
        st.setupDone = false;
      });
    }
  }

  testWidgets('tourOpen is true while the tour is on screen', (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    AppState.I.setupDone = false;

    expect(tourOpen.value, isFalse);
    await tester.pumpWidget(const MaterialApp(home: OnboardingScreen()));
    await tester.pumpAndSettle();
    expect(tourOpen.value, isTrue);

    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    expect(tourOpen.value, isFalse);
  });
}
