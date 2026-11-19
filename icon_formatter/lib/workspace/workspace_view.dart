import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../app/state.dart';
import '../app/theme.dart';
import '../services/export_service.dart';
import '../widgets/common.dart';
import '../widgets/glass_menu.dart';
import 'studio2_plate_sheets.dart';
import '../widgets/liquid_glass.dart';
import '../widgets/studio_guide.dart';
import 'adjust_panel.dart';
import 'studio_list.dart';
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
    final picked = c.isSelected(it);
    return Tooltip(
      message: '${it.label ?? it.rel}\n$tip',
      waitDuration: const Duration(milliseconds: 600),
      child: GestureDetector(
        // a tap picks the preview; while icons are selected it toggles them
        onTap: () => c.selecting ? c.toggleSelect(it) : c.select(it.id),
        onDoubleTap: () => showZoom(context, path: out ?? it.path, bytes: out == null ? it.bytes : null, title: it.label ?? it.name),
        // long press starts the selection; the menu is on right click and in the preview
        onLongPress: () => c.toggleSelect(it),
        onSecondaryTapDown: (d) => menu(context, c, it, d.globalPosition),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            color: sel || picked ? accent.withValues(alpha: 0.10) : Palette.fg.withValues(alpha: 0.025),
            border: Border.all(color: sel || picked ? accent.withValues(alpha: 0.7) : Palette.fg.withValues(alpha: 0.06)),
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
                    if (it.hasOverride) Positioned(left: 0, top: 0, child: Icon(Icons.edit, size: 12, color: Palette.text2)),
                    if (it.isDuplicate) Positioned(right: 0, bottom: 0, child: Tooltip(message: S.studioDuplicato, child: Icon(Icons.content_copy_rounded, size: 14, color: Palette.warn))),
                    if (picked) Positioned(left: 0, bottom: 0, child: Icon(Icons.check_circle, size: 18, color: accent)),
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

  /// Per-icon menu: right click on a tile, or the "more" button of the preview.
  static Future<void> menu(BuildContext context, WorkspaceController c, WorkItem it, [Offset? pos]) async {
    final items = <PopupMenuEntry<String>>[
      PopupMenuItem(value: 'zoom', child: Text(S.ingrandisci)),
      PopupMenuItem(value: 'exclude', child: Text(it.excluded ? S.includi : S.escludi)),
      PopupMenuItem(value: 'redo', child: Text(S.rielaboraQuestaIcona)),
      PopupMenuItem(value: 'size', child: Text(S.dimensione)),
      PopupMenuItem(value: 'mode', child: Text(S.rigeneraConModalita)),
      PopupMenuItem(value: 'white', child: Text(c.keepsInnerWhite(it) ? S.togliBiancoInterno : S.mantieniBiancoInterno)),
      PopupMenuItem(value: 'plate', child: Text(S.sfondoComePack)),
      if (c.mode == StudioMode.translucent) ...[
        PopupMenuItem(value: 'shape', child: Text(S.studio2FormaPiattoMenu)),
        PopupMenuItem(value: 'backdrop', child: Text(S.studio2ColorePiattoMenu)),
      ],
      if (it.hasOverride) PopupMenuItem(value: 'reset', child: Text(S.rimuoviCorrezioni)),
      if (it.hasOverride && !c.batch.running && c.overrideTargets(it).isNotEmpty) PopupMenuItem(value: 'applyAll', child: Text(S.applicaATutte)),
      PopupMenuItem(value: 'remove', child: Text(S.rimuoviDallaLista)),
    ];
    String? v;
    if (pos != null) {
      v = await showMenu<String>(context: context, position: RelativeRect.fromLTRB(pos.dx, pos.dy, pos.dx, pos.dy), items: items);
    } else {
      v = await showAppSheet<String>(
        context: context,
        // scrolls when the actions are taller than the sheet
        builder: (ctx) => SingleChildScrollView(
          padding: const EdgeInsets.only(bottom: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final e in items.whereType<PopupMenuItem<String>>())
                ListTile(contentPadding: const EdgeInsets.symmetric(horizontal: 22), title: e.child, onTap: () => Navigator.pop(ctx, e.value)),
            ],
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
      case 'size':
        if (context.mounted) await showIconSizeDialog(context, c, [it]);
      case 'white':
        c.setKeepInnerWhite(it, !c.keepsInnerWhite(it));
      case 'plate':
        final r = await c.matchPlateOf([it]);
        if (context.mounted) showMsg(context, plateMatchMessage(r), error: r == null);
      case 'shape':
        if (context.mounted) await studio2PlateShapeSheet(context, c, it);
      case 'backdrop':
        if (context.mounted) await studio2PlateColorSheet(context, c, it);
      case 'mode':
        if (!context.mounted) return;
        final cur = it.strategyOverride ?? LucentStrategy.auto;
        final st = await showAppSheet<LucentStrategy>(
          context: context,
          builder: (ctx) => SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(S.modalitaSimbolo(it.label ?? it.name), style: Theme.of(ctx).textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Text(S.modalitaSimboloInfo, style: TextStyle(fontSize: 12, color: Palette.text2)),
                  const SizedBox(height: 8),
                  for (final (v, t, d) in [
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
      case 'applyAll':
        if (!context.mounted) return;
        final n = c.overrideTargets(it).length;
        if (await confirm(context, S.applicaATutte, S.applicaATutteConferma(n), ok: S.applicaATutteOk) && context.mounted) {
          final done = await c.applyOverridesToAll(it);
          if (context.mounted) showMsg(context, S.applicaATutteFatto(done));
        }
      case 'remove':
        c.remove(it);
    }
  }
}

/// What "Sfondo come il pack" did, for a notice.
String plateMatchMessage(PlateMatch? r) {
  if (r == null) return S.sfondoNientePack;
  if (r.changed == 0) return S.sfondoGiaUguale;
  return S.sfondoUniformato(r.changed, (r.reference * 100).round());
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
          return Center(
            child: Text(S.selezionaOImportaIcona, style: TextStyle(color: Palette.text3)),
          );
        }
        final info = c.previewInfo;
        final compare = ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Stack(fit: StackFit.expand, children: [
          BeforeAfter(
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
                              style: TextStyle(color: Palette.danger, fontSize: 11),
                            ),
                          )
                        : const CircularProgressIndicator(strokeWidth: 2),
                  ),
          ),
          // preview only: the guide is never written to the output
          if (c.safeGuide) const Positioned.fill(child: IgnorePointer(child: CustomPaint(painter: StudioGuidePainter()))),
          ]),
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
        final guide = IconButton(
          key: const ValueKey('preview-guide'),
          tooltip: S.studioGuidaArea,
          isSelected: c.safeGuide,
          icon: const Icon(Icons.crop_square_outlined),
          selectedIcon: Icon(Icons.crop_square_rounded, color: Theme.of(context).colorScheme.primary),
          onPressed: c.toggleSafeGuide,
        );
        final more = IconButton(
          key: const ValueKey('preview-more'),
          tooltip: S.studioAltreIcona,
          icon: const Icon(Icons.more_horiz_rounded),
          onPressed: () => WorkTile.menu(context, c, it),
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
                            style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: Palette.text),
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
                        style: TextStyle(fontSize: 11.5, color: Palette.text2),
                      ),
                    ],
                    if (info != null && info.ambiguous)
                      Text(
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
                        more,
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
                      style: TextStyle(fontSize: 12, color: Palette.text2),
                    ),
                  ),
                ] else
                  const Spacer(),
                if (c.previewBusy) const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
                zoom,
                save,
                guide,
                more,
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
    this.compactPrimaryAction,
    this.moreActions = const [],
  });

  /// Phones: round "+" next to Personalizza, shown once the list has icons
  /// (before that the centre button does the same). Gets the button rect.
  final void Function(Rect anchor)? onAdd;

  /// Phones: the one big action of the bottom bar ("Elabora tutte").
  final Widget? primaryAction;

  /// Icon-only start button for the compact bar (tab bar folded).
  final Widget? compactPrimaryAction;

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

  /// "Stile": every adjustment of the icons, with a title that explains it.
  Future<void> openStyleSheet(BuildContext context) => showAppSheet(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => SizedBox(
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
        final grid = _grid(context, medium ? 112 : 92, search: true, jump: true);
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
                      child: Text(b.fatal!, style: TextStyle(color: Palette.danger)),
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
        final floating = FloatingBarSlot(
          side: -8,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // the glass shape clips the scrolling actions, so they disappear
              // along its rounded edge instead of a straight inner line
              if (primaryAction != null)
                ActionBar(primary: primaryAction!, compactPrimary: compactPrimaryAction, more: moreActions)
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
                            if (c.items.isNotEmpty) const SizedBox(height: 8),
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

  /// Bar above the grid while icons are picked (long press): acts on them.
  Widget _selectionBar(BuildContext context) {
    final n = c.selection.length;
    final src = c.selected;
    final canApply = src != null && src.hasOverride && !c.batch.running;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(S.studioSelezionate(n), key: const ValueKey('studio-selection-count'), style: TextStyle(fontWeight: FontWeight.w600, color: Palette.text)),
          FilledButton.tonal(
            key: const ValueKey('studio-sel-apply'),
            // the corrections of the previewed icon go to the picked ones
            onPressed: canApply
                ? () async {
                    final done = await c.applySelectionCorrections();
                    if (context.mounted) showMsg(context, done == 0 ? S.studioNessunaCorrezione : S.studioCorrezioniApplicate(done));
                  }
                : null,
            child: Text(S.studioApplicaCorrezioni),
          ),
          OutlinedButton(key: const ValueKey('studio-sel-exclude'), onPressed: () => c.setSelectedExcluded(true), child: Text(S.studioEscludi)),
          OutlinedButton(
            key: const ValueKey('studio-sel-remove'),
            onPressed: () async {
              if (await confirm(context, S.studioRimuoviSelezioneTitolo(n), S.studioRimuoviSelezioneSub, ok: S.studioRimuovi)) c.removeSelected();
            },
            child: Text(S.studioRimuovi),
          ),
          IconButton(tooltip: S.studioDeselezionaTutte, icon: const Icon(Icons.close_rounded), onPressed: c.clearSelection),
        ],
      ),
    );
  }

  Widget _grid(BuildContext context, double tile, {double bottomPad = 0, bool search = false, bool jump = false}) {
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) {
        if (c.items.isEmpty) {
          // scrollable: the guide never overflows on short screens
          return LayoutBuilder(
            builder: (context, box) => SingleChildScrollView(
              padding: EdgeInsets.only(bottom: bottomPad, top: 2),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: (box.maxHeight - bottomPad - 8).clamp(0, double.infinity)),
                // right under the header: centred it left a big empty gap
                child: Align(
                  alignment: Alignment.topCenter,
                  child: emptyHint ?? Text(S.nessunaIcona, style: TextStyle(color: Palette.text3)),
                ),
              ),
            ),
          );
        }
        final list = c.visibleItems;
        final view = CustomScrollView(
          controller: c.gridScroll,
          slivers: [
            // the search stays at the top while the icons scroll under it
            if (search || c.query.isNotEmpty) SliverPinnedSearch(padding: const EdgeInsets.fromLTRB(4, 4, 4, 6), child: StudioSearch(c: c)),
            if (c.selecting) SliverToBoxAdapter(child: _selectionBar(context)),
            if (list.isEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Text(
                    c.filter != StudioFilter.all && c.query.trim().isEmpty ? S.studioNessunaIconaFiltrata : S.nessunRisultato(c.query),
                    key: const ValueKey('studio-no-results'),
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Palette.text2),
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
        if (!jump) return view;
        // desktop layouts: top / bottom buttons in the corner of the grid
        return Stack(children: [
          view,
          Positioned(right: 8, bottom: 8, child: ScrollJumpButtons(controller: c.gridScroll)),
        ]);
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
      decoration: pillSearchDecoration(context, S.cercaLista).copyWith(
        suffixIcon: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ValueListenableBuilder(
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
            // sort and filter of the list: display only
            ListenableBuilder(
              listenable: widget.c,
              builder: (context, _) {
                final on = widget.c.sort != StudioSort.added || widget.c.filter != StudioFilter.all;
                return IconButton(
                  key: const ValueKey('studio-arrange'),
                  tooltip: S.studioOrdinaFiltra,
                  icon: Icon(Icons.tune_rounded, color: on ? Theme.of(context).colorScheme.primary : null),
                  onPressed: () => showArrangeSheet(context, widget.c),
                );
              },
            ),
          ],
        ),
      ),
      onChanged: widget.c.setQuery,
    );
  }
}

