import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icon_formatter/app/state.dart';
import 'package:icon_formatter/l10n/strings.dart';
import 'package:icon_formatter/screens/setup_screen.dart';

// Runs on the host (no Android channels): the permissions page is skipped.
void main() {
  testWidgets('tour has no style page and finishes', (tester) async {
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    final st = AppState.I;
    st.setupDone = false;

    await tester.pumpWidget(const MaterialApp(home: OnboardingScreen()));
    // the Nothing style is the only look: no style cards in the tour
    expect(find.text(S.stileVetro), findsNothing);
    expect(find.text(S.stileNothing), findsNothing);
    expect(find.text(S.tourSalta), findsOneWidget);
    expect(find.text(S.tourIndietro), findsNothing);

    // language -> done (no permissions page on the host)
    await tester.tap(find.text(S.tourAvanti));
    await tester.pumpAndSettle();
    expect(find.text(S.tourSalta), findsNothing);
    expect(find.text(S.tourInizia), findsOneWidget);

    await tester.tap(find.text(S.tourInizia));
    await tester.pump();
    expect(st.setupDone, isTrue);
    st.setupDone = false;
  });

  testWidgets('skip marks the tour as done', (tester) async {
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    final st = AppState.I;
    st.setupDone = false;
    await tester.pumpWidget(const MaterialApp(home: OnboardingScreen()));
    await tester.tap(find.text(S.tourSalta));
    await tester.pump();
    expect(st.setupDone, isTrue);
    st.setupDone = false;
  });
}
