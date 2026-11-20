part of 'pb_controller.dart';

/// Corrections, variants, profiles and quality checks.
extension PbControllerCorrections on PackBuilderController {
  Map<String, dynamic> _corrOf(PbRow r) => Map<String, dynamic>.from(AppState.I.packCorrections[r.original.key] ?? {});

  /// Stores the corrections of [r]; an empty map removes the entry.
  void _putCorr(PbRow r, Map<String, dynamic> m) {
    final key = r.original.key;
    AppState.I.update(() {
      if (m.isEmpty) {
        AppState.I.packCorrections.remove(key);
      } else {
        AppState.I.packCorrections[key] = m;
      }
    });
  }

  /// Keys of the apps that also get this icon ("Use for other apps").
  List<String> aliasesOf(PbRow r) => ((AppState.I.packCorrections[r.original.key]?['alias'] as List?) ?? const []).cast<String>();

  void setAliases(PbRow r, List<String> keys) {
    final m = _corrOf(r);
    if (keys.isEmpty) {
      m.remove('alias');
    } else {
      m['alias'] = keys;
    }
    _putCorr(r, m);
    notifyListeners();
  }

  /// "Name in the pack": empty or the original title removes the label.
  void setLabel(PbRow r, String label) {
    final m = _corrOf(r);
    final t = label.trim();
    if (t.isEmpty || t == r.original.title) {
      m.remove('label');
    } else {
      m['label'] = t;
    }
    _putCorr(r, m);
    notifyListeners();
  }

  /// Extra icon files of an app, besides its generated one (at most two).
  List<String> variantPaths(PbRow r) => ((AppState.I.packCorrections[r.original.key]?['variants'] as List?) ?? const []).cast<String>();

  /// The variant file in use, or null for the generated icon.
  String? chosenVariant(PbRow r) => AppState.I.packCorrections[r.original.key]?['variant'] as String?;

  /// False when the app already has two extra icons or this one is listed.
  bool addVariant(PbRow r, String path) {
    final list = variantPaths(r);
    if (list.length >= 2 || list.contains(path)) return false;
    final m = _corrOf(r)..['variants'] = [...list, path];
    _putCorr(r, m);
    notifyListeners();
    return true;
  }

  /// Removes an extra icon; if it was the one in use, the generated icon returns.
  void removeVariant(PbRow r, String path) {
    final m = _corrOf(r);
    final list = [...variantPaths(r)]..remove(path);
    if (list.isEmpty) {
      m.remove('variants');
    } else {
      m['variants'] = list;
    }
    if (m['variant'] == path) m.remove('variant');
    _putCorr(r, m);
    _linkVariant(r);
    _recount();
    notifyListeners();
  }

  /// Uses the variant file [path] for [r]; null goes back to the generated icon.
  void chooseVariant(PbRow r, String? path) {
    final m = _corrOf(r);
    if (path == null) {
      m.remove('variant');
    } else {
      m['variant'] = path;
    }
    _putCorr(r, m);
    _linkVariant(r);
    _recount();
    notifyListeners();
  }

  /// A new icon replaced the variant in use: the choice is forgotten.
  void _forgetChoice(PbRow row) {
    row.variant = false;
    final m = _corrOf(row);
    if (m.remove('variant') != null) _putCorr(row, m);
  }

  /// Points [row] at its chosen variant file, else back at its base icon.
  void _linkVariant(PbRow row) {
    final v = chosenVariant(row);
    row.variant = false;
    row.generatedId = row.baseGeneratedId;
    if (v == null || row.custom || row.excluded || !File(v).existsSync()) return;
    final o = row.original;
    final id = 'var:${o.key}|$v';
    var g = _genById[id];
    if (g == null) {
      g = PbIcon(id: id, label: o.label, package: o.package, activity: o.activity, file: p.basename(v), path: v);
      generated.add(g);
      _genById[id] = g;
    }
    row.generatedId = id;
    row.variant = true;
    row.reason = S.pack2VarianteScelta;
  }

  /// Contact sheets of the generated icons (96 per sheet, 400 at most), written
  /// to one folder. Each icon is read only when its sheet is drawn.
  Future<List<String>> contactSheetFiles() async {
    final todo = [for (final r in rows) if (!r.excluded && generatedById(r.generatedId)?.path != null) r];
    final n = todo.length < contactSheetMaxIcons ? todo.length : contactSheetMaxIcons;
    if (n == 0 || busy) return const [];
    final out = await AppPaths.I.workDir('sheetout');
    final files = <String>[];
    _set(S.pack2AnteprimaProgresso(0, n), prog: 0, running: true);
    try {
      // the folder only holds the sheets of this run
      await for (final e in Directory(out).list()) {
        if (e is File) await e.delete();
      }
      var start = 0;
      for (final count in contactSheetPages(n)) {
        final icons = <({String name, Uint8List png})>[];
        for (final r in todo.sublist(start, start + count)) {
          try {
            icons.add((name: nameOf(r), png: await File(generatedById(r.generatedId)!.path!).readAsBytes()));
          } catch (_) {
            // a missing icon file is left off the sheet
          }
        }
        start += count;
        // the export draws one sheet into its cache folder; copy it out
        final tmp = await ExportService.exportContactSheet(icons);
        if (tmp != null) {
          final dest = p.join(out, 'IconFormatter-anteprima_${files.length + 1}.png');
          await File(tmp).copy(dest);
          files.add(dest);
        }
        _set(S.pack2AnteprimaProgresso(start, n), prog: start / n, running: true, throttle: true);
      }
    } finally {
      _set(null, running: false);
    }
    return files;
  }

