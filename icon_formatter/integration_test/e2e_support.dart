// Shared helpers for the end-to-end tests (app_flow_test.dart and
// stress_5000_test.dart). Bootstraps the app the way lib/main.dart does, minus
// the window and the system UI setup, and skips the first-run onboarding.
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icon_formatter/app/state.dart';
import 'package:icon_formatter/app/storage.dart';
import 'package:icon_formatter/l10n/strings.dart';
import 'package:icon_formatter/main.dart' show IconFormatterApp;
import 'package:icon_formatter/screens/studio_screen.dart';
import 'package:icon_formatter/src/rust/api/engine.dart';
import 'package:icon_formatter/src/rust/frb_generated.dart';
import 'package:icon_formatter/widgets/theme_reveal.dart';
import 'package:icon_formatter/workspace/workspace_controller.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:path/path.dart' as p;

bool _booted = false;

/// Same order as lib/main.dart. Runs once per process (all tests share it).
Future<void> bootstrapApp() async {
  if (_booted) return;
  _booted = true;
  await LiquidGlassWidgets.initialize(enablePerformanceMonitor: false);
  await RustLib.init();
  await AppPaths.init();
  await AppState.I.load();
  if (Platform.isAndroid) setWorkerThreads(n: AppState.I.threads > 0 ? AppState.I.threads : 4);
  // deterministic: Italian, no onboarding, no tour
  AppState.I.update(() {
    AppState.I.setupDone = true;
    AppState.I.tourDone = true;
    AppState.I.appearance.language = 'it';
  });
  S.current = stringsFor('it');
}

/// The widget tree of main(): the app wrapped by the glass and theme-reveal layers.
Widget appUnderTest() => LiquidGlassWidgets.wrap(
      child: ThemeReveal.wrap(const IconFormatterApp()),
      brightnessResolver: Theme.maybeBrightnessOf,
      adaptiveQuality: false,
    );

/// Pumps the app from scratch (fresh Shell, first tab selected).
Future<void> pumpApp(WidgetTester tester) async {
  installErrorAllowlist();
  await bootstrapApp();
  await tester.pumpWidget(appUnderTest());
  await pumpFor(tester, const Duration(milliseconds: 800));
}

