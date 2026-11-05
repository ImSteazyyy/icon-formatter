import 'package:flutter/material.dart';

import '../app/models.dart';
import '../app/state.dart';
import '../app/theme.dart';
import '../src/rust/api/engine.dart';
import '../widgets/ai_mask.dart';
import '../widgets/common.dart';
import 'workspace_controller.dart';
import '../l10n/strings.dart';

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
              const SectionTitle(S.modalita),
              SegmentedButton<StudioMode>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: StudioMode.original, label: Text(S.original)),
                  ButtonSegment(value: StudioMode.translucent, label: Text(S.translucent)),
                  ButtonSegment(value: StudioMode.preset, label: Text(S.preset)),
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
          const SectionTitle(S.baseIcon),
          if (st.bases.isEmpty)
            const Text(S.nessunBaseIconImportaneUno, style: TextStyle(color: Palette.text2))
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
                  child: Text(S.baseNonCalibratoUsoProporzioni,
                      style: TextStyle(fontSize: 12, color: Palette.text2)),
                ),
                if (onOpenBases != null) TextButton(onPressed: onOpenBases, child: const Text(S.calibra)),
              ]),
            )
          else if (b?.calibration != null)
            Text(
              S.calibratoGlyphCentro((b!.calibration!.glyphRatio * 100).toStringAsFixed(1), b.calibration!.centerX.toStringAsFixed(3), b.calibration!.centerY.toStringAsFixed(3)),
              style: const TextStyle(fontSize: 12, color: Palette.text2),
            ),
        ];
      case StudioMode.translucent:
        return lucentControls(st);
      case StudioMode.preset:
        final id = c.presetId ?? (c.packSettings ? st.packPresetId : st.activePresetId);
        final pr = st.presetById(id);
        return [
          const SectionTitle(S.preset),
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
              tooltip: S.salvaComeNuovoPreset,
              icon: const Icon(Icons.save_as_outlined),
              onPressed: () async {
                final name = await askText(context, S.nomeDelPreset, initial: '${pr.name} copia');
                if (name != null && name.isNotEmpty) {
                  final n = st.savePresetAs(name, pr.params);
                  c.setPreset(n.id);
                }
              },
            ),
            if (pr.builtIn)
              IconButton(tooltip: S.ripristinaValori, icon: const Icon(Icons.restart_alt), onPressed: () => st.resetPreset(pr.id))
            else
              IconButton(
                tooltip: S.eliminaPreset,
                icon: const Icon(Icons.delete_outline),
                onPressed: () async {
                  if (await confirm(context, S.eliminarePreset, pr.name, ok: S.elimina)) {
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
      SectionTitle(S.composizione,
          trailing: it != null && it.hasOverride
              ? TextButton(onPressed: () => c.clearOverrides(it), child: const Text(S.rimuoviCorrezioni))
              : null),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        dense: true,
        title: const Text(S.correggiSoloLIconaSelezionata, style: TextStyle(fontSize: 13)),
        subtitle: Text(it == null ? S.nessunaIconaSelezionata : it.name, style: const TextStyle(fontSize: 11)),
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
        label: S.scala,
        value: pl.scaleMul,
        min: 0.5,
        max: 1.6,
        format: (v) => '${(v * 100).round()}%',
        onChanged: (v) => c.setPlacement(copyPlacement(pl, scaleMul: v)),
      ),
      SliderRow(
        label: S.posizioneX,
        value: pl.offsetX,
        min: -0.15,
        max: 0.15,
        format: (v) => (v * 100).toStringAsFixed(1),
        onChanged: (v) => c.setPlacement(copyPlacement(pl, offsetX: v)),
      ),
      SliderRow(
        label: S.posizioneY,
        value: pl.offsetY,
        min: -0.15,
        max: 0.15,
        format: (v) => (v * 100).toStringAsFixed(1),
        onChanged: (v) => c.setPlacement(copyPlacement(pl, offsetY: v)),
      ),
      if (c.editSelectedOnly)
        SliderRow(
          label: S.latoGlyph,
          value: pl.glyphRatio,
          min: 0.3,
          max: 0.9,
          format: (v) => '${(v * 100).round()}%',
          onChanged: (v) => c.setPlacement(copyPlacement(pl, glyphRatio: v)),
        ),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        dense: true,
        title: const Text(S.dimensioneOtticaArea, style: TextStyle(fontSize: 13)),
        subtitle: const Text(S.uniformaGlyphLarghiStrettiArea, style: TextStyle(fontSize: 11)),
        value: pl.areaFit,
        onChanged: c.editSelectedOnly ? (v) => c.setPlacement(copyPlacement(pl, areaFit: v)) : null,
      ),
      Text(
        S.areaUtileLatoGlyphCentro((pl.glyphRatio * pl.scaleMul * 100).toStringAsFixed(1), (pl.centerX + pl.offsetX).toStringAsFixed(3), (pl.centerY + pl.offsetY).toStringAsFixed(3)),
        style: const TextStyle(fontSize: 11, color: Palette.text3),
      ),
    ];
  }

  List<Widget> _segmentSection(BuildContext context) {
    final s = c.editSegment;
    return [
      const SectionTitle(S.isolamentoGlyph),
      DropdownButtonFormField<SegMode>(
        key: ValueKey('seg${s.mode}${c.editSelectedOnly}'),
        initialValue: s.mode,
        isExpanded: true,
        items: [for (final m in SegMode.values) DropdownMenuItem(value: m, child: Text(segModeLabel(m)))],
        onChanged: (v) => c.setSegment(copySegment(s, mode: v)),
      ),
      const SizedBox(height: 6),
      SliderRow(
        label: S.sensibilita,
        value: s.tolerance,
        min: 0.03,
        max: 0.30,
        format: (v) => v.toStringAsFixed(2),
        onChanged: (v) => c.setSegment(copySegment(s, tolerance: v)),
      ),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        dense: true,
        title: const Text(S.rimuoviSfondoRacchiusoBuchi, style: TextStyle(fontSize: 13)),
        value: s.removeHoles,
        onChanged: (v) => c.setSegment(copySegment(s, removeHoles: v)),
      ),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        dense: true,
        title: const Text(S.rifinisciBordiAntiAlias, style: TextStyle(fontSize: 13)),
        value: s.refineEdges,
        onChanged: (v) => c.setSegment(copySegment(s, refineEdges: v)),
      ),
      if (AppState.I.aiSettings != null && c.selected != null)
        OutlinedButton.icon(
          icon: const Icon(Icons.layers_outlined),
          label: const Text(S.aiAnteprimaMascheraSelezionata),
          onPressed: () => showAiMaskDialog(context, path: c.selected!.path, bytes: c.selected!.bytes),
        ),
    ];
  }

  List<Widget> _sizeSection(BuildContext context, AppState st) {
    final ex = st.export;
    final auto = c.mode == StudioMode.original && st.selectedBase != null
        ? S.dimensioneDelBasePx(st.selectedBase!.size)
        : '${st.translucentSize}px';
    return [
      const SectionTitle(S.risoluzione),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        dense: true,
        title: const Text(S.risoluzionePersonalizzata, style: TextStyle(fontSize: 13)),
        subtitle: Text(ex.customSize ? '${ex.size}px' : S.predefinita(auto), style: const TextStyle(fontSize: 11)),
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
      SliderRow(label: S.luminosita, value: t.brightness, onChanged: (v) => on(copyTranslucent(t, brightness: v))),
      SliderRow(label: S.frosting, value: t.frost, onChanged: (v) => on(copyTranslucent(t, frost: v))),
      SliderRow(label: S.trasparenzaSim, value: t.transparency, onChanged: (v) => on(copyTranslucent(t, transparency: v))),
      SliderRow(
        label: S.tintaNeutra,
        value: t.tint,
        min: -1,
        max: 1,
        format: (v) => v == 0 ? '0' : (v > 0 ? 'calda ${(v * 100).round()}' : 'fredda ${(-v * 100).round()}'),
        onChanged: (v) => on(copyTranslucent(t, tint: v)),
      ),
      SliderRow(label: S.contrasto, value: t.contrast, onChanged: (v) => on(copyTranslucent(t, contrast: v))),
      SliderRow(label: S.bordi, value: t.border, onChanged: (v) => on(copyTranslucent(t, border: v))),
      SliderRow(label: S.riflessi, value: t.reflection, onChanged: (v) => on(copyTranslucent(t, reflection: v))),
      SliderRow(label: S.profondita, value: t.depth, onChanged: (v) => on(copyTranslucent(t, depth: v))),
      SliderRow(
        label: S.curvatura,
        value: t.exponent,
        min: 3.0,
        max: 8.0,
        format: (v) => v.toStringAsFixed(2),
        onChanged: (v) => on(copyTranslucent(t, exponent: v)),
      ),
      SliderRow(
        label: S.dimensioneForma,
        value: t.shapeRatio,
        min: 0.80,
        max: 1.0,
        format: (v) => '${(v * 100).round()}%',
        onChanged: (v) => on(copyTranslucent(t, shapeRatio: v)),
      ),
    ];


/// Lucent (Nothing OS 5.0) controls. Changes go through AppState, so the
/// preview re-renders with the same Rust function used by the export.
List<Widget> lucentControls(AppState st) {
  final l = st.lucent;
  void set(VoidCallback f) => st.update(f);
  return [
    SectionTitle(S.lucentTitle, trailing: TextButton(onPressed: () => set(l.reset), child: const Text(S.ripristina))),
    const Text(S.lucentInfo, style: TextStyle(fontSize: 12, color: Palette.text2)),
    const SizedBox(height: 10),
    SegmentedButton<bool>(
      showSelectedIcon: false,
      segments: const [
        ButtonSegment(value: true, label: Text(S.lucentScuro), icon: Icon(Icons.dark_mode_outlined)),
        ButtonSegment(value: false, label: Text(S.lucentChiaro), icon: Icon(Icons.light_mode_outlined)),
      ],
      selected: {l.dark},
      onSelectionChanged: (v) => set(() => l.dark = v.first),
    ),
    const SizedBox(height: 10),
    DropdownButtonFormField<LucentShape>(
      key: ValueKey('lshape${l.shape}'),
      initialValue: l.shape,
      decoration: const InputDecoration(labelText: S.lucentForma, isDense: true),
      items: const [
        DropdownMenuItem(value: LucentShape.squircle, child: Text(S.lucentFormaSquircle)),
        DropdownMenuItem(value: LucentShape.circle, child: Text(S.lucentFormaCerchio)),
        DropdownMenuItem(value: LucentShape.original, child: Text(S.lucentFormaOriginale)),
      ],
      onChanged: (v) => set(() => l.shape = v ?? l.shape),
    ),
    const SizedBox(height: 6),
    SliderRow(label: S.lucentOpacitaPiatto, value: l.backdropAlpha, onChanged: (v) => set(() => l.backdropAlpha = v)),
    SliderRow(label: S.lucentScalaGlifo, value: l.glyphScale, min: 0.5, max: 1.6, format: (v) => '${(v * 100).round()}%', onChanged: (v) => set(() => l.glyphScale = v)),
    SliderRow(label: S.lucentBordoLuce, value: l.rim, onChanged: (v) => set(() => l.rim = v)),
    SwitchListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      title: const Text(S.lucentMantieniComposizione, style: TextStyle(fontSize: 13)),
      subtitle: const Text(S.lucentMantieniComposizioneSub, style: TextStyle(fontSize: 11)),
      value: l.keepComposition,
      onChanged: (v) => set(() => l.keepComposition = v),
    ),
    SwitchListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      title: const Text(S.lucentMonocromatico, style: TextStyle(fontSize: 13)),
      subtitle: const Text(S.lucentMonocromaticoSub, style: TextStyle(fontSize: 11)),
      value: l.monochrome,
      onChanged: (v) => set(() => l.monochrome = v),
    ),
    SwitchListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      title: const Text(S.lucentOmbraLauncher, style: TextStyle(fontSize: 13)),
      value: l.launcherShadow && !l.nothingEncode,
      onChanged: l.nothingEncode ? null : (v) => set(() => l.launcherShadow = v),
    ),
    SwitchListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      title: const Text(S.lucentCodificaNothing, style: TextStyle(fontSize: 13)),
      subtitle: const Text(S.lucentCodificaNothingSub, style: TextStyle(fontSize: 11)),
      value: l.nothingEncode,
      onChanged: (v) => set(() => l.nothingEncode = v),
    ),
  ];
}
