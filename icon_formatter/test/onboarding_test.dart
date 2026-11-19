import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icon_formatter/app/models.dart';
import 'package:icon_formatter/app/state.dart';
import 'package:icon_formatter/l10n/strings.dart';
import 'package:icon_formatter/screens/setup_screen.dart';

// Runs on the host (no Android channels): the permissions page is skipped.
void main() {
  testWidgets('tour pages, style card and finish', (tester) async {
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    final st = AppState.I;
    final a = st.appearance;
    st.setupDone = false;
    a.style = UiStyle.nothing;

    await tester.pumpWidget(const MaterialApp(home: OnboardingScreen()));
    expect(find.text(S.tourBenvenutoSub), findsOneWidget);
    expect(find.text(S.tourSalta), findsOneWidget);
    expect(find.text(S.tourIndietro), findsNothing);

    // welcome -> theme
    await tester.tap(find.text(S.tourAvanti));
    await tester.pumpAndSettle();
    expect(find.text(S.tourIndietro), findsOneWidget);

    // the glass card applies the style at once
    await tester.tap(find.text(S.stileVetro));
    await tester.pump();
    expect(a.style, UiStyle.glass);

    // theme -> language -> done (no permissions page on the host)
    await tester.tap(find.text(S.tourAvanti));
    await tester.pumpAndSettle();
    await tester.tap(find.text(S.tourAvanti));
    await tester.pumpAndSettle();
    expect(find.text(S.tourSalta), findsNothing);
    expect(find.text(S.tourInizia), findsOneWidget);

    await tester.tap(find.text(S.tourInizia));
    await tester.pump();
    expect(st.setupDone, isTrue);

    a.style = UiStyle.nothing;
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
