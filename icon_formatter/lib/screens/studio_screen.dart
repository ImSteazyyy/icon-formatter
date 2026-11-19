import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';

import '../app/state.dart';
import '../app/theme.dart';
import '../services/export_service.dart';
import '../services/folder_watch.dart';
import '../services/import_service.dart';
import '../services/platform_service.dart';
import '../services/share_intake.dart';
import '../widgets/common.dart';
import '../widgets/glass_menu.dart';
import '../widgets/liquid_glass.dart' show nothingStyle, NothingColors;
import 'pack_builder_screen.dart';
import '../workspace/studio_clipboard.dart';
import '../workspace/workspace_controller.dart';
import '../workspace/workspace_view.dart';
import '../l10n/strings.dart';
import '../src/rust/api/engine.dart' show PackImage;

/// Original Composition / Translucent / Custom Presets.
class StudioScreen extends StatefulWidget {
  const StudioScreen({super.key, required this.onOpenBases, this.onOpenPack, this.onOpenApps, this.onShow, this.tabShown});

  final VoidCallback onOpenBases;

  /// Android: opens the installed-apps section (icons of the phone's apps).
  final VoidCallback? onOpenApps;

  /// Switches to the Pack tab (after "Manda al Pack").
  final VoidCallback? onOpenPack;

  /// Shows this tab (images shared to the app while another tab is open).
  final VoidCallback? onShow;

  /// True while this tab is shown; the folder watch runs only then.
  final ValueListenable<bool>? tabShown;

  @override
  State<StudioScreen> createState() => _StudioScreenState();
}

