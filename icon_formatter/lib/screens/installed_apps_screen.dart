import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../app/state.dart';
import '../app/storage.dart';
import '../app/theme.dart';
import '../services/app_lists.dart';
import '../services/export_service.dart';
import '../services/platform_service.dart';
import '../src/rust/api/engine.dart';
import '../widgets/common.dart';
import '../widgets/liquid_glass.dart';
import '../workspace/adjust_panel.dart';
import '../workspace/workspace_controller.dart';
import '../workspace/workspace_view.dart';
import '../l10n/strings.dart';

enum AppPipeline { original, translucent, preset }

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
  bool hideSystem = false;
  bool onlyUnprocessed = false;
  bool loading = true;
  String? error;
  final _scroll = ScrollController();
  final _search = TextEditingController();

  /// Name of the icon pack the launcher uses (the list shows its icons).
  String? activePack;
  AppPipeline pipeline = AppPipeline.translucent;

  // AI sequential run

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _scroll.dispose();
    _search.dispose();
    c.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      // by name: the system lists them in no fixed order (no install time to sort by)
      final list = [...await PlatformService.listApps(includeSystem: true)]..sort((a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()));
      final pack = await PlatformService.activeIconPack().catchError((_) => null);
      setState(() {
        apps = list;
        activePack = pack?['label'] as String?;
        loading = false;
      });
      // icons in chunks, UI stays responsive
      for (var i = 0; i < list.length; i += 24) {
        final chunk = list.sublist(i, (i + 24).clamp(0, list.length));
        final icons = await PlatformService.getIcons(chunk, size: 144, glyphOnly: false, activePack: true);
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
          if (mounted) showMsg(context, S.iconaNonDisponibile(a.label), error: true);
          return;
        }
        glyph[a.key] = b;
      }
      final existing = c.items.where((i) => i.id == a.key);
      if (existing.isEmpty) c.addItem(_itemFor(a, b));
      c.select(a.key);
      if (!mounted) return;
      await showAppSheet(
        context: context,
        isScrollControlled: true,
        builder: (ctx) => SizedBox(
          height: MediaQuery.of(ctx).size.height * 0.85,
          child: Column(
            children: [
              SizedBox(
                height: 300,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: PreviewPane(c: c, compact: true),
                ),
              ),
              Expanded(
                child: AdjustPanel(c: c, showModes: true, onOpenBases: widget.onOpenBases),
              ),
            ],
          ),
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

  /// "Liste": saved selections of apps. Loading one replaces the selection.
  Future<void> _lists() async {
    await showAppSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) {
          final lists = AppState.I.appLists;
          void changed() => setS(() {});
          return SingleChildScrollView(
            padding: const EdgeInsets.only(bottom: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(padding: const EdgeInsets.fromLTRB(22, 0, 22, 8), child: Text(S.pack3ListeTitolo, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: Palette.text))),
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 22),
                  leading: const Icon(Icons.bookmark_add_outlined),
                  title: Text(S.pack3ListaSalvaSelezione),
                  onTap: () async {
                    if (selected.isEmpty) {
                      showMsg(context, S.pack3ListaSelezioneVuota);
                      return;
                    }
                    final name = await askText(context, S.pack3ListaSalvaCome);
                    if (name == null || name.trim().isEmpty) return;
                    final list = AppState.I.appLists.addList(name: name, packages: {...selected});
                    AppState.I.update();
                    if (mounted) showMsg(context, S.pack3ListaSalvata(list.name));
                    changed();
                  },
                ),
                if (lists.isEmpty) Padding(padding: const EdgeInsets.fromLTRB(22, 8, 22, 16), child: Text(S.pack3ListaVuota, style: TextStyle(color: Palette.text2))),
                for (final l in lists)
                  ListTile(
                    contentPadding: const EdgeInsets.only(left: 22, right: 8),
                    title: Text(l.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text(S.pack3ListaN(l.packages.length), style: TextStyle(fontSize: 12, color: Palette.text3)),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: S.pack3ListaCarica,
                          icon: const Icon(Icons.playlist_add_check_rounded),
                          onPressed: () {
                            // only the apps still installed are selected
                            final known = {for (final a in apps) a.key};
                            setState(() {
                              selected
                                ..clear()
                                ..addAll(l.packages.where(known.contains));
                            });
                            Navigator.pop(ctx);
                            showMsg(context, S.pack3ListaCaricata(l.name));
                          },
                        ),
                        IconButton(
                          tooltip: S.pack3ListaRinomina,
                          icon: const Icon(Icons.drive_file_rename_outline),
                          onPressed: () async {
                            final name = await askText(context, S.pack3ListaRinominaTitolo, initial: l.name);
                            if (name == null) return;
                            AppState.I.update(() => AppState.I.appLists.renameList(l.id, name));
                            changed();
                          },
                        ),
                        IconButton(
                          tooltip: S.elimina,
                          icon: const Icon(Icons.delete_outline_rounded),
                          onPressed: () async {
                            final ok = await confirm(context, S.pack3ListaEliminaConferma(l.name), S.pack3ListaEliminaCorpo, ok: S.elimina);
                            if (!ok) return;
                            AppState.I.update(() => AppState.I.appLists.deleteList(l.id));
                            changed();
                          },
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _process() async {
    final list = apps.where((a) => selected.contains(a.key)).toList();
    if (list.isEmpty) {
      showMsg(context, S.selezionaAlmenoApp);
      return;
    }
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
    if (mounted && skipped > 0) showMsg(context, S.appSenzaIconaLeggibileSono(skipped));
  }

  Future<void> _exportPack({required String kind}) async {
    final done = c.items.where((i) => i.outputPath != null && File(i.outputPath!).existsSync()).toList();
    if (done.isEmpty) {
      showMsg(context, S.nessunaIconaElaborataAvviaPrima, error: true);
      return;
    }
    try {
      final dir = await AppPaths.I.workDir('iconpack');
      final name = S.iconformatterPack(DateTime.now().millisecondsSinceEpoch ~/ 1000);
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
      if (res != null && mounted) showMsg(context, S.iconeAppfilterXmlGenerato(res.message, r.icons));
    } catch (e) {
      if (mounted) showMsg(context, S.exportNonRiuscito(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (!Platform.isAndroid) return const SizedBox.shrink();
    final list = filtered;
    final accent = Theme.of(context).colorScheme.primary;
    final under = GlassInsets.of(context);
    // the shell's SafeArea already removed it from MediaQuery: read the view
    final view = View.of(context);
    final statusBar = view.padding.top / view.devicePixelRatio;
    return SafeArea(
      bottom: false,
      child: Stack(
        // the list slides up under the status bar (no cut at the safe area)
        clipBehavior: Clip.none,
        children: [
          // title, search and filters scroll away with the icons, so the grid
          // gets the whole screen
          CustomScrollView(
            controller: _scroll,
            // the icons slide up under the status bar instead of being cut
            // at the safe-area edge (no offscreen mask: stays at 120 fps)
            clipBehavior: Clip.none,
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                  child: LargeHeader(
                    S.leTueApp,
                    actions: [
                      GlassIconButton(
                        tooltip: S.regolazioni,
                        icon: Icons.tune,
                        label: S.stile,
                        onPressed: () => showAppSheet(
                          context: context,
                          isScrollControlled: true,
                          showDragHandle: true,
                          // the style (what the apps become) first, then its adjustments
                          builder: (ctx) => StatefulBuilder(
                            builder: (ctx, setS) => SizedBox(
                              height: MediaQuery.of(ctx).size.height * 0.80,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Padding(
                                    padding: EdgeInsets.fromLTRB(20, 0, 20, 4),
                                    child: Text(
                                      S.stileTitolo,
                                      style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: Palette.text),
                                    ),
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 12),
                                    child: ChoiceRows<AppPipeline>(
                                      options: [
                                        (AppPipeline.translucent, S.traslucido),
                                        (AppPipeline.original, S.originalComposition),
                                        (AppPipeline.preset, S.customPreset),
                                        ],
                                      value: pipeline,
                                      onChanged: (v) {
                                        setState(() => pipeline = v);
                                        setS(() {});
                                      },
                                    ),
                                  ),
                                  Expanded(
                                      child: AdjustPanel(c: c, showModes: false, onOpenBases: widget.onOpenBases),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              // the search stays at the top while the icons scroll under it
              SliverPinnedSearch(
                // the bars sit close together; the icons get a bit more air below them
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
                child: TextField(controller: _search, decoration: pillSearchDecoration(context, S.cercaNomeOPackage), onChanged: (v) => setState(() => query = v)),
              ),
              SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // filters fit on screen (nothing hidden off the edge)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
                      // two equal toggles, edge to edge
                      child: Row(
                        children: [
                          Expanded(
                            child: ChoicePill(label: S.mostraAppSistema, on: !hideSystem, onTap: () => setState(() => hideSystem = !hideSystem)),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: ChoicePill(label: S.soloNonElaborate, on: onlyUnprocessed, onTap: () => setState(() => onlyUnprocessed = !onlyUnprocessed)),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              loading
                  ? const SliverFillRemaining(hasScrollBody: false, child: Center(child: CircularProgressIndicator()))
                  : error != null
                  ? SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(S.impossibileLeggereApp(error), style: TextStyle(color: Palette.danger)),
                      ),
                    )
                  : ListenableBuilder(
                      listenable: c,
                      builder: (context, _) {
                        // one lookup table per build (not a scan per cell)
                        final byId = {for (final x in c.items) x.id: x};
                        return SliverPadding(
                          padding: EdgeInsets.fromLTRB(20, 16, 20, under + 200),
                          sliver: SliverGrid.builder(
                            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 120, mainAxisExtent: 150, mainAxisSpacing: 8, crossAxisSpacing: 8),
                            itemCount: list.length,
                            itemBuilder: (context, i) {
                              final a = list[i];
                              final it = byId[a.key];
                              final out = it?.outputPath;
                              final res = it?.result;
                              final sel = selected.contains(a.key);
                              Color? dot;
                              if (res != null) dot = !res.ok ? Palette.danger : (res.ambiguous ? Palette.warn : Palette.ok);
                              void toggle() => setState(() => sel ? selected.remove(a.key) : selected.add(a.key));
                              final status = a.isSystem ? S.pbSistema : (AppState.I.processedPackages.contains(a.key) ? S.elaborataBreve : '');
                              // same card as in Pack: the icon large on its own
                              // tile, name and state centred under it
                              return Tile(
                                padding: const EdgeInsets.all(6),
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(12),
                                  onTap: toggle,
                                  onLongPress: () => _preview(a),
                                  child: Column(
                                    children: [
                                      Expanded(
                                        child: AnimatedContainer(
                                          duration: const Duration(milliseconds: 150),
                                          decoration: BoxDecoration(
                                            color: sel ? accent.withValues(alpha: 0.16) : (nothingStyle ? NothingColors.raised : Palette.fg.withValues(alpha: 0.04)),
                                            borderRadius: BorderRadius.circular(14),
                                            border: Border.all(color: sel ? accent.withValues(alpha: 0.7) : Colors.transparent, width: 1.5),
                                          ),
                                          child: Stack(
                                            children: [
                                              Positioned.fill(
                                                child: Padding(
                                                  padding: const EdgeInsets.all(12),
                                                  child: out != null
                                                      ? IconImage(key: ValueKey(out + res.hashCode.toString()), path: out)
                                                      : missingIcons.contains(a.key)
                                                      ? Icon(Icons.hide_image_outlined, color: Palette.text3)
                                                      : display[a.key] != null
                                                      ? IconImage(bytes: display[a.key])
                                                      : const Center(child: SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 1.5))),
                                                ),
                                              ),
                                              Positioned(
                                                left: 6,
                                                top: 6,
                                                child: Icon(
                                                  sel ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                                                  size: 20,
                                                  color: sel ? accent : Palette.text3,
                                                ),
                                              ),
                                              if (dot != null) Positioned(right: 6, top: 6, child: StatusDot(color: dot)),
                                            ],
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      Text(a.label, maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500, color: Palette.text)),
                                      Text(status, maxLines: 1, style: TextStyle(fontSize: 11, color: Palette.text3)),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                        );
                      },
                    ),
            ],
          ),
          // soft dark fade under the status bar: what scrolls up there stays
          // readable behind the clock and fades out instead of being cut
          Positioned(
            left: 0,
            right: 0,
            top: -statusBar,
            height: statusBar + 28,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    // fully opaque from the screen top down to the pinned search
                    // (translucent glass cells showed through the status bar), then
                    // a short fade
                    colors: [Palette.bg, Palette.bg, Palette.bg.withValues(alpha: 0)],
                    stops: [0.0, statusBar / (statusBar + 28), 1.0],
                  ),
                ),
              ),
            ),
          ),
          // progress / completion floats right under the status bar (nothing
          // moves); a sideways swipe removes it
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: ListenableBuilder(
                listenable: c.batch,
                builder: (context, _) {
                  final b = c.batch;
                  if (b.total == 0) return const SizedBox.shrink();
                  return ProgressStrip(
                    done: b.done,
                    total: b.total,
                    errors: b.errors,
                    running: b.running,
                    onCancel: b.cancel,
                    label: b.cancelled ? S.annullato : (b.running && b.phase != null ? b.phase : null),
                    onDismiss: b.dismissProgress,
                  );
                },
              ),
            ),
          ),
          if (MediaQuery.viewInsetsOf(context).bottom == 0) JumpButtonsSlot(controller: _scroll, openBottom: under + 76, foldedBottom: MediaQuery.viewPaddingOf(context).bottom + 74),
      // floating liquid-glass action bar (content scrolls underneath);
          // hidden while the keyboard is open, so it never covers the filters
          if (MediaQuery.viewInsetsOf(context).bottom == 0)
            FloatingBarSlot(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // one start button; exports in "Altro" (tap or drag the bar up)
                  ActionBar(
                    // how many are selected, and select all / none, under the
                    // thumb next to the start button
                    // select all / none with the count, on the same row as
                    // the start button
                    leading: Tooltip(
                      message: '${S.appSelezionate(list.length, selected.length)} · ${S.toccaSelezionareTieniPremutoAnteprima}',
                      child: OutlinedButton(
                        key: const ValueKey('apps-select-all'),
                        style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 14), minimumSize: const Size(0, kButtonHeight)),
                        onPressed: list.isEmpty
                            ? null
                            : () => setState(() {
                                final all = list.every((a) => selected.contains(a.key));
                                all ? selected.removeAll(list.map((a) => a.key)) : selected.addAll(list.map((a) => a.key));
                              }),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(list.isNotEmpty && list.every((a) => selected.contains(a.key)) ? Icons.check_box_rounded : Icons.check_box_outline_blank_rounded, size: 20),
                          const SizedBox(width: 6),
                          Text('${selected.length}', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                        ]),
                      ),
                    ),
                    compactLeading: Tooltip(
                      message: S.selezionaTutte,
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(padding: EdgeInsets.zero, minimumSize: Size.zero, shape: const CircleBorder()),
                        onPressed: list.isEmpty
                            ? null
                            : () => setState(() {
                                final all = list.every((a) => selected.contains(a.key));
                                all ? selected.removeAll(list.map((a) => a.key)) : selected.addAll(list.map((a) => a.key));
                              }),
                        child: Icon(list.isNotEmpty && list.every((a) => selected.contains(a.key)) ? Icons.check_box_rounded : Icons.check_box_outline_blank_rounded, size: 22),
                      ),
                    ),
                    compactPrimary: ListenableBuilder(
                      listenable: c.batch,
                      builder: (context, _) => Tooltip(
                        message: selected.isEmpty ? S.selezionaLeApp : S.elaboraApp(selected.length),
                        child: FilledButton(
                          style: FilledButton.styleFrom(minimumSize: Size.zero, padding: EdgeInsets.zero),
                          onPressed: c.batch.running || selected.isEmpty ? null : _process,
                          child: const Icon(Icons.play_arrow_rounded, size: 26),
                        ),
                      ),
                    ),
                    primary: ListenableBuilder(
                      listenable: c.batch,
                      builder: (context, _) => FilledButton.icon(
                        key: const ValueKey('apps-start'),
                        onPressed: c.batch.running || selected.isEmpty ? null : _process,
                        icon: const Icon(Icons.play_arrow_rounded),
                        // one line in the bar, whatever the count
                        label: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(selected.isEmpty ? S.selezionaLeApp : S.elaboraApp(selected.length), maxLines: 1, style: const TextStyle(fontSize: 16)),
                        ),
                      ),
                    ),
                    more: [
                      MoreAction(Icons.refresh_rounded, S.ricarica, S.ricaricaSub, loading ? null : _load),
                      MoreAction(Icons.list_alt_rounded, S.pack3Liste, S.pack3ListeSub, _lists),
                      MoreAction(Icons.folder_zip_outlined, S.iconPackZipAppfilterXml, S.esportaZipSub, () => _exportPack(kind: 'zip')),
                      MoreAction(Icons.drive_folder_upload_outlined, S.iconPackCartella, S.esportaCartellaSub, () => _exportPack(kind: 'folder')),
                      MoreAction(Icons.image_outlined, S.soloPngIndividuali, S.esportaCartellaSub, () => _exportPack(kind: 'png')),
                      MoreAction(Icons.share_outlined, S.condividiZip, S.condividiSub, () => _exportPack(kind: 'share')),
                    ],
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Full-width on/off pill (filters of the apps list).
