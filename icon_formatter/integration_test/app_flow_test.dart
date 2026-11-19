// End-to-end flows of the app, run on a device or emulator:
//   flutter test integration_test/app_flow_test.dart -d emulator-5554
// Windows desktop works too (-d windows); the Apps tab exists on Android only.
// Language is forced to Italian, onboarding and tour are skipped (e2e_support.dart).
//
// The Apps tab opens the Shizuku permission prompt on the emulator, so it is
// only walked with --dart-define=E2E_APPS=true.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icon_formatter/app/models.dart';
import 'package:icon_formatter/app/state.dart';
import 'package:icon_formatter/app/storage.dart';
import 'package:icon_formatter/l10n/strings.dart';
import 'package:icon_formatter/screens/pack_builder_screen.dart';
import 'package:icon_formatter/services/import_service.dart';
import 'package:icon_formatter/workspace/workspace_controller.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;

import 'e2e_support.dart';

const _walkApps = bool.fromEnvironment('E2E_APPS');
const _sampleCount = 13;

/// Bottom bar: the three tabs of every platform must be on screen.
void expectTabBar() {
  for (final l in [S.studio, S.pbTitolo, S.impostazioni]) {
    expect(find.bySemanticsLabel(l).hitTestable().evaluate().isNotEmpty || find.text(l).hitTestable().evaluate().isNotEmpty,
        isTrue, reason: 'Tab bar entry "$l" is not visible');
  }
}

/// Imports the 13 samples through the Studio controller, runs "Elabora tutte"
/// and waits until every item has a result. Returns the controller.
Future<WorkspaceController> importAndProcess(WidgetTester tester) async {
  final dir = p.join(AppPaths.I.cache.path, 'e2e_samples');
  final files = await tester.runAsync(() => writeSampleIcons(dir));
  expect(files, hasLength(_sampleCount), reason: 'Sample icons were not written');

  final c = studioController(tester);
  final imgs = await tester.runAsync(() => ImportService.expand([dir]));
  expect(imgs, hasLength(_sampleCount), reason: 'Import did not find the 13 sample icons in $dir');
  c.addPaths(imgs!);
  await pumpFor(tester, const Duration(milliseconds: 500));
  expect(c.items, hasLength(_sampleCount), reason: 'Studio does not list the imported icons');

  await tapText(tester, S.elaboraTutte);
  await pumpUntil(
    tester,
    () => !c.batch.running && c.items.every((i) => c.batch.results[i.id] != null),
    timeout: const Duration(minutes: 5),
    what: 'all ${c.items.length} icons processed (results: ${c.batch.results.length})',
  );
  expect(tester.takeException(), isNull);
  return c;
}

