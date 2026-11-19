import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icon_formatter/app/state.dart';
import 'package:icon_formatter/app/storage.dart';
import 'package:icon_formatter/src/rust/api/engine.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('plugins.flutter.io/path_provider');

  test('cutout settings survive a save and a restore; old files keep the defaults', () async {
    final tmp = await Directory.systemTemp.createTemp('ritagli_test');
    addTearDown(() => tmp.delete(recursive: true));
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async => tmp.path);
    addTearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null));
    await AppPaths.init();

    final st = AppState.I;
    // save() reads these; load() would need the Rust library, which tests do not load
    st.segment = st.defaultSegment = st.packSegment = SegmentSettings(mode: SegMode.auto, tolerance: 0.1, removeHoles: true, refineEdges: true);
    st.keepCutouts = false;
    st.cutoutLimitMb = 123;
    await st.save();
    final saved = jsonDecode(await File(AppPaths.I.stateFile).readAsString()) as Map<String, dynamic>;
    expect(saved['keepCutouts'], false);
    expect(saved['cutoutLimitMb'], 123);

    st.keepCutouts = true;
    st.cutoutLimitMb = 500;
    await st.restoreBackup(jsonEncode(saved));
    expect(st.keepCutouts, false);
    expect(st.cutoutLimitMb, 123);
    expect(st.cutCacheDir, isNull, reason: 'off: no folder is passed to Rust');

    st.keepCutouts = true;
    expect(st.cutCacheDir, AppPaths.I.cutouts);

    // a state file written before the feature has neither key: values stay
    final old = Map<String, dynamic>.from(saved)
      ..remove('keepCutouts')
      ..remove('cutoutLimitMb');
    st.cutoutLimitMb = 77;
    await st.restoreBackup(jsonEncode(old));
    expect(st.keepCutouts, true);
    expect(st.cutoutLimitMb, 77);
  });
}
