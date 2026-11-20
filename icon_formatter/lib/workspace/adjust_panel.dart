import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../app/models.dart';
import '../app/state.dart';
import '../app/storage.dart';
import '../app/theme.dart';
import '../services/preset_share.dart';
import '../src/rust/api/engine.dart';
import '../widgets/ai_mask.dart';
import '../widgets/common.dart';
import 'preset_chooser.dart';
import 'workspace_controller.dart';
import 'extra_compare_styles.dart';
import 'studio2_color_section.dart';
import '../l10n/strings.dart';

/// The one "Icon style" panel, shared by Studio and Your apps (and the
/// pack's style editor). Order: the mode, the essentials of the style, the
/// symbol size and the resolution. Everything technical sits in "Advanced",
/// collapsed, with one-line descriptions.
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
              SegmentedButton<StudioMode>(
                showSelectedIcon: false,
                segments: [
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
            ..._symbolSizeSection(),
            const SizedBox(height: 18),
            ..._resolutionSection(st),
            const SizedBox(height: 18),
            _advancedSection(context, st),
          ],
        );
      },
    );
  }

  /// Essentials of the chosen pipeline.
  List<Widget> _styleSection(BuildContext context, AppState st) {
    switch (c.mode) {
      case StudioMode.original:
        final b = st.selectedBase;
        return [
          SectionTitle(S.baseIcon),
          if (st.bases.isEmpty)
            Text(S.nessunBaseIconImportaneUno, style: TextStyle(color: Palette.text2))
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
                Icon(Icons.info_outline, color: Palette.warn, size: 18),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(S.baseNonCalibratoUsoProporzioni,
                      style: TextStyle(fontSize: 12, color: Palette.text2)),
                ),
                if (onOpenBases != null) TextButton(onPressed: onOpenBases, child: Text(S.calibra)),
              ]),
            ),
        ];
      case StudioMode.translucent:
        return _lucentEssentialsFor(st, context);
      case StudioMode.preset:
        final id = c.presetId ?? (c.packSettings ? st.packPresetId : st.activePresetId);
        return _presetBar(context, st, st.presetById(id));
    }
  }

  /// Preset chooser with its state: name, "Modified" pill and the actions that
  /// belong to that state (update, reset, save as new, rename, delete).
  List<Widget> _presetBar(BuildContext context, AppState st, StylePreset pr) {
    final modified = st.presetModified(pr);
    return [
      SectionTitle(S.preset),
      // every preset with its live thumbnail (rendered lazily, cached)
      SizedBox(
        height: 116,
        child: ListView.separated(
          key: const ValueKey('preset-strip'),
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(vertical: 2),
          itemCount: st.presets.length,
          separatorBuilder: (_, _) => const SizedBox(width: 8),
          itemBuilder: (_, i) {
            final x = st.presets[i];
            return PresetTile(preset: x, selected: x.id == pr.id, onTap: () => applyPresetChoice(c, x));
          },
        ),
      ),
      if (modified) ...[
        const SizedBox(height: 6),
        Align(alignment: Alignment.centerLeft, child: _ModifiedPill(label: S.ux1aModificato)),
      ],
      const SizedBox(height: 4),
      Text(
        modified ? S.ux1aModificatoNonSalvato : (pr.builtIn ? S.ux1aPresetIntegrato : S.ux1aPresetSalvato),
        style: TextStyle(fontSize: 12, color: modified ? Palette.text : Palette.text3),
      ),
      const SizedBox(height: 6),
      Wrap(spacing: 4, runSpacing: 4, children: [
        if (modified && !pr.builtIn)
          TextButton(key: const ValueKey('preset-update'), onPressed: () => st.updatePreset(pr.id), child: Text(S.ux1aAggiornaPreset)),
        if (modified)
          TextButton(key: const ValueKey('preset-reset'), onPressed: () => st.resetPreset(pr.id), child: Text(S.ux1aRipristinaPreset)),
        TextButton.icon(
          key: const ValueKey('preset-save-new'),
          icon: const Icon(Icons.save_as_outlined, size: 18),
          label: Text(S.salvaComeNuovoPreset),
          onPressed: () async {
            final name = await askText(context, S.nomeDelPreset, initial: modified || pr.builtIn ? '${pr.name} copia' : pr.name);
            if (name != null && name.isNotEmpty) {
              // the edited values become the new preset; the old one keeps its saved state
              final lk = pr.lucent;
              final n = lk != null ? st.savePresetLucent(name, lk) : st.savePresetAs(name, pr.params);
              c.setPreset(n.id);
            }
          },
        ),
        if (!pr.builtIn)
          TextButton.icon(
            key: const ValueKey('preset-rename'),
            icon: const Icon(Icons.edit_outlined, size: 18),
            label: Text(S.ux1aRinominaPreset),
            onPressed: () async {
              final name = await askText(context, S.ux1aRinominaPreset, initial: pr.name);
              if (name != null) st.renamePreset(pr.id, name);
            },
          ),
        if (!pr.builtIn)
          TextButton.icon(
            key: const ValueKey('preset-delete'),
            icon: const Icon(Icons.delete_outline, size: 18),
            label: Text(S.eliminaPreset),
            onPressed: () async {
              if (await confirm(context, S.eliminarePreset, pr.name, ok: S.elimina)) {
                st.deletePreset(pr.id);
                c.setPreset(null);
              }
            },
          ),
      ]),
      Align(
        alignment: Alignment.centerLeft,
        child: Wrap(spacing: 4, children: [
          TextButton.icon(
            onPressed: () => showCompareStyles(context, c, pr.id),
            icon: const Icon(Icons.compare_outlined, size: 18),
            label: Text(S.extraConfrontaStili),
          ),
          IconButton(tooltip: S.presetCondividiCondividi, icon: const Icon(Icons.ios_share), onPressed: () => _sharePreset(context, pr)),
          IconButton(tooltip: S.presetCondividiImporta, icon: const Icon(Icons.file_download_outlined), onPressed: () => _importPresets(context, st)),
        ]),
      ),
    ];
  }

  /// Mobile: share sheet. Desktop: save dialog, like the settings backup.
  Future<void> _sharePreset(BuildContext context, StylePreset pr) async {
    final bytes = Uint8List.fromList(utf8.encode(encodePresets([pr])));
    final fileName = 'preset-${pr.name.replaceAll(RegExp(r'[^\w-]+'), '_')}.json';
    try {
      if (Platform.isAndroid || Platform.isIOS) {
        final file = File('${AppPaths.I.cache.path}/$fileName');
        await file.writeAsBytes(bytes);
        await SharePlus.instance.share(ShareParams(files: [XFile(file.path)]));
      } else {
        final path = await FilePicker.platform.saveFile(fileName: fileName, bytes: bytes, type: FileType.custom, allowedExtensions: ['json']);
        if (path == null) return;
        await File(path).writeAsBytes(bytes);
        if (context.mounted) showMsg(context, S.presetCondividiSalvato);
      }
    } catch (e) {
      if (context.mounted) showMsg(context, S.errore(e), error: true);
    }
  }

  Future<void> _importPresets(BuildContext context, AppState st) async {
    final r = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['json'], withData: true);
    final f = r?.files.firstOrNull;
    if (f == null) return;
    try {
      final data = f.bytes ?? await File(f.path!).readAsBytes();
      final items = decodePresets(utf8.decode(data), st.defaultTranslucent);
      final id = st.importPresets(items);
      if (id != null) {
        c.setPreset(id);
        if (!c.packSettings) st.update(() => st.activePresetId = id);
      }
      if (context.mounted) showMsg(context, S.presetCondividiImportati(items.length));
    } on FormatException {
      if (context.mounted) showMsg(context, S.presetCondividiNonValido, error: true);
    } catch (e) {
      if (context.mounted) showMsg(context, S.errore(e), error: true);
    }
  }

  /// One size control for the symbol. It is the placement scale, which applies
  /// to every pipeline (the Lucent symbol scale is no longer shown twice).
  List<Widget> _symbolSizeSection() {
    final pl = c.editPlacement;
    return [
      SliderRow(
        label: S.ux1aSimbolo,
        value: pl.scaleMul,
        min: 0.5,
        max: 1.6,
        format: (v) => '${(v * 100).round()}%',
        onChanged: (v) => c.setPlacement(copyPlacement(pl, scaleMul: v)),
      ),
    ];
  }

  /// Resolution: the default is the same for Studio and Your apps (the size
  /// of the pipeline), and it is written next to the switch.
  List<Widget> _resolutionSection(AppState st) {
    final ex = st.export;
    final auto = '${st.sizeFor(c.mode)}px';
    return [
      SectionTitle(S.risoluzione),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        dense: true,
        title: Text(S.risoluzionePersonalizzata, style: TextStyle(fontSize: 13)),
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

  /// Collapsed by default. Each group opens on its own.
  Widget _advancedSection(BuildContext context, AppState st) {
    final lucent = c.mode == StudioMode.translucent;
    final pr = st.presetById(c.presetId ?? (c.packSettings ? st.packPresetId : st.activePresetId));
    return Glass(
      padding: EdgeInsets.zero,
      child: ExpansionTile(
        key: const ValueKey('style-advanced'),
        shape: const Border(),
        collapsedShape: const Border(),
        title: Text(S.ux1aAvanzate, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Palette.text)),
        childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
        children: [
          _group(S.ux1aTaglio, _segmentSection(context)),
          _group(S.composizione, _compositionSection()),
          if (c.mode == StudioMode.preset && pr.lucent != null) _group(S.ux1aAspetto, _lucentPresetControls(st, pr)),
          if (c.mode == StudioMode.preset && pr.lucent == null) _group(S.ux1aAspetto, translucentSliders(pr.params, (t) => st.setPresetParams(pr.id, t))),
          // one heading: the colour section draws its own (it used to be wrapped twice)
          if (lucent || pr.lucent != null) Studio2ColorSection(c: c),
          if (lucent) _group(S.ux1aLancio, _launcherSection(st)),
        ],
      ),
    );
  }

  Widget _group(String title, List<Widget> children) => ExpansionTile(
        title: Text(title, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Palette.text2)),
        childrenPadding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
        shape: const Border(),
        collapsedShape: const Border(),
        children: children,
      );

  /// Position, size of the usable area and the per-icon switch.
  List<Widget> _compositionSection() {
    final it = c.selected;
    final pl = c.editPlacement;
    return [
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        dense: true,
        title: Text(S.correggiSoloLIconaSelezionata, style: TextStyle(fontSize: 13)),
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
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        dense: true,
        title: Text(S.dimensioneOtticaArea, style: TextStyle(fontSize: 13)),
        subtitle: Text(S.uniformaGlyphLarghiStrettiArea, style: TextStyle(fontSize: 11)),
        value: pl.areaFit,
        onChanged: c.editSelectedOnly ? (v) => c.setPlacement(copyPlacement(pl, areaFit: v)) : null,
      ),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        dense: true,
        title: Text(S.studio2CentraturaOttica, style: TextStyle(fontSize: 13)),
        value: AppState.I.look.opticalCentre,
        onChanged: (v) => AppState.I.update(() => AppState.I.look.opticalCentre = v),
      ),
      Text(
        S.ux1aUsoAreaHint((pl.glyphRatio * pl.scaleMul * 100).toStringAsFixed(1), (pl.centerX + pl.offsetX).toStringAsFixed(3), (pl.centerY + pl.offsetY).toStringAsFixed(3)),
        style: TextStyle(fontSize: 11, color: Palette.text3),
      ),
    ];
  }

  List<Widget> _segmentSection(BuildContext context) {
    final s = c.editSegment;
    return [
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
        title: Text(S.rimuoviSfondoRacchiusoBuchi, style: TextStyle(fontSize: 13)),
        value: s.removeHoles,
        onChanged: (v) => c.setSegment(copySegment(s, removeHoles: v)),
      ),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        dense: true,
        title: Text(S.rifinisciBordiAntiAlias, style: TextStyle(fontSize: 13)),
        value: s.refineEdges,
        onChanged: (v) => c.setSegment(copySegment(s, refineEdges: v)),
      ),
      if (AppState.I.aiSettings != null && c.selected != null)
        OutlinedButton.icon(
          icon: const Icon(Icons.layers_outlined),
          label: Text(S.aiAnteprimaMascheraSelezionata),
          onPressed: () => showAiMaskDialog(context, path: c.selected!.path, bytes: c.selected!.bytes),
        ),
    ];
  }

  /// Controls of a Lucent preset: they edit the preset itself (shape, glyph
  /// colour, plate alpha), so "Modified" and the reset follow them.
  List<Widget> _lucentPresetControls(AppState st, StylePreset pr) {
    final l = pr.lucent!;
    void set(VoidCallback f) => st.update(f);
    return [
      DropdownButtonFormField<LucentShape>(
        key: ValueKey('plshape${pr.id}${l.shape}'),
        initialValue: l.shape,
        isExpanded: true,
        decoration: InputDecoration(labelText: S.lucentForma, isDense: true),
        items: [
          DropdownMenuItem(value: LucentShape.squircle, child: Text(S.lucentFormaSquircle)),
          DropdownMenuItem(value: LucentShape.circle, child: Text(S.lucentFormaCerchio)),
        ],
        onChanged: (v) => set(() => l.shape = v ?? l.shape),
      ),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        dense: true,
        title: Text(S.ux2cMonoGlyph, style: TextStyle(fontSize: 13)),
        value: l.monochrome,
        onChanged: (v) => set(() => l.monochrome = v),
      ),
      SliderRow(label: S.ux1aOpacitaSfondo, value: l.backdropAlpha, onChanged: (v) => set(() => l.backdropAlpha = v)),
    ];
  }

  List<Widget> _launcherSection(AppState st) {
    final l = st.lucent;
    void set(VoidCallback f) => st.update(f);
    return [
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        dense: true,
        title: Text(S.lucentOmbraLauncher, style: TextStyle(fontSize: 13)),
        value: l.launcherShadow && !l.launcherEncode,
        onChanged: l.launcherEncode ? null : (v) => set(() => l.launcherShadow = v),
      ),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        dense: true,
        title: Text(S.lucentCodificaLauncher, style: TextStyle(fontSize: 13)),
        subtitle: Text(S.lucentCodificaLauncherSub, style: TextStyle(fontSize: 11)),
        value: l.launcherEncode,
        onChanged: (v) => set(() => l.launcherEncode = v),
      ),
    ];
  }
}

