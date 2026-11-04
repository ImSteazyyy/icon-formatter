import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../app/state.dart';
import '../app/storage.dart';
import '../app/theme.dart';
import '../services/ai_service.dart';
import '../services/export_service.dart';
import '../services/platform_service.dart';
import '../src/rust/api/engine.dart';
import '../widgets/common.dart';
import '../widgets/liquid_glass.dart';
import '../workspace/adjust_panel.dart';
import '../workspace/workspace_controller.dart';
import '../workspace/workspace_view.dart';

enum AppPipeline { original, translucent, preset, ai }

/// Installed Apps / App Icon Scanner. Android only: never built into the
/// Windows navigation (see shell.dart).
class InstalledAppsScreen extends StatefulWidget {
  const InstalledAppsScreen({super.key, required this.onOpenBases});

  final VoidCallback onOpenBases;

  @override
  State<InstalledAppsScreen> createState() => _InstalledAppsScreenState();
}

class _InstalledAppsScreenState extends State<InstalledAppsScreen> with AutomaticKeepAliveClientMixin {
  final c = WorkspaceController(tag: 'apps', mode: StudioMode.translucent);
  List<InstalledApp> apps = [];
  final Map<String, Uint8List?> display = {};
  final Map<String, Uint8List> glyph = {};
  final Set<String> selected = {};
  final Set<String> missingIcons = {};
  String query = '';
  bool hideSystem = true;
  bool onlyUnprocessed = false;
  bool loading = true;
  String? error;
  AppPipeline pipeline = AppPipeline.translucent;