/// Sort and filter of the list. Stays open, so both can be combined.
Future<void> showArrangeSheet(BuildContext context, WorkspaceController c) {
  return showAppSheet(
    context: context,
    builder: (ctx) => ListenableBuilder(
      listenable: c,
      builder: (ctx, _) {
        final accent = Theme.of(ctx).colorScheme.primary;
        return SingleChildScrollView(
          padding: const EdgeInsets.only(bottom: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 0, 22, 2),
                child: Text(S.studioOrdinaFiltra, style: Theme.of(ctx).textTheme.titleMedium),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 0, 22, 6),
                child: Text(S.studioFiltroSub, style: TextStyle(fontSize: 12, color: Palette.text2)),
              ),
              for (final (v, t) in [(StudioSort.added, S.studioOrdineAggiunta), (StudioSort.name, S.studioOrdinaNome), (StudioSort.state, S.studioOrdinaStato)])
                ListTile(
                  key: ValueKey('sort-${v.name}'),
                  title: Text(t),
                  trailing: c.sort == v ? Icon(Icons.check_rounded, color: accent) : null,
                  onTap: () => c.setSort(v),
                ),
              const Divider(height: 16),
              for (final (f, t) in [
                (StudioFilter.all, S.studioFiltroTutte),
                (StudioFilter.modified, S.studioFiltroModificate),
                (StudioFilter.errors, S.studioFiltroErrori),
                (StudioFilter.excluded, S.studioFiltroEscluse),
              ])
                ListTile(
                  key: ValueKey('filter-${f.name}'),
                  title: Text(t),
                  trailing: c.filter == f ? Icon(Icons.check_rounded, color: accent) : null,
                  onTap: () => c.setFilter(f),
                ),
            ],
          ),
        );
      },
    ),
  );
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
  const ActionBar({super.key, required this.primary, required this.more, this.header, this.leading, this.compactPrimary, this.compactLeading});
  final Widget primary;
  final List<MoreAction> more;

  /// Small control before the start button, on the same row.
  final Widget? leading;

  /// Icon-only versions shown while the tab bar is folded: the bar then
  /// sits next to the folded button, as tall as it, with no labels.
  final Widget? compactPrimary;
  final Widget? compactLeading;

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
    if (compactPrimary != null && GlassInsets.foldedOf(context)) {
      // folded: icons only, 50 dp like the folded tab button. The start
      // button keeps its open look (same colour) and stays wide; "Altro" is
      // the same outlined round button as in the open bar
      return LiquidGlass(
        key: const ValueKey('action-bar'),
        radius: 25,
        live: true,
        child: _barButtons(context, SizedBox(
          height: 50,
          child: Padding(
            // same proportions as the open bar (60 dp, 6 dp around 48 dp
            // buttons, 8 dp apart): 50 dp, 5 dp around 40 dp buttons, 7 apart
            padding: const EdgeInsets.all(5),
            child: Row(children: [
              if (compactLeading != null) ...[SizedBox(width: 40, height: 40, child: compactLeading!), const SizedBox(width: 7)],
              Expanded(child: SizedBox(height: 40, child: compactPrimary!)),
              const SizedBox(width: 7),
              Builder(
                builder: (bctx) => SizedBox(
                  width: 40,
                  height: 40,
                  child: OutlinedButton(
                    key: const ValueKey('more-actions'),
                    style: OutlinedButton.styleFrom(padding: EdgeInsets.zero, minimumSize: Size.zero, shape: const CircleBorder()),
                    onPressed: more.isEmpty ? null : () => _open(context, anchorOf(bctx)),
                    child: const Icon(Icons.keyboard_arrow_up_rounded),
                  ),
                ),
              ),
            ]),
          ),
        )),
      );
    }
    return LiquidGlass(
      key: const ValueKey('action-bar'),
      radius: 30,
      live: true,
      child: _barButtons(context, Padding(
        padding: const EdgeInsets.all(6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (header != null) Padding(padding: const EdgeInsets.fromLTRB(10, 2, 0, 4), child: header),
            Row(
              children: [
                if (leading != null) ...[SizedBox(height: kButtonHeight, child: leading), const SizedBox(width: 8)],
                // both buttons share one height (the start button used the
                // theme's own, shorter than "Altro")
                Expanded(
                  child: SizedBox(height: kButtonHeight, child: primary),
                ),
                const SizedBox(width: 8),
                // narrow bar (next to the folded tab button): "Altro" is just
                // its arrow, so the start button keeps a readable label
                LayoutBuilder(
                  builder: (bctx, _) {
                    final narrow = MediaQuery.sizeOf(bctx).width - (GlassInsets.foldedOf(bctx) ? 70 : 0) < 400;
                    void open() => _open(context, anchorOf(bctx));
                    return SizedBox(
                      height: kButtonHeight,
                      width: narrow ? kButtonHeight : null,
                      child: narrow
                          ? Tooltip(
                              message: S.altro,
                              child: OutlinedButton(
                                key: const ValueKey('more-actions'),
                                style: OutlinedButton.styleFrom(padding: EdgeInsets.zero, shape: const CircleBorder()),
                                onPressed: more.isEmpty ? null : open,
                                child: const Icon(Icons.keyboard_arrow_up_rounded),
                              ),
                            )
                          : OutlinedButton.icon(
                              key: const ValueKey('more-actions'),
                              onPressed: more.isEmpty ? null : open,
                              icon: const Icon(Icons.keyboard_arrow_up_rounded),
                              label: Text(S.altro),
                            ),
                    );
                  },
                ),
              ],
            ),
          ],
        ),
      )),
    );
  }

  /// Glass style: the buttons speak the bottom bar's language. No outlines;
  /// the start button is the white puck of the active tab ("Scheda attiva").
  static Widget _barButtons(BuildContext context, Widget child) {
    if (nothingStyle) return child;
    final g = AppState.I.glass;
    final puck = Palette.fg.withValues(alpha: g.native ? g.nActiveTab.clamp(0.12, 1.0) : 0.18);
    final t = Theme.of(context);
    return Theme(
      data: t.copyWith(
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(side: BorderSide.none, foregroundColor: Palette.fg, backgroundColor: Colors.transparent),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: puck,
            foregroundColor: Palette.fg,
            disabledBackgroundColor: puck,
            disabledForegroundColor: Palette.fg.withValues(alpha: 0.85),
          ),
        ),
      ),
      child: child,
    );
  }
}

