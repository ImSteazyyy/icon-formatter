import 'dart:io';

import 'package:flutter/material.dart';

import '../app/theme.dart';
import '../services/export_service.dart';
import '../widgets/common.dart';
import '../widgets/glass_menu.dart';
import '../widgets/liquid_glass.dart';
import 'adjust_panel.dart';
import 'workspace_controller.dart';
import '../l10n/strings.dart';
import '../src/rust/api/engine.dart';

/// Grid tile with source or processed icon and status.
class WorkTile extends StatelessWidget {
  const WorkTile({super.key, required this.c, required this.it, this.selectable = false, this.checked = false, this.onCheck});

  final WorkspaceController c;
  final WorkItem it;
  final bool selectable;
  final bool checked;
  final ValueChanged<bool>? onCheck;

  @override
  Widget build(BuildContext context) {
    final sel = c.selectedId == it.id;
    final r = it.result;
    final out = it.outputPath;
    Color? dot;
    String tip = S.nonElaborata;
    if (r != null) {
      if (!r.ok) {
        dot = Palette.danger;
        tip = r.error ?? S.errore4;
      } else if (r.ambiguous) {
        dot = Palette.warn;
        tip = S.verificare(r.notes.join('; '));
      } else {
        dot = Palette.ok;
        tip = S.ok(r.method);
      }
    }
    final accent = Theme.of(context).colorScheme.primary;
    return Tooltip(
      message: '${it.label ?? it.rel}\n$tip',
      waitDuration: const Duration(milliseconds: 600),
      child: GestureDetector(
        onTap: () => c.select(it.id),
        onDoubleTap: () => showZoom(context, path: out ?? it.path, bytes: out == null ? it.bytes : null, title: it.label ?? it.name),
        onLongPress: () => _menu(context, null),
        onSecondaryTapDown: (d) => _menu(context, d.globalPosition),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            color: sel ? accent.withValues(alpha: 0.10) : Colors.white.withValues(alpha: 0.025),
            border: Border.all(color: sel ? accent.withValues(alpha: 0.7) : Colors.white.withValues(alpha: 0.06)),
          ),
          padding: const EdgeInsets.all(8),
          child: Column(
            children: [
              Expanded(
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: Opacity(
                        opacity: it.excluded ? 0.3 : 1,
                        child: out != null ? IconImage(key: ValueKey('$out${r.hashCode}'), path: out) : IconImage(path: it.path, bytes: it.bytes),
                      ),
                    ),
                    if (dot != null) Positioned(right: 0, top: 0, child: StatusDot(color: dot)),
                    if (it.hasOverride) const Positioned(left: 0, top: 0, child: Icon(Icons.edit, size: 12, color: Palette.text2)),
                    if (selectable)
                      Positioned(
                        left: -8,
                        bottom: -8,
                        child: Checkbox(value: checked, onChanged: (v) => onCheck?.call(v ?? false)),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              Text(
                it.label ?? it.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11, color: it.excluded ? Palette.text3 : Palette.text2, decoration: it.excluded ? TextDecoration.lineThrough : null),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _menu(BuildContext context, Offset? pos) async {
    final items = <PopupMenuEntry<String>>[
      const PopupMenuItem(value: 'zoom', child: Text(S.ingrandisci)),
      PopupMenuItem(value: 'exclude', child: Text(it.excluded ? S.includi : S.escludi)),
      const PopupMenuItem(value: 'redo', child: Text(S.rielaboraQuestaIcona)),
      const PopupMenuItem(value: 'mode', child: Text(S.rigeneraConModalita)),
      PopupMenuItem(value: 'white', child: Text(c.keepsInnerWhite(it) ? S.togliBiancoInterno : S.mantieniBiancoInterno)),
      if (it.hasOverride) const PopupMenuItem(value: 'reset', child: Text(S.rimuoviCorrezioni)),
      const PopupMenuItem(value: 'remove', child: Text(S.rimuoviDallaLista)),
    ];
    String? v;
    if (pos != null) {
      v = await showMenu<String>(context: context, position: RelativeRect.fromLTRB(pos.dx, pos.dy, pos.dx, pos.dy), items: items);
    } else {
      v = await showModalBottomSheet<String>(
        context: context,
        builder: (ctx) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [for (final e in items.whereType<PopupMenuItem<String>>()) ListTile(title: e.child, onTap: () => Navigator.pop(ctx, e.value))],
          ),
        ),
      );
    }
    switch (v) {
      case 'zoom':
        if (context.mounted) {
          showZoom(context, path: it.outputPath ?? it.path, bytes: it.outputPath == null ? it.bytes : null, title: it.label ?? it.name);
        }
      case 'exclude':
        c.toggleExcluded(it);
      case 'redo':
        c.process(only: [it]);
      case 'white':
        c.setKeepInnerWhite(it, !c.keepsInnerWhite(it));
      case 'mode':
        if (!context.mounted) return;
        final cur = it.strategyOverride ?? LucentStrategy.auto;
        final st = await showModalBottomSheet<LucentStrategy>(
          context: context,
          builder: (ctx) => SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(S.modalitaSimbolo(it.label ?? it.name), style: Theme.of(ctx).textTheme.titleMedium),
                  const SizedBox(height: 4),
                  const Text(S.modalitaSimboloInfo, style: TextStyle(fontSize: 12, color: Palette.text2)),
                  const SizedBox(height: 8),
                  for (final (v, t, d) in const [
                    (LucentStrategy.auto, S.modoAuto, S.modoAutoDesc),
                    (LucentStrategy.plateColor, S.modoColorePiatto, S.modoColorePiattoDesc),
                    (LucentStrategy.fullBleed, S.modoBordoPieno, S.modoBordoPienoDesc),
                    (LucentStrategy.asIs, S.modoNormale, S.modoNormaleDesc),
                    (LucentStrategy.cleanEdge, S.modoSenzaAlone, S.modoSenzaAloneDesc),
                    (LucentStrategy.tile, S.modoPagina, S.modoPaginaDesc),
                  ])
                    ListTile(
                      key: ValueKey('mode-${v.name}'),
                      title: Text(t),
                      subtitle: Text(d),
                      trailing: v == cur ? Icon(Icons.check_rounded, color: Theme.of(ctx).colorScheme.primary) : null,
                      onTap: () => Navigator.pop(ctx, v),
                    ),
                ],
              ),
            ),
          ),
        );
        if (st != null) c.setStrategy(it, st);
      case 'reset':
        c.clearOverrides(it);
      case 'remove':
        c.remove(it);
    }
  }
}

