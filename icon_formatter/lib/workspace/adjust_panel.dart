import 'package:flutter/material.dart';

import '../app/models.dart';
import '../app/state.dart';
import '../app/theme.dart';
import '../src/rust/api/engine.dart';
import '../widgets/common.dart';
import 'workspace_controller.dart';

/// Controls shared by all pipelines.
class AdjustPanel extends StatelessWidget {
  const AdjustPanel({super.key, required this.c, this.showModes = true, this.onOpenBases});

  final WorkspaceController c;
  final bool showModes;
  final VoidCallback? onOpenBases;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([c, AppState.I]),
      builder: (context, _) {
        final st = AppState.I;
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          children: [
            if (showModes) ...[
              const SectionTitle('Modalità'),
              SegmentedButton<StudioMode>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: StudioMode.original, label: Text('Original')),
                  ButtonSegment(value: StudioMode.translucent, label: Text('Translucent')),
                  ButtonSegment(value: StudioMode.preset, label: Text('Preset')),
                ],
                selected: {c.mode},
                onSelectionChanged: (s) => c.mode = s.first,
              ),
              const SizedBox(height: 18),
            ],
            ..._styleSection(context, st),
            const SizedBox(height: 18),
            _overrideSwitch(context),
            ..._placementSection(context),
            const SizedBox(height: 18),
            ..._segmentSection(context),
            const SizedBox(height: 18),
            ..._sizeSection(context, st),
          ],
        );
      },
    );
  }

  List<Widget> _styleSection(BuildContext context, AppState st) {
    switch (c.mode) {
      case StudioMode.original:
        final b = st.selectedBase;
        return [
          const SectionTitle('Base icon'),
          if (st.bases.isEmpty)
            const Text('Nessun base icon: importane uno in Base Icons.', style: TextStyle(color: Palette.text2))
          else
            DropdownButtonFormField<String>(
              key: ValueKey('base${b?.id}'),
              initialValue: b?.id,
              isExpanded: true,
              items: [for (final x in st.bases) DropdownMenuItem(value: x.id, child: Text('${x.name}  ·  ${x.width}×${x.height}'))],
              onChanged: (v) => st.update(() => st.selectedBaseId = v),
            ),
          const SizedBox(height: 8),
          if (b != null && b.calibration == null)
            Glass(
              padding: const EdgeInsets.all(12),
              child: Row(children: [
                const Icon(Icons.info_outline, color: Palette.warn, size: 18),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text('Base non calibrato: uso proporzioni predefinite. Calibralo con circa 20 icone di esempio.',
                      style: TextStyle(fontSize: 12, color: Palette.text2)),
                ),
                if (onOpenBases != null) TextButton(onPressed: onOpenBases, child: const Text('Calibra')),
              ]),
            )
          else if (b?.calibration != null)
            Text(
              'Calibrato: glyph ${(b!.calibration!.glyphRatio * 100).toStringAsFixed(1)}% · centro '
              '(${b.calibration!.centerX.toStringAsFixed(3)}, ${b.calibration!.centerY.toStringAsFixed(3)})',
              style: const TextStyle(fontSize: 12, color: Palette.text2),
            ),
        ];
      case StudioMode.translucent:
        return [
          SectionTitle('Nothing Translucent', trailing: TextButton(onPressed: () => st.resetPreset('nothing'), child: const Text('Ripristina'))),
          ...translucentSliders(st.presetById('nothing').params, (t) => st.setPresetParams('nothing', t)),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: const Text('Usa la calibrazione del base selezionato', style: TextStyle(fontSize: 13)),
            value: st.useBaseCalibrationForTranslucent,
            onChanged: (v) => st.update(() => st.useBaseCalibrationForTranslucent = v),
          ),
        ];
      case StudioMode.preset:
        final id = c.presetId ?? (c.packSettings ? st.packPresetId : st.activePresetId);
        final pr = st.presetById(id);
        return [
          const SectionTitle('Preset'),
          Row(children: [
            Expanded(
              child: DropdownButtonFormField<String>(
                key: ValueKey('preset${pr.id}${st.presets.length}'),
                initialValue: pr.id,
                isExpanded: true,
                items: [for (final x in st.presets) DropdownMenuItem(value: x.id, child: Text(x.name))],
                onChanged: (v) {
                  c.setPreset(v);
                  if (!c.packSettings) st.update(() => st.activePresetId = v!);
                },
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              tooltip: 'Salva come nuovo preset',
              icon: const Icon(Icons.save_as_outlined),
              onPressed: () async {
                final name = await askText(context, 'Nome del preset', initial: '${pr.name} copia');
                if (name != null && name.isNotEmpty) {
                  final n = st.savePresetAs(name, pr.params);
                  c.setPreset(n.id);
                }
              },
            ),
            if (pr.builtIn)
              IconButton(tooltip: 'Ripristina valori', icon: const Icon(Icons.restart_alt), onPressed: () => st.resetPreset(pr.id))
            else
              IconButton(
                tooltip: 'Elimina preset',
                icon: const Icon(Icons.delete_outline),
                onPressed: () async {
                  if (await confirm(context, 'Eliminare il preset?', pr.name, ok: 'Elimina')) {
                    st.deletePreset(pr.id);
                    c.setPreset(null);
                  }
                },
              ),
          ]),
          const SizedBox(height: 10),
          ...translucentSliders(pr.params, (t) => st.setPresetParams(pr.id, t)),
        ];
    }
  }

  Widget _overrideSwitch(BuildContext context) {
    final it = c.selected;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SectionTitle('Composizione',
          trailing: it != null && it.hasOverride
              ? TextButton(onPressed: () => c.clearOverrides(it), child: const Text('Rimuovi correzioni'))
              : null),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        dense: true,
        title: const Text('Correggi solo l\'icona selezionata', style: TextStyle(fontSize: 13)),
        subtitle: Text(it == null ? 'Nessuna icona selezionata' : it.name, style: const TextStyle(fontSize: 11)),
        value: c.editSelectedOnly,
        onChanged: it == null
            ? null
            : (v) {
                c.editSelectedOnly = v;
                if (v) {
                  it.placementOverride ??= c.settings.placement;
                  it.segOverride ??= c.settings.segment;
                }
                c.notify();
              },
      ),
    ]);
  }

  List<Widget> _placementSection(BuildContext context) {
    final pl = c.editPlacement;
    return [
      SliderRow(
        label: 'Scala',
        value: pl.scaleMul,
        min: 0.5,
        max: 1.6,
        format: (v) => '${(v * 100).round()}%',
        onChanged: (v) => c.setPlacement(copyPlacement(pl, scaleMul: v)),
      ),
      SliderRow(
        label: 'Posizione X',
        value: pl.offsetX,
        min: -0.15,
        max: 0.15,
        format: (v) => (v * 100).toStringAsFixed(1),
        onChanged: (v) => c.setPlacement(copyPlacement(pl, offsetX: v)),
      ),
      SliderRow(
        label: 'Posizione Y',
        value: pl.offsetY,
        min: -0.15,
        max: 0.15,
        format: (v) => (v * 100).toStringAsFixed(1),
        onChanged: (v) => c.setPlacement(copyPlacement(pl, offsetY: v)),
      ),
      if (c.editSelectedOnly)
        SliderRow(
          label: 'Lato glyph',
          value: pl.glyphRatio,
          min: 0.3,
          max: 0.9,
          format: (v) => '${(v * 100).round()}%',
          onChanged: (v) => c.setPlacement(copyPlacement(pl, glyphRatio: v)),
        ),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        dense: true,
        title: const Text('Dimensione ottica (area)', style: TextStyle(fontSize: 13)),
        subtitle: const Text('Uniforma glyph larghi e stretti per area invece che per lato lungo', style: TextStyle(fontSize: 11)),
        value: pl.areaFit,
        onChanged: c.editSelectedOnly ? (v) => c.setPlacement(copyPlacement(pl, areaFit: v)) : null,
      ),
      Text(
        'Area utile: lato glyph ${(pl.glyphRatio * pl.scaleMul * 100).toStringAsFixed(1)}% · centro '
        '(${(pl.centerX + pl.offsetX).toStringAsFixed(3)}, ${(pl.centerY + pl.offsetY).toStringAsFixed(3)})',
        style: const TextStyle(fontSize: 11, color: Palette.text3),
      ),
    ];
  }

  List<Widget> _segmentSection(BuildContext context) {
    final s = c.editSegment;
    return [
      const SectionTitle('Isolamento glyph'),
      DropdownButtonFormField<SegMode>(
        key: ValueKey('seg${s.mode}${c.editSelectedOnly}'),
        initialValue: s.mode,
        isExpanded: true,
        items: [for (final m in SegMode.values) DropdownMenuItem(value: m, child: Text(segModeLabel(m)))],
        onChanged: (v) => c.setSegment(copySegment(s, mode: v)),
      ),
      const SizedBox(height: 6),
      SliderRow(
        label: 'Sensibilità',
        value: s.tolerance,
        min: 0.03,
        max: 0.30,
        format: (v) => v.toStringAsFixed(2),
        onChanged: (v) => c.setSegment(copySegment(s, tolerance: v)),
      ),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        dense: true,
        title: const Text('Rimuovi sfondo racchiuso (buchi)', style: TextStyle(fontSize: 13)),
        value: s.removeHoles,
        onChanged: (v) => c.setSegment(copySegment(s, removeHoles: v)),
      ),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        dense: true,
        title: const Text('Rifinisci bordi anti-alias', style: TextStyle(fontSize: 13)),
        value: s.refineEdges,
        onChanged: (v) => c.setSegment(copySegment(s, refineEdges: v)),
      ),
    ];
  }

  List<Widget> _sizeSection(BuildContext context, AppState st) {
    final ex = st.export;
    final auto = c.mode == StudioMode.original && st.selectedBase != null
        ? 'dimensione del base (${st.selectedBase!.size}px)'
        : '${st.translucentSize}px';
    return [
      const SectionTitle('Risoluzione'),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        dense: true,
        title: const Text('Risoluzione personalizzata', style: TextStyle(fontSize: 13)),
        subtitle: Text(ex.customSize ? '${ex.size}px' : 'Predefinita: $auto', style: const TextStyle(fontSize: 11)),
        value: ex.customSize,
        onChanged: (v) => st.update(() => ex.customSize = v),
      ),
      if (ex.customSize)
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final s in [128, 192, 256, 432, 512, 1024])
            ChoiceChip(label: Text('$s'), selected: ex.size == s, onSelected: (_) => st.update(() => ex.size = s)),
          SizedBox(
            width: 110,
            child: TextFormField(
              key: ValueKey('size${ex.size}'),
              initialValue: '${ex.size}',
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(suffixText: 'px'),
              onFieldSubmitted: (v) {
                final n = int.tryParse(v);
                if (n != null && n >= 16 && n <= 4096) st.update(() => ex.size = n);
              },
            ),
          ),
        ]),
    ];
  }
}

