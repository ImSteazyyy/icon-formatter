import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icon_formatter/app/models.dart';
import 'package:icon_formatter/src/rust/api/engine.dart';
import 'package:icon_formatter/app/preset_names.dart';
import 'package:icon_formatter/app/state.dart';
import 'package:icon_formatter/app/storage.dart';
import 'package:icon_formatter/l10n/strings.dart';
import 'package:icon_formatter/screens/settings_screen.dart';
import 'package:icon_formatter/screens/setup_screen.dart';
import 'package:icon_formatter/widgets/coach_hint.dart';
import 'package:icon_formatter/widgets/tour2_visibility.dart';

// Settings > Processing, the first-run hints and the tour's last page.
// Runs on the host: no Android channels, so the permissions page is skipped.
const t0 = TranslucentSettings(
  brightness: 0.5,
  frost: 0.5,
  transparency: 0,
  tint: 0,
  contrast: 0.5,
  border: 0.6,
  reflection: 0.45,
  depth: 0.5,
  shapeRatio: 0.93,
  exponent: 4.25,
  seed: 7,
);

void setView(WidgetTester tester, {Size size = const Size(390, 844)}) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  addTearDown(() => S.current = stringsFor('it'));
  addTearDown(() => requestedTab.value = null);
  final a = AppState.I.appearance;
  AppState.I.setupDone = false;
  a.themeChoice = ThemeChoice.dark;
  a.syncLight();
}