/// Large preview with Before/After, zoom, alpha checkerboard and diagnostics.
class PreviewPane extends StatelessWidget {
  const PreviewPane({super.key, required this.c, this.compact = false});

  final WorkspaceController c;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) {
        final it = c.selected;
        if (it == null) {
          return const Center(
            child: Text(S.selezionaOImportaIcona, style: TextStyle(color: Palette.text3)),
          );
        }
        final info = c.previewInfo;
        final compare = ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: BeforeAfter(
            before: Padding(
              padding: EdgeInsets.all(compact ? 12 : 18),
              child: IconImage(path: it.path, bytes: it.bytes),
            ),
            after: c.previewPng != null
                ? IconImage(bytes: c.previewPng)
                : Center(
                    child: c.previewError != null
                        ? Padding(
                            padding: const EdgeInsets.all(8),
                            child: Text(
                              c.previewError!,
                              maxLines: 4,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: Palette.danger, fontSize: 11),
                            ),
                          )
                        : const CircularProgressIndicator(strokeWidth: 2),
                  ),
          ),
        );
        final zoom = IconButton(
          tooltip: S.ingrandisci,
          icon: const Icon(Icons.zoom_in),
          onPressed: c.previewPng == null ? null : () => showZoom(context, bytes: c.previewPng, title: it.label ?? it.name),
        );
        final save = IconButton(
          tooltip: S.salvaQuestaIconaPng,
          icon: const Icon(Icons.download_outlined),
          onPressed: c.previewPng == null
              ? null
              : () async {
                  final r = await ExportService.saveSingle(c.previewPng!, '${it.name}.png');
                  if (r != null && context.mounted) showMsg(context, '${r.message}${r.location != null ? ': ${r.location}' : ''}');
                },
        );
        if (compact) {
          // phones: Before/After on the left, name, details and buttons on the
          // right, so the list below gets the height
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AspectRatio(aspectRatio: 1, child: compare),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        if (info != null) ...[StatusDot(color: info.ambiguous ? Palette.warn : Palette.ok), const SizedBox(width: 6)],
                        Expanded(
                          child: Text(
                            it.label ?? it.name,
                            key: const ValueKey('preview-name'),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: Palette.text),
                          ),
                        ),
                      ],
                    ),
                    if (info != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        '${info.size}px · ${info.method} · ${(info.confidence * 100).round()}%',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 11.5, color: Palette.text2),
                      ),
                    ],
                    if (info != null && info.ambiguous)
                      const Text(
                        S.risultatoAmbiguoVerifica,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 11, color: Palette.warn),
                      ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        zoom,
                        save,
                        if (c.previewBusy) const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Center(child: AspectRatio(aspectRatio: 1, child: compare)),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                if (info != null) ...[
                  StatusDot(color: info.ambiguous ? Palette.warn : Palette.ok),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      S.pxConfidenza(it.label ?? it.name, info.size, info.method, (info.confidence * 100).round()),
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12, color: Palette.text2),
                    ),
                  ),
                ] else
                  const Spacer(),
                if (c.previewBusy) const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
                zoom,
                save,
              ],
            ),
            if (info != null && (info.ambiguous || info.notes.isNotEmpty))
              Text((info.ambiguous ? S.risultatoAmbiguoVerifica : '') + info.notes.join(' · '), style: TextStyle(fontSize: 11, color: info.ambiguous ? Palette.warn : Palette.text3)),
          ],
        );
      },
    );
  }
}

