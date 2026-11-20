// Change background, on the device or emulator (Rust core inside):
//   flutter test integration_test/pack_plate_bench_test.dart -d emulator-5556
// 200 synthetic icons. The first pass segments and composes; a second plate
// on the same cut-out cache only composes (fast path); a third plate on an
// empty cache segments again (reference). The fast path must be faster and
// give the same bytes as the reference, and must differ from the first plate.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:icon_formatter/screens/pack/pb_model.dart';
import 'package:icon_formatter/src/rust/api/engine.dart';
import 'package:icon_formatter/src/rust/frb_generated.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;

import 'e2e_support.dart';

const int _n = 200;
const int _size = 192;

ProcessSettings _base(String cacheDir) => ProcessSettings(
  size: _size,
  background: BackgroundSettings.lucent(params: defaultLucentSettings(dark: false)),
  placement: defaultPlacementSettings(),
  segment: defaultSegmentSettings(),
  cutCacheDir: cacheDir,
);

/// One full pass over [srcs]: returns the time and the output bytes by item id.
Future<(Duration, Map<String, Uint8List>)> _pass(List<String> srcs, String outDir, ProcessSettings s) async {
  await Directory(outDir).create(recursive: true);
  final items = [
    for (var i = 0; i < srcs.length; i++)
      BatchItem(id: '$i', name: 'i$i', path: srcs[i], output: p.join(outDir, 'i$i.png'), skipIsolation: false),
  ];
  final sw = Stopwatch()..start();
  final events = await runBatch(items: items, settings: s, threads: 0, cancel: CancelToken()).toList();
  sw.stop();
  final bytes = <String, Uint8List>{};
  for (final e in events) {
    expect(e.result.ok, isTrue, reason: 'item ${e.result.id} failed');
    bytes[e.result.id] = File(e.result.output!).readAsBytesSync();
  }
  expect(bytes.length, srcs.length);
  return (sw.elapsed, bytes);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async => RustLib.init());

  testWidgets('plate change on the cut-out cache: fast, and equal to a fresh run', (tester) async {
    final root = await Directory.systemTemp.createTemp('if_plate_bench');
    final srcDir = p.join(root.path, 'src');
    await writeSyntheticIcons(srcDir, _n, size: 256);
    final srcs = Directory(srcDir).listSync().whereType<File>().map((f) => f.path).where((f) => f.endsWith('.png')).toList()..sort();
    expect(srcs.length, greaterThanOrEqualTo(_n));

    final cacheA = p.join(root.path, 'cacheA');
    final cacheB = p.join(root.path, 'cacheB');

    // 1. first generation (segments every icon)
    final (t1, out1) = await _pass(srcs, p.join(root.path, 'out1'), plateSettings(_base(cacheA), const PlateOverride(opacity: 0.4, mode: 'auto')));
    // 2. another plate on the same cache (fast path)
    final (t2, out2) = await _pass(srcs, p.join(root.path, 'out2'), plateSettings(_base(cacheA), const PlateOverride(opacity: 0.8, mode: 'dark')));
    // 3. the same plate as 2, fresh cache: reference output
    final (t3, out3) = await _pass(srcs, p.join(root.path, 'out3'), plateSettings(_base(cacheB), const PlateOverride(opacity: 0.8, mode: 'dark')));

    // ignore: avoid_print
    print('PLATE_BENCH n=${srcs.length} first=${t1.inMilliseconds}ms cached_plate=${t2.inMilliseconds}ms fresh_plate=${t3.inMilliseconds}ms');

    // no stale pixels: the new plate gives other bytes than the first one
    var changed = 0;
    for (final id in out1.keys) {
      if (!_same(out1[id]!, out2[id]!)) changed++;
    }
    expect(changed, greaterThan(0), reason: 'the plate change did not reach the output');

    // equality: the cached plate change equals a fresh generation
    for (final id in out2.keys) {
      expect(_same(out2[id]!, out3[id]!), isTrue, reason: 'icon $id differs from a fresh generation');
    }

    expect(t2 < t3, isTrue, reason: 'the cached plate change should be faster than a fresh generation');
    await root.delete(recursive: true);
  }, timeout: const Timeout(Duration(minutes: 20)));
}

bool _same(Uint8List a, Uint8List b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
