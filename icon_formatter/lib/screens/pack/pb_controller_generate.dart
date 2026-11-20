part of 'pb_controller.dart';

/// Generation, matching and hand edits.
extension PbControllerGenerate on PackBuilderController {
  /// The plate of the pack with [plate] applied: the alpha of the frosted
  /// backdrop and its colour. The segmentation is not touched, so the cut-outs
  /// in the cache are reused and only the composition runs again.
  ProcessSettings _withPlate(ProcessSettings s) => plateSettings(s, plate);

  /// Renders the originals with the current Studio settings (pack mode).
  Future<void> generateFromOriginals({List<PbRow>? only}) async {
    final st = AppState.I;
    // icons of a pack or of the Studio are finished: a bulk render leaves them
    // alone (a row is rendered again only when asked for it: "Rielabora")
    final finished = {
      for (final r in rows)
        if (r.generatedId?.startsWith('pk') ?? false) r.original.id,
    };
    final targets =
        only?.map((r) => r.original).toList() ??
        [
          for (final o in originals)
            if ((o.path != null || o.bytes != null) &&
                renderOnBulk(
                  originalId: o.id,
                  hasStudioIcon: _studioFor(o) != null,
                  rowFinished: finished.contains(o.id),
                ))
              o,
        ];
    if (targets.isEmpty) return;
    final byId = {for (final t in targets) t.id: t};
    final rowById = {for (final r in rows) r.original.id: r};
    final out = await AppPaths.I.outputSession('builder');
    final items = [
      for (final o in targets)
        BatchItem(
          id: o.id,
          name: o.title,
          path: o.path,
          bytes: o.path == null ? o.bytes : null,
          output: p.join(
            out,
            '${sanitizeDrawableName(name: o.package.isNotEmpty ? o.package : o.title)}_${o.id.hashCode.toUnsigned(32).toRadixString(16)}.png',
          ),
          // per-app choice: keep the white closed inside the symbol
          segment: st.packCorrections[o.key]?['keepWhite'] == true
              ? copySegment(st.packSegment, removeHoles: false)
              : null,
          skipIsolation: false,
        ),
    ];
    _set(S.pbGenerazione(0, items.length), prog: 0, running: true);
    _deferAppSaves = true;
    final cancel = CancelToken();
    _runCancel = cancel;
    var done = 0;
    var okCount = 0;
    try {
      await for (final ev in runBatch(
        items: items,
        settings: _withPlate(st.settingsFor(
          st.packMode,
          presetId: st.packPresetId,
          seg: st.packSegment,
        )),
        threads: st.threads,
        cancel: cancel,
      )) {
        done = ev.done;
        final r = ev.result;
        final o = byId[r.id];
        if (o != null && r.ok && r.output != null) {
          final gid = 'gen:${o.id}';
          okCount++;
          // a scan of the whole list per icon was quadratic over a 5000 batch
          if (_genById.containsKey(gid))
            generated.removeWhere((g) => g.id == gid);
          // same name/package as the original: the association is exact
          final g = PbIcon(
            id: gid,
            label: o.label,
            package: o.package,
            activity: o.activity,
            file: o.file.isNotEmpty ? o.file : p.basename(r.output!),
            path: r.output,
          );
          generated.add(g);
          _genById[gid] = g;
          // the new render is the reference for the change check of the system icon
          _changedKeys.remove(o.key);
          if (o.id.startsWith('app:')) unawaited(_rememberFingerprint(o));
          final row = rowById[o.id];
          if (row != null &&
              !row.custom &&
              (only != null || _studioFor(o) == null)) {
            row.generatedId = gid;
            row.baseGeneratedId = gid;
            row.auto = MatchState.confident;
            row.manual = false;
            row.changedOriginal = false;
            row.reason = S.pbRielaborata;
            _forgetChoice(row);
            _save(row);
          }
        }
        _set(
          S.pbGenerazione(done, ev.total),
          prog: ev.total == 0 ? null : done / ev.total,
          throttle: done < ev.total,
        );
      }
      if (okCount > 0)
        _log(
          only == null ? S.packLogCreate(okCount) : S.packLogRielabora(okCount),
        );
      if (only == null) await _redoCustom();
    } finally {
      _runCancel = null;
      _deferAppSaves = false;
      if (_appSavePending) {
        _appSavePending = false;
        AppState.I.update(() {});
      }
      _recount();
      _set(S.pbGenerateCaricate(generated.length), running: false);
      unawaited(st.pruneCutouts());
    }
    if (only == null) await match();
  }

