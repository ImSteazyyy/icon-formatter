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
import '../widgets/liquid_glass.dart';
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
      final r = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['zip', 'apk'], dialogTitle: S.iconPackZip);
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

  /// Icons to check: uncertain (yellow) or failed. Shared by the review row and
  /// its previous/next buttons.
  List<WorkItem> get _toReview => c.items.where((i) => i.result?.ambiguous == true || i.result?.ok == false).toList();

  /// Moves the selection to the next (step 1) or previous (step -1) icon to check.
  void _stepReview(int step) {
    final amb = _toReview;
    if (amb.isEmpty) {
      showMsg(context, S.ux1bNoReview);
      return;
    }
    final idx = amb.indexWhere((i) => i.id == c.selectedId);
    // nothing selected yet: next starts at the first icon, previous at the last
    final next = idx < 0 ? (step > 0 ? 0 : amb.length - 1) : (idx + step + amb.length) % amb.length;
    c.select(amb[next].id);
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
    final review = _toReview.length;
    final header = Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // what this screen is for, then the three steps it walks through
          Text(S.ux1bCleanupRole, style: TextStyle(fontSize: 13, color: Palette.text2)),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 6, children: [
            _stepChip(S.ux1bStep1, done: pi != null),
            _stepChip(S.ux1bStep2, done: false),
            _stepChip(S.ux1bStep3, done: false),
          ]),
          if (pi != null) ...[
            const SizedBox(height: 10),
            Glass(
              padding: const EdgeInsets.all(12),
              child: Wrap(spacing: 18, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
                _stat(S.icone, '${pi.images.length}'),
                _stat('appfilter.xml', pi.appfilter == null ? S.ux1bNone : S.ux1bEntries(pi.appfilterItems.length)),
                _stat(S.drawableMancanti, '${pi.missingDrawables.length}', warn: pi.missingDrawables.isNotEmpty),
                _stat(S.iconeNonMappate, '${pi.unmappedIcons.length}'),
                _stat(S.altriFilePreservati, '${pi.otherFiles}'),
                if (pi.missingDrawables.isNotEmpty || pi.notes.isNotEmpty)
                  TextButton(onPressed: () => _details(pi), child: Text(S.dettagli)),
              ]),
            ),
          ],
          // the review row: a count, a legend for the yellow icons, and prev/next
          if (pi != null) ...[
            const SizedBox(height: 10),
            Glass(
              padding: const EdgeInsets.fromLTRB(12, 8, 6, 8),
              child: Row(children: [
                Container(width: 10, height: 10, decoration: BoxDecoration(color: Palette.warn, shape: BoxShape.circle)),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(review == 0 ? S.ux1bNoReview : S.ux1bReviewCount(review), style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Palette.text)),
                    Text(S.ux1bReviewLegend, style: TextStyle(fontSize: 12, color: Palette.text2)),
                  ]),
                ),
                if (review > 0) ...[
                  FilledButton(onPressed: () => _stepReview(1), child: Text(S.ux1bReviewStart)),
                  IconButton(tooltip: S.ux1bPrev, icon: const Icon(Icons.chevron_left_rounded), onPressed: () => _stepReview(-1)),
                  IconButton(tooltip: S.ux1bNext, icon: const Icon(Icons.chevron_right_rounded), onPressed: () => _stepReview(1)),
                ],
              ]),
            ),
          ],
        ],
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
            : Text(
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
            label: Text(S.rielaboraCorretteErrori),
          ),
          OutlinedButton.icon(onPressed: pi == null ? null : () => _export(zip: false), icon: const Icon(Icons.drive_folder_upload_outlined), label: Text(S.esportaCartella)),
          OutlinedButton.icon(onPressed: pi == null ? null : () => _export(zip: true), icon: const Icon(Icons.archive_outlined), label: Text(S.esportaZip)),
          if (Platform.isAndroid)
            OutlinedButton.icon(onPressed: pi == null ? null : () => _export(zip: true, share: true), icon: const Icon(Icons.share_outlined), label: Text(S.condividi)),
        ],
      ),
    );
  }

  /// One of the three steps: a neutral pill, filled once the step is done.
  Widget _stepChip(String label, {required bool done}) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: done ? Palette.fg.withValues(alpha: 0.12) : Palette.fg.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: done ? Palette.text : Palette.text2)),
      );

  Widget _stat(String k, String v, {bool warn = false}) => Row(mainAxisSize: MainAxisSize.min, children: [
        Text('$k ', style: TextStyle(fontSize: 12, color: Palette.text3)),
        Text(v, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: warn ? Palette.warn : Palette.text)),
      ]);

  void _details(PackInfo pi) {
    showAppDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(S.dettagliMapping),
        content: SizedBox(
          width: 520,
          height: 420,
          child: ListView(children: [
            if (pi.notes.isNotEmpty) ...[SectionTitle(S.note), for (final n in pi.notes) Text('• $n')],
            if (pi.missingDrawables.isNotEmpty) ...[
              const SizedBox(height: 10),
              SectionTitle(S.drawableAppfilterXmlSenzaIcona),
              for (final d in pi.missingDrawables) Text(d, style: const TextStyle(fontFamily: 'Consolas', fontSize: 12)),
            ],
            if (pi.unmappedIcons.isNotEmpty) ...[
              const SizedBox(height: 10),
              SectionTitle(S.iconeNonReferenziate),
              Text(pi.unmappedIcons.join(', '), style: TextStyle(fontSize: 12, color: Palette.text2)),
            ],
          ]),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: Text(S.chiudi))],
      ),
    );
  }
}