/// Generic responsive workspace: grid + preview + adjustments.
class WorkspaceView extends StatelessWidget {
  const WorkspaceView({
    super.key,
    required this.c,
    required this.title,
    required this.toolbar,
    required this.bottomActions,
    this.header,
    this.emptyHint,
    this.showModes = true,
    this.onOpenBases,
    this.tileBuilder,
    this.onAdd,
    this.primaryAction,
    this.moreActions = const [],
  });

  /// Phones: round "+" next to Personalizza, shown once the list has icons
  /// (before that the centre button does the same). Gets the button rect.
  final void Function(Rect anchor)? onAdd;

  /// Phones: the one big action of the bottom bar ("Elabora tutte").
  final Widget? primaryAction;

  /// Phones: the other actions, in a sheet opened from "Altro" (tap or drag up).
  final List<MoreAction> moreActions;

  final WorkspaceController c;
  final String title;
  final List<Widget> toolbar;
  final List<Widget> bottomActions;
  final Widget? header;
  final Widget? emptyHint;
  final bool showModes;
  final VoidCallback? onOpenBases;
  final Widget Function(WorkItem it)? tileBuilder;

  /// One-line guide for the current state of the list.
  String _hint() {
    if (c.items.isEmpty) return S.hintVuoto;
    if (c.batch.running) return S.hintInCorso;
    final n = c.processedCount;
    if (n == 0) return S.hintDaElaborare;
    if (n < c.active.length) return S.hintParziale(n, c.active.length);
    return S.hintFatto;
  }