  /// Name/package index first, visual comparison only where needed: the
  /// heavy work runs in Rust (rayon pool, cached signatures), off the UI.
  Future<void> match() async {
    if (originals.isEmpty) return;
    _set(S.pbAbbinamento, running: true);
    try {
      if (!_sigCacheSet) {
        _sigCacheSet = true;
        await setMatchCacheFile(
          path: p.join(AppPaths.I.root.path, 'match_signatures.bin'),
        );
      }
      final res = generated.isEmpty
          ? const <MatchOutput>[]
          : await matchIcons(
              originals: [for (final o in originals) o.toInput()],
              generated: [for (final g in generated) g.toInput()],
            );
      final byId = {for (final r in res) r.original: r};
      rows
        ..clear()
        ..addAll(originals.map(PbRow.new));
      final corr = AppState.I.packCorrections;
      // saved hand associations point at an app key: when several icons
      // share it, a Studio icon is the one meant
      final genByKey = <String, PbIcon>{};
      for (final g in generated) {
        if (g.id.startsWith('studio:')) {
          genByKey[g.key] = g;
        } else {
          genByKey.putIfAbsent(g.key, () => g);
        }
      }
      for (final row in rows) {
        final m = byId[row.original.id];
        if (m != null) {
          row.generatedId = m.generated;
          row.auto = m.state;
          row.reason = m.generated == null
              ? S.pbNessunaIcona
              : matchReasonText(m.reason);
        } else {
          row.reason = S.pbNessunaIcona;
        }
        // icons of an opened pack are finished: they count as confident
        final pkIcon = generatedById(row.generatedId);
        if (pkIcon != null &&
            pkIcon.id.startsWith('pk') &&
            pkIcon.package == row.original.package)
          row.auto = MatchState.confident;
        // saved corrections win over the automatic association
        final c = corr[row.original.key];
        if (c != null) {
          row.excluded = c['excluded'] == true;
          row.verified = c['verified'] == true;
          // saved by icon id now; an older save holds the app key (first icon of it)
          final gk = c['generated'] as String?;
          final pick = gk == null ? null : (_genById[gk] ?? genByKey[gk]);
          if (pick != null) {
            row.generatedId = pick.id;
            row.manual = true;
            row.reason = S.pbCorrezioneSalvata;
          }
        }
        // saved flag of an app added earlier: it stays "please check" until the user looks
        if (row.original.id.startsWith('app:')) {
          row.original.isFresh = corr[row.original.key]?['fresh'] == true;
        }
        _applyCustom(row);
        _applyStudio(row);
        // an added app never reuses a pack, Studio or saved icon: only its own render
        if (row.original.isFresh) {
          final own = generatedById('gen:${row.original.id}');
          row.generatedId = own?.id;
          row.manual = false;
          row.auto = own == null ? MatchState.missing : MatchState.confident;
          row.reason = own == null ? S.ux1bGenNotice : S.pbRielaborata;
        }
        row.changedOriginal = _changedKeys.contains(row.original.key);
        row.baseGeneratedId = row.generatedId;
        _linkVariant(row);
      }
      _recount();
      final n = rows
          .where(
            (r) => r.state == PbState.confident || r.state == PbState.verified,
          )
          .length;
      _set(S.pbRisultatoAbbinamento(n, rows.length), running: false);
    } catch (e) {
      _set(S.errore(e), running: false);
    }
  }

