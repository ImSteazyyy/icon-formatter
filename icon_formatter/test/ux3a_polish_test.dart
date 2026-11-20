import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icon_formatter/app/state.dart';
import 'package:icon_formatter/app/theme.dart';
import 'package:icon_formatter/widgets/app_search.dart';
import 'package:icon_formatter/widgets/common.dart';
import 'package:icon_formatter/widgets/liquid_glass.dart';

// Runs on the host. Covers the polish pass: the progress strip sits in the
// layout (never over the preview caption), auto-hides after a clean batch,
// the status dots have labels, the search field matches the nav pill surface,
// and selection is the neutral Palette.selection.
void main() {
  void setUpView(WidgetTester tester) {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    AppState.I.setupDone = true;
  }

  Widget app(Widget body, double scale) => MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(textScaler: TextScaler.linear(scale)),
      child: Scaffold(body: body),
    ),
  );

  for (final scale in const [1.0, 1.3]) {
    testWidgets('strip does not cover the preview caption at $scale', (tester) async {
      setUpView(tester);
      final caption = GlobalKey();
      await tester.pumpWidget(
        app(
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                SizedBox(
                  height: 120,
                  child: Text('512px · alpha · plate · 99%', key: caption),
                ),
                ProgressStrip(done: 4, total: 4, errors: 0, running: false, note: '1 re-composed from cache, 3 re-cut', onDismiss: () {}),
                const Expanded(child: SizedBox()),
              ],
            ),
          ),
          scale,
        ),
      );
      expect(tester.takeException(), isNull);
      final captionRect = tester.getRect(find.byKey(caption));
      final stripRect = tester.getRect(find.byType(ProgressStrip));
      expect(stripRect.overlaps(captionRect), isFalse);
      expect(stripRect.height, lessThan(160));
    });
  }

  testWidgets('clean finished batch leaves by itself after six seconds', (tester) async {
    setUpView(tester);
    var dismissed = 0;
    await tester.pumpWidget(app(ProgressStrip(done: 4, total: 4, errors: 0, running: false, onDismiss: () => dismissed++), 1.0));
    await tester.pump(const Duration(seconds: 5));
    expect(dismissed, 0);
    await tester.pump(const Duration(seconds: 2));
    expect(dismissed, 1);
  });

  testWidgets('finished batch with errors stays', (tester) async {
    setUpView(tester);
    var dismissed = 0;
    await tester.pumpWidget(app(ProgressStrip(done: 4, total: 4, errors: 2, running: false, onDismiss: () => dismissed++), 1.0));
    await tester.pump(const Duration(seconds: 10));
    expect(dismissed, 0);
    // finished with errors: the close button stays so the user can dismiss it
    expect(find.byKey(const ValueKey('progress-close')), findsOneWidget);
  });

  testWidgets('status dot carries a semantics label', (tester) async {
    setUpView(tester);
    await tester.pumpWidget(app(const StatusDot(color: Palette.ok, label: 'Pronta'), 1.0));
    expect(find.bySemanticsLabel('Pronta'), findsOneWidget);
  });

  testWidgets('search field uses the nav pill surface', (tester) async {
    setUpView(tester);
    final controller = TextEditingController();
    await tester.pumpWidget(app(AppSearchField(controller: controller, hint: 'Cerca', onChanged: (_) {}), 1.0));
    final inside = find.descendant(of: find.byType(AppSearchField), matching: find.byType(ColoredBox));
    expect(tester.widget<ColoredBox>(inside.first).color, NothingColors.navPill);
    expect(find.descendant(of: find.byType(AppSearchField), matching: find.byType(BackdropFilter)), findsOneWidget);
  });

  test('selection is neutral: no hue in Palette.selection', () {
    final s = Palette.selection;
    expect(s.r == s.g && s.g == s.b, isTrue);
  });
}
