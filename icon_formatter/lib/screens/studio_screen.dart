import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';

import '../app/state.dart';
import '../app/theme.dart';
import '../services/export_service.dart';
import '../services/import_service.dart';
import '../widgets/common.dart';
import '../widgets/glass_menu.dart';
import 'pack_builder_screen.dart';
import '../workspace/workspace_controller.dart';
import '../workspace/workspace_view.dart';
import '../l10n/strings.dart';

/// Original Composition / Nothing Translucent / Custom Presets.
class StudioScreen extends StatefulWidget {
  const StudioScreen({super.key, required this.onOpenBases, this.onOpenPack, this.onOpenApps});

  final VoidCallback onOpenBases;

  /// Android: opens the installed-apps section (icons of the phone's apps).
  final VoidCallback? onOpenApps;

  /// Switches to the Pack tab (after "Manda al Pack").
  final VoidCallback? onOpenPack;

  @override
  State<StudioScreen> createState() => _StudioScreenState();
}

class _StudioScreenState extends State<StudioScreen> with AutomaticKeepAliveClientMixin {
  final c = WorkspaceController(tag: 'studio', mode: StudioMode.translucent);
  bool dragging = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void dispose() {
    c.dispose();
    super.dispose();
  }

  Future<void> _import(Future<List<dynamic>> Function() f, {bool placeOnly = false}) async {
    try {
      final imgs = await f();
      if (imgs.isEmpty) return;
      c.addPaths(imgs.cast(), placeOnly: placeOnly);
      if (mounted) showMsg(context, S.iconeImportate(imgs.length));
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
        ),
    ]);
    if (!mounted) return;
    showMsg(context, S.mandateAlPack(n), actionLabel: widget.onOpenPack == null ? null : S.apri, onAction: widget.onOpenPack);
  }

  Future<void> _process() async {
    await c.process();
    if (!c.batch.cancelled && AppState.I.autoSendToPack) await _sendToPack(auto: true);
  }

  /// The one import menu (centre button and "+"): files, folder, ZIP/APK
  /// and, on Android, the phone's apps. iOS 26 style glass pop-up.
  Future<void> _importMenu(Rect anchor) async {
    final v = await showGlassMenu<String>(context, anchor: anchor, items: [
      const GlassMenuItem(value: 'file', label: S.importaImmagini, subtitle: S.importaImmaginiSub, icon: Icons.image_outlined),
      const GlassMenuItem(value: 'folder', label: S.importaCartella, subtitle: S.importaCartellaSub, icon: Icons.folder_open_outlined),
      const GlassMenuItem(value: 'zip', label: S.importaZipApk, subtitle: S.importaZipSub, icon: Icons.folder_zip_outlined),
      const GlassMenuItem(value: 'ready', label: S.importaPronti, subtitle: S.importaProntiSub, icon: Icons.crop_free_rounded),
      if (Platform.isAndroid && widget.onOpenApps != null)
        const GlassMenuItem(value: 'apps', label: S.usaAppDelTelefono, subtitle: S.usaAppDelTelefonoSub, icon: Icons.apps_rounded),
    ]);
    switch (v) {
      case 'file':
        await _import(ImportService.pickFiles);
      case 'folder':
        await _import(ImportService.pickFolderImages);
      case 'zip':
        await _import(ImportService.pickZip);
      case 'ready':
        await _import(ImportService.pickFiles, placeOnly: true);
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
        label: const Text(S.mandaAlPack),
      ),
      OutlinedButton.icon(onPressed: c.items.isEmpty ? null : () => _export(zip: false), icon: const Icon(Icons.drive_folder_upload_outlined), label: const Text(S.esportaCartella)),
      OutlinedButton.icon(onPressed: c.items.isEmpty ? null : () => _export(zip: true), icon: const Icon(Icons.archive_outlined), label: const Text(S.esportaZip)),
      if (Platform.isAndroid)
        OutlinedButton.icon(onPressed: c.items.isEmpty ? null : () => _export(zip: true, share: true), icon: const Icon(Icons.share_outlined), label: const Text(S.condividi)),
    ];
    // empty Studio: one obvious primary action, the steps underneath
    Widget step(int n, String title) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(children: [
            Container(
              width: 24,
              height: 24,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.16), shape: BoxShape.circle),
              child: Text('$n', style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.w700)),
            ),
            const SizedBox(width: 10),
            Expanded(child: Text(title, style: const TextStyle(fontSize: 13.5, color: Palette.text2))),
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
          const Text(S.studioVuotoTitolo, textAlign: TextAlign.center, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: Palette.text)),
          const SizedBox(height: 6),
          Text(Platform.isWindows ? S.studioVuotoSubWin : S.studioVuotoSub, textAlign: TextAlign.center, style: const TextStyle(fontSize: 13.5, color: Palette.text2)),
          const SizedBox(height: 18),
          // the only button: every source opens from here
          Builder(
            builder: (bctx) => FilledButton.icon(
              key: const ValueKey('studio-import'),
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
              onPressed: () => _importMenu(anchorOf(bctx)),
              icon: const Icon(Icons.add_rounded),
              label: const Text(S.importaIcone, style: TextStyle(fontSize: 16)),
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
        toolbar: c.items.isEmpty ? const [] : toolbar,
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
        moreActions: [
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
                  child: const Center(child: Text(S.rilasciaImportare, style: TextStyle(fontSize: 18))),
                ),
              ),
            ),
        ]),
      );
    }
    return view;
  }
}