  /// The Studio icon made for [o]: same component, else same package, else
  /// a file name that spells the package. The newest one wins.
  PbIcon? _studioFor(PbIcon o, {Iterable<PbIcon>? among}) {
    if (o.package.isEmpty) return null;
    PbIcon? byComp, byPkg;
    for (final g in among ?? generated) {
      if (!g.id.startsWith('studio:') || g.path == null) continue;
      final pkg = g.package.isNotEmpty ? g.package : null;
      if (pkg == o.package) {
        if (g.activity.isNotEmpty && g.activity == o.activity) byComp = g;
        if (g.activity.isEmpty || g.activity == o.activity) byPkg = g;
      } else if (pkg == null &&
          PackBuilderController._norm(p.basenameWithoutExtension(g.file)) ==
              PackBuilderController._norm(o.package)) {
        byPkg = g;
      }
    }
    return byComp ?? byPkg;
  }

  /// Studio icons come before anything matched or regenerated here; only a
  /// later hand association or hand-made icon in the Pack goes above them.
  bool _applyStudio(PbRow row) {
    if (row.manual || row.custom) return false;
    final g = _studioFor(row.original);
    if (g == null) return false;
    row.generatedId = g.id;
    row.auto = MatchState.confident;
    row.reason = S.pbDaStudio;
    return true;
  }

  /// Hand-made icons follow the pack style too: each one is rendered again
  /// from its own source image with its own treatment, on the current
  /// background/plate ("Use as is" icons stay untouched).
  Future<void> _redoCustom() async {
    for (final e in custom.entries.toList()) {
      final src = e.value['src'];
      final t = EditTreatment.values
          .where((v) => v.name == e.value['treatment'])
          .firstOrNull;
      final path = e.value['path'];
      if (src == null ||
          t == null ||
          t == EditTreatment.raw ||
          path == null ||
          !File(src).existsSync())
        continue;
      try {
        final png = await renderEdit(src, t);
        await File(path).writeAsBytes(png, flush: true);
        ImageStamps.bump(path);
      } catch (_) {
        // the previous file stays
      }
    }
  }

  /// A hand-made icon replaces whatever the matcher chose.
  void _applyCustom(PbRow row) {
    final c = custom[row.original.key];
    if (c == null) return;
    final id = 'custom:${row.original.key}';
    var g = _genById[id];
    if (g == null) {
      g = PbIcon(
        id: id,
        label: row.original.label,
        package: row.original.package,
        activity: row.original.activity,
        file: p.basename(c['path']!),
        path: c['path'],
      );
      generated.add(g);
      _genById[id] = g;
    }
    row.generatedId = id;
    row.custom = true;
    row.reason = S.pbIconaPersonalizzata;
  }

  void _save(PbRow row) {
    final g = generatedById(row.generatedId);
    // keeps the other saved fields (label, aliases, variants, keepWhite)
    final old = AppState.I.packCorrections[row.original.key] ?? {};
    void apply() => AppState.I.packCorrections[row.original.key] = {
      ...old,
      // ids of an opened pack change at each opening: its app key is saved instead
      'generated': row.manual && g != null
          ? (g.id.startsWith('pk') ? g.key : g.id)
          : null,
      'excluded': row.excluded,
      'verified': row.verified,
    };
    // a batch saves per icon: one app-wide rebuild and one disk save at the end
    if (_deferAppSaves) {
      apply();
      _appSavePending = true;
    } else {
      AppState.I.update(apply);
    }
  }

  void assign(PbRow row, PbIcon g) {
    row.generatedId = g.id;
    row.baseGeneratedId = g.id;
    row.manual = true;
    row.reason = S.pbAssegnataManualmente;
    _forgetChoice(row);
    _save(row);
    _recount();
    notifyListeners();
  }

  /// Per app: keep the white areas closed inside the symbol (Calendar's
  /// page) instead of removing them as background. Regenerates that icon.
  bool keepsInnerWhite(PbRow row) =>
      AppState.I.packCorrections[row.original.key]?['keepWhite'] == true;