/// Pumps real frames for [d]. pumpAndSettle never returns while the app has
/// running animations (progress indicators, glass shaders), so flows use this.
Future<void> pumpFor(WidgetTester tester, Duration d) async {
  final end = DateTime.now().add(d);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// Pumps until [cond] is true, failing with [what] after [timeout].
Future<void> pumpUntil(
  WidgetTester tester,
  bool Function() cond, {
  Duration timeout = const Duration(seconds: 30),
  required String what,
}) async {
  final end = DateTime.now().add(timeout);
  while (!cond()) {
    if (DateTime.now().isAfter(end)) {
      fail('Timeout after ${timeout.inSeconds}s waiting for: $what');
    }
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Taps the first visible widget showing [text]; fails with a readable message.
Future<void> tapText(WidgetTester tester, String text) async {
  final f = find.text(text).hitTestable();
  expect(f, findsWidgets, reason: 'No visible "$text" on screen');
  await tester.tap(f.first);
  await pumpFor(tester, const Duration(milliseconds: 500));
}

/// Taps a bottom bar tab. The bar shows the full or the short label, depending
/// on the layout, so both are tried.
Future<void> openTab(WidgetTester tester, List<String> labels) async {
  for (final l in labels) {
    final bySemantics = find.bySemanticsLabel(l).hitTestable();
    if (bySemantics.evaluate().isNotEmpty) {
      await tester.tap(bySemantics.first);
      await pumpFor(tester, const Duration(milliseconds: 700));
      return;
    }
    final byText = find.text(l).hitTestable();
    if (byText.evaluate().isNotEmpty) {
      await tester.tap(byText.last);
      await pumpFor(tester, const Duration(milliseconds: 700));
      return;
    }
  }
  fail('No tab bar entry found for any of $labels');
}

/// Back gesture (Android back / Escape): pops the top route.
Future<void> pressBack(WidgetTester tester) async {
  await tester.binding.handlePopRoute();
  await pumpFor(tester, const Duration(milliseconds: 600));
}

/// The Studio tab's WorkspaceController. _StudioScreenState keeps it in the
/// public field `c`; the state class is private, so the field is read dynamically.
WorkspaceController studioController(WidgetTester tester) {
  final state = tester.state<State>(find.byType(StudioScreen));
  return (state as dynamic).c as WorkspaceController;
}

/// Writes 13 synthetic 256x256 icons (drawn here, no third-party art) to [dir].
Future<List<String>> writeSampleIcons(String dir) async {
  final d = Directory(dir);
  if (d.existsSync()) d.deleteSync(recursive: true);
  d.createSync(recursive: true);
  final out = <String>[];
  for (var i = 0; i < 13; i++) {
    final rec = ui.PictureRecorder();
    final canvas = ui.Canvas(rec, const ui.Rect.fromLTWH(0, 0, 256, 256));
    final hue = ui.Color(0xFF000000 | ((i * 0x1F3D5B) & 0xFFFFFF));
    canvas.drawRRect(
      ui.RRect.fromRectAndRadius(const ui.Rect.fromLTWH(12, 12, 232, 232), const ui.Radius.circular(48)),
      ui.Paint()..color = hue,
    );
    final fg = ui.Paint()..color = const ui.Color(0xFFFFFFFF);
    if (i.isEven) {
      canvas.drawCircle(const ui.Offset(128, 128), 60 + (i % 4) * 8.0, fg);
    } else {
      canvas.drawRect(ui.Rect.fromLTWH(70 + i * 2.0, 70, 116, 116), fg);
    }
    final img = await rec.endRecording().toImage(256, 256);
    final bytes = (await img.toByteData(format: ui.ImageByteFormat.png))!.buffer.asUint8List();
    final path = p.join(dir, 'sample_${i.toString().padLeft(2, '0')}.png');
    File(path).writeAsBytesSync(bytes);
    out.add(path);
  }
  return out;
}

/// Renders one synthetic icon. [variant] changes the colours, the dot and a
/// 16-bit code in the corner, so every variant has distinct pixels.
Future<Uint8List> _renderIcon({required int base, required int variant, required int size}) async {
  final s = size / 256;
  final rec = ui.PictureRecorder();
  final canvas = ui.Canvas(rec, ui.Rect.fromLTWH(0, 0, size.toDouble(), size.toDouble()));
  final hue = ui.Color(0xFF000000 | ((variant * 0x9E3779B1 + base * 0x1F3D5B) & 0xFFFFFF));
  canvas.drawRRect(
    ui.RRect.fromRectAndRadius(ui.Rect.fromLTWH(12 * s, 12 * s, 232 * s, 232 * s), ui.Radius.circular(48 * s)),
    ui.Paint()..color = hue,
  );
  final fg = ui.Paint()..color = const ui.Color(0xFFFFFFFF);
  if (base.isEven) {
    canvas.drawCircle(ui.Offset(size / 2, size / 2), (60 + (base % 4) * 8) * s, fg);
  } else {
    canvas.drawRect(ui.Rect.fromLTWH((70 + base * 2) * s, 70 * s, 116 * s, 116 * s), fg);
  }
  final cell = 8 * s;
  for (var bit = 0; bit < 16; bit++) {
    final on = ((variant >> bit) & 1) == 1;
    canvas.drawRect(
      ui.Rect.fromLTWH((bit % 4) * cell, (bit ~/ 4) * cell, cell, cell),
      ui.Paint()..color = on ? const ui.Color(0xFFFFFFFF) : const ui.Color(0xFF000000),
    );
  }
  final img = await rec.endRecording().toImage(size, size);
  final bytes = (await img.toByteData(format: ui.ImageByteFormat.png))!.buffer.asUint8List();
  img.dispose();
  return bytes;
}

/// Writes [n] distinct synthetic PNGs (size x size) to [dir]; returns the count.
/// Call inside tester.runAsync (real engine work).
Future<int> writeSyntheticIcons(String dir, int n, {int size = 512}) async {
  final d = Directory(dir);
  if (d.existsSync()) d.deleteSync(recursive: true);
  d.createSync(recursive: true);
  for (var i = 0; i < n; i++) {
    final base = i % 13;
    final bytes = await _renderIcon(base: base, variant: i, size: size);
    File(p.join(dir, 's${i.toString().padLeft(5, '0')}_b$base.png')).writeAsBytesSync(bytes);
  }
  return n;
}

/// FlutterErrors the flows tolerate: a fragment of the message and where it is
/// raised. Keep this list short; every entry is a known problem in lib/.
/// TODO(lib): remove the entry once AutoSyncCard gets a Material ancestor
/// (lib/screens/pack_builder_screen.dart:3116, its SwitchListTile and
/// ListTile sit in a Tile = DecoratedBox, shown in the Pack tab).
const allowedFlutterErrors = <(String, String)>[
  (
    'ListTile background color or ink splashes may be invisible',
    'lib/screens/pack_builder_screen.dart:3116 AutoSyncCard (TODO: wrap in Material)',
  ),
];

/// Allowed errors seen in this process (printed by the tests, not failures).
final List<String> allowedErrorHits = [];

/// Installs the allowlist on top of the test framework's error handler. Called
/// by pumpApp at the start of each test; the framework restores its own
/// handler after the test.
void installErrorAllowlist() {
  final prev = FlutterError.onError;
  FlutterError.onError = (details) {
    final msg = details.exceptionAsString();
    final hit = allowedFlutterErrors.where((a) => msg.contains(a.$1)).firstOrNull;
    if (hit == null) {
      if (prev != null) {
        prev(details);
      } else {
        FlutterError.presentError(details);
      }
      return;
    }
    final where = listTileOffenders();
    // app frames of the stack name the code that built the ListTile
    final appFrames = '${details.stack ?? ''}'.split('\n').where((l) => l.contains('icon_formatter')).take(6).join('\n');
    final text = '${hit.$2}\n$where\n$appFrames\n${details.informationCollector?.call().map((n) => n.toString()).join('\n') ?? ''}';
    allowedErrorHits.add(text);
    debugPrint('E2E_ALLOWED $text');
  };
}

/// ListTiles that have a DecoratedBox between them and the nearest Material,
/// with their creation location (the source line of the widget).
String listTileOffenders() {
  final out = <String>[];
  void visit(Element e) {
    if (e.widget is ListTile) {
      // a DecoratedBox met before the nearest Material is the offence
      var deco = false;
      e.visitAncestorElements((a) {
        if (a.widget is Material) return false;
        if (a.widget is DecoratedBox) deco = true;
        return true;
      });
      // the creator chain names the source file and line of each widget
      if (deco) out.add(e.debugGetCreatorChain(14));
    }
    e.visitChildren(visit);
  }

  final root = WidgetsBinding.instance.rootElement;
  if (root != null) visit(root);
  return out.join('\n');
}
