import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../l10n/strings.dart';
import '../../widgets/liquid_glass.dart';
import 'pb_controller.dart';
import 'pb_model.dart';

/// "Change background" of the whole pack: plate opacity and colour, applied to
/// every icon from its saved cut-out (no segmentation again).
Future<void> showPlateSheet(BuildContext context, PackBuilderController c) =>
    showAppSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _PlateSheet(c: c),
    );

class _PlateSheet extends StatefulWidget {
  const _PlateSheet({required this.c});

  final PackBuilderController c;

  @override
  State<_PlateSheet> createState() => _PlateSheetState();
}

class _PlateSheetState extends State<_PlateSheet> {
  late double _opacity = widget.c.plate?.opacity ?? 0.4;
  late String _mode = widget.c.plate?.mode ?? 'auto';

  /// True while the pack is re-composed: the sheet shows the progress and Cancel.
  bool _running = false;

  /// Starts the re-composition. The sheet stays open with progress and a
  /// Cancel button; icons already done are kept when it is cancelled.
  Future<void> _apply() async {
    final c = widget.c;
    c.plate = PlateOverride(opacity: _opacity, mode: _mode);
    setState(() => _running = true);
    await c.generateFromOriginals(only: [for (final r in c.rows) if (!r.excluded) r]);
    if (mounted) setState(() => _running = false);
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.c;
    final shown = c.generated.take(6).toList();
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(S.ux1bChangeBg, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: Palette.text)),
            const SizedBox(height: 4),
            Text(S.ux1bPlateHint, style: TextStyle(fontSize: 13, color: Palette.text2)),
            const SizedBox(height: 14),
            // the icons as they are now: the new plate shows once applied
            SizedBox(
              height: 64,
              child: shown.isEmpty
                  ? const SizedBox()
                  : ListView(
                      scrollDirection: Axis.horizontal,
                      children: [for (final g in shown) Padding(padding: const EdgeInsets.only(right: 8), child: g.image(size: 56))],
                    ),
            ),
            const SizedBox(height: 4),
            Text(S.ux1bPlatePreview, style: TextStyle(fontSize: 12, color: Palette.text3)),
            const SizedBox(height: 14),
            Row(children: [
              Expanded(child: Text(S.ux1bPlateOpacity, style: TextStyle(fontSize: 14, color: Palette.text))),
              Text('${(_opacity * 100).round()}%', style: TextStyle(fontSize: 13, color: Palette.text2)),
            ]),
            Slider(
              key: const ValueKey('plate-opacity'),
              value: _opacity,
              min: 0.1,
              max: 1,
              onChanged: _running ? null : (v) => setState(() => _opacity = v),
            ),
            const SizedBox(height: 6),
            Text(S.ux1bPlateMode, style: TextStyle(fontSize: 14, color: Palette.text)),
            const SizedBox(height: 8),
            SegmentedButton<String>(
              key: const ValueKey('plate-mode'),
              segments: [
                ButtonSegment(value: 'auto', label: Text(S.ux1bPlateAuto)),
                ButtonSegment(value: 'dark', label: Text(S.ux1bPlateDark)),
                ButtonSegment(value: 'light', label: Text(S.ux1bPlateLight)),
              ],
              selected: {_mode},
              onSelectionChanged: _running ? null : (s) => setState(() => _mode = s.first),
            ),
            const SizedBox(height: 18),
            if (_running) ...[
              LinearProgressIndicator(key: const ValueKey('plate-progress'), value: c.progress),
              const SizedBox(height: 6),
              Text(c.status ?? '', style: TextStyle(fontSize: 12, color: Palette.text2)),
              const SizedBox(height: 10),
              SizedBox(
                height: 52,
                child: OutlinedButton.icon(
                  key: const ValueKey('plate-cancel'),
                  icon: const Icon(Icons.close_rounded),
                  label: Text(S.annulla),
                  onPressed: c.cancelGeneration,
                ),
              ),
            ] else
              SizedBox(
                height: 52,
                child: FilledButton.icon(
                  key: const ValueKey('plate-apply'),
                  icon: const Icon(Icons.format_paint_outlined),
                  label: Text(S.ux1bApplyAll),
                  onPressed: c.busy || c.rows.isEmpty ? null : _apply,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