  // AI sequential run
  bool aiRunning = false;
  bool aiCancel = false;
  int aiDone = 0, aiTotal = 0, aiErrors = 0;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    c.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final list = await PlatformService.listApps(includeSystem: true);
      setState(() {
        apps = list;
        loading = false;
      });
      // icons in chunks, UI stays responsive
      for (var i = 0; i < list.length; i += 24) {
        final chunk = list.sublist(i, (i + 24).clamp(0, list.length));
        final icons = await PlatformService.getIcons(chunk, size: 144, glyphOnly: false);
        if (!mounted) return;
        setState(() {
          for (var k = 0; k < chunk.length; k++) {
            display[chunk[k].key] = icons[k];
            if (icons[k] == null) missingIcons.add(chunk[k].key);
          }
        });
      }
    } catch (e) {
      setState(() {
        loading = false;
        error = e.toString();
      });
    }
  }

  List<InstalledApp> get filtered {
    final q = query.toLowerCase();
    return apps.where((a) {
      if (hideSystem && a.isSystem) return false;
      if (onlyUnprocessed && AppState.I.processedPackages.contains(a.key)) return false;
      if (q.isNotEmpty && !a.label.toLowerCase().contains(q) && !a.package.toLowerCase().contains(q)) return false;
      return true;
    }).toList();
  }

  WorkItem _itemFor(InstalledApp a, Uint8List bytes) => WorkItem(
        id: a.key,
        name: sanitizeDrawableName(name: a.activity.isEmpty ? a.package : '${a.package}_${a.activity.split('.').last}'),
        rel: a.package,
        bytes: bytes,
        label: a.label,
        package: a.package,
        activity: a.activity,
      );

  Future<void> _preview(InstalledApp a) async {
    try {
      var b = glyph[a.key];
      if (b == null) {
        final r = await PlatformService.getIcons([a], size: 432);
        b = r.first;
        if (b == null) {
          if (mounted) showMsg(context, 'Icona non disponibile per ${a.label}', error: true);
          return;
        }
        glyph[a.key] = b;
      }
      final existing = c.items.where((i) => i.id == a.key);
      if (existing.isEmpty) c.addItem(_itemFor(a, b));
      c.select(a.key);
      if (!mounted) return;
      await showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        builder: (ctx) => SizedBox(
          height: MediaQuery.of(ctx).size.height * 0.85,
          child: Column(children: [
            SizedBox(height: 300, child: Padding(padding: const EdgeInsets.all(12), child: PreviewPane(c: c, compact: true))),
            Expanded(child: AdjustPanel(c: c, showModes: pipeline != AppPipeline.ai, onOpenBases: widget.onOpenBases)),
          ]),
        ),
      );
    } catch (e) {
      if (mounted) showMsg(context, '$e', error: true);
    }
  }

  Future<List<WorkItem>> _prepare(List<InstalledApp> list) async {
    final need = list.where((a) => !glyph.containsKey(a.key)).toList();
    for (var i = 0; i < need.length; i += 16) {
      final chunk = need.sublist(i, (i + 16).clamp(0, need.length));
      final icons = await PlatformService.getIcons(chunk, size: 432);
      for (var k = 0; k < chunk.length; k++) {
        if (icons[k] != null) glyph[chunk[k].key] = icons[k]!;
      }
    }
    final items = <WorkItem>[];
    for (final a in list) {
      final b = glyph[a.key];
      if (b == null) continue;
      var it = c.items.where((i) => i.id == a.key).firstOrNull;
      if (it == null) {
        it = _itemFor(a, b);
        c.addItem(it);
      }
      items.add(it);
    }
    return items;
  }

  Future<void> _process() async {
    final list = apps.where((a) => selected.contains(a.key)).toList();
    if (list.isEmpty) {
      showMsg(context, 'Seleziona almeno un\'app');
      return;
    }
    if (pipeline == AppPipeline.ai) return _processAi(list);
    c.mode = switch (pipeline) {
      AppPipeline.original => StudioMode.original,
      AppPipeline.preset => StudioMode.preset,
      _ => StudioMode.translucent,
    };
    final items = await _prepare(list);
    final skipped = list.length - items.length;
    await c.process(only: items);
    final ok = items.where((i) => i.result?.ok == true).map((i) => i.id);
    AppState.I.update(() => AppState.I.processedPackages.addAll(ok));
    if (mounted && skipped > 0) showMsg(context, '$skipped app senza icona leggibile sono state saltate');
  }

  Future<void> _processAi(List<InstalledApp> list) async {
    if (!await AiService.isConfigured()) {
      if (mounted) showMsg(context, 'AI non configurata: imposta provider e API key in Impostazioni.', error: true);
      return;
    }
    if (!mounted) return;
    final ok = await confirm(
      context,
      'Generare ${list.length} icone con AI?',
      'Ogni icona è una richiesta a pagamento al provider (${aiProviders[AppState.I.ai.provider]!.name}). '
          '${aiProviders[AppState.I.ai.provider]!.costNote}',
      ok: 'Genera',
    );
    if (!ok) return;
    final items = await _prepare(list);
    c.outputDir ??= await AppPaths.I.outputSession('apps');
    final themePrompt = aiThemes.values.first;
    setState(() {
      aiRunning = true;
      aiCancel = false;
      aiDone = 0;
      aiErrors = 0;
      aiTotal = items.length;
    });
    for (final it in items) {
      if (aiCancel) break;
      try {
        final full = display[it.id] ?? it.bytes!;
        final png = await AiService.generate(references: [full], prompt: AiService.buildPrompt(theme: themePrompt, regeneration: false));
        final out = p.join(c.outputDir!, '${it.name}.png');
        // normalise through the Rust compositor: isolate + calibrated size
        final composed = await previewBytes(bytes: png, settings: c.settingsForItem(it));
        await File(out).writeAsBytes(composed.png);
        it.result = ItemResult(id: it.id, name: it.name, ok: true, output: out, ambiguous: composed.ambiguous, confidence: composed.confidence, method: 'ai+${composed.method}', notes: composed.notes);
        AppState.I.update(() => AppState.I.processedPackages.add(it.id));
      } catch (e) {
        aiErrors++;
        it.result = ItemResult(id: it.id, name: it.name, ok: false, error: e.toString(), ambiguous: true, confidence: 0, method: 'ai', notes: const []);
      }
      if (!mounted) return;
      setState(() => aiDone++);
      c.notify();
    }
    if (mounted) setState(() => aiRunning = false);
  }

  Future<void> _exportPack({required String kind}) async {
    final done = c.items.where((i) => i.outputPath != null && File(i.outputPath!).existsSync()).toList();
    if (done.isEmpty) {
      showMsg(context, 'Nessuna icona elaborata: avvia prima l\'elaborazione', error: true);
      return;
    }
    try {
      final dir = await AppPaths.I.workDir('iconpack');
      final name = 'IconFormatter_pack_${DateTime.now().millisecondsSinceEpoch ~/ 1000}';
      final r = await buildIconPack(
        apps: [for (final i in done) IconPackApp(label: i.label ?? i.name, package: i.package!, activity: i.activity ?? '', png: i.outputPath!)],
        outDir: dir,
        packName: name,
      );
      ExportResult? res;
      switch (kind) {
        case 'zip':
          res = await ExportService.exportDir(dir, name: name, zip: true);
        case 'folder':
          res = await ExportService.exportDir(dir, name: name, zip: false);
        case 'png':
          res = await ExportService.exportDir(p.join(dir, 'icons'), name: '${name}_png', zip: false);
        case 'share':
          await ExportService.shareDirAsZip(dir, name);
      }
      if (res != null && mounted) showMsg(context, '${res.message} · ${r.icons} icone, appfilter.xml generato');
    } catch (e) {
      if (mounted) showMsg(context, 'Export non riuscito: $e', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (!Platform.isAndroid) return const SizedBox.shrink();
    final list = filtered;
    final accent = Theme.of(context).colorScheme.primary;
    final under = GlassInsets.of(context);
    return SafeArea(
      bottom: false,
      child: Stack(children: [
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
          child: Row(children: [
            Expanded(child: Text('App installate', style: Theme.of(context).textTheme.titleLarge)),
            IconButton(tooltip: 'Ricarica', onPressed: loading ? null : _load, icon: const Icon(Icons.refresh)),
            PopupMenuButton<String>(
              tooltip: 'Esporta icon pack',
              icon: const Icon(Icons.ios_share),
              onSelected: (k) => _exportPack(kind: k),
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'zip', child: Text('Icon pack ZIP (appfilter.xml)')),
                PopupMenuItem(value: 'folder', child: Text('Icon pack in cartella')),
                PopupMenuItem(value: 'png', child: Text('Solo PNG individuali')),
                PopupMenuItem(value: 'share', child: Text('Condividi ZIP')),
              ],
            ),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: TextField(
            decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Cerca per nome o package'),
            onChanged: (v) => setState(() => query = v),
          ),
        ),
        SizedBox(
          height: 48,
          child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), children: [
            FilterChip(label: const Text('Escludi app di sistema'), selected: hideSystem, onSelected: (v) => setState(() => hideSystem = v)),
            const SizedBox(width: 8),
            FilterChip(label: const Text('Solo non elaborate'), selected: onlyUnprocessed, onSelected: (v) => setState(() => onlyUnprocessed = v)),
            const SizedBox(width: 8),
            ActionChip(label: const Text('Seleziona tutte'), onPressed: () => setState(() => selected.addAll(list.map((a) => a.key)))),
            const SizedBox(width: 8),
            ActionChip(label: const Text('Deseleziona'), onPressed: () => setState(() => selected.removeAll(list.map((a) => a.key)))),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(children: [
            Tooltip(
              message: 'Tocca per selezionare · tieni premuto per anteprima e correzioni',
              child: Text('${list.length} app · ${selected.length} selezionate', style: const TextStyle(fontSize: 12, color: Palette.text2)),
            ),
            const Spacer(),
            DropdownButton<AppPipeline>(
              value: pipeline,
              underline: const SizedBox.shrink(),
              items: const [
                DropdownMenuItem(value: AppPipeline.original, child: Text('Original Composition')),
                DropdownMenuItem(value: AppPipeline.translucent, child: Text('Nothing Translucent')),
                DropdownMenuItem(value: AppPipeline.preset, child: Text('Custom Preset')),
                DropdownMenuItem(value: AppPipeline.ai, child: Text('AI Icon Theme')),
              ],
              onChanged: (v) => setState(() => pipeline = v!),
            ),
          ]),
        ),
        Expanded(
          child: loading
              ? const Center(child: CircularProgressIndicator())
              : error != null
                  ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text('Impossibile leggere le app: $error', style: const TextStyle(color: Palette.danger))))
                  : ListenableBuilder(
                      listenable: c,
                      builder: (context, _) => GridView.builder(
                        padding: EdgeInsets.fromLTRB(12, 8, 12, under + 160),
                        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 100, mainAxisSpacing: 8, crossAxisSpacing: 8, childAspectRatio: 0.72),
                        itemCount: list.length,
                        itemBuilder: (context, i) {
                          final a = list[i];
                          final it = c.items.where((x) => x.id == a.key).firstOrNull;
                          final out = it?.outputPath;
                          final res = it?.result;
                          final sel = selected.contains(a.key);
                          Color? dot;
                          if (res != null) dot = !res.ok ? Palette.danger : (res.ambiguous ? Palette.warn : Palette.ok);
                          return GestureDetector(
                            onTap: () => setState(() => sel ? selected.remove(a.key) : selected.add(a.key)),
                            onLongPress: () => _preview(a),
                            child: Container(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(14),
                                color: sel ? accent.withValues(alpha: 0.10) : Colors.white.withValues(alpha: 0.025),
                                border: Border.all(color: sel ? accent.withValues(alpha: 0.6) : Colors.white.withValues(alpha: 0.06)),
                              ),
                              padding: const EdgeInsets.all(6),
                              child: Column(children: [
                                Expanded(
                                  child: Stack(children: [
                                    Positioned.fill(
                                      child: out != null
                                          ? IconImage(key: ValueKey(out + res.hashCode.toString()), path: out)
                                          : missingIcons.contains(a.key)
                                              ? const Icon(Icons.hide_image_outlined, color: Palette.text3)
                                              : display[a.key] != null
                                                  ? IconImage(bytes: display[a.key])
                                                  : const Center(child: SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 1.5))),
                                    ),
                                    Positioned(left: -6, top: -6, child: Checkbox(visualDensity: VisualDensity.compact, value: sel, onChanged: (v) => setState(() => v! ? selected.add(a.key) : selected.remove(a.key)))),
                                    if (dot != null) Positioned(right: 0, top: 0, child: StatusDot(color: dot)),
                                  ]),
                                ),
                                Text(a.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11)),
                                Text(a.isSystem ? 'sistema' : (AppState.I.processedPackages.contains(a.key) ? 'elaborata' : ''), style: const TextStyle(fontSize: 9, color: Palette.text3)),
                              ]),
                            ),
                          );
                        },
                      ),
                    ),
        ),
      ]),
      // floating liquid-glass action bar (content scrolls underneath)
      Positioned(
        left: 12,
        right: 12,
        bottom: under - 4, // the nav box includes 12dp of top padding
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          ListenableBuilder(
            listenable: c.batch,
            builder: (context, _) {
              final b = c.batch;
              if (aiRunning || aiTotal > 0) {
                return ProgressStrip(done: aiDone, total: aiTotal, errors: aiErrors, running: aiRunning, label: 'AI', onCancel: () => setState(() => aiCancel = true));
              }
              if (b.total == 0) return const SizedBox.shrink();
              return ProgressStrip(
                done: b.done,
                total: b.total,
                errors: b.errors,
                running: b.running,
                onCancel: b.cancel,
                label: b.cancelled ? 'Annullato' : (b.running && b.phase != null ? b.phase : null),
              );
            },
          ),
          const SizedBox(height: 6),
          LiquidGlass(
            radius: 32,
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
            child: Row(children: [
              IconButton.filledTonal(
                tooltip: 'Regolazioni',
                onPressed: () => showModalBottomSheet(
                  context: context,
                  isScrollControlled: true,
                  builder: (ctx) => SizedBox(height: MediaQuery.of(ctx).size.height * 0.78, child: AdjustPanel(c: c, showModes: false, onOpenBases: widget.onOpenBases)),
                ),
                icon: const Icon(Icons.tune),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ListenableBuilder(
                  listenable: c.batch,
                  builder: (context, _) => FilledButton.icon(
                    style: FilledButton.styleFrom(shape: const StadiumBorder()),
                    onPressed: c.batch.running || aiRunning || selected.isEmpty ? null : _process,
                    icon: const Icon(Icons.play_arrow_rounded),
                    label: Text('Elabora ${selected.length} app'),
                  ),
                ),
              ),
            ]),
          ),
        ]),
      ),
      ]),
    );
  }
}
