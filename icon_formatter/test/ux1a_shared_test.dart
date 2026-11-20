import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icon_formatter/app/models.dart';
import 'package:icon_formatter/app/state.dart';
import 'package:icon_formatter/app/theme.dart';
import 'package:icon_formatter/l10n/strings.dart';
import 'package:icon_formatter/src/rust/api/engine.dart' show PlacementSettings, SegMode, SegmentSettings, TranslucentSettings;
import 'package:icon_formatter/widgets/app_search.dart';
import 'package:icon_formatter/widgets/common.dart';
import 'package:icon_formatter/widgets/empty_state.dart';
import 'package:icon_formatter/widgets/glass_menu.dart';
import 'package:icon_formatter/widgets/liquid_glass.dart';
import 'package:icon_formatter/workspace/adjust_panel.dart';
import 'package:icon_formatter/workspace/workspace_controller.dart';

// Shared UI of the redesign: the Icon style panel, the unified search field,
// the grouped menu, the empty state and the semantic colours. Runs on the host.

Widget _app(Widget home, double scale) => MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(scale)),
        child: Scaffold(body: home),
      ),
    );

void _phone(WidgetTester tester) {
  tester.view.physicalSize = const Size(400, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  AppState.I.setupDone = true;
  // the defaults that AppState.load() sets (no storage in tests)
  final st = AppState.I;
  st.defaultTranslucent = const TranslucentSettings(
    brightness: 0.5, frost: 0.5, transparency: 0.5, tint: 0, contrast: 0.5, border: 0.5, reflection: 0.5, depth: 0.5, shapeRatio: 0.9, exponent: 5, seed: 1,
  );
  st.defaultPlacement = const PlacementSettings(
    glyphRatio: 0.7, areaRatio: 0.7, centerX: 0.5, centerY: 0.5, areaFit: false, scaleMul: 1, offsetX: 0, offsetY: 0,
  );
  st.defaultSegment = SegmentSettings(mode: SegMode.values.first, tolerance: 0.1, removeHoles: false, refineEdges: false);
  st.segment = st.defaultSegment;
  st.packSegment = st.defaultSegment;
  st.presets = builtInPresets(st.defaultTranslucent);
}

void main() {
  for (final scale in const [1.0, 1.3]) {
    for (final style in UiStyle.values) {
      for (final light in const [false, true]) {
        final name = '$style ${light ? 'light' : 'dark'} x$scale';

        testWidgets('style sheet: advanced collapsed, one size control, $name', (tester) async {
          _phone(tester);
          AppState.I.appearance.style = style;
          AppState.I.appearance.light = light;
          final c = WorkspaceController(tag: 'ux1a-sheet', mode: StudioMode.translucent);
          await tester.pumpWidget(_app(AdjustPanel(c: c), scale));
          await tester.pump(const Duration(milliseconds: 300));
          expect(tester.takeException(), isNull);
          // the technical options are behind "Advanced", collapsed
          expect(find.text(S.ux1aAvanzate), findsOneWidget);
          expect(find.text(S.sensibilita), findsNothing);
          expect(find.text(S.lucentCodificaLauncher), findsNothing);
          // exactly one symbol-size control, and no second "Size" or Lucent scale
          expect(find.byWidgetPredicate((w) => w is SliderRow && w.label == S.ux1aSimbolo), findsOneWidget);
          expect(find.byWidgetPredicate((w) => w is SliderRow && w.label == S.scala), findsNothing);
          expect(find.byWidgetPredicate((w) => w is SliderRow && w.label == S.lucentScalaGlifo), findsNothing);
        });
      }
    }
  }

  testWidgets('style sheet: opening Advanced shows the groups, each collapsed', (tester) async {
    _phone(tester);
    final c = WorkspaceController(tag: 'ux1a-adv', mode: StudioMode.translucent);
    await tester.pumpWidget(_app(AdjustPanel(c: c), 1.0));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text(S.ux1aAvanzate));
    await tester.pumpAndSettle();
    expect(find.text(S.ux1aTaglio), findsOneWidget);
    expect(find.text(S.composizione), findsOneWidget);
    // the groups are collapsed too
    expect(find.text(S.sensibilita), findsNothing);
    await tester.tap(find.text(S.ux1aTaglio));
    await tester.pumpAndSettle();
    expect(find.text(S.sensibilita), findsOneWidget);
  });

  testWidgets('presets: modified pill, reset to preset, update of a saved preset', (tester) async {
    _phone(tester);
    final st = AppState.I;
    st.appearance.style = UiStyle.nothing;
    st.appearance.light = false;
    st.activePresetId = 'sqColour';
    final c = WorkspaceController(tag: 'ux1a-preset', mode: StudioMode.preset);
    await tester.pumpWidget(_app(AdjustPanel(c: c), 1.0));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text(S.ux1aModificato), findsNothing);

    // edit a built-in: the state says so and reset comes back
    final builtIn = st.presetById('sqColour');
    st.update(() => builtIn.lucent!.backdropAlphaDark = 0.2);
    await tester.pump();
    expect(st.presetModified(builtIn), isTrue);
    expect(find.text(S.ux1aModificato), findsOneWidget);
    expect(find.text(S.ux1aModificatoNonSalvato), findsOneWidget);
    expect(find.byKey(const ValueKey('preset-reset')), findsOneWidget);
    expect(find.byKey(const ValueKey('preset-update')), findsNothing); // built-ins are not updated
    await tester.tap(find.byKey(const ValueKey('preset-reset')));
    await tester.pump();
    expect(st.presetModified(builtIn), isFalse);
    expect(find.text(S.ux1aModificato), findsNothing);

    // a user preset: its last save is the baseline, "Update preset" makes the edit the new one
    final mine = st.savePresetAs('ux1a test preset', builtIn.params);
    st.activePresetId = mine.id;
    await tester.pump();
    st.setPresetParams(mine.id, copyTranslucent(mine.params, frost: mine.params.frost > 0.5 ? 0.1 : 0.9));
    await tester.pump();
    expect(st.presetModified(mine), isTrue);
    expect(find.byKey(const ValueKey('preset-update')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('preset-update')));
    await tester.pump();
    expect(st.presetModified(mine), isFalse);
    expect(find.text(S.ux1aPresetSalvato), findsOneWidget);
    // let the preview debounce timer of the controller run out
    await tester.pump(const Duration(milliseconds: 200));
  });

  testWidgets('search field: clear button and a separate filter with its badge', (tester) async {
    final ctrl = TextEditingController();
    var filterTaps = 0;
    var last = 'unset';
    await tester.pumpWidget(_app(
      AppSearchField(
        controller: ctrl,
        hint: 'Find',
        onChanged: (v) => last = v,
        onFilter: () => filterTaps++,
        filterOn: true,
        fieldKey: const ValueKey('field'),
        filterKey: const ValueKey('filter'),
      ),
      1.3,
    ));
    expect(find.byIcon(Icons.close_rounded), findsNothing);
    await tester.enterText(find.byKey(const ValueKey('field')), 'abc');
    await tester.pump();
    expect(last, 'abc');
    expect(find.byIcon(Icons.close_rounded), findsOneWidget);
    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pump();
    expect(ctrl.text, isEmpty);
    expect(last, isEmpty);
    await tester.tap(find.byKey(const ValueKey('filter')));
    expect(filterTaps, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('glass menu: section titles are not actions, destructive entry returns its value', (tester) async {
    _phone(tester);
    int? picked;
    await tester.pumpWidget(_app(
      Builder(
        builder: (ctx) => TextButton(
          onPressed: () async {
            picked = await showGlassMenu<int>(ctx, anchor: const Rect.fromLTWH(120, 300, 40, 40), items: const [
              GlassMenuItem(value: -1, label: 'Edit', section: true),
              GlassMenuItem(value: 0, label: 'Undo'),
              GlassMenuItem(value: -2, label: 'Remove', section: true),
              GlassMenuItem(value: 1, label: 'Clear', destructive: true),
            ]);
          },
          child: const Text('open'),
        ),
      ),
      1.0,
    ));
    await tester.tap(find.text('open'));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Edit'), findsOneWidget);
    await tester.tap(find.text('Edit'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Undo'), findsOneWidget); // still open
    await tester.tap(find.text('Clear'));
    await tester.pump(const Duration(seconds: 1));
    expect(picked, 1);
  });

  testWidgets('empty state shows title and hint at 1.3 scale', (tester) async {
    _phone(tester);
    await tester.pumpWidget(_app(const EmptyState(icon: Icons.image_outlined, title: 'No icon selected', hint: 'Choose an image to see the result'), 1.3));
    await tester.pump();
    expect(find.text('No icon selected'), findsOneWidget);
    expect(find.text('Choose an image to see the result'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('selection colour is monochrome in the Nothing style, not the red accent', () {
    AppState.I.appearance.style = UiStyle.nothing;
    AppState.I.appearance.light = false;
    expect(Palette.selection, NothingColors.on);
    expect(Palette.selection, isNot(Palette.danger));
  });
}