/// "Dimensione": one slider for [its] with the first icon as live preview.
/// The icons are re-rendered when the finger lifts.
Future<void> showIconSizeDialog(BuildContext context, WorkspaceController c, List<WorkItem> its) async {
  if (its.isEmpty) return;
  var v = c.itemScale(its.first);
  await showAppDialog<void>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setS) => AlertDialog(
        title: Text(S.dimensioneIcona),
        content: SizedBox(
          width: 360,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(S.dimensioneSub(its.length), style: TextStyle(fontSize: 12, color: Palette.text2)),
            const SizedBox(height: 12),
            ListenableBuilder(
              listenable: c,
              builder: (_, _) {
                final it = its.first;
                return SizedBox(
                  width: 132,
                  height: 132,
                  child: Checkerboard(cell: 8, child: IconImage(path: it.outputPath ?? it.path, bytes: it.outputPath == null ? it.bytes : null)),
                );
              },
            ),
            Row(children: [
              Expanded(
                child: Slider(
                  value: v,
                  min: 0.5,
                  max: 1.6,
                  divisions: 110,
                  onChanged: (x) => setS(() => v = x),
                  onChangeEnd: (x) => c.setItemsScale(its, x),
                ),
              ),
              SizedBox(width: 44, child: Text('${(v * 100).round()}%', textAlign: TextAlign.end)),
            ]),
          ]),
        ),
        actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: Text(S.fatto))],
      ),
    ),
  );
}