  Future<void> setKeepInnerWhite(PbRow row, bool keep) async {
    final c = Map<String, dynamic>.from(
      AppState.I.packCorrections[row.original.key] ?? {},
    );
    if (keep) {
      c['keepWhite'] = true;
    } else {
      c.remove('keepWhite');
    }
    AppState.I.update(() => AppState.I.packCorrections[row.original.key] = c);
    notifyListeners();
    await generateFromOriginals(only: [row]);
  }

  void setExcluded(PbRow row, bool v) {
    row.excluded = v;
    _linkVariant(row);
    _save(row);
    _recount();
    notifyListeners();
  }

  void setVerified(PbRow row, bool v) {
    row.verified = v;
    // a verified icon is accepted as it is now: its fingerprint is the new reference
    if (v && row.changedOriginal) _acceptOriginal(row);
    _save(row);
    notifyListeners();
  }

  void _acceptOriginal(PbRow row) {
    row.changedOriginal = false;
    _changedKeys.remove(row.original.key);
    unawaited(_rememberFingerprint(row.original));
  }

  /// Settings of the pack mode with the per-icon treatment applied.
  ProcessSettings editSettings(EditTreatment t, {int? size}) {
    final st = AppState.I;
    final s = st.settingsFor(
      st.packMode,
      presetId: st.packPresetId,
      seg: st.packSegment,
    );
    final strategy = switch (t) {
      EditTreatment.plateColor => LucentStrategy.plateColor,
      EditTreatment.fullBleed => LucentStrategy.fullBleed,
      EditTreatment.asIs => LucentStrategy.asIs,
      // the image as it is: only size and position on the plate, nothing
      // cut out, colours untouched (a full tile covers the plate edge)
      EditTreatment.placeOnly => LucentStrategy.tile,
      _ => LucentStrategy.auto,
    };
    var bg = s.background;
    if (bg is BackgroundSettings_Lucent) {
      final l = bg.params;
      bg = BackgroundSettings.lucent(
        params: LucentSettings(
          ink: l.ink,
          backdrop: l.backdrop,
          shape: l.shape,
          monochrome: l.monochrome,
          keepComposition: l.keepComposition,
          glyphScale: l.glyphScale,
          rim: l.rim,
          launcherShadow: l.launcherShadow,
          launcherEncode: l.launcherEncode,
          strategy: strategy,
        ),
      );
    }
    return ProcessSettings(
      size: size ?? s.size,
      background: bg,
      placement: s.placement,
      segment: s.segment,
      ai: s.ai,
      effects: AppState.I.look.effects,
      cutCacheDir: s.cutCacheDir,
    );
  }

  Future<Uint8List> renderEdit(String source, EditTreatment t) {
    _lastEdit = (source, t);
    return _renderEditAt(source, t, null);
  }

  /// Small render of [t] (about [size] px) for the treatment picker: the same
  /// engine path as [renderEdit], kept apart from the big preview's state.
  Future<Uint8List> renderEditThumb(String source, EditTreatment t, int size) {
    // "Originale" is the source itself: no engine call needed
    if (t == EditTreatment.raw) return File(source).readAsBytes();
    return _renderEditAt(source, t, size);
  }

  Future<Uint8List> _renderEditAt(
    String source,
    EditTreatment t,
    int? size,
  ) async {
    if (t == EditTreatment.raw) {
      final dest = p.join(await AppPaths.I.workDir('edit'), 'raw.png');
      await importAsPng(src: source, dest: dest);
      return File(dest).readAsBytes();
    }
    if (t == EditTreatment.placeOnly) {
      // own file per size: a thumbnail and the big preview may run at once
      final dest = p.join(
        await AppPaths.I.workDir('edit'),
        'place${size ?? ''}.png',
      );
      await importAsPng(src: source, dest: dest);
      return composeGlyphPng(
        glyphPng: await File(dest).readAsBytes(),
        settings: editSettings(t, size: size),
      );
    }
    final r = await previewFile(
      path: source,
      settings: editSettings(t, size: size),
    );
    return r.png;
  }