  /// Keeps the fingerprint of an installed app's icon as the reference.
  Future<void> _rememberFingerprint(PbIcon o) async {
    final path = o.path;
    if (path == null) return;
    try {
      // hashing every byte in Dart: done off the UI isolate
      final fp = await Isolate.run(() => pack2Fingerprint(File(path).readAsBytesSync()));
      if (_deferAppSaves) {
        AppState.I.packFingerprints[o.key] = fp;
        _appSavePending = true;
      } else {
        AppState.I.update(() => AppState.I.packFingerprints[o.key] = fp);
      }
    } catch (_) {
      // an unreadable icon keeps its old reference
    }
  }

  /// Compares each installed app's icon with the reference kept at its last
  /// generation; changed rows become "review". One icon per step, with a yield
  /// in between, so the first frame is never held up.
  Future<void> checkChangedOriginals() async {
    if (_checkingOriginals) return;
    final fps = AppState.I.packFingerprints;
    final todo = [for (final r in rows) if (isInstalled(r) && r.original.path != null && fps.containsKey(r.original.key)) r.original];
    if (todo.isEmpty) return;
    _checkingOriginals = true;
    final before = Set<String>.of(_changedKeys);
    try {
      for (final o in todo) {
        try {
          final now = pack2Fingerprint(await File(o.path!).readAsBytes());
          if (pack2FingerprintChanged(fps[o.key], now)) {
            _changedKeys.add(o.key);
          } else {
            _changedKeys.remove(o.key);
          }
        } catch (_) {
          // unreadable: no verdict for this app
        }
        await Future<void>.delayed(Duration.zero);
      }
    } finally {
      _checkingOriginals = false;
    }
    for (final r in rows) {
      r.changedOriginal = _changedKeys.contains(r.original.key);
    }
    if (before.length != _changedKeys.length || !before.every(_changedKeys.contains)) notifyListeners();
  }

  bool hasSource(PbRow r) => r.original.path != null || r.original.bytes != null;

  /// Missing rows that have an original to render from.
  List<PbRow> get _missingWithSource => [for (final r in rows) if (r.state == PbState.missing && hasSource(r)) r];

  int get missingCount => _missingWithSource.length;

  /// Generates only the rows without an icon, from their originals.
  Future<void> generateMissing() async {
    final todo = _missingWithSource;
    if (todo.isEmpty) return;
    await generateFromOriginals(only: todo);
  }

  /// Pixel checks on every generated icon; only the icons with problems.
  Future<List<(PbRow, List<PbProblem>)>> scanQuality() async {
    final todo = [for (final r in rows) if (!r.excluded && generatedById(r.generatedId)?.path != null) r];
    final out = <(PbRow, List<PbProblem>)>[];
    if (todo.isEmpty) return out;
    _set(S.packQualitaScan(0, todo.length), prog: 0, running: true);
    try {
      for (var i = 0; i < todo.length; i++) {
        try {
          final png = await File(generatedById(todo[i].generatedId)!.path!).readAsBytes();
          final img = await packDecodeRgba(png);
          final probs = packCheckPixels(img.rgba, img.width, img.height);
          if (probs.isNotEmpty) out.add((todo[i], probs));
        } catch (_) {
          // an unreadable icon is skipped
        }
        _set(S.packQualitaScan(i + 1, todo.length), prog: (i + 1) / todo.length, running: true, throttle: true);
      }
    } finally {
      _set(null, running: false);
    }
    return out;
  }

  /// Newest first, the last 30 lines (release notes).
  void _log(String text) {
    final st = AppState.I;
    st.update(() {
      st.packLog.insert(0, {'date': DateTime.now().toIso8601String(), 'text': text});
      if (st.packLog.length > 30) st.packLog.removeRange(30, st.packLog.length);
    });
  }

  /// Changes when the icon is rendered again or hand-edited.
  String _sig(PbRow r) => generatedById(r.generatedId)?.path ?? '';

  /// Changed since the last export; with no export yet, the hand-made ones.
  bool _changedSince(PbRow r) {
    final snap = AppState.I.packExportSnapshot;
    if (snap == null) return r.custom || r.manual;
    return snap[r.original.key] != _sig(r);
  }

  /// False until the first export: "Changed only" then means hand edits.
  bool get hasExportBaseline => AppState.I.packExportSnapshot != null;

  /// Saves the current corrections under [name] (same name replaces it).
  void saveProfile(String name) {
    final st = AppState.I;
    final copy = PackBuilderController._copyCorrections(st.packCorrections);
    st.update(() {
      st.packProfiles.removeWhere((e) => e['name'] == name);
      st.packProfiles.insert(0, {'name': name, 'date': DateTime.now().toIso8601String(), 'corrections': copy});
    });
  }

  /// Replaces the current corrections with a saved set, then matches again.
  Future<void> loadProfile(Map<String, dynamic> profile) async {
    final st = AppState.I;
    final corr = PackBuilderController._copyCorrections((profile['corrections'] as Map?) ?? {});
    st.update(() => st.packCorrections = corr);
    _log(S.packLogProfilo(profile['name'] as String));
    await match();
  }

  void deleteProfile(String name) => AppState.I.update(() => AppState.I.packProfiles.removeWhere((e) => e['name'] == name));

  Future<String> _materialize(PbIcon g) async {
    final f = File(p.join(await AppPaths.I.workDir('pbmem'), '${g.id.replaceAll(':', '_')}.png'));
    await f.writeAsBytes(g.bytes!);
    g.path = f.path;
    return f.path;
  }
}
