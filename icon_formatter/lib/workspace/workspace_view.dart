import 'dart:io';

import 'package:flutter/material.dart';

import '../app/theme.dart';
import '../services/export_service.dart';
import '../widgets/common.dart';
import '../widgets/liquid_glass.dart';
import 'adjust_panel.dart';
import 'workspace_controller.dart';
import '../l10n/strings.dart';

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
          child: Column(children: [
            Expanded(
              child: Stack(children: [
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
              ]),
            ),
            const SizedBox(height: 6),
            Text(
              it.label ?? it.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11, color: it.excluded ? Palette.text3 : Palette.text2, decoration: it.excluded ? TextDecoration.lineThrough : null),
            ),
          ]),
        ),
      ),
    );
  }

  Future<void> _menu(BuildContext context, Offset? pos) async {
    final items = <PopupMenuEntry<String>>[
      const PopupMenuItem(value: 'zoom', child: Text(S.ingrandisci)),
      PopupMenuItem(value: 'exclude', child: Text(it.excluded ? S.includi : S.escludi)),
      const PopupMenuItem(value: 'redo', child: Text(S.rielaboraQuestaIcona)),
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
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            for (final e in items.whereType<PopupMenuItem<String>>()) ListTile(title: e.child, onTap: () => Navigator.pop(ctx, e.value)),
          ]),
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
          return const Center(child: Text(S.selezionaOImportaIcona, style: TextStyle(color: Palette.text3)));
        }
        final info = c.previewInfo;
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Expanded(
            child: Center(
              child: AspectRatio(
                aspectRatio: 1,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: BeforeAfter(
                    before: Padding(padding: const EdgeInsets.all(18), child: IconImage(path: it.path, bytes: it.bytes)),
                    after: c.previewPng != null
                        ? IconImage(bytes: c.previewPng)
                        : Center(
                            child: c.previewError != null
                                ? Padding(
                                    padding: const EdgeInsets.all(16),
                                    child: Text(c.previewError!, style: const TextStyle(color: Palette.danger)),
                                  )
                                : const CircularProgressIndicator(strokeWidth: 2),
                          ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Row(children: [
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
            IconButton(
              tooltip: S.ingrandisci,
              icon: const Icon(Icons.zoom_in),
              onPressed: c.previewPng == null ? null : () => showZoom(context, bytes: c.previewPng, title: it.label ?? it.name),
            ),
            IconButton(
              tooltip: S.salvaQuestaIconaPng,
              icon: const Icon(Icons.download_outlined),
              onPressed: c.previewPng == null
                  ? null
                  : () async {
                      final r = await ExportService.saveSingle(c.previewPng!, '${it.name}.png');
                      if (r != null && context.mounted) showMsg(context, '${r.message}${r.location != null ? ': ${r.location}' : ''}');
                    },
            ),
          ]),
          if (info != null && (info.ambiguous || info.notes.isNotEmpty) && !compact)
            Text(
              (info.ambiguous ? S.risultatoAmbiguoVerifica : '') + info.notes.join(' · '),
              style: TextStyle(fontSize: 11, color: info.ambiguous ? Palette.warn : Palette.text3),
            ),
        ]);
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
  });

  final WorkspaceController c;
  final String title;
  final List<Widget> toolbar;
  final List<Widget> bottomActions;
  final Widget? header;
  final Widget? emptyHint;
  final bool showModes;
  final VoidCallback? onOpenBases;
  final Widget Function(WorkItem it)? tileBuilder;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      final w = box.maxWidth;
      final wide = w >= 1080;
      final medium = w >= 720;
      final grid = _grid(context, medium ? 112 : 92);
      final progress = ListenableBuilder(
        listenable: c.batch,
        builder: (context, _) {
          final b = c.batch;
          if (b.total == 0 && b.fatal == null) return const SizedBox.shrink();
          return Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Column(children: [
              ProgressStrip(
                done: b.done,
                total: b.total,
                errors: b.errors,
                running: b.running,
                onCancel: b.cancel,
                label: b.cancelled ? S.annullato : (b.running && b.phase != null ? b.phase : null),
              ),
              if (b.fatal != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text(b.fatal!, style: const TextStyle(color: Palette.danger))),
            ]),
          );
        },
      );
      final actions = Wrap(spacing: 8, runSpacing: 8, alignment: WrapAlignment.end, children: bottomActions);
      final head = Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: Theme.of(context).textTheme.headlineSmall, maxLines: 1, softWrap: false),
          if (medium) ...[
            const SizedBox(height: 6),
            Wrap(spacing: 2, runSpacing: 2, children: toolbar),
          ],
        ]),
      );

      if (wide) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Expanded(
              flex: 5,
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                head,
                ?header,
                Expanded(child: Glass(padding: const EdgeInsets.all(10), child: grid)),
                progress,
                const SizedBox(height: 10),
                actions,
              ]),
            ),
            const SizedBox(width: 16),
            Expanded(flex: 5, child: Glass(child: PreviewPane(c: c))),
            const SizedBox(width: 16),
            SizedBox(width: 360, child: Glass(padding: EdgeInsets.zero, child: AdjustPanel(c: c, showModes: showModes, onOpenBases: onOpenBases))),
          ]),
        );
      }
      if (medium) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                head,
                ?header,
                SizedBox(height: box.maxHeight * 0.42, child: Glass(child: PreviewPane(c: c, compact: true))),
                const SizedBox(height: 10),
                Expanded(child: Glass(padding: const EdgeInsets.all(8), child: grid)),
                progress,
                const SizedBox(height: 8),
                actions,
              ]),
            ),
            const SizedBox(width: 12),
            SizedBox(width: 330, child: Glass(padding: EdgeInsets.zero, child: AdjustPanel(c: c, showModes: showModes, onOpenBases: onOpenBases))),
          ]),
        );
      }
      // phone portrait: grid scrolls under floating liquid-glass bars
      final under = GlassInsets.of(context);
      final floating = Positioned(
        left: 0,
        right: 0,
        bottom: under - 4, // the nav box includes 12dp of top padding
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          progress,
          const SizedBox(height: 6),
          LiquidGlass(
            radius: 30,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: [for (final a in bottomActions) Padding(padding: const EdgeInsets.symmetric(horizontal: 4), child: a)]),
            ),
          ),
        ]),
      );
      return Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
        child: Stack(children: [
          Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(child: Text(title, style: Theme.of(context).textTheme.titleLarge)),
            GlassIconButton(
              tooltip: S.regolazioni,
              icon: Icons.tune,
              onPressed: () => showModalBottomSheet(
                context: context,
                isScrollControlled: true,
                builder: (ctx) => SizedBox(
                  height: MediaQuery.of(ctx).size.height * 0.78,
                  child: AdjustPanel(c: c, showModes: showModes, onOpenBases: onOpenBases),
                ),
              ),
            ),
          ]),
          SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(children: toolbar)),
          ?header,
          SizedBox(height: (box.maxHeight * 0.36).clamp(200, 360), child: PreviewPane(c: c, compact: true)),
          const SizedBox(height: 8),
          Expanded(child: _grid(context, 92, bottomPad: under + 150)),
          ]),
          floating,
        ]),
      );
    });
  }

  Widget _grid(BuildContext context, double tile, {double bottomPad = 0}) {
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) {
        if (c.items.isEmpty) {
          return Padding(
            padding: EdgeInsets.only(bottom: bottomPad),
            child: Center(child: emptyHint ?? const Text(S.nessunaIcona, style: TextStyle(color: Palette.text3))),
          );
        }
        return GridView.builder(
          padding: EdgeInsets.fromLTRB(4, 4, 4, 4 + bottomPad),
          gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: tile, mainAxisSpacing: 8, crossAxisSpacing: 8, childAspectRatio: 0.82),
          itemCount: c.items.length,
          itemBuilder: (context, i) => tileBuilder?.call(c.items[i]) ?? WorkTile(c: c, it: c.items[i]),
        );
      },
    );
  }
}

/// Result summary dialog after an export.
Future<void> showExportDone(BuildContext context, ExportResult r) async {
  if (!context.mounted) return;
  showMsg(context, '${r.message}${r.location != null ? ' · ${r.location}' : ''}');
}

bool get isMobile => Platform.isAndroid || Platform.isIOS;