  /// Confirms a hand-made icon for [row]: stored in the app folder, linked
  /// to the app's package/activity and used by every export and by the pack
  /// applied on the phone. The previous choice is kept for "Ripristina".
  Future<void> applyEdit(PbRow row, Uint8List png) async {
    await Directory(_customDir).create(recursive: true);
    final name =
        '${sanitizeDrawableName(name: row.original.package.isNotEmpty ? row.original.package : row.original.title)}_${DateTime.now().millisecondsSinceEpoch}.png';
    final path = p.join(_customDir, name);
    await File(path).writeAsBytes(png, flush: true);
    final old = custom[row.original.key];
    final prev = old != null
        ? old['prev']
        : (row.custom ? null : generatedById(row.generatedId)?.id);
    // an older hand-made file of the same app is replaced
    if (old?['path'] != null) {
      try {
        await File(old!['path']!).delete();
      } catch (_) {}
    }
    // the source image and treatment, to redo this icon when the pack's
    // background/plate settings change (the user's choice stays)
    String? src;
    final le = _lastEdit;
    if (le != null && File(le.$1).existsSync()) {
      src = p.join(
        _customDir,
        '${p.basenameWithoutExtension(name)}_src${p.extension(le.$1)}',
      );
      await File(le.$1).copy(src);
    }
    if (old?['src'] != null) {
      try {
        await File(old!['src']!).delete();
      } catch (_) {}
    }
    custom[row.original.key] = {
      'path': path,
      'prev': prev,
      if (src != null) 'src': src,
      if (le != null) 'treatment': le.$2.name,
    };
    final id = 'custom:${row.original.key}';
    generated.removeWhere((g) => g.id == id);
    _genById.remove(id);
    row.variant = false;
    _applyCustom(row);
    row.baseGeneratedId = row.generatedId;
    _recount();
    status = S.pbIconaAggiornata(row.original.title);
    notifyListeners();
  }

  bool hasCustom(PbRow row) => custom.containsKey(row.original.key);

  /// Back to the icon used before "Edit icon".
  Future<void> restoreEdit(PbRow row) async {
    final c = custom.remove(row.original.key);
    if (c == null) return;
    final id = 'custom:${row.original.key}';
    generated.removeWhere((g) => g.id == id);
    _genById.remove(id);
    try {
      await File(c['path']!).delete();
    } catch (_) {}
    row.custom = false;
    final prev = generatedById(c['prev']);
    row.baseGeneratedId = prev?.id;
    _linkVariant(row);
    _recount();
    row.reason = prev == null ? S.pbNessunaIcona : S.pbRipristinata;
    status = S.pbIconaRipristinata(row.original.title);
    notifyListeners();
  }

  /// Builds the pack folder (drawables, appfilter.xml, mapping.json).
  Future<String?> _buildPackDir(String name) async {
    final ok = rows.where((r) => !r.excluded && r.generatedId != null).toList();
    if (ok.isEmpty) return null;
    final dir = await AppPaths.I.workDir('iconpack');
    final apps = [...await _packEntries(ok), ..._calendarApps];
    final res = await buildIconPack(
      apps: apps,
      outDir: dir,
      packName: name,
      zipPath: null,
    );
    return res.outDir;
  }

  /// Pack entries of [ok]: each icon under its own app and under the apps it
  /// is aliased to (an alias replaces that app's own entry). Label = pack name.
  Future<List<IconPackApp>> _packEntries(List<PbRow> ok) async {
    final byKey = {for (final r in rows) r.original.key: r};
    final pngByKey = <String, String>{};
    final keyed = <(String, IconPackApp)>[];
    for (final r in ok) {
      final g = generatedById(r.generatedId)!;
      final png = pngByKey[r.original.key] = g.path ?? await _materialize(g);
      keyed.add((
        PackBuilderController._compKey(r.original),
        IconPackApp(
          label: nameOf(r),
          package: r.original.package,
          activity: r.original.activity,
          png: png,
        ),
      ));
    }
    for (final r in ok) {
      for (final k in aliasesOf(r)) {
        final t = byKey[k];
        if (t == null || t.excluded || t.original.package.isEmpty) continue;
        keyed.add((
          PackBuilderController._compKey(t.original),
          IconPackApp(
            label: nameOf(t),
            package: t.original.package,
            activity: t.original.activity,
            png: pngByKey[r.original.key]!,
          ),
        ));
      }
    }
    return pack2LastWins(keyed);
  }

