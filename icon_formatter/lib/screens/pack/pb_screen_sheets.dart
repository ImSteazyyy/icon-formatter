part of 'pb_screen.dart';

extension _PbScreenSheets on _PackBuilderScreenState {
  /// "Apri un pack": the one installed on this phone, or an APK/ZIP file.
  Future<void> _openPack(Rect anchor) async {
    final installed = Platform.isAndroid ? await PlatformService.devicePackSource() : null;
    if (!mounted) return;
    final v = await showGlassMenu<String>(
      context,
      anchor: anchor,
      title: S.pbApriPack,
      items: [
        if (installed != null) GlassMenuItem(value: 'installed', label: S.pbPackInstallato, subtitle: S.pbPackInstallatoSub, icon: Icons.phone_android_rounded),
        GlassMenuItem(value: 'file', label: S.pbPackDaFile, subtitle: S.pbPackDaFileSub, icon: Icons.folder_zip_outlined),
        GlassMenuItem(value: 'mappings', label: S.pack3ImportaAbbinamenti, subtitle: S.pack3ImportaSub, icon: Icons.compare_arrows_rounded),
      ],
    );
    if (v == 'mappings') {
      await _importMappings();
      return;
    }
    String? path;
    if (v == 'installed') {
      path = installed;
    } else if (v == 'file') {
      final r = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['apk', 'zip']);
      path = r?.files.single.path;
    }
    if (path == null) return;
    final n = await c.openExistingPack(path);
    if (mounted && n > 0) showMsg(context, S.pbPackAperto(n));
  }

  /// "Home screen preview": the generated icons on a mock launcher.
  Future<void> _homePreview() async {
    await showAppSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => HomePreview(
        apps: [
          for (final r in c.rows)
            if (!r.excluded && c.generatedById(r.generatedId) != null) (c.nameOf(r), c.generatedById(r.generatedId)!.image(size: 56)),
        ],
      ),
    );
  }

  /// "Export preview": contact sheets of the icons, shared (Android).
  Future<void> _contactSheet() async {
    final files = await c.contactSheetFiles();
    if (!mounted) return;
    if (files.isEmpty) {
      showMsg(context, S.pack2AnteprimaVuota);
      return;
    }
    await ExportService.share(files, text: S.pack2AnteprimaTitolo);
  }

  /// Before/after with a draggable divider, from the details dialog.
  Future<void> _compare(PbRow r, PbIcon g) => showAppDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(S.confrontoTitolo),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // the comparison needs a bounded height: the Stack fills it
          SizedBox(height: 240, child: BeforeAfter(before: r.original.image(size: 240), after: g.image(size: 240))),
          const SizedBox(height: 10),
          Text(S.confrontoSuggerimento, textAlign: TextAlign.center, style: TextStyle(fontSize: 12.5, color: Palette.text3)),
        ],
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: Text(S.chiudi))],
    ),
  );

  /// "Esporta": folder or ZIP, asked when the button is tapped.
  Future<void> _exportChoose() async {
    final choice = await showAppSheet<({bool zip, bool changed})>(
      context: context,
      builder: (ctx) => SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(contentPadding: const EdgeInsets.symmetric(horizontal: 22), leading: const Icon(Icons.drive_folder_upload_outlined), title: Text(S.esportaCartella), onTap: () => Navigator.pop(ctx, (zip: false, changed: false))),
            ListTile(contentPadding: const EdgeInsets.symmetric(horizontal: 22), leading: const Icon(Icons.folder_zip_outlined), title: Text(S.pbEsportaZip), onTap: () => Navigator.pop(ctx, (zip: true, changed: false))),
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 22),
              leading: const Icon(Icons.difference_outlined),
              title: Text(S.packEsportaModificate),
              subtitle: Text(c.hasExportBaseline ? S.packEsportaModificateSub : S.packEsportaPrimaSub, style: TextStyle(fontSize: 12, color: Palette.text3)),
              onTap: () => Navigator.pop(ctx, (zip: false, changed: true)),
            ),
          ],
        ),
      ),
    );
    if (choice != null) await _export(choice.zip, changed: choice.changed);
  }

  Future<void> _export(bool zip, {bool changed = false}) async {
    try {
      final r = await c.export(zip: zip, onlyChanged: changed);
      if (mounted) showMsg(context, r?.message ?? (changed ? S.packNessunaModificata : S.pbNienteDaEsportare));
    } catch (e) {
      if (mounted) showMsg(context, S.errore(e), error: true);
    }
  }

  /// "Quality check": pixel checks, then the icons with problems.
  Future<void> _quality() async {
    final found = await c.scanQuality();
    if (!mounted) return;
    if (found.isEmpty) {
      showMsg(context, S.packQualitaOk);
      return;
    }
    final redo = [for (final f in found) if (c.hasSource(f.$1)) f.$1];
    await showAppSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(padding: const EdgeInsets.fromLTRB(22, 0, 22, 8), child: Text(S.packQualitaN(found.length), style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: Palette.text))),
            for (final (r, probs) in found)
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 22),
                leading: c.generatedById(r.generatedId)?.image(size: 44),
                title: Text(c.nameOf(r), maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Wrap(spacing: 6, runSpacing: 4, children: [for (final prob in probs) _probChip(prob)]),
                onTap: () {
                  Navigator.pop(ctx);
                  _details(r);
                },
              ),
            if (redo.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 10, 22, 0),
                child: FilledButton.icon(
                  icon: const Icon(Icons.refresh_rounded),
                  label: Text(S.packQualitaRielabora(redo.length)),
                  onPressed: c.busy
                      ? null
                      : () {
                          Navigator.pop(ctx);
                          _run(() => c.generateFromOriginals(only: redo));
                        },
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _probChip(PbProblem prob) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
    decoration: BoxDecoration(color: Palette.warn.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(10)),
    child: Text(_probLabel(prob), style: TextStyle(fontSize: 11.5, color: Palette.warn)),
  );

  String _probLabel(PbProblem prob) => switch (prob) {
    PbProblem.nearlyEmpty => S.packProbVuota,
    PbProblem.tooSmall => S.packProbPiccola,
    PbProblem.offCentre => S.packProbDecentrata,
    PbProblem.tooDark => S.packProbScura,
    PbProblem.lowContrast => S.pack2ProbContrasto,
  };

  /// Coverage of the installed apps; a tap shows only those still without an icon.
  Widget _coverageTile() => Tile(
    padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
    child: InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => rebuildScreen(() {
        installedMissing = !installedMissing;
        filter = installedMissing ? PbState.missing : null;
      }),
      child: Row(
        children: [
          Icon(Icons.pie_chart_outline_rounded, size: 20, color: installedMissing ? Palette.warn : Palette.text2),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              S.pack2Copertura(c.coverDone, c.coverTotal, c.coverPercent),
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Palette.text),
            ),
          ),
          if (installedMissing) Icon(Icons.close_rounded, size: 18, color: Palette.text3),
        ],
      ),
    ),
  );

  /// "Pack log": what happened, copied as release notes.
  Future<void> _logSheet() async {
    await showAppSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        final log = AppState.I.packLog;
        return SingleChildScrollView(
          padding: const EdgeInsets.only(bottom: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(padding: const EdgeInsets.fromLTRB(22, 0, 22, 8), child: Text(S.packRegistro, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: Palette.text))),
              if (log.isEmpty) Padding(padding: const EdgeInsets.fromLTRB(22, 8, 22, 16), child: Text(S.packRegistroVuoto, style: TextStyle(color: Palette.text2))),
              for (final e in log)
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 22),
                  title: Text('${e['text']}', style: TextStyle(fontSize: 14, color: Palette.text)),
                  subtitle: Text(_PackBuilderScreenState._fmtDate('${e['date']}'), style: TextStyle(fontSize: 12, color: Palette.text3)),
                ),
              if (log.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(22, 10, 22, 0),
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.copy_rounded),
                    label: Text(S.packRegistroCopia),
                    onPressed: () async {
                      final text = [for (final e in log) '${_PackBuilderScreenState._fmtDate('${e['date']}')}  ${e['text']}'].join('\n');
                      await Clipboard.setData(ClipboardData(text: text));
                      if (mounted) showMsg(context, S.packRegistroCopiato);
                    },
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  /// "Pack salvati": named sets of corrections, loaded or deleted here.
  Future<void> _profilesSheet() async {
    await showAppSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => ListenableBuilder(
        listenable: AppState.I,
        builder: (ctx, _) {
          final list = AppState.I.packProfiles;
          return SingleChildScrollView(
            padding: const EdgeInsets.only(bottom: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 22),
                  leading: const Icon(Icons.bookmark_add_outlined),
                  title: Text(S.packSalvaCome),
                  onTap: () {
                    Navigator.pop(ctx);
                    _saveProfile();
                  },
                ),
                if (list.isEmpty) Padding(padding: const EdgeInsets.fromLTRB(22, 8, 22, 16), child: Text(S.packProfiliVuoto, style: TextStyle(color: Palette.text2))),
                for (final pr in list)
                  ListTile(
                    contentPadding: const EdgeInsets.only(left: 22, right: 8),
                    leading: const Icon(Icons.bookmark_outline),
                    title: Text('${pr['name']}', maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text(S.packProfiloN(((pr['corrections'] as Map?) ?? {}).length, _PackBuilderScreenState._fmtDate('${pr['date']}')), style: TextStyle(fontSize: 12, color: Palette.text3)),
                    onTap: () {
                      Navigator.pop(ctx);
                      _loadProfile(pr);
                    },
                    trailing: IconButton(tooltip: S.elimina, icon: const Icon(Icons.delete_outline), onPressed: c.busy ? null : () => _deleteProfile(pr)),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _saveProfile() async {
    final name = await askText(context, S.packSalvaCome);
    if (name == null || name.trim().isEmpty) return;
    c.saveProfile(name.trim());
    if (mounted) showMsg(context, S.packSalvato(name.trim()));
  }

  Future<void> _loadProfile(Map<String, dynamic> pr) async {
    final ok = await confirm(context, S.packCaricaConferma('${pr['name']}'), S.packCaricaCorpo, ok: S.packCarica);
    if (!ok || !mounted) return;
    await _run(() => c.loadProfile(pr));
  }

  Future<void> _deleteProfile(Map<String, dynamic> pr) async {
    final name = '${pr['name']}';
    final ok = await confirm(context, S.packEliminaConferma(name), S.packEliminaCorpo, ok: S.elimina);
    if (ok) c.deleteProfile(name);
  }

  /// "Altro": the tools used less often than the buttons of the page, in one
  /// sheet of rows grouped by section. The sheet closes, then the tool runs.
  Future<void> _moreSheet(Rect anchor) async {
    final busy = c.busy;
    final canPreview = !busy && c.rows.any((r) => !r.excluded && c.generatedById(r.generatedId) != null);
    await showAppSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      belowStatusBar: true,
      builder: (ctx) {
        void then(Future<void> Function() tool) {
          Navigator.pop(ctx);
          _run(tool);
        }

        final chevron = Icon(Icons.chevron_right_rounded, color: Palette.text3);
        return SingleChildScrollView(
          // the sheet reaches the top edge: the title starts under the status bar
          padding: EdgeInsets.fromLTRB(16, 8, 16, MediaQuery.viewPaddingOf(ctx).bottom + 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(6, 0, 6, 0),
                child: Text(S.altro, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: Palette.text)),
              ),
              SectionTitle(S.altroSezVerifica, top: 16, bottom: 8),
              SettingsCard(
                children: [
                  PackRow(key: const ValueKey('pb-altro-quality'), icon: Icons.fact_check_outlined, title: S.packQualita, subtitle: S.altroControlloSub, trailing: chevron, onTap: busy ? null : () => then(_quality)),
                  PackRow(key: const ValueKey('pb-altro-conflicts'), icon: Icons.warning_amber_rounded, title: S.pack3Conflitti, subtitle: S.pack3ConflittoCondiviso, trailing: chevron, onTap: busy ? null : () => then(_conflicts)),
                  PackRow(key: const ValueKey('pb-altro-log'), icon: Icons.history_rounded, title: S.btnRegistro, subtitle: S.altroRegistroSub, trailing: chevron, onTap: () => then(_logSheet)),
                ],
              ),
              SectionTitle(S.pack, top: 20, bottom: 8),
              SettingsCard(
                children: [
                  PackRow(key: const ValueKey('pb-altro-profiles'), icon: Icons.bookmarks_outlined, title: S.packProfili, subtitle: S.altroProfiliSub, trailing: chevron, onTap: busy ? null : () => then(_profilesSheet)),
                  PackRow(key: const ValueKey('pb-altro-cleanup'), icon: Icons.cleaning_services_outlined, title: S.packCleanup, subtitle: S.altroPuliziaSub, trailing: chevron, onTap: () => then(_cleanup)),
                  PackRow(key: const ValueKey('pb-altro-open'), icon: Icons.inventory_outlined, title: S.pbApriPack, subtitle: S.altroApriSub, trailing: chevron, onTap: busy ? null : () => then(() => _openPack(anchor))),
                  PackRow(key: const ValueKey('pb-altro-import'), icon: Icons.collections_outlined, title: S.pbImportaGenerate, subtitle: S.altroImportaSub, trailing: chevron, onTap: busy ? null : () => then(() => c.addSource(original: false))),
                ],
              ),
              SectionTitle(S.altroSezEsporta, top: 20, bottom: 8),
              SettingsCard(
                children: [
                  PackRow(key: const ValueKey('pb-altro-plate'), icon: Icons.format_paint_outlined, title: S.ux1bChangeBg, subtitle: S.ux1bPlateHint, trailing: chevron, onTap: busy || c.rows.isEmpty ? null : () => then(() => showPlateSheet(context, c))),
                  PackRow(key: const ValueKey('pb-altro-sheet'), icon: Icons.photo_library_outlined, title: S.pack2Anteprima, subtitle: S.altroAnteprimaSub, trailing: chevron, onTap: canPreview ? () => then(_contactSheet) : null),
                  if (Platform.isAndroid) PackRow(key: const ValueKey('pb-altro-share'), icon: Icons.share_outlined, title: S.pbCondividiApk, subtitle: S.altroCondividiSub, trailing: chevron, onTap: busy ? null : () => then(c.shareApk)),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  /// "Pulizia pack": the cleanup screen, pushed over the Pack tab.
  Future<void> _cleanup() async {
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (ctx) => Scaffold(
          body: Backdrop(
            child: SafeArea(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                    child: LargeHeader(S.packCleanup, onBack: () => Navigator.of(ctx).pop()),
                  ),
                  Expanded(child: PackScreen(onOpenBases: () {})),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

}