  /// "Stile": every adjustment of the icons, with a title that explains it.
  Future<void> openStyleSheet(BuildContext context) => showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => SizedBox(
      height: MediaQuery.of(ctx).size.height * 0.80,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 0, 20, 4),
            child: Text(
              S.stileTitolo,
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: Palette.text),
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text(S.stileSpiegazione, style: TextStyle(fontSize: 13, color: Palette.text2)),
          ),
          Expanded(
            child: AdjustPanel(c: c, showModes: showModes, onOpenBases: onOpenBases),
          ),
        ],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        final w = box.maxWidth;
        final wide = w >= 1080;
        final medium = w >= 720;
        final grid = _grid(context, medium ? 112 : 92, search: true);
        final progress = ListenableBuilder(
          listenable: c.batch,
          builder: (context, _) {
            final b = c.batch;
            if (b.total == 0 && b.fatal == null) return const SizedBox.shrink();
            return Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Column(
                children: [
                  ProgressStrip(
                    done: b.done,
                    total: b.total,
                    errors: b.errors,
                    running: b.running,
                    onCancel: b.cancel,
                    label: b.cancelled ? S.annullato : (b.running && b.phase != null ? b.phase : null),
                    onDismiss: b.dismissProgress,
                  ),
                  if (b.fatal != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(b.fatal!, style: const TextStyle(color: Palette.danger)),
                    ),
                ],
              ),
            );
          },
        );
        final actions = Wrap(spacing: 8, runSpacing: 8, alignment: WrapAlignment.end, children: bottomActions);
        final head = Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.headlineSmall, maxLines: 1, softWrap: false),
              if (medium) ...[const SizedBox(height: 6), Wrap(spacing: 2, runSpacing: 2, children: toolbar)],
            ],
          ),
        );

        if (wide) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  flex: 5,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      head,
                      ?header,
                      Expanded(
                        child: Glass(padding: const EdgeInsets.all(10), child: grid),
                      ),
                      progress,
                      const SizedBox(height: 10),
                      actions,
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  flex: 5,
                  child: Glass(child: PreviewPane(c: c)),
                ),
                const SizedBox(width: 16),
                SizedBox(
                  width: 360,
                  child: Glass(
                    padding: EdgeInsets.zero,
                    child: AdjustPanel(c: c, showModes: showModes, onOpenBases: onOpenBases),
                  ),
                ),
              ],
            ),
          );
        }
        if (medium) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      head,
                      ?header,
                      SizedBox(
                        height: box.maxHeight * 0.42,
                        child: Glass(child: PreviewPane(c: c)),
                      ),
                      const SizedBox(height: 10),
                      Expanded(
                        child: Glass(padding: const EdgeInsets.all(8), child: grid),
                      ),
                      progress,
                      const SizedBox(height: 8),
                      actions,
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 330,
                  child: Glass(
                    padding: EdgeInsets.zero,
                    child: AdjustPanel(c: c, showModes: showModes, onOpenBases: onOpenBases),
                  ),
                ),
              ],
            ),
          );
        }
        // phone portrait: grid scrolls under floating liquid-glass bars
        final under = GlassInsets.of(context);
        // floating bars line up with the navigation pill (12 dp from the edge)
        final floating = Positioned(
          left: -8,
          right: -8,
          bottom: under - 4, // the nav box includes 12dp of top padding
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // the glass shape clips the scrolling actions, so they disappear
              // along its rounded edge instead of a straight inner line
              if (primaryAction != null)
                ActionBar(primary: primaryAction!, more: moreActions)
              else if (bottomActions.isNotEmpty && onAdd == null)
                LiquidGlass(
                  radius: 30,
                  live: true,
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    clipBehavior: Clip.none,
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                    child: Row(
                      children: [for (final a in bottomActions) Padding(padding: const EdgeInsets.symmetric(horizontal: 4), child: a)],
                    ),
                  ),
                ),
            ],
          ),
        );
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
          // the floating bars reach 8 dp past the page padding to line up with
          // the navigation pill: no clip, or their rounded ends are cut straight
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  LargeHeader(
                    title,
                    // empty list: the centre card explains; then one line of guidance
                    subtitle: c.items.isEmpty ? null : _hint(),
                    // "Aggiungi" (once the list has icons: the empty state has its
                    // own central button) and "Personalizza", equal pills
                    actions: [
                      if (onAdd != null && c.items.isNotEmpty)
                        Builder(
                          builder: (bctx) =>
                              GlassIconButton(key: const ValueKey('studio-add'), tooltip: S.aggiungi, icon: Icons.add_rounded, label: S.aggiungi, onPressed: () => onAdd!(anchorOf(bctx))),
                        ),
                      GlassIconButton(key: const ValueKey('open-style'), tooltip: S.regolazioni, icon: Icons.tune, label: S.stile, onPressed: () => openStyleSheet(context)),
                    ],
                  ),
                  // progress / completion floats over the content right under the
                  // title (nothing moves); a sideways swipe removes it
                  Expanded(
                    child: Stack(
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // chips scroll out to the screen edge (no straight cut at the page padding)
                            if (toolbar.isNotEmpty && onAdd == null)
                              SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                clipBehavior: Clip.none,
                                child: Row(children: toolbar),
                              ),
                            ?header,
                            // the preview appears once there is something to show
                            if (c.items.isNotEmpty)
                              SizedBox(
                                height: (box.maxHeight * 0.20).clamp(128, 176),
                                child: PreviewPane(c: c, compact: true),
                              ),
                            const SizedBox(height: 8),
                            Expanded(child: _grid(context, 92, bottomPad: under + 136, search: true)),
                          ],
                        ),
                        Positioned(left: 0, right: 0, top: -10, child: progress),
                      ],
                    ),
                  ),
                ],
              ),
              if (MediaQuery.viewInsetsOf(context).bottom == 0) floating,
              // jump to the top / bottom of the icons, above the action bar
              if (MediaQuery.viewInsetsOf(context).bottom == 0 && c.items.isNotEmpty)
                Positioned(right: -2, bottom: under + 74, child: ScrollJumpButtons(controller: c.gridScroll)),
            ],
          ),
        );
      },
    );
  }

  Widget _grid(BuildContext context, double tile, {double bottomPad = 0, bool search = false}) {
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) {
        if (c.items.isEmpty) {
          // scrollable: the guide never overflows on short screens
          return LayoutBuilder(
            builder: (context, box) => SingleChildScrollView(
              padding: EdgeInsets.only(bottom: bottomPad, top: 8),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: (box.maxHeight - bottomPad - 8).clamp(0, double.infinity)),
                child: Center(
                  child: emptyHint ?? const Text(S.nessunaIcona, style: TextStyle(color: Palette.text3)),
                ),
              ),
            ),
          );
        }
        final list = c.visibleItems;
        return CustomScrollView(
          controller: c.gridScroll,
          slivers: [
            // the search stays at the top while the icons scroll under it
            if (search || c.query.isNotEmpty) SliverPinnedSearch(padding: const EdgeInsets.fromLTRB(4, 4, 4, 6), child: StudioSearch(c: c)),
            if (list.isEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Text(
                    S.nessunRisultato(c.query),
                    key: const ValueKey('studio-no-results'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Palette.text2),
                  ),
                ),
              ),
            SliverPadding(
              padding: EdgeInsets.fromLTRB(4, 4, 4, 4 + bottomPad),
              sliver: SliverGrid.builder(
                gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: tile, mainAxisSpacing: 8, crossAxisSpacing: 8, childAspectRatio: 0.82),
                itemCount: list.length,
                itemBuilder: (context, i) => tileBuilder?.call(list[i]) ?? WorkTile(c: c, it: list[i]),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Search on the file names (and app names) of the Studio project.
class StudioSearch extends StatefulWidget {
  const StudioSearch({super.key, required this.c});
  final WorkspaceController c;

  @override
  State<StudioSearch> createState() => _StudioSearchState();
}

class _StudioSearchState extends State<StudioSearch> {
  late final TextEditingController t = TextEditingController(text: widget.c.query);

  @override
  void dispose() {
    t.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      key: const ValueKey('studio-search'),
      controller: t,
      decoration: pillSearchDecoration(context, S.cercaNomeFile).copyWith(
        suffixIcon: ValueListenableBuilder(
          valueListenable: t,
          builder: (_, v, _) => v.text.isEmpty
              ? const SizedBox.shrink()
              : IconButton(
                  tooltip: S.cancellaRicerca,
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () {
                    t.clear();
                    widget.c.setQuery('');
                  },
                ),
        ),
      ),
      onChanged: widget.c.setQuery,
    );
  }
}

/// Result summary dialog after an export.
Future<void> showExportDone(BuildContext context, ExportResult r) async {
  if (!context.mounted) return;
  showMsg(context, '${r.message}${r.location != null ? ' · ${r.location}' : ''}');
}

bool get isMobile => Platform.isAndroid || Platform.isIOS;

/// One entry of the "Altro" sheet.
class MoreAction {
  const MoreAction(this.icon, this.label, this.subtitle, this.onTap);
  final IconData icon;
  final String label;
  final String subtitle;
  final VoidCallback? onTap;
}

/// Bottom bar on phones: one big start button and "Altro" (the other
/// actions, in a glass pop-up menu).
class ActionBar extends StatelessWidget {
  const ActionBar({super.key, required this.primary, required this.more, this.header});
  final Widget primary;
  final List<MoreAction> more;

  /// Small line above the buttons (e.g. selection count + "Seleziona tutte").
  final Widget? header;

  Future<void> _open(BuildContext context, [Rect? anchor]) async {
    final i = await showGlassMenu<int>(
      context,
      anchor: anchor ?? anchorOf(context),
      title: S.altreAzioni,
      items: [for (var k = 0; k < more.length; k++) GlassMenuItem(value: k, label: more[k].label, subtitle: more[k].subtitle, icon: more[k].icon, enabled: more[k].onTap != null)],
    );
    if (i != null) more[i].onTap?.call();
  }

  @override
  Widget build(BuildContext context) {
    return LiquidGlass(
      key: const ValueKey('action-bar'),
      radius: 30,
      live: true,
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (header != null) Padding(padding: const EdgeInsets.fromLTRB(10, 2, 0, 4), child: header),
            Row(
              children: [
                // both buttons share one height (the start button used the
                // theme's own, shorter than "Altro")
                Expanded(
                  child: SizedBox(height: kButtonHeight, child: primary),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  height: kButtonHeight,
                  child: Builder(
                    builder: (bctx) => OutlinedButton.icon(
                      key: const ValueKey('more-actions'),
                      onPressed: more.isEmpty ? null : () => _open(context, anchorOf(bctx)),
                      icon: const Icon(Icons.keyboard_arrow_up_rounded),
                      label: const Text(S.altro),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