  /// Entries the pack will hold (each icon's own app and its aliases), as
  /// findConflicts reads them, with the row each entry belongs to.
  ({List<PackEntryInfo> entries, List<PbRow> owners}) conflictInput() {
    final ok = rows
        .where((r) => !r.excluded && generatedById(r.generatedId) != null)
        .toList();
    final byKey = {for (final r in rows) r.original.key: r};
    final entries = <PackEntryInfo>[];
    final owners = <PbRow>[];
    PackEntryInfo entryOf(PbRow t) => packEntryFor(
      package: t.original.package,
      activity: t.original.activity,
      label: nameOf(t),
      drawableOf: (k) => sanitizeDrawableName(name: k),
    );
    for (final r in ok) {
      entries.add(entryOf(r));
      owners.add(r);
    }
    for (final r in ok) {
      for (final k in aliasesOf(r)) {
        final t = byKey[k];
        if (t == null || t.excluded || t.original.package.isEmpty) continue;
        entries.add(entryOf(t));
        owners.add(t);
      }
    }
    return (entries: entries, owners: owners);
  }

  /// Icons of another pack (its appfilter links them to apps) matched to the
  /// rows without an icon. Nothing changes until [applyMatches].
  Future<List<PbMatch>> matchFromPack(String path) async {
    _set(S.pbLettura, running: true);
    try {
      final (src, _, _) = await _readSource(
        path,
        'im${DateTime.now().millisecondsSinceEpoch}_',
      );
      final open = [
        for (final r in rows)
          if (r.generatedId == null &&
              !r.excluded &&
              r.original.package.isNotEmpty)
            r,
      ];
      final byPkg = <String, PbRow>{};
      for (final r in open) {
        byPkg.putIfAbsent(r.original.package, () => r);
      }
      final installed = [
        for (final r in byPkg.values)
          InstalledAppInfo(
            package: r.original.package,
            label: nameOf(r),
            activity: r.original.activity,
          ),
      ];
      final entries = mappingSourceEntries([
        for (final g in src)
          (
            package: g.package,
            activity: g.activity,
            drawable: p.basenameWithoutExtension(g.file),
          ),
      ]);
      final icons = {
        for (final g in src)
          if (g.package.isNotEmpty)
            p.basenameWithoutExtension(g.file).toLowerCase(): g,
      };
      final mapped = importMappingsDetailed(
        source: entries,
        installed: installed,
      );
      _set(null, running: false);
      return [
        for (final e in mapped.entries)
          if (byPkg[e.key] != null && icons[e.value.drawable] != null)
            PbMatch(
              row: byPkg[e.key]!,
              icon: icons[e.value.drawable]!,
              match: e.value.match,
            ),
      ];
    } catch (e) {
      _set(S.errore(e), running: false);
      rethrow;
    }
  }

  /// Assigns the matched icons, copied next to the app data first. Rows that
  /// got an icon meanwhile are skipped. Returns how many were assigned.
  Future<int> applyMatches(List<PbMatch> matches) async {
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final dir = Directory(
      p.join(AppPaths.I.root.path, 'pack_imported', '$stamp'),
    );
    await dir.create(recursive: true);
    var n = 0;
    for (final m in matches) {
      final src = m.icon.path;
      if (m.row.generatedId != null || src == null) continue;
      final dest = p.join(dir.path, 'icon_$n.png');
      await File(src).copy(dest);
      final g = PbIcon(
        id: 'im${stamp}_$n',
        label: m.icon.label,
        package: m.icon.package,
        activity: m.icon.activity,
        file: m.icon.file,
        path: dest,
      );
      generated.add(g);
      _reindex();
      assign(m.row, g);
      n++;
    }
    return n;
  }
}