/// Many images at once (an icon pack, a big folder): pick the ones to add.
/// Returns null when cancelled.
Future<List<PackImage>?> pickImagesDialog(BuildContext context, List<PackImage> all) {
  final chosen = <String>{};
  var q = '';
  return showAppDialog<List<PackImage>>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setS) {
        final list = q.isEmpty ? all : all.where((i) => i.rel.toLowerCase().contains(q)).toList();
        final mq = MediaQuery.of(ctx);
        final avail = mq.size.height - mq.viewInsets.bottom - mq.padding.vertical - 220;
        final allShown = list.isNotEmpty && list.every((i) => chosen.contains(i.abs));
        return AlertDialog(
          title: Text(S.scegliIconeTitolo(all.length)),
          insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
          content: SizedBox(
            width: 560,
            height: avail.clamp(200.0, 560.0),
            child: Column(children: [
              Row(children: [
                Expanded(child: TextField(decoration: pillSearchDecoration(ctx, S.cercaIcone), onChanged: (v) => setS(() => q = v.trim().toLowerCase()))),
                const SizedBox(width: 8),
                TextButton(
                  onPressed: () => setS(() => allShown ? chosen.removeAll(list.map((i) => i.abs)) : chosen.addAll(list.map((i) => i.abs))),
                  child: Text(allShown ? S.nessuna : S.selezionaTutte),
                ),
              ]),
              const SizedBox(height: 8),
              Expanded(
                child: GridView.builder(
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 88, mainAxisExtent: 100, crossAxisSpacing: 4, mainAxisSpacing: 4),
                  itemCount: list.length,
                  itemBuilder: (_, i) {
                    final im = list[i];
                    final on = chosen.contains(im.abs);
                    return InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () => setS(() => on ? chosen.remove(im.abs) : chosen.add(im.abs)),
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: on ? Theme.of(ctx).colorScheme.primary : Colors.transparent, width: 2),
                          color: on ? Theme.of(ctx).colorScheme.primary.withValues(alpha: 0.14) : null,
                        ),
                        child: Column(children: [
                          SizedBox(width: 60, height: 60, child: IconImage(path: im.abs)),
                          const SizedBox(height: 2),
                          Text(p.basenameWithoutExtension(im.rel), maxLines: 2, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: const TextStyle(fontSize: 10)),
                        ]),
                      ),
                    );
                  },
                ),
              ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text(S.annulla)),
            FilledButton(
              onPressed: chosen.isEmpty ? null : () => Navigator.pop(ctx, all.where((i) => chosen.contains(i.abs)).toList()),
              child: Text(S.aggiungiN(chosen.length)),
            ),
          ],
        );
      },
    ),
  );
}