class _StudioScreenState extends State<StudioScreen> with AutomaticKeepAliveClientMixin, WidgetsBindingObserver {
  final c = WorkspaceController(tag: 'studio', mode: StudioMode.translucent);
  bool dragging = false;
  FolderWatch? _watch;
  String? _watchedDir;
  bool _tabShown = true;
  bool _appActive = true;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _tabShown = widget.tabShown?.value ?? true;
    widget.tabShown?.addListener(_onTabShown);
    AppState.I.addListener(_syncWatch);
    _syncWatch();
    // after the first frame: images shared to the app before it was opened
    WidgetsBinding.instance.addPostFrameCallback((_) => _takeShared());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // inactive (window unfocused, e.g. files saved in Explorer) keeps the watch
    _appActive = state == AppLifecycleState.resumed || state == AppLifecycleState.inactive;
    _syncWatch();
    if (state == AppLifecycleState.resumed) _takeShared();
  }

  void _onTabShown() {
    _tabShown = widget.tabShown?.value ?? true;
    _syncWatch();
  }

  /// Runs the folder watch only while this tab is shown and the app is active.
  void _syncWatch() {
    final dir = AppState.I.watchDir;
    if (dir == null || !_tabShown || !_appActive) {
      _watch?.stop();
      _watchedDir = null;
      return;
    }
    if (_watchedDir == dir && (_watch?.isRunning ?? false)) return;
    _watchedDir = dir;
    (_watch ??= FolderWatch()).start(dir, _onWatched);
  }

  void _onWatched(List<String> paths) {
    if (mounted) _import(() => ImportService.expand(paths));
  }

  /// Images sent to the app from the share sheet: shown here and imported.
  Future<void> _takeShared() async {
    final paths = await takeSharedImages();
    if (paths.isEmpty || !mounted) return;
    widget.onShow?.call();
    await _import(() => ImportService.expand(paths));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.tabShown?.removeListener(_onTabShown);
    AppState.I.removeListener(_syncWatch);
    _watch?.stop();
    c.dispose();
    super.dispose();
  }

  Future<void> _import(Future<List<PackImage>> Function() f, {bool placeOnly = false}) async {
    try {
      var imgs = await f();
      if (imgs.isEmpty || !mounted) return;
      // an icon pack or a big folder: the user picks the icons wanted
      if (imgs.length > 24) {
        final picked = await pickImagesDialog(context, imgs);
        if (picked == null || picked.isEmpty || !mounted) return;
        imgs = picked;
      }
      final added = c.addPaths(imgs, placeOnly: placeOnly);
      if (mounted) showMsg(context, S.iconeImportate(imgs.length));
      // ready-made icons: size them right away
      if (placeOnly && mounted) {
        await c.process(only: added);
        if (mounted) await showIconSizeDialog(context, c, added);
      }
    } catch (e) {
      if (mounted) showMsg(context, S.importazioneNonRiuscita(e), error: true);
    }
  }

  Future<void> _export({required bool zip, bool share = false}) async {
    if (c.batch.running) return;
    if (c.processed.length < c.active.length) {
      await c.process();
      if (c.batch.cancelled) return;
    }
    final done = c.processed;
    if (done.isEmpty) {
      if (mounted) showMsg(context, S.nessunaIconaElaborataEsportare, error: true);
      return;
    }
    try {
      final stage = await ExportService.stage({for (final i in done) i.name: i.outputPath!}, c.settings.size);
      final name = S.iconformatter(c.mode.name, DateTime.now().millisecondsSinceEpoch ~/ 1000);
      if (share) {
        await ExportService.shareDirAsZip(stage, name);
        return;
      }
      final r = await ExportService.exportDir(stage, name: name, zip: zip);
      if (r != null && mounted) await showExportDone(context, r);
    } catch (e) {
      if (mounted) showMsg(context, S.esportazioneNonRiuscita(e), error: true);
    }
  }

  /// Sends the processed icons to the Pack builder (step 2).
  Future<void> _sendToPack({bool auto = false}) async {
    final done = c.processed;
    if (done.isEmpty) {
      if (!auto && mounted) showMsg(context, S.nessunaIconaElaborataEsportare, error: true);
      return;
    }
    final n = await PackBuilderController.I.addFromStudio([
      for (final it in done)
        PbIcon(
          id: 'studio:${it.id}',
          label: it.label ?? it.name,
          package: it.package ?? '',
          activity: it.activity ?? '',
          file: '${it.name}.png',
          path: it.outputPath,
          calendarDay: it.calendarDay ?? 0,
        ),
    ]);
    if (!mounted) return;
    showMsg(context, S.mandateAlPack(n), actionLabel: widget.onOpenPack == null ? null : S.apri, onAction: widget.onOpenPack);
  }

  Future<void> _process() async {
    await c.process();
    if (!c.batch.cancelled && AppState.I.autoSendToPack) await _sendToPack(auto: true);
  }

  /// "Incolla dagli appunti": image files or a copied bitmap on the clipboard.
  Future<void> _paste() async {
    final paths = await clipboardImagePaths();
    if (!mounted) return;
    if (paths.isEmpty) {
      showMsg(context, S.studioAppuntiVuoti, error: true);
      return;
    }
    await _import(() => ImportService.expand(paths));
  }

  /// Undo, redo and duplicates, as toolbar buttons (desktop; enabled state
  /// read on each rebuild). The phone has them in "Altro".
  List<Widget> _studioTools() => [
        ToolButton(key: const ValueKey('studio-undo'), icon: Icons.undo_rounded, label: S.btnAnnulla, onTap: c.canUndo ? () => c.undo() : null),
        ToolButton(key: const ValueKey('studio-redo'), icon: Icons.redo_rounded, label: S.btnRipristina, onTap: c.canRedo ? () => c.redo() : null),
        if (c.duplicateCount > 0)
          ToolButton(key: const ValueKey('studio-dup'), icon: Icons.content_copy_outlined, label: S.btnDuplicati, onTap: () => _excludeDuplicates()),
      ];

  void _excludeDuplicates() {
    final n = c.excludeDuplicates();
    if (mounted) showMsg(context, S.studioDuplicatiEsclusi(n));
  }

  /// The one import menu (centre button and "+"): files, folder, ZIP/APK
  /// and, on Android, the phone's apps. Glass pop-up.
  Future<void> _importMenu(Rect anchor) async {
    final v = await showGlassMenu<String>(context, anchor: anchor, items: [
      GlassMenuItem(value: 'file', label: S.importaImmagini, subtitle: S.importaImmaginiSub, icon: Icons.image_outlined),
      GlassMenuItem(value: 'folder', label: S.importaCartella, subtitle: S.importaCartellaSub, icon: Icons.folder_open_outlined),
      GlassMenuItem(value: 'ready', label: S.importaPronti, subtitle: S.importaProntiSub, icon: Icons.crop_free_rounded),
      GlassMenuItem(value: 'paste', label: S.studioIncollaAppunti, subtitle: S.studioIncollaAppuntiSub, icon: Icons.content_paste_rounded),
      GlassMenuItem(value: 'calendar', label: S.calendarioDaPack, subtitle: S.calendarioDaPackSub, icon: Icons.calendar_month_outlined),
      if (Platform.isAndroid && widget.onOpenApps != null)
        GlassMenuItem(value: 'apps', label: S.usaAppDelTelefono, subtitle: S.usaAppDelTelefonoSub, icon: Icons.apps_rounded),
    ]);
    switch (v) {
      case 'file':
        await _import(ImportService.pickFiles);
      case 'folder':
        await _import(ImportService.pickFolderImages);
      case 'ready':
        await _import(ImportService.pickFiles, placeOnly: true);
      case 'paste':
        await _paste();
      case 'calendar':
        try {
          var days = await ImportService.pickCalendarPack();
          if (!mounted) return;
          if (days.isEmpty) {
            showMsg(context, S.calendarioNessuno, error: true);
            return;
          }
          // only the calendar apps installed on this phone, not every launcher's
          if (Platform.isAndroid) {
            final have = {for (final a in await PlatformService.listApps()) a.package};
            days = [for (final d in days) if (have.contains(d.package)) d];
            if (!mounted) return;
            if (days.isEmpty) {
              showMsg(context, S.calendarioNonInstallati, error: true);
              return;
            }
          }
          c.addCalendar(days);
          final apps = days.map((d) => d.package).toSet().length;
          showMsg(context, S.calendarioImportato(days.length, apps));
        } catch (e) {
          if (mounted) showMsg(context, S.importazioneNonRiuscita(e), error: true);
        }
      case 'apps':
        widget.onOpenApps?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final toolbar = [
      Builder(builder: (bctx) => ToolButton(icon: Icons.add_rounded, label: S.aggiungi, onTap: () => _importMenu(anchorOf(bctx)))),
      ToolButton(
        icon: Icons.clear_all,
        label: S.svuota,
        onTap: () async {
          if (c.items.isNotEmpty && await confirm(context, S.svuotareLista, S.fileOriginaliNonVengonoToccati, ok: S.svuota)) c.clear();
        },
      ),
    ];
    List<Widget> buildActions() => <Widget>[
      ListenableBuilder(
        listenable: c.batch,
        builder: (context, _) => FilledButton.icon(
          onPressed: c.items.isEmpty || c.batch.running ? null : _process,
          icon: const Icon(Icons.play_arrow_rounded),
          label: Text(c.batch.running ? S.elaborazione : S.elaboraTutte),
        ),
      ),
      OutlinedButton.icon(
        key: const ValueKey('send-to-pack'),
        onPressed: c.items.isEmpty ? null : _sendToPack,
        icon: const Icon(Icons.dashboard_customize_outlined),
        label: Text(S.mandaAlPack),
      ),
      OutlinedButton.icon(onPressed: c.items.isEmpty ? null : () => _export(zip: false), icon: const Icon(Icons.drive_folder_upload_outlined), label: Text(S.esportaCartella)),
      OutlinedButton.icon(onPressed: c.items.isEmpty ? null : () => _export(zip: true), icon: const Icon(Icons.archive_outlined), label: Text(S.esportaZip)),
      if (Platform.isAndroid)
        OutlinedButton.icon(onPressed: c.items.isEmpty ? null : () => _export(zip: true, share: true), icon: const Icon(Icons.share_outlined), label: Text(S.condividi)),
    ];
    // empty Studio: one obvious primary action, the steps underneath
    Widget step(int n, String title) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(children: [
            Container(
              width: 24,
              height: 24,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: nothingStyle ? NothingColors.tertiary : Theme.of(context).colorScheme.primary.withValues(alpha: 0.16), shape: BoxShape.circle),
              child: Text('$n', style: TextStyle(fontSize: 12, color: nothingStyle ? Palette.fg : Theme.of(context).colorScheme.primary, fontWeight: FontWeight.w700)),
            ),
            const SizedBox(width: 10),
            Expanded(child: Text(title, style: TextStyle(fontSize: 13.5, color: Palette.text2))),
          ]),
        );
    final empty = ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 420),
      // static card: glass like the rest of the chrome (it does not scroll)
      child: Glass(
        key: const ValueKey('studio-guide'),
        padding: const EdgeInsets.fromLTRB(20, 22, 20, 18),
        radius: AppState.I.appearance.radius + 8,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Icon(Icons.auto_awesome_mosaic_outlined, size: 44, color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: 12),
          Text(S.studioVuotoTitolo, textAlign: TextAlign.center, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: Palette.text)),
          const SizedBox(height: 6),
          Text(Platform.isWindows ? S.studioVuotoSubWin : S.studioVuotoSub, textAlign: TextAlign.center, style: TextStyle(fontSize: 13.5, color: Palette.text2)),
          const SizedBox(height: 18),
          // the only button: every source opens from here
          Builder(
            builder: (bctx) => FilledButton.icon(
              key: const ValueKey('studio-import'),
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
              onPressed: () => _importMenu(anchorOf(bctx)),
              icon: const Icon(Icons.add_rounded),
              label: Text(S.importaIcone, style: TextStyle(fontSize: 16)),
            ),
          ),
          const SizedBox(height: 18),
          step(1, S.studioPasso1Breve),
          step(2, S.studioPasso2Breve),
          step(3, S.studioPasso3Breve),
        ]),
      ),
    );
    Widget view = ListenableBuilder(
      listenable: c,
      builder: (context, _) => WorkspaceView(
        c: c,
        title: S.studio,
        // nothing to act on yet: only the empty-state action is shown
        toolbar: c.items.isEmpty ? const [] : [...toolbar, ..._studioTools()],
        bottomActions: c.items.isEmpty ? const [] : buildActions(),
        // phones: "+" next to Personalizza, one start button, the rest in "Altro"
        onAdd: _importMenu,
        primaryAction: c.items.isEmpty
            ? null
            : ListenableBuilder(
                listenable: c.batch,
                builder: (context, _) => FilledButton.icon(
                  key: const ValueKey('studio-start'),
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
                  onPressed: c.batch.running ? null : _process,
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: Text(c.batch.running ? S.elaborazione : S.elaboraTutte, style: const TextStyle(fontSize: 16)),
                ),
              ),
        compactPrimaryAction: c.items.isEmpty
            ? null
            : ListenableBuilder(
                listenable: c.batch,
                builder: (context, _) => Tooltip(
                  message: S.elaboraTutte,
                  child: FilledButton(
                    style: FilledButton.styleFrom(minimumSize: Size.zero, padding: EdgeInsets.zero),
                    onPressed: c.batch.running ? null : _process,
                    child: const Icon(Icons.play_arrow_rounded, size: 26),
                  ),
                ),
              ),
        moreActions: [
          MoreAction(Icons.undo_rounded, S.studioAnnullaModifica, S.studioAnnullaModificaSub, c.canUndo ? () => c.undo() : null),
          MoreAction(Icons.redo_rounded, S.studioRipristinaModifica, S.studioRipristinaModificaSub, c.canRedo ? () => c.redo() : null),
          MoreAction(Icons.crop_square_outlined, S.studioGuidaArea, S.studioGuidaAreaSub, c.toggleSafeGuide),
          if (c.duplicateCount > 0) MoreAction(Icons.content_copy_outlined, S.studioEscludiDuplicati, S.studioEscludiDuplicatiSub(c.duplicateCount), _excludeDuplicates),
          if (c.items.any((i) => i.calendarDay != null))
            MoreAction(Icons.opacity_rounded, S.sfondoComePack, S.sfondoComePackSub, () async {
              final r = await c.matchPlateAll();
              if (mounted) showMsg(this.context, plateMatchMessage(r), error: r == null);
            }),
          MoreAction(Icons.dashboard_customize_outlined, S.mandaAlPack, S.mandaAlPackSub, _sendToPack),
          MoreAction(Icons.drive_folder_upload_outlined, S.esportaCartella, S.esportaCartellaSub, () => _export(zip: false)),
          MoreAction(Icons.archive_outlined, S.esportaZip, S.esportaZipSub, () => _export(zip: true)),
          if (Platform.isAndroid) MoreAction(Icons.share_outlined, S.condividi, S.condividiSub, () => _export(zip: true, share: true)),
          MoreAction(Icons.clear_all, S.svuota, S.svuotaSub, () async {
            if (c.items.isNotEmpty && await confirm(context, S.svuotareLista, S.fileOriginaliNonVengonoToccati, ok: S.svuota)) c.clear();
          }),
        ],
        emptyHint: empty,
        onOpenBases: widget.onOpenBases,
      ),
    );
    if (Platform.isWindows) {
      view = DropTarget(
        onDragEntered: (_) => setState(() => dragging = true),
        onDragExited: (_) => setState(() => dragging = false),
        onDragDone: (d) async {
          setState(() => dragging = false);
          final paths = d.files.map((f) => f.path).toList();
          await _import(() => ImportService.expand(paths));
        },
        child: Stack(children: [
          view,
          if (dragging)
            Positioned.fill(
              child: IgnorePointer(
                child: Container(
                  margin: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.08),
                    border: Border.all(color: Theme.of(context).colorScheme.primary, width: 2),
                  ),
                  child: Center(child: Text(S.rilasciaImportare, style: TextStyle(fontSize: 18))),
                ),
              ),
            ),
        ]),
      );
    }
    return view;
  }
}
