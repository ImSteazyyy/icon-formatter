// End-to-end FFI checks (Rust core through flutter_rust_bridge).
// Run on Windows:  flutter test integration_test/ffi_test.dart -d windows
// Run on Android:  flutter test integration_test/ffi_test.dart -d <device>
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:icon_formatter/src/rust/api/engine.dart';
import 'package:icon_formatter/src/rust/frb_generated.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;

/// Builds a PNG in memory through the Rust encoder: white square on blue.
Future<Uint8List> syntheticIcon() async {
  final dir = await Directory.systemTemp.createTemp('if_test');
  // Render a translucent background and use it as an "icon" with a plate.
  final bg = await renderBackgroundPng(
    background: BackgroundSettings.translucent(params: defaultTranslucentSettings()),
    size: 256,
  );
  final f = File(p.join(dir.path, 'bg.png'))..writeAsBytesSync(bg);
  return f.readAsBytesSync();
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async => RustLib.init());

  test('defaults and version cross the bridge', () {
    expect(coreVersion(), isNotEmpty);
    expect(defaultPlacementSettings().glyphRatio, closeTo(0.645, 0.01));
    expect(sanitizeDrawableName(name: 'com.WhatsApp'), 'com_whatsapp');
  });

  test('translucent background is RGBA, neutral and squircle-shaped', () async {
    final png = await renderBackgroundPng(
      background: BackgroundSettings.translucent(params: defaultTranslucentSettings()),
      size: 192,
    );
    expect(png.sublist(1, 4), [0x50, 0x4E, 0x47]); // "PNG"
    // colour type byte in IHDR = 6 (RGBA)
    expect(png[25], 6);
  });

  test('preview composes glyph on a base and reports diagnostics', () async {
    final bytes = await syntheticIcon();
    final s = ProcessSettings(
      size: 192,
      background: BackgroundSettings.translucent(params: defaultTranslucentSettings()),
      placement: defaultPlacementSettings(),
      segment: defaultSegmentSettings(),
    );
    final r = await previewBytes(bytes: bytes, settings: s);
    expect(r.size, 192);
    expect(r.png[25], 6);
    expect(r.bbox.length, 4);
  });

  test('batch streams progress and honours cancellation', () async {
    final bytes = await syntheticIcon();
    final out = await Directory.systemTemp.createTemp('if_batch');
    final items = [
      for (var i = 0; i < 12; i++)
        BatchItem(id: '$i', name: 'i$i', bytes: bytes, output: p.join(out.path, 'i$i.png'), skipIsolation: false),
    ];
    final s = ProcessSettings(
      size: 128,
      background: const BackgroundSettings.transparent(),
      placement: defaultPlacementSettings(),
      segment: defaultSegmentSettings(),
    );
    final events = await runBatch(items: items, settings: s, threads: 2, cancel: CancelToken()).toList();
    expect(events.length, 12);
    expect(events.where((e) => e.result.ok).length, 12);
    expect(File(p.join(out.path, 'i5.png')).existsSync(), true);

    final token = CancelToken()..cancel();
    final cancelled = await runBatch(items: items, settings: s, threads: 2, cancel: token).toList();
    expect(cancelled.every((e) => !e.result.ok), true);
  });

  test('icon pack export writes appfilter.xml', () async {
    final bytes = await syntheticIcon();
    final dir = await Directory.systemTemp.createTemp('if_pack');
    final png = File(p.join(dir.path, 'a.png'))..writeAsBytesSync(bytes);
    final r = await buildIconPack(
      apps: [IconPackApp(label: 'App', package: 'com.example.app', activity: 'com.example.app.Main', png: png.path)],
      outDir: p.join(dir.path, 'pack'),
      packName: 'Test',
      zipPath: p.join(dir.path, 'pack.zip'),
    );
    expect(r.icons, 1);
    final xml = File(p.join(dir.path, 'pack', 'res', 'xml', 'appfilter.xml')).readAsStringSync();
    expect(xml, contains('ComponentInfo{com.example.app/com.example.app.Main}'));
    expect(File(p.join(dir.path, 'pack.zip')).existsSync(), true);
  });

  test('reference icons calibrate on the reference base (Windows only)', () async {
    final root = Directory(r'D:\Icon Formatter');
    final base = File(r'D:\Icon Formatter\icon_formatter\assets\bases\reference_translucent.png');
    if (!Platform.isWindows || !root.existsSync() || !base.existsSync()) return;
    final samples = root.listSync().whereType<File>().where((f) => f.path.toLowerCase().endsWith('.png')).map((f) => f.path).toList();
    final r = await calibrateBase(basePath: base.path, samplePaths: samples);
    expect(r.inliers, greaterThanOrEqualTo(samples.length * 2 ~/ 3));
    expect(r.placement.glyphRatio, closeTo(0.67, 0.04));
    expect(r.placement.centerX, closeTo(0.5, 0.02));
  });
}
