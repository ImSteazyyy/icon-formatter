import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../app/storage.dart';
import '../app/theme.dart';
import '../services/export_service.dart';
import '../services/import_service.dart';
import '../src/rust/api/engine.dart';
import '../widgets/common.dart';
import '../workspace/workspace_controller.dart';
import '../workspace/workspace_view.dart';
import '../l10n/strings.dart';

/// Pack Cleanup: uniform an existing icon pack, keeping names and mapping.
class PackScreen extends StatefulWidget {
  const PackScreen({super.key, required this.onOpenBases});

  final VoidCallback onOpenBases;

  @override
  State<PackScreen> createState() => _PackScreenState();
}

class _PackScreenState extends State<PackScreen> with AutomaticKeepAliveClientMixin {
  late final WorkspaceController c = WorkspaceController(
    tag: 'pack',
    packSettings: true,
    outputRelFor: (it) => _outRel[it.id] ?? '${it.name}.png',
  );
  final Map<String, String> _outRel = {};
  PackInfo? info;
  String? sourceName;
  bool opening = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void dispose() {
    c.dispose();
    super.dispose();
  }

  Future<void> _open({required bool zip}) async {
    String? input;
    if (zip) {
      final r = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['zip'], dialogTitle: S.iconPackZip);
      input = r?.files.single.path;
    } else {
      input = await ImportService.pickFolder();
    }
    if (input == null) return;
    setState(() => opening = true);
    try {
      final work = await AppPaths.I.workDir('pack');
      final pi = await openPack(input: input, workDir: work);
      c.clear();
      _outRel.clear();
      for (final im in pi.images) {
        final it = WorkItem(
          id: 'p${_outRel.length}',
          name: c.uniqueStem(p.basenameWithoutExtension(im.rel)),
          rel: im.rel,
          path: im.abs,
        );
        _outRel[it.id] = im.outputRel;
        c.addItem(it);
      }
      c.notify();
      c.schedulePreview(immediate: true);
      setState(() {
        info = pi;
        sourceName = p.basenameWithoutExtension(input!);
      });
    } catch (e) {
      if (mounted) showMsg(context, S.impossibileAprirePack(e), error: true);
    } finally {
      if (mounted) setState(() => opening = false);
    }
  }

  void _nextAmbiguous() {
    final amb = c.items.where((i) => i.result?.ambiguous == true || i.result?.ok == false).toList();
    if (amb.isEmpty) {
      showMsg(context, S.nessunRisultatoVerificare);
      return;
    }
    final idx = amb.indexWhere((i) => i.id == c.selectedId);
    c.select(amb[(idx + 1) % amb.length].id);
  }

  Future<void> _export({required bool zip, bool share = false}) async {
    final pi = info;
    if (pi == null || c.batch.running) return;
    final todo = c.active.where((i) => i.outputPath == null).toList();
    if (todo.isNotEmpty) {
      await c.process(only: todo);
      if (c.batch.cancelled) return;
    }
    final out = c.outputDir;
    if (out == null) return;
    try {
      // excluded icons are kept unchanged so the pack stays complete
      for (final it in c.items.where((i) => i.excluded)) {
        final dest = p.joinAll([out, ...it.rel.split('/')]);
        await Directory(p.dirname(dest)).create(recursive: true);
        await File(it.path!).copy(dest);
      }
      final notes = await finalizePack(root: pi.root, outDir: out);
      final name = '${sourceName ?? 'pack'}_cleanup';
      if (share) {
        await ExportService.shareDirAsZip(out, name);
      } else {
        final r = await ExportService.exportDir(out, name: name, zip: zip);
        if (r != null && mounted) await showExportDone(context, r);
      }
      if (notes.isNotEmpty && mounted) showMsg(context, notes.join('\n'));
    } catch (e) {
      if (mounted) showMsg(context, S.esportazioneNonRiuscita(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final pi = info;
    final header = pi == null
        ? null
        : Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Glass(
              padding: const EdgeInsets.all(12),
              child: Wrap(spacing: 18, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
                _stat(S.icone, '${pi.images.length}'),
                _stat('appfilter.xml', pi.appfilter == null ? 'assente' : '${pi.appfilterItems.length} voci'),
                _stat(S.drawableMancanti, '${pi.missingDrawables.length}', warn: pi.missingDrawables.isNotEmpty),
                _stat(S.iconeNonMappate, '${pi.unmappedIcons.length}'),
                _stat(S.altriFilePreservati, '${pi.otherFiles}'),
                if (pi.missingDrawables.isNotEmpty || pi.notes.isNotEmpty)
                  TextButton(onPressed: () => _details(pi), child: const Text(S.dettagli)),
                TextButton.icon(onPressed: _nextAmbiguous, icon: const Icon(Icons.flag_outlined, size: 16), label: const Text(S.prossimaVerificare)),
              ]),
            ),
          );
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) => WorkspaceView(
        c: c,
        title: S.packCleanup,
        header: header,
        onOpenBases: widget.onOpenBases,
        toolbar: [
          ToolButton(icon: Icons.folder_open_outlined, label: S.apriCartella, onTap: opening ? null : () => _open(zip: false)),
          ToolButton(icon: Icons.folder_zip_outlined, label: S.apriZip, onTap: opening ? null : () => _open(zip: true)),
        ],
        emptyHint: opening
            ? const CircularProgressIndicator()
            : const Text(
                S.apriIconPackCartellaO,
                textAlign: TextAlign.center,
                style: TextStyle(color: Palette.text2),
              ),
        bottomActions: [
          ListenableBuilder(
            listenable: c.batch,
            builder: (context, _) => FilledButton.icon(
              onPressed: c.items.isEmpty || c.batch.running ? null : () => c.process(),
              icon: const Icon(Icons.cleaning_services_outlined),
              label: Text(c.batch.running ? S.elaborazione : S.uniformaPack),
            ),
          ),
          OutlinedButton.icon(
            onPressed: c.items.isEmpty ? null : () => c.process(only: c.items.where((i) => i.hasOverride || i.result?.ok == false)),
            icon: const Icon(Icons.refresh),
            label: const Text(S.rielaboraCorretteErrori),
          ),
          OutlinedButton.icon(onPressed: pi == null ? null : () => _export(zip: false), icon: const Icon(Icons.drive_folder_upload_outlined), label: const Text(S.esportaCartella)),
          OutlinedButton.icon(onPressed: pi == null ? null : () => _export(zip: true), icon: const Icon(Icons.archive_outlined), label: const Text(S.esportaZip)),
          if (Platform.isAndroid)
            OutlinedButton.icon(onPressed: pi == null ? null : () => _export(zip: true, share: true), icon: const Icon(Icons.share_outlined), label: const Text(S.condividi)),
        ],
      ),
    );
  }

  Widget _stat(String k, String v, {bool warn = false}) => Row(mainAxisSize: MainAxisSize.min, children: [
        Text('$k ', style: const TextStyle(fontSize: 12, color: Palette.text3)),
        Text(v, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: warn ? Palette.warn : Palette.text)),
      ]);

  void _details(PackInfo pi) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text(S.dettagliMapping),
        content: SizedBox(
          width: 520,
          height: 420,
          child: ListView(children: [
            if (pi.notes.isNotEmpty) ...[const SectionTitle(S.note), for (final n in pi.notes) Text('• $n')],
            if (pi.missingDrawables.isNotEmpty) ...[
              const SizedBox(height: 10),
              const SectionTitle(S.drawableAppfilterXmlSenzaIcona),
              for (final d in pi.missingDrawables) Text(d, style: const TextStyle(fontFamily: 'Consolas', fontSize: 12)),
            ],
            if (pi.unmappedIcons.isNotEmpty) ...[
              const SizedBox(height: 10),
              const SectionTitle(S.iconeNonReferenziate),
              Text(pi.unmappedIcons.join(', '), style: const TextStyle(fontSize: 12, color: Palette.text2)),
            ],
          ]),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text(S.chiudi))],
      ),
    );
  }
}
