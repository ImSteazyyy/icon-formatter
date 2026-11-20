part of '../state.dart';

/// Base icons used for calibration and the reference base.
extension AppStateBases on AppState {
  BaseIcon? get selectedBase {
    for (final b in bases) {
      if (b.id == selectedBaseId) return b;
    }
    return bases.isEmpty ? null : bases.first;
  }

  Future<BaseIcon> importBase(String src, String name) async {
    final id = 'b${DateTime.now().microsecondsSinceEpoch}';
    final dest = p.join(AppPaths.I.bases, '$id.png');
    final dims = await importAsPng(src: src, dest: dest);
    final b = BaseIcon(id: id, name: name, path: dest, width: dims[0], height: dims[1]);
    update(() {
      bases.add(b);
      selectedBaseId = id;
    });
    return b;
  }

  /// Saves a rendered background (e.g. the current translucent preset) as base.
  Future<BaseIcon> addBaseFromPng(Uint8List png, String name, int size) async {
    final id = 'b${DateTime.now().microsecondsSinceEpoch}';
    final dest = p.join(AppPaths.I.bases, '$id.png');
    await File(dest).writeAsBytes(png);
    final b = BaseIcon(id: id, name: name, path: dest, width: size, height: size);
    update(() {
      bases.add(b);
      selectedBaseId = id;
    });
    return b;
  }

  void renameBase(BaseIcon b, String name) => update(() => b.name = name);

  Future<void> deleteBase(BaseIcon b) async {
    update(() {
      bases.remove(b);
      if (selectedBaseId == b.id) selectedBaseId = bases.isEmpty ? null : bases.first.id;
    });
    final f = File(b.path);
    if (await f.exists()) await f.delete();
  }

  void saveCalibration(BaseIcon b, PlacementSettings pl, Map<String, dynamic> info) => update(() {
        b.calibration = pl;
        b.calibrationInfo = info;
      });

  /// Built-in bases, drawn by the app (tool/make_bases.py): a squircle and a
  /// circle plate with the reference proportions and calibration. The old
  /// "reference" base is replaced by the squircle.
  Future<void> _ensureReferenceBase() async {
    final cal = jsonDecode(await rootBundle.loadString('assets/bases/reference_calibration.json')) as Map<String, dynamic>;
    final squircleCal = placementFromJson((cal['placement'] as Map).cast(), defaultPlacement);
    var changed = false;
    for (final (id, asset, glyph) in const [('squircle', 'assets/bases/squircle.png', 0.0), ('circle', 'assets/bases/circle.png', 0.62)]) {
      final dest = p.join(AppPaths.I.bases, '$id.png');
      if (bases.any((b) => b.id == id) && File(dest).existsSync()) continue;
      final data = await rootBundle.load(asset);
      await File(dest).writeAsBytes(data.buffer.asUint8List());
      bases.removeWhere((b) => b.id == id);
      bases.insert(
        id == 'squircle' ? 0 : 1,
        BaseIcon(
          id: id,
          name: id,
          path: dest,
          width: 192,
          height: 192,
          // the circle keeps the squircle's centre with a smaller symbol, so
          // square glyphs stay inside the round plate
          calibration: glyph > 0 ? copyPlacement(squircleCal, glyphRatio: glyph, areaRatio: glyph * glyph * 1.4) : squircleCal,
          calibrationInfo: (cal['info'] as Map).cast(),
        ),
      );
      changed = true;
    }
    if (bases.any((b) => b.id == 'reference')) {
      bases.removeWhere((b) => b.id == 'reference');
      if (selectedBaseId == 'reference') selectedBaseId = 'squircle';
      changed = true;
    }
    if (selectedBaseId == null || !bases.any((b) => b.id == selectedBaseId)) {
      selectedBaseId = 'squircle';
      changed = true;
    }
    if (changed) await save();
  }
}