/// One preset of the strip: its live thumbnail and name. The selected one has
/// the selection colour (never the error colour).
/// Small "Modified" pill next to the preset chooser.
class _ModifiedPill extends StatelessWidget {
  const _ModifiedPill({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Palette.selection.withValues(alpha: 0.6)),
      ),
      child: Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Palette.text)),
    );
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

/// Lucent essentials: the mode, the plate shape and its opacity. The rest of
/// the Lucent options sit in "Advanced" (see [AdjustPanel._launcherSection]).
/// Changes go through AppState, so the preview re-renders with the same Rust
/// function used by the export.
List<Widget> _lucentEssentialsFor(AppState st, BuildContext context) {
  final l = st.lucent;
  void set(VoidCallback f) => st.update(f);
  return [
    SectionTitle(
      S.lucentTitle,
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        IconButton(tooltip: S.ux1aInfo, icon: const Icon(Icons.info_outline, size: 20), onPressed: () => showMsg(context, S.lucentInfo)),
        TextButton(onPressed: () => set(l.reset), child: Text(S.ripristina)),
      ]),
    ),
    SegmentedButton<bool>(
      showSelectedIcon: false,
      segments: [
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
      isExpanded: true,
      decoration: InputDecoration(labelText: S.lucentForma, isDense: true),
      items: [
        DropdownMenuItem(value: LucentShape.squircle, child: Text(S.lucentFormaSquircle)),
        DropdownMenuItem(value: LucentShape.circle, child: Text(S.lucentFormaCerchio)),
        DropdownMenuItem(value: LucentShape.original, child: Text(S.lucentFormaOriginale)),
      ],
      onChanged: (v) => set(() => l.shape = v ?? l.shape),
    ),
    const SizedBox(height: 6),
    SliderRow(label: S.ux1aOpacitaSfondo, value: l.backdropAlpha, onChanged: (v) => set(() => l.backdropAlpha = v)),
  ];
}
