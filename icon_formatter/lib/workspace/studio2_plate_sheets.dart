import 'package:flutter/material.dart';

import '../app/state.dart';
import '../app/theme.dart';
import '../l10n/strings.dart';
import '../src/rust/api/engine.dart';
import '../widgets/color_picker.dart';
import '../widgets/common.dart';
import '../widgets/liquid_glass.dart';
import 'workspace_controller.dart';

/// Per-icon plate shape (Lightnt only). Picking one processes the icon again.
Future<void> studio2PlateShapeSheet(
  BuildContext context,
  WorkspaceController c,
  WorkItem it,
) async {
  final options = <(LucentShape?, String)>[
    (LucentShape.circle, S.lucentFormaCerchio),
    (LucentShape.squircle, S.lucentFormaSquircle),
    (LucentShape.original, S.lucentFormaOriginale),
    (null, S.studio2FormaPredefinita),
  ];
  final r = await showAppSheet<({LucentShape? shape})>(
    context: context,
    builder: (ctx) => SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final (v, t) in options)
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 22),
              title: Text(t),
              trailing: v == it.shapeOverride
                  ? Icon(
                      Icons.check_rounded,
                      color: Palette.selection,
                    )
                  : null,
              onTap: () => Navigator.pop(ctx, (shape: v)),
            ),
        ],
      ),
    ),
  );
  if (r != null) c.setItemShape(it, r.shape);
}

/// Per-icon plate colour (Lightnt only): colour picker and opacity. "Default"
/// clears the override. Dismissing the sheet changes nothing.
Future<void> studio2PlateColorSheet(
  BuildContext context,
  WorkspaceController c,
  WorkItem it,
) async {
  var argb = it.backdropOverride ?? AppState.I.lucent.toSettings().backdrop;
  final r = await showAppSheet<({int? value})>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, set) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              S.studio2ColorePiattoTitolo,
              style: Theme.of(ctx).textTheme.titleMedium,
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color(argb),
                ),
              ),
              title: Text(S.studio2ColoreScegli),
              onTap: () => showColorPicker(
                ctx,
                initial: 0xFF000000 | (argb & 0xFFFFFF),
                title: S.studio2ColorePiattoTitolo,
                onChanged: (v) =>
                    set(() => argb = (argb & 0xFF000000) | (v & 0xFFFFFF)),
              ),
            ),
            SliderRow(
              label: S.lucentOpacitaPiatto,
              value: (argb >> 24) / 255,
              onChanged: (v) => set(
                () => argb = (((v * 255).round()) << 24) | (argb & 0xFFFFFF),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, (value: null)),
                  child: Text(S.studio2PredefinitoColore),
                ),
                const Spacer(),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx, (value: argb)),
                  child: Text(S.studio2Applica),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
  if (r != null) c.setItemBackdrop(it, r.value);
}