Widget wrap(Widget home, {double scale = 1}) => MaterialApp(
  home: MediaQuery(
    data: MediaQueryData(textScaler: TextScaler.linear(scale)),
    child: home,
  ),
);

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final tmp = await Directory.systemTemp.createTemp('ux1a2_test');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => tmp.path,
        );
    await AppPaths.init();
  });

  group('Settings > Processing', () {
    for (final scale in const [1.0, 1.3]) {
      for (final style in UiStyle.values) {
        testWidgets(
          'no duplicated cut-out controls, advanced collapsed at $scale in $style',
          (tester) async {
            setView(tester);
            AppState.I.appearance.style = style;
            await tester.pumpWidget(
              wrap(
                SettingsScreen(initial: SettingsCat.processing),
                scale: scale,
              ),
            );
            await tester.pump(const Duration(milliseconds: 400));
            expect(tester.takeException(), isNull);
            // Automatic / Sensitivity / enclosed background live only in Icon style
            expect(find.text(S.sensibilita), findsNothing);
            expect(find.text(S.rimuoviSfondoRacchiusoBuchi), findsNothing);
            expect(find.text(S.presetStile), findsNothing);
            expect(
              find.byKey(const ValueKey('processing-fine-tune')),
              findsOneWidget,
            );
            // engine details are collapsed by default
            expect(
              find.byKey(const ValueKey('processing-advanced')),
              findsOneWidget,
            );
            expect(
              find.byKey(const ValueKey('processors-choice')),
              findsNothing,
            );
            await tester.ensureVisible(
              find.byKey(const ValueKey("collapsible-header")),
            );
            await tester.pump();
            await tester.pump();
            await tester.tap(find.byKey(const ValueKey("collapsible-header")));
            await tester.pump(const Duration(milliseconds: 400));
            expect(
              find.byKey(const ValueKey('processors-choice')),
              findsOneWidget,
            );
            expect(tester.takeException(), isNull);
          },
        );
      }
    }

    testWidgets('processors choice is stored in the settings', (tester) async {
      setView(tester);
      final st = AppState.I;
      await tester.pumpWidget(
        wrap(SettingsScreen(initial: SettingsCat.processing)),
      );
      await tester.pump(const Duration(milliseconds: 400));
      await tester.ensureVisible(
        find.byKey(const ValueKey("collapsible-header")),
      );
      await tester.pump();
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey("collapsible-header")));
      await tester.pump(const Duration(milliseconds: 400));
      final cores = Platform.numberOfProcessors;
      await tester.ensureVisible(find.text(S.ux1a2ProcTutti));
      await tester.pump();
      await tester.tap(find.text(S.ux1a2ProcTutti));
      await tester.pump();
      expect(st.threads, cores);
      await tester.ensureVisible(find.text(S.ux1a2ProcPochi));
      await tester.pump();
      await tester.tap(find.text(S.ux1a2ProcPochi));
      await tester.pump();
      expect(st.threads, cores >= 2 ? cores ~/ 2 : 1);
      await tester.ensureVisible(find.text(S.ux1a2ProcAuto));
      await tester.pump();
      await tester.tap(find.text(S.ux1a2ProcAuto));
      await tester.pump();
      expect(st.threads, 0);
    });

    test('built-in preset names are localised, user names are kept', () {
      S.current = stringsFor('en');
      final sq = StylePreset(
        id: 'sqColour',
        name: 'Quadrato',
        builtIn: true,
        params: t0,
      );
      expect(presetDisplayName(sq), 'Squircle · Colour');
      final mine = StylePreset(id: 'p1', name: 'Mio', params: t0);
      expect(presetDisplayName(mine), 'Mio');
      S.current = stringsFor('it');
    });
  });

  group('first-run hints', () {
    testWidgets(
      'shown once, dismissed for good, hidden while the tour is open',
      (tester) async {
        setView(tester);
        final st = AppState.I;
        st.seenGuides.remove('coach-studio');
        await tester.pumpWidget(
          wrap(
            CoachHintLayer(tabId: 'studio', bottom: 0, child: const SizedBox()),
          ),
        );
        await tester.pump();
        expect(find.text(S.ux1a2CoachStudio), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('coach-ok-studio')));
        await tester.pump();
        expect(find.text(S.ux1a2CoachStudio), findsNothing);
        expect(st.seenGuides, contains('coach-studio'));
        // a new start: already seen, nothing shown
        await tester.pumpWidget(
          wrap(
            CoachHintLayer(tabId: 'studio', bottom: 0, child: const SizedBox()),
          ),
        );
        await tester.pump();
        expect(find.text(S.ux1a2CoachStudio), findsNothing);
        // the tour owns the screen: no hint for a section not seen yet
        st.seenGuides.remove('coach-builder');
        tourOpen.value = true;
        await tester.pumpWidget(
          wrap(
            CoachHintLayer(
              tabId: 'builder',
              bottom: 0,
              child: const SizedBox(),
            ),
          ),
        );
        await tester.pump();
        expect(find.text(S.ux1a2CoachPack), findsNothing);
        tourOpen.value = false;
        await tester.pump();
        expect(find.text(S.ux1a2CoachPack), findsOneWidget);
        st.seenGuides.remove('coach-builder');
      },
    );

    for (final scale in const [1.0, 1.3]) {
      for (final light in const [true, false]) {
        testWidgets('hint fits at $scale, ${light ? 'light' : 'dark'}', (
          tester,
        ) async {
          setView(tester, size: const Size(360, 640));
          AppState.I.appearance.themeChoice = light
              ? ThemeChoice.light
              : ThemeChoice.dark;
          AppState.I.appearance.syncLight();
          AppState.I.seenGuides.remove('coach-apps');
          await tester.pumpWidget(
            wrap(
              CoachHintLayer(
                tabId: 'apps',
                bottom: 90,
                child: const SizedBox(),
              ),
              scale: scale,
            ),
          );
          await tester.pump();
          expect(tester.takeException(), isNull);
          expect(find.text(S.ux1a2CoachApps), findsOneWidget);
          final rect = tester.getRect(
            find.byKey(const ValueKey('coach-card-apps')),
          );
          expect(rect.bottom, lessThanOrEqualTo(640 - 90));
          AppState.I.seenGuides.remove('coach-apps');
        });
      }
    }
  });

  group('tour', () {
    testWidgets(
      'last page: three steps close the tour and open their section',
      (tester) async {
        setView(tester, size: const Size(360, 640));
        await tester.pumpWidget(wrap(const OnboardingScreen()));
        await tester.pumpAndSettle();
        for (var i = 0; i < 3; i++) {
          await tester.tap(find.byKey(const ValueKey('tour-next')));
          await tester.pumpAndSettle();
        }
        expect(find.text(S.ux1a2Step1), findsOneWidget);
        expect(find.text(S.ux1a2Step3), findsOneWidget);
        final pack = find.byKey(const ValueKey('tour-step-pack'));
        await tester.ensureVisible(pack);
        await tester.pumpAndSettle();
        await tester.tap(pack);
        await tester.pumpAndSettle();
        expect(AppState.I.setupDone, isTrue);
        expect(requestedTab.value, 'builder');
      },
    );

    testWidgets('texts follow the language chosen on the Language page', (
      tester,
    ) async {
      setView(tester);
      await tester.pumpWidget(wrap(const OnboardingScreen()));
      await tester.pumpAndSettle();
      // the tour opens on the language page (the host has no permissions page)
      // the language page: the app sets S.current and notifies, the page follows at once
      final en = stringsFor('en');
      S.current = en;
      AppState.I.update(() => AppState.I.appearance.language = 'en');
      await tester.pump();
      expect(find.text(en.lingua), findsWidgets);
      expect(find.text(stringsFor('it').lingua), findsNothing);
      AppState.I.update(() => AppState.I.appearance.language = '');
      S.current = stringsFor('it');
    });
  });
}
