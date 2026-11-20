import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icon_formatter/app/models.dart';
import 'package:icon_formatter/app/state.dart';
import 'package:icon_formatter/screens/pack/pb_controller.dart';
import 'package:icon_formatter/screens/pack/pb_edit_page.dart';
import 'package:icon_formatter/screens/pack/pb_model.dart';

// The edit page must fit a 720x1600 phone (360x800 dp at 2x) without scrolling
// at text scale 1.0: the treatment options and the Annulla/Conferma bar are on
// screen together. At 1.3 only "no exception" is required (it scrolls).
void main() {
  final looks = <(String, UiStyle, ThemeChoice)>[
    ('Nothing dark', UiStyle.nothing, ThemeChoice.dark),
    ('Nothing light', UiStyle.nothing, ThemeChoice.light),
  ];
  for (final look in looks) {
    testWidgets('edit page fits 360x800 without scrolling: ${look.$1}', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(720, 1600);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      AppState.I.setupDone = true;
      AppState.I.appearance.style = look.$2;
      AppState.I.appearance.themeChoice = look.$3;
      final row = PbRow(
        PbIcon(
          id: 'app:com.test.fit',
          label: 'Fit',
          package: 'com.test.fit',
          file: 'fit.png',
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: IconEditPage(controller: PackBuilderController.I, row: row),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.takeException(), isNull);

      final more = tester.getRect(find.byKey(const ValueKey('edit-more')));
      final cancel = tester.getRect(find.byKey(const ValueKey('edit-cancel')));
      final confirm = tester.getRect(
        find.byKey(const ValueKey('edit-confirm')),
      );
      expect(
        more.bottom,
        lessThanOrEqualTo(cancel.top),
        reason: '"Altre opzioni" is hidden behind the bottom bar',
      );
      expect(
        confirm.bottom,
        lessThanOrEqualTo(800),
        reason: 'Conferma is off the screen',
      );
      final list = tester.state<ScrollableState>(find.byType(Scrollable).first);
      expect(
        list.position.maxScrollExtent,
        lessThanOrEqualTo(0.5),
        reason: 'the page needs scrolling at text scale 1.0',
      );
    });

    testWidgets('edit page builds at text scale 1.3: ${look.$1}', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(720, 1600);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      AppState.I.setupDone = true;
      AppState.I.appearance.style = look.$2;
      AppState.I.appearance.themeChoice = look.$3;
      final row = PbRow(
        PbIcon(
          id: 'app:com.test.fit',
          label: 'Fit',
          package: 'com.test.fit',
          file: 'fit.png',
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(
              size: Size(360, 800),
              devicePixelRatio: 2,
              textScaler: TextScaler.linear(1.3),
            ),
            child: IconEditPage(controller: PackBuilderController.I, row: row),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.takeException(), isNull);
      expect(find.byKey(const ValueKey('edit-confirm')), findsOneWidget);
    });
  }
}
