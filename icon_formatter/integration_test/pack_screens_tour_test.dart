// Pack screens, driven on the emulator, with screenshots taken from the shell:
//   flutter test integration_test/pack_screens_tour_test.dart -d emulator-5556
// Every "SHOT <name>" line is a pause: the shell takes the screenshot then
// (see the watcher used by the agent). Also checks the new-apps notice (fresh
// flag, badge, snackbar, no reuse) and Change background with Cancel.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icon_formatter/app/models.dart';
import 'package:icon_formatter/app/state.dart';
import 'package:icon_formatter/app/storage.dart';
import 'package:icon_formatter/l10n/strings.dart';
import 'package:icon_formatter/screens/pack/pb_controller.dart';
import 'package:icon_formatter/screens/pack/pb_model.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;

import 'e2e_support.dart';

Future<void> _shot(WidgetTester tester, String name, {int seconds = 4}) async {
  // ignore: avoid_print
  print('SHOT $name');
  // real time, so the shell can take the screenshot while the screen is still
  await tester.runAsync(() => Future<void>.delayed(Duration(seconds: seconds)));
  await pumpFor(tester, const Duration(milliseconds: 200));
}

Future<void> _look(WidgetTester tester, UiStyle style, ThemeChoice theme) async {
  AppState.I.update(() {
    AppState.I.appearance.style = style;
    AppState.I.appearance.themeChoice = theme;
  });
  await pumpFor(tester, const Duration(seconds: 1));
}

/// Seeds [n] synthetic non-app originals and renders them once.
Future<void> _seed(WidgetTester tester, PackBuilderController pack, int n, String dirName) async {
  final dir = p.join(AppPaths.I.cache.path, dirName);
  await tester.runAsync(() => writeSyntheticIcons(dir, n, size: 256));
  final files = Directory(dir).listSync().whereType<File>().map((f) => f.path).where((f) => f.endsWith('.png')).toList()..sort();
  pack.originals.removeWhere((o) => !o.id.startsWith('app:'));
  pack.originals.addAll([
    for (var i = 0; i < files.length; i++)
      PbIcon(id: 'seed$dirName$i', label: 'Tour ${i + 1}', package: 'com.test.tour$dirName$i', file: p.basename(files[i]), path: files[i]),
  ]);
  pack.rows.clear();
  await tester.runAsync(() => pack.generateFromOriginals());
  await tester.runAsync(() => pack.match());
  await pumpFor(tester, const Duration(seconds: 1));
}

Future<void> _openMore(WidgetTester tester) async {
  final b = find.byKey(const ValueKey('pb-altro'));
  await tester.dragUntilVisible(b, find.byType(Scrollable).first, const Offset(0, -240));
  await tester.pump(const Duration(milliseconds: 300));
  await tester.tap(b);
  await pumpFor(tester, const Duration(milliseconds: 800));
}