/// "Manda al Pack" from the Studio, via the button or the "Altro" sheet.
Future<void> sendToPack(WidgetTester tester) async {
  if (find.text(S.mandaAlPack).hitTestable().evaluate().isEmpty) {
    // phones keep the rest of the actions in the "Altro" button (icon, tooltip)
    final more = find.byTooltip(S.altro).hitTestable();
    expect(more, findsWidgets, reason: 'Neither "${S.mandaAlPack}" nor the "${S.altro}" button is visible in the Studio');
    await tester.tap(more.first);
    await pumpFor(tester, const Duration(milliseconds: 600));
  }
  await tapText(tester, S.mandaAlPack);
  await pumpUntil(
    tester,
    () => find.text(S.mandateAlPack(_sampleCount)).evaluate().isNotEmpty,
    timeout: const Duration(seconds: 15),
    what: 'the "${S.mandateAlPack(_sampleCount)}" confirmation',
  );
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('a: the tabs open without exceptions and the bar is visible', (tester) async {
    await pumpApp(tester);
    expect(find.byType(Scaffold), findsWidgets, reason: 'The app did not build a screen');

    await openTab(tester, [S.studio]);
    expectTabBar();
    expect(tester.takeException(), isNull, reason: 'Studio tab threw an exception');

    await openTab(tester, [S.pbTitolo, S.pack]);
    expectTabBar();
    expect(tester.takeException(), isNull, reason: 'Pack tab threw an exception');

    await openTab(tester, [S.impostazioni, S.opzioni]);
    expectTabBar();
    expect(tester.takeException(), isNull, reason: 'Settings tab threw an exception');

    if (Platform.isAndroid && _walkApps) {
      await openTab(tester, [S.app]);
      expect(tester.takeException(), isNull, reason: 'Apps tab threw an exception');
      await pressBack(tester);
    } else if (Platform.isAndroid) {
      // the Apps tab asks for Shizuku: not opened unless E2E_APPS is set
      debugPrint('E2E: Apps tab skipped (pass --dart-define=E2E_APPS=true to walk it)');
    }
  });

  testWidgets('b: Settings > Appearance switches Nothing/Glass and light/dark, then back', (tester) async {
    await pumpApp(tester);
    await openTab(tester, [S.impostazioni, S.opzioni]);
    await tapText(tester, S.appearance);
    final a = AppState.I.appearance;

    await tapText(tester, S.stileVetro);
    expect(a.style, UiStyle.glass, reason: 'Glass style was not applied');
    expect(tester.takeException(), isNull, reason: 'Glass style threw an exception');

    await tapText(tester, S.comodoTemaScuro);
    expect(a.themeChoice, ThemeChoice.dark, reason: 'Dark theme was not chosen');
    expect(a.light, isFalse, reason: 'Dark theme not applied');
    expect(tester.takeException(), isNull, reason: 'Dark theme threw an exception');

    await tapText(tester, S.comodoTemaChiaro);
    expect(a.light, isTrue, reason: 'Light theme not applied');
    expect(tester.takeException(), isNull, reason: 'Light theme threw an exception');

    await tapText(tester, S.stileNothing);
    expect(a.style, UiStyle.nothing, reason: 'Nothing style was not restored');
    await tapText(tester, S.comodoTemaSistema);
    expect(tester.takeException(), isNull, reason: 'Switching back threw an exception');
  });

  testWidgets('c: Studio imports the samples, Elabora tutte gives outputs without errors', (tester) async {
    await pumpApp(tester);
    await openTab(tester, [S.studio]);
    final c = await importAndProcess(tester);

    for (final it in c.items) {
      final r = c.batch.results[it.id]!;
      expect(r.error, isNull, reason: 'Icon ${it.name} failed: ${r.error}');
      expect(r.ok, isTrue, reason: 'Icon ${it.name} was not processed');
      expect(it.outputPath, isNotNull, reason: 'Icon ${it.name} has no output path');
      expect(File(it.outputPath!).existsSync(), isTrue, reason: 'Output of ${it.name} is missing: ${it.outputPath}');
    }
    await sendToPack(tester);
  });

  testWidgets('d: the Pack tab shows the rows and Abbina runs', (tester) async {
    await pumpApp(tester);
    await openTab(tester, [S.studio]);
    final c = await importAndProcess(tester);
    await sendToPack(tester);

    // The Pack tab lists the catalogue apps, so the sent icons are checked in
    // the Pack builder's data: each Studio item is a generated icon 'studio:<id>'.
    final pack = PackBuilderController.I;
    final sent = pack.generated.map((g) => g.id).toSet();
    final missing = [for (final it in c.items) if (!sent.contains('studio:${it.id}')) it.name];
    expect(missing, isEmpty, reason: 'Icons not in the Pack builder: $missing');

    await openTab(tester, [S.pbTitolo, S.pack]);
    final shown = find.byType(Text).evaluate().map((e) => (e.widget as Text).data).whereType<String>().take(80).join(' | ');
    debugPrint('E2E_PACK_TEXTS $shown');
    expect(tester.takeException(), isNull, reason: 'Pack tab threw an exception');

    await tapText(tester, S.pbAbbina);
    await pumpFor(tester, const Duration(seconds: 3));
    expect(tester.takeException(), isNull, reason: 'Abbina threw an exception');
  });

  testWidgets('e: Settings > System shows the cache rows', (tester) async {
    await pumpApp(tester);
    await openTab(tester, [S.impostazioni, S.opzioni]);
    // "Sistema" is both a group title and the row: the row is the lower one
    await tester.tap(find.text(S.system).hitTestable().last);
    await pumpFor(tester, const Duration(milliseconds: 800));
    expect(find.text(S.cache).hitTestable(), findsWidgets, reason: 'The cache rows are not shown in Settings > System');
    expect(tester.takeException(), isNull, reason: 'Settings > System threw an exception');
    await pressBack(tester);
  });
}
