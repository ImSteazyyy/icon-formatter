import 'package:flutter/material.dart';

import '../app/models.dart';
import '../app/preset_names.dart';
import '../app/state.dart';
import '../app/theme.dart';
import '../l10n/strings.dart';
import 'preset_thumb.dart';
import 'workspace_controller.dart';

/// One look as a tile: the live thumbnail (rendered by the engine) with its
/// name under it. Selected: the accent outline.
class PresetTile extends StatelessWidget {
  const PresetTile({super.key, required this.preset, required this.selected, required this.onTap, this.thumb = 72});

  final StylePreset preset;
  final bool selected;
  final VoidCallback onTap;

  /// Edge of the thumbnail in dp (at least 64).
  final double thumb;

  @override
  Widget build(BuildContext context) {
    final name = presetDisplayName(preset);
    return Semantics(
      button: true,
      selected: selected,
      label: name,
      excludeSemantics: true,
      child: SizedBox(
        width: thumb + 12,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: thumb,
              height: thumb,
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                color: Palette.raised,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: selected ? Palette.selection : Palette.fg.withValues(alpha: 0.12), width: selected ? 2 : 1),
              ),
              child: ClipRRect(borderRadius: BorderRadius.circular(14), child: PresetThumb(preset: preset)),
            ),
            const SizedBox(height: 4),
            Text(
              name,
              textAlign: TextAlign.center,
              maxLines: 2,
              style: TextStyle(fontSize: 12, fontWeight: selected ? FontWeight.w700 : FontWeight.w500, color: selected ? Palette.text : Palette.text2),
            ),
          ]),
        ),
      ),
    );
  }
}

/// The built-in looks as a 2x2 grid: squircle and circle, colour and mono.
class PresetChooser extends StatelessWidget {
  const PresetChooser({super.key, required this.selectedId, required this.onPick, this.thumb = 72});

  final String? selectedId;
  final ValueChanged<StylePreset> onPick;
  final double thumb;

  @override
  Widget build(BuildContext context) {
    final builtIns = AppState.I.presets.where((p) => p.builtIn).toList();
    Widget cell(StylePreset p) => PresetTile(preset: p, selected: p.id == selectedId, thumb: thumb, onTap: () => onPick(p));
    final rows = <Widget>[];
    for (var i = 0; i < builtIns.length; i += 2) {
      rows.add(Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          cell(builtIns[i]),
          if (i + 1 < builtIns.length) cell(builtIns[i + 1]) else const SizedBox(width: 84),
        ],
      ));
      if (i + 2 < builtIns.length) rows.add(const SizedBox(height: 8));
    }
    return Column(mainAxisSize: MainAxisSize.min, children: rows);
  }
}

/// Applies a look to the workspace: switches to the preset pipeline and makes
/// it the active look (the pack keeps its own choice).
void applyPresetChoice(WorkspaceController c, StylePreset p) {
  c.mode = StudioMode.preset;
  c.setPreset(p.id);
  if (!c.packSettings) AppState.I.update(() => AppState.I.activePresetId = p.id);
}

/// "Choose a style" card shown right after icons are imported: the four looks
/// as tiles; a tap applies the look. Processing starts only from the bottom
/// "Process all" button, so the screen has one start action.
class ImportStyleCard extends StatelessWidget {
  const ImportStyleCard({super.key, required this.c});
  final WorkspaceController c;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([c, AppState.I]),
      builder: (context, _) {
        final st = AppState.I;
        final selected = c.packSettings ? st.packPresetId : st.activePresetId;
        return Container(
          key: const ValueKey('import-style-card'),
          margin: const EdgeInsets.fromLTRB(8, 4, 8, 8),
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          decoration: BoxDecoration(
            color: Palette.raised,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Palette.fg.withValues(alpha: 0.12)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(S.ux2cChooseStyle, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Palette.text)),
              const SizedBox(height: 2),
              Text(S.ux2cChooseStyleSub, style: TextStyle(fontSize: 12, color: Palette.text2)),
              const SizedBox(height: 10),
              Center(child: PresetChooser(selectedId: selected, thumb: 64, onPick: (p) => applyPresetChoice(c, p))),
            ],
          ),
        );
      },
    );
  }
}
