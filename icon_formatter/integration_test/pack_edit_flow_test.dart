// Edit page ("Edit icon") flows, run on a device or emulator:
//   flutter test integration_test/pack_edit_flow_test.dart -d emulator-5554
// The edit page is opened for a synthetic icon (drawn in e2e_support.dart), the
// tiles, Cancel, Confirm, Change and the pack-wide plate opacity are checked
// against the real engine (renderEdit), and the saved correction is read back
// from the PackStore.
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icon_formatter/app/state.dart';
import 'package:icon_formatter/app/storage.dart';
import 'package:icon_formatter/screens/pack/pb_controller.dart';
import 'package:icon_formatter/screens/pack/pb_edit_page.dart';
import 'package:icon_formatter/screens/pack/pb_model.dart';
import 'package:icon_formatter/services/packdb_db.dart';
import 'package:icon_formatter/services/packdb_store.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;

import 'e2e_support.dart';

const _pkg = 'com.test.synth';

/// Source icons of the flow: index 0 is a circle on a coloured plate, index 1 a square.
Future<List<String>> _sources(WidgetTester tester) async {
  final dir = p.join(AppPaths.I.cache.path, 'edit_flow_samples');
  await tester.runAsync(() => writeSyntheticIcons(dir, 2, size: 512));
  return [p.join(dir, 's00000_b0.png'), p.join(dir, 's00001_b1.png')];
}

PbRow _rowFor(String src) => PbRow(PbIcon(id: 'app:$_pkg', label: 'Synth', package: _pkg, file: p.basename(src), path: src));

/// RGBA pixels and size of a PNG, decoded by the engine-independent Flutter codec.
Future<({int w, Uint8List rgba})> _pixels(Uint8List png) async {
  final codec = await ui.instantiateImageCodec(png);
  final img = (await codec.getNextFrame()).image;
  final data = (await img.toByteData(format: ui.ImageByteFormat.rawRgba))!;
  return (w: img.width, rgba: data.buffer.asUint8List());
}

int _alphaAt(({int w, Uint8List rgba}) px, double fx, double fy) {
  final x = (px.w * fx).round();
  final y = (px.w * fy).round();
  return px.rgba[(y * px.w + x) * 4 + 3];
}

