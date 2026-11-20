import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icon_formatter/app/models.dart';
import 'package:icon_formatter/app/state.dart';
import 'package:icon_formatter/screens/pack/pb_model.dart';
import 'package:icon_formatter/screens/pack/pb_treatment_picker.dart';

// The treatment picker of the icon edit page: tiles keep their selected state
// and the rare options open behind "Altre opzioni", at 1.0 and 1.3 text scale
// in every style. Runs on the host (thumbnails stay pending, no engine call).
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

      Widget app(Widget child) => MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(scale)),
          child: Scaffold(
            body: ListView(
              padding: const EdgeInsets.all(20),
              children: [child],
            ),
          ),
        ),
      );

      testWidgets('Treatment picker fits at $scale in $style', (tester) async {
        setUpView(tester);
        await tester.pumpWidget(
          app(
            TreatmentPicker(
              value: EditTreatment.auto,
              onChanged: (_) {},
              thumbnail: (_) => Completer<Uint8List>().future,
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 300));
        expect(tester.takeException(), isNull);
        expect(find.byKey(const ValueKey('treatment-auto')), findsOneWidget);
        expect(find.byKey(const ValueKey('treatment-asIs')), findsOneWidget);
        expect(
          find.byKey(const ValueKey('treatment-plateColor')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('treatment-fullBleed')),
          findsOneWidget,
        );
        // the rare options stay closed by default
        expect(find.byKey(const ValueKey('treatment-raw')), findsNothing);
        expect(find.byKey(const ValueKey('treatment-placeOnly')), findsNothing);
      });

      testWidgets(
        'Selected tile is marked and taps report the choice at $scale in $style',
        (tester) async {
          setUpView(tester);
          final semantics = tester.ensureSemantics();
          
          var picked = EditTreatment.auto;
          await tester.pumpWidget(
            app(TreatmentPicker(value: picked, onChanged: (v) => picked = v)),
          );
          await tester.pump(const Duration(milliseconds: 300));
          expect(
            tester.getSemantics(find.byKey(const ValueKey('treatment-auto'))),
            matchesSemantics(
              isButton: true,
              hasSelectedState: true,
              isSelected: true,
              hasTapAction: true,
            ),
          );
          expect(
            tester.getSemantics(find.byKey(const ValueKey('treatment-asIs'))),
            matchesSemantics(
              isButton: true,
              hasSelectedState: true,
              isSelected: false,
              hasTapAction: true,
            ),
          );

          await tester.tap(find.byKey(const ValueKey('treatment-asIs')));
          await tester.pump();
          expect(picked, EditTreatment.asIs);
        semantics.dispose();
        },
      );

      testWidgets(
        'Altre opzioni opens the two rare treatments at $scale in $style',
        (tester) async {
          setUpView(tester);
          await tester.pumpWidget(
            app(TreatmentPicker(value: EditTreatment.auto, onChanged: (_) {})),
          );
          await tester.pump(const Duration(milliseconds: 300));
          await tester.tap(find.byKey(const ValueKey('edit-more')));
          await tester.pump(const Duration(milliseconds: 300));
          expect(tester.takeException(), isNull);
          expect(
            find.byKey(const ValueKey('treatment-placeOnly')),
            findsOneWidget,
          );
          expect(find.byKey(const ValueKey('treatment-raw')), findsOneWidget);
        },
      );

      testWidgets(
        'A rare treatment in use opens the list at $scale in $style',
        (tester) async {
          setUpView(tester);
          await tester.pumpWidget(
            app(TreatmentPicker(value: EditTreatment.raw, onChanged: (_) {})),
          );
          await tester.pump(const Duration(milliseconds: 300));
          expect(find.byKey(const ValueKey('treatment-raw')), findsOneWidget);
        },
      );
    }
  }
}