/// Live controls of the procedural translucent background.
List<Widget> translucentSliders(TranslucentSettings t, ValueChanged<TranslucentSettings> on) => [
      SliderRow(label: 'Luminosità', value: t.brightness, onChanged: (v) => on(copyTranslucent(t, brightness: v))),
      SliderRow(label: 'Frosting', value: t.frost, onChanged: (v) => on(copyTranslucent(t, frost: v))),
      SliderRow(label: 'Trasparenza sim.', value: t.transparency, onChanged: (v) => on(copyTranslucent(t, transparency: v))),
      SliderRow(
        label: 'Tinta neutra',
        value: t.tint,
        min: -1,
        max: 1,
        format: (v) => v == 0 ? '0' : (v > 0 ? 'calda ${(v * 100).round()}' : 'fredda ${(-v * 100).round()}'),
        onChanged: (v) => on(copyTranslucent(t, tint: v)),
      ),
      SliderRow(label: 'Contrasto', value: t.contrast, onChanged: (v) => on(copyTranslucent(t, contrast: v))),
      SliderRow(label: 'Bordi', value: t.border, onChanged: (v) => on(copyTranslucent(t, border: v))),
      SliderRow(label: 'Riflessi', value: t.reflection, onChanged: (v) => on(copyTranslucent(t, reflection: v))),
      SliderRow(label: 'Profondità', value: t.depth, onChanged: (v) => on(copyTranslucent(t, depth: v))),
      SliderRow(
        label: 'Curvatura',
        value: t.exponent,
        min: 3.0,
        max: 8.0,
        format: (v) => v.toStringAsFixed(2),
        onChanged: (v) => on(copyTranslucent(t, exponent: v)),
      ),
      SliderRow(
        label: 'Dimensione forma',
        value: t.shapeRatio,
        min: 0.80,
        max: 1.0,
        format: (v) => '${(v * 100).round()}%',
        onChanged: (v) => on(copyTranslucent(t, shapeRatio: v)),
      ),
    ];