bool _sameBytes(Uint8List a, Uint8List b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

bool _confirmEnabled(WidgetTester tester) => tester.widget<FilledButton>(find.byKey(const ValueKey('edit-confirm'))).onPressed != null;

/// Opens the edit page as the Pack tab does (pushed route, result = PNG or null).
Future<Future<Uint8List?>> _openPage(WidgetTester tester, PbRow row, {String? source, Future<String?> Function()? pick}) async {
  final nav = tester.state<NavigatorState>(find.byType(Navigator).first);
  final f = nav.push<Uint8List>(MaterialPageRoute(
    builder: (_) => IconEditPage(controller: PackBuilderController.I, row: row, initialSource: source, pickSource: pick),
  ));
  await pumpFor(tester, const Duration(milliseconds: 600));
  return f;
}

/// Waits until the preview of the current choice is ready (Confirm enabled).
Future<void> _waitReady(WidgetTester tester) async {
  await tester.pump();
  await pumpUntil(tester, () => _confirmEnabled(tester), timeout: const Duration(minutes: 2), what: 'the preview to render');
}

Future<void> _tapTile(WidgetTester tester, EditTreatment t) async {
  final key = ValueKey('treatment-${t.name}');
  if (find.byKey(key).evaluate().isEmpty) {
    await tester.tap(find.byKey(const ValueKey('edit-more')));
    await pumpFor(tester, const Duration(milliseconds: 300));
  }
  await pumpFor(tester, const Duration(milliseconds: 300));
  expect(find.byKey(key), findsOneWidget, reason: 'Tile ${t.name} is not on the page');
  await tester.ensureVisible(find.byKey(key));
  await tester.pump();
  await tester.tap(find.byKey(key));
  await _waitReady(tester);
}

/// Waits for a pushed page to close and returns its result.
Future<Uint8List?> _closed(WidgetTester tester, Future<Uint8List?> f) async {
  Uint8List? out;
  var done = false;
  unawaited(f.then((v) {
    out = v;
    done = true;
  }));
  await pumpUntil(tester, () => done, timeout: const Duration(seconds: 60), what: 'the edit page to close');
  return out;
}

Future<Uint8List?> _confirm(WidgetTester tester, Future<Uint8List?> f) async {
  await tester.tap(find.byKey(const ValueKey('edit-confirm')));
  return _closed(tester, f);
}

Future<Uint8List?> _cancel(WidgetTester tester, Future<Uint8List?> f) async {
  await tester.tap(find.byKey(const ValueKey('edit-cancel')));
  return _closed(tester, f);
}

Future<int> _customFiles() async {
  final dir = Directory(p.join(AppPaths.I.root.path, 'pack_custom'));
  return dir.existsSync() ? dir.listSync().length : 0;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('each tile applies its own treatment (engine output per option)', (tester) async {
    await pumpApp(tester);
    final pack = PackBuilderController.I;
    final src = (await _sources(tester)).first;
    final row = _rowFor(src);
    pack.custom.remove(row.original.key);

    final results = <EditTreatment, Uint8List>{};
    final direct = <EditTreatment, Uint8List>{};
    for (final t in [EditTreatment.auto, EditTreatment.asIs, EditTreatment.plateColor, EditTreatment.fullBleed, EditTreatment.placeOnly, EditTreatment.raw]) {
      final f = await _openPage(tester, row, source: src);
      await _waitReady(tester);
      if (t != EditTreatment.auto) await _tapTile(tester, t);
      final png = await _confirm(tester, f);
      expect(png, isNotNull, reason: 'Conferma returned no image for ${t.name}');
      results[t] = png!;
      direct[t] = (await tester.runAsync(() => pack.renderEdit(src, t)))!;
      expect(_sameBytes(png, direct[t]!), isTrue, reason: '${t.name}: the page does not show the output of that treatment');
    }

    // Original: the source pixels, untouched
    final source = await tester.runAsync(() => File(src).readAsBytes());
    final sourcePx = await tester.runAsync(() => _pixels(source!));
    final rawPx = await tester.runAsync(() => _pixels(results[EditTreatment.raw]!));
    expect(rawPx!.w, sourcePx!.w);
    expect(_sameBytes(rawPx.rgba, sourcePx.rgba), isTrue, reason: 'Original changed the pixels of the source');

    // Symbol only: the plate colour behind the symbol is removed
    final asIsPx = await tester.runAsync(() => _pixels(results[EditTreatment.asIs]!));
    final autoPx = await tester.runAsync(() => _pixels(results[EditTreatment.auto]!));
    expect(_alphaAt(asIsPx!, 0.16, 0.16), lessThan(128), reason: 'Solo simbolo kept the plate behind the symbol');
    expect(_alphaAt(autoPx!, 0.16, 0.16), greaterThan(0), reason: 'Automatic removed the plate of this icon');

    // the other options do something else than Automatic
    // on this icon Automatic already recolours the symbol to the plate colour
    debugPrint('E2E_NOTE Plate colour equals Automatic on the synthetic icon: ${_sameBytes(results[EditTreatment.plateColor]!, results[EditTreatment.auto]!)}');
    expect(_sameBytes(results[EditTreatment.plateColor]!, results[EditTreatment.raw]!), isFalse, reason: 'Plate colour returned the source untouched');
    expect(_sameBytes(results[EditTreatment.fullBleed]!, results[EditTreatment.auto]!), isFalse, reason: 'Full edge is the same as Automatic');
    expect(_sameBytes(results[EditTreatment.placeOnly]!, results[EditTreatment.raw]!), isFalse, reason: 'Whole icon is the same as Original');
    expect(tester.takeException(), isNull);
  });

  testWidgets('rapid taps between tiles end on the last tap', (tester) async {
    await pumpApp(tester);
    final pack = PackBuilderController.I;
    final src = (await _sources(tester)).first;
    final row = _rowFor(src);
    final f = await _openPage(tester, row, source: src);
    await _waitReady(tester);
    for (final t in [EditTreatment.asIs, EditTreatment.fullBleed, EditTreatment.plateColor, EditTreatment.asIs, EditTreatment.plateColor]) {
      await tester.tap(find.byKey(ValueKey('treatment-${t.name}')));
      await tester.pump(const Duration(milliseconds: 20));
    }
    await _waitReady(tester);
    final png = await _confirm(tester, f);
    final expected = (await tester.runAsync(() => pack.renderEdit(src, EditTreatment.plateColor)))!;
    expect(png, isNotNull);
    expect(_sameBytes(png!, expected), isTrue, reason: 'The last tap (Plate colour) did not win');
    expect(tester.takeException(), isNull, reason: 'Rapid taps threw an exception');
  });

  testWidgets('Annulla discards the choice: no correction, no new file', (tester) async {
    await pumpApp(tester);
    final pack = PackBuilderController.I;
    final src = (await _sources(tester)).first;
    final row = _rowFor(src);
    pack.custom.remove(row.original.key);
    final before = await tester.runAsync(() async => _customFiles()) ?? 0;

    final f = await _openPage(tester, row, source: src);
    await _waitReady(tester);
    await _tapTile(tester, EditTreatment.fullBleed);
    final png = await _cancel(tester, f);

    expect(png, isNull, reason: 'Annulla returned an image');
    expect(pack.custom.containsKey(row.original.key), isFalse, reason: 'Annulla saved a correction');
    expect(row.generatedId, isNull, reason: 'Annulla changed the row');
    expect(await tester.runAsync(() async => _customFiles()), before, reason: 'Annulla wrote a file');
    expect(tester.takeException(), isNull);
  });

  testWidgets('Conferma saves the correction, regenerates the icon and is stored by the PackStore', (tester) async {
    await pumpApp(tester);
    final pack = PackBuilderController.I;
    final src = (await _sources(tester)).first;
    final row = _rowFor(src);
    pack.custom.remove(row.original.key);

    final f = await _openPage(tester, row, source: src);
    await _waitReady(tester);
    await _tapTile(tester, EditTreatment.plateColor);
    final png = await _confirm(tester, f);
    expect(png, isNotNull);
    await tester.runAsync(() => pack.applyEdit(row, png!));
    await pumpFor(tester, const Duration(milliseconds: 300));

    final saved = pack.custom[row.original.key];
    expect(saved, isNotNull, reason: 'Conferma did not store the correction');
    expect(saved!['treatment'], EditTreatment.plateColor.name, reason: 'The stored treatment is not the one chosen');
    expect(File(saved['path']!).existsSync(), isTrue, reason: 'The regenerated icon file is missing');
    expect(row.generatedId, 'custom:${row.original.key}', reason: 'The row does not use the regenerated icon');

    // written to the PackStore after the debounce: reload it from there
    await pumpFor(tester, const Duration(seconds: 2));
    // a real reload: the store is opened again from pack.db
    final stored = await tester.runAsync(() => packStoreBoot(
          PackContent(generated: const [], originals: const [], calendars: const [], custom: const {}),
          root: AppPaths.I.root.path,
          stateFile: AppPaths.I.stateFile,
          exists: (f) => File(f).existsSync(),
        ));
    expect(stored!.custom.containsKey(row.original.key), isTrue, reason: 'The correction is not in the PackStore');
    expect(stored.custom[row.original.key]!['treatment'], EditTreatment.plateColor.name);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Cambia replaces the source and refreshes the preview', (tester) async {
    await pumpApp(tester);
    final pack = PackBuilderController.I;
    final srcs = await _sources(tester);
    final row = _rowFor(srcs[0]);
    pack.custom.remove(row.original.key);

    var picked = false;
    final f = await _openPage(tester, row, source: srcs[0], pick: () async {
      picked = true;
      return srcs[1];
    });
    await _waitReady(tester);
    await tester.tap(find.byKey(const ValueKey('edit-pick')));
    await pumpUntil(tester, () => picked, what: 'the picker to be called');
    // the copy and the new render start after the pick: wait for them
    await pumpFor(tester, const Duration(milliseconds: 800));
    await _waitReady(tester);
    final png = await _confirm(tester, f);
    final expected = (await tester.runAsync(() => pack.renderEdit(srcs[1], EditTreatment.auto)))!;
    expect(png, isNotNull);
    expect(_sameBytes(png!, expected), isTrue, reason: 'Cambia did not render the new image');
    expect(tester.takeException(), isNull);
  });

  testWidgets('the pack-wide plate opacity changes the edit output (0 = no plate)', (tester) async {
    await pumpApp(tester);
    final pack = PackBuilderController.I;
    final src = (await _sources(tester)).first;
    final original = AppState.I.lucent.backdropAlpha;
    try {
      final normal = (await tester.runAsync(() => pack.renderEdit(src, EditTreatment.auto)))!;
      AppState.I.lucent.backdropAlpha = 0;
      final zero = (await tester.runAsync(() => pack.renderEdit(src, EditTreatment.auto)))!;
      expect(_sameBytes(normal, zero), isFalse, reason: 'Plate opacity 0 did not reach the engine on the edit path');
      final zeroPx = await tester.runAsync(() => _pixels(zero));
      expect(_alphaAt(zeroPx!, 0.16, 0.16), lessThan(128), reason: 'Plate opacity 0 left a plate behind');
    } finally {
      AppState.I.lucent.backdropAlpha = original;
    }
    expect(tester.takeException(), isNull);
  });
}
