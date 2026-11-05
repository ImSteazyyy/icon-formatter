import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';

import '../app/state.dart';
import '../app/theme.dart';
import '../services/export_service.dart';
import '../services/import_service.dart';
import '../widgets/common.dart';
import '../workspace/workspace_controller.dart';
import '../workspace/workspace_view.dart';
import '../l10n/strings.dart';

/// Original Composition / Nothing Translucent / Custom Presets.
class StudioScreen extends StatefulWidget {
  const StudioScreen({super.key, required this.onOpenBases});

  final VoidCallback onOpenBases;

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

  Future<void> _import(Future<List<dynamic>> Function() f) async {
    try {
      final imgs = await f();
      if (imgs.isEmpty) return;
      c.addPaths(imgs.cast());
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

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final toolbar = [
      ToolButton(icon: Icons.add_photo_alternate_outlined, label: S.file, onTap: () => _import(ImportService.pickFiles)),
      ToolButton(icon: Icons.folder_open_outlined, label: S.cartella, onTap: () => _import(ImportService.pickFolderImages)),
      ToolButton(icon: Icons.folder_zip_outlined, label: S.zipOApk, onTap: () => _import(ImportService.pickZip)),
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
          onPressed: c.items.isEmpty || c.batch.running ? null : () => c.process(),
          icon: const Icon(Icons.play_arrow_rounded),
          label: Text(c.batch.running ? S.elaborazione : S.elaboraTutte),
        ),
      ),
      OutlinedButton.icon(onPressed: c.items.isEmpty ? null : () => _export(zip: false), icon: const Icon(Icons.drive_folder_upload_outlined), label: const Text(S.esportaCartella)),
      OutlinedButton.icon(onPressed: c.items.isEmpty ? null : () => _export(zip: true), icon: const Icon(Icons.archive_outlined), label: const Text(S.esportaZip)),
      if (Platform.isAndroid)
        OutlinedButton.icon(onPressed: c.items.isEmpty ? null : () => _export(zip: true, share: true), icon: const Icon(Icons.share_outlined), label: const Text(S.condividi)),
    ];
    final empty = Column(mainAxisSize: MainAxisSize.min, children: [
      Icon(Icons.auto_awesome_mosaic_outlined, size: 40, color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.7)),
      const SizedBox(height: 10),
      Text(
        Platform.isWindows ? S.trascinaQuiIconeCartelleO : S.importaIconeCartelleOZip,
        textAlign: TextAlign.center,
        style: const TextStyle(color: Palette.text2),
      ),
    ]);
    Widget view = ListenableBuilder(
      listenable: c,
      builder: (context, _) => WorkspaceView(
        c: c,
        title: S.studio,
        toolbar: toolbar,
        bottomActions: buildActions(),
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