/// Taps a More entry by key (the sheet pops itself before the tool runs).
Future<void> _moreItem(WidgetTester tester, String key) async {
  await _openMore(tester);
  final f = find.byKey(ValueKey(key));
  expect(f, findsOneWidget, reason: 'More entry $key is missing');
  // the More sheet scrolls: the lower rows (Cambia sfondo) can be below the fold
  await tester.scrollUntilVisible(f, 200, scrollable: find.descendant(of: find.byType(SingleChildScrollView).last, matching: find.byType(Scrollable)).first);
  await pumpFor(tester, const Duration(milliseconds: 300));
  await tester.tap(f);
  await pumpFor(tester, const Duration(milliseconds: 900));
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Pack screens in three looks, notice and Change background', (tester) async {
    await pumpApp(tester);
    final pack = PackBuilderController.I;
    await _seed(tester, pack, 12, 'tour12');
    // ignore: avoid_print
    print('SEED generated=${pack.generated.length} rows=${pack.rows.length}');
    await openTab(tester, [S.pbTitolo, S.pack]);

    final looks = <(String, UiStyle, ThemeChoice)>[
      ('nothing-dark', UiStyle.nothing, ThemeChoice.dark),
      ('nothing-light', UiStyle.nothing, ThemeChoice.light),
    ];
    for (final (name, style, theme) in looks) {
      await _look(tester, style, theme);
      await _shot(tester, '$name-pack');

      if (name == 'nothing-dark') {
        // single-icon sheet of the first icon, then its "Edit icon" (empty state)
        final first = pack.rows.firstWhere((r) => r.original.id.startsWith('seed'));
        final card = find.byKey(ValueKey('pb-card-${first.original.id}'));
        await tester.dragUntilVisible(card, find.byType(Scrollable).first, const Offset(0, -240));
        await tester.pump(const Duration(milliseconds: 300));
        await tester.tap(card);
        await pumpFor(tester, const Duration(milliseconds: 900));
        await _shot(tester, '$name-sheet');
        await tester.tap(find.byKey(const ValueKey('pb-edit-primary')));
        await pumpFor(tester, const Duration(milliseconds: 900));
        await _shot(tester, '$name-editempty');
        await pressBack(tester);

      }

      // More sheet, cleanup screen, Change background sheet
      await _openMore(tester);
      await _shot(tester, '$name-more');
      await pressBack(tester);
      await _moreItem(tester, 'pb-altro-cleanup');
      await _shot(tester, '$name-cleanup');
      await pressBack(tester);
      await _moreItem(tester, 'pb-altro-plate');
      await _shot(tester, '$name-plate');
      await pressBack(tester);
    }

    // new-apps notice: the catalogue is read, three apps are taken out of the
    // pack list, then "Aggiorna" adds them again: they are fresh, not reused
    await _look(tester, UiStyle.nothing, ThemeChoice.dark);
    await tester.runAsync(() => pack.loadCatalog());
    final victims = pack.originals.where((o) => o.id.startsWith('app:')).take(3).map((o) => o.id).toList();
    expect(victims.length, 3, reason: 'the catalogue has fewer than 3 apps');
    pack.originals.removeWhere((o) => victims.contains(o.id));
    // back to the top of the Pack list, where the catalogue buttons are
    await tester.drag(find.byType(Scrollable).first, const Offset(0, 3000));
    await pumpFor(tester, const Duration(milliseconds: 600));
    await tapText(tester, S.pbAggiornaCatalogo);
    await pumpUntil(tester, () => !pack.busy, timeout: const Duration(minutes: 5), what: 'the catalogue refresh');
    final fresh = pack.rows.where((r) => r.original.isFresh).toList();
    expect(fresh.map((r) => r.original.id).toSet(), victims.toSet(), reason: 'exactly the added apps must be fresh');
    for (final r in fresh) {
      final gid = r.generatedId ?? '';
      expect(gid.startsWith('pk') || gid.startsWith('studio:'), isFalse, reason: 'an added app reused a pack or Studio icon');
    }
    await pumpUntil(tester, () => find.text(S.ux1bGenBanner(3)).evaluate().isNotEmpty, timeout: const Duration(seconds: 30), what: 'the notice');
    expect(find.byIcon(Icons.new_releases_outlined), findsWidgets, reason: 'the badge is missing');
    await _shot(tester, 'nothing-dark-notice');

    // Review opens the first fresh icon and clears its flag
    await tapText(tester, S.ux1bReviewStart);
    await pumpFor(tester, const Duration(milliseconds: 900));
    await pressBack(tester);
    expect(pack.rows.where((r) => r.original.isFresh).length, lessThan(3), reason: 'opening an icon must clear its flag');

    // Change background on 200 icons, then Cancel mid-run
    await _seed(tester, pack, 200, 'tour200');
    await _moreItem(tester, 'pb-altro-plate');
    expect(find.byKey(const ValueKey('plate-apply')), findsOneWidget, reason: 'the Change background sheet did not open');
    await tester.tap(find.byKey(const ValueKey('plate-apply')));
    await pumpFor(tester, const Duration(seconds: 2));
    await _shot(tester, 'nothing-dark-plate-running', seconds: 2);
    await pumpUntil(tester, () => find.byKey(const ValueKey('plate-cancel')).evaluate().isNotEmpty, timeout: const Duration(seconds: 30), what: 'the running state with Cancel');
    await tester.tap(find.byKey(const ValueKey('plate-cancel')));
    await pumpUntil(tester, () => !pack.busy, timeout: const Duration(minutes: 3), what: 'the cancelled run to stop');
    final kept = pack.generated.where((g) => g.path != null).length;
    // ignore: avoid_print
    print('PLATE_CANCEL kept=$kept');
    expect(kept, greaterThan(0), reason: 'the icons done before Cancel must stay');
    await pumpFor(tester, const Duration(seconds: 1));
    await _shot(tester, 'nothing-dark-plate-cancelled');
  }, timeout: const Timeout(Duration(minutes: 40)));
}
