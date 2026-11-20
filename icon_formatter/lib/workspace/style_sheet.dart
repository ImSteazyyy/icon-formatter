import 'package:flutter/material.dart';

import '../app/theme.dart';
import '../l10n/strings.dart';
import '../widgets/liquid_glass.dart';
import 'adjust_panel.dart';
import 'preset_chooser.dart';
import 'workspace_controller.dart';

/// The one "Icon style" sheet: Studio and Your apps both open it, so the two
/// stay identical. [modeChooser] is an optional row above the panel (Your apps
/// uses it for its pipeline choice); it gets the sheet's setState so it can
/// redraw the panel too.
Future<void> showStyleSheet(
  BuildContext context, {
  required WorkspaceController c,
  bool showModes = true,
  VoidCallback? onOpenBases,
  Widget Function(StateSetter setSheet)? modeChooser,
}) {
  return showAppSheet(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setSheet) => SizedBox(
        height: MediaQuery.of(ctx).size.height * 0.80,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
              child: Text(S.stileTitolo, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: Palette.text)),
            ),
            if (modeChooser != null) Padding(padding: const EdgeInsets.fromLTRB(12, 0, 12, 0), child: modeChooser(setSheet)),
            // icons waiting to be processed: the four looks are one tap away
            if (c.active.isNotEmpty && c.processed.isEmpty) ImportStyleCard(c: c),
            Expanded(child: AdjustPanel(c: c, showModes: showModes, onOpenBases: onOpenBases)),
            _RecomposeBar(c: c),
          ],
        ),
      ),
    ),
  );
}

/// Re-composes the processed icons with the plate chosen above, from their
/// saved cut-outs: no segmentation, so no "Process all" is needed for a plate change.
class _RecomposeBar extends StatelessWidget {
  const _RecomposeBar({required this.c});

  final WorkspaceController c;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: Listenable.merge([c, c.batch]),
        builder: (context, _) => Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
          child: Row(children: [
            Expanded(child: Text(S.ux2bChangeBgSub, style: TextStyle(fontSize: 11.5, color: Palette.text2))),
            const SizedBox(width: 10),
            FilledButton.tonalIcon(
              key: const ValueKey('style-recompose'),
              // close the sheet first: the progress strip behind it is the feedback
              onPressed: c.canRecompose ? () { Navigator.of(context).pop(); c.recomposeProcessed(); } : null,
              icon: const Icon(Icons.format_paint_outlined, size: 18),
              label: Text(S.ux2bApplyProcessed),
            ),
          ]),
        ),
      );
}
