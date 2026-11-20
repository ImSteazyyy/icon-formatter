import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../app/state.dart';
import '../../app/theme.dart';
import '../../l10n/strings.dart';
import '../../widgets/common.dart';
import 'pb_model.dart';

/// One way to treat the icon, as the picker shows it.
class TreatmentOption {
  const TreatmentOption(
    this.value,
    this.icon,
    this.title,
    this.hint, {
    this.recommended = false,
  });

  final EditTreatment value;
  final IconData icon;
  final String title;
  final String hint;
  final bool recommended;
}

/// Choice of the edit page: a two-column grid of tiles, each with an icon and
/// a live thumbnail of the icon under that treatment. The rarer options sit
/// behind "Altre opzioni", so the first view shows four choices.
class TreatmentPicker extends StatefulWidget {
  const TreatmentPicker({
    super.key,
    required this.value,
    required this.onChanged,
    this.thumbnail,
    this.enabled = true,
  });

  final EditTreatment value;
  final ValueChanged<EditTreatment> onChanged;

  /// Thumbnail of one treatment; null while there is no image to show.
  final Future<Uint8List> Function(EditTreatment treatment)? thumbnail;

  /// False until an image is picked: the tiles stay visible but dimmed.
  final bool enabled;

  @override
  State<TreatmentPicker> createState() => _TreatmentPickerState();
}

List<TreatmentOption> get _mainOptions => [
  TreatmentOption(
    EditTreatment.auto,
    Icons.auto_awesome_rounded,
    S.modoAuto,
    S.ux1bHintAuto,
    recommended: true,
  ),
  TreatmentOption(
    EditTreatment.asIs,
    Icons.category_outlined,
    S.pbOptSimboloT,
    S.ux1bHintSymbol,
  ),
  TreatmentOption(
    EditTreatment.plateColor,
    Icons.palette_outlined,
    S.modoColorePiatto,
    S.ux1bHintPlate,
  ),
  TreatmentOption(
    EditTreatment.fullBleed,
    Icons.border_outer_rounded,
    S.modoBordoPieno,
    S.ux1bHintFull,
  ),
];

List<TreatmentOption> get _moreOptions => [
  TreatmentOption(
    EditTreatment.placeOnly,
    Icons.crop_free_rounded,
    S.pbOptIconaT,
    S.ux1bHintPlace,
  ),
  TreatmentOption(
    EditTreatment.raw,
    Icons.image_outlined,
    S.pbOptOriginaleT,
    S.ux1bHintRaw,
  ),
];

class _TreatmentPickerState extends State<TreatmentPicker> {
  /// Opened by default when the icon already uses one of the rarer options.
  late bool _more = _moreOptions.any((o) => o.value == widget.value);

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Opacity(
          opacity: widget.enabled ? 1 : 0.45,
          child: IgnorePointer(
            ignoring: !widget.enabled,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _grid(_mainOptions),
                Semantics(
                  expanded: _more,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      key: const ValueKey('edit-more'),
              style: TextButton.styleFrom(foregroundColor: Palette.text2),
                      icon: Icon(
                        _more
                            ? Icons.expand_less_rounded
                            : Icons.expand_more_rounded,
                        size: 20,
                      ),
                      label: Text(S.pbEditAltre),
                      onPressed: () => setState(() => _more = !_more),
                    ),
                  ),
                ),
                if (_more) _grid(_moreOptions),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _grid(List<TreatmentOption> items) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (var i = 0; i < items.length; i += 2) ...[
        if (i > 0) const SizedBox(height: 8),
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: _tile(items[i])),
              const SizedBox(width: 8),
              Expanded(
                child: i + 1 < items.length
                    ? _tile(items[i + 1])
                    : const SizedBox(),
              ),
            ],
          ),
        ),
      ],
    ],
  );

  Widget _tile(TreatmentOption o) {
    final selected = o.value == widget.value;
    final accent = Palette.selection;
    final radius = BorderRadius.circular(AppState.I.appearance.radius);
    return Semantics(
      key: ValueKey('treatment-${o.value.name}'),
      button: true,
      selected: selected,
      label: '${o.title}. ${o.hint}',
      excludeSemantics: true,
      onTap: () => widget.onChanged(o.value),
      child: InkWell(
        borderRadius: radius,
        onTap: () => widget.onChanged(o.value),
        child: Container(
          // the outline is drawn over the tile, so the tile keeps its own fill
          foregroundDecoration: selected && widget.enabled
              ? BoxDecoration(
                  borderRadius: radius,
                  border: Border.all(color: accent, width: 2),
                )
              : null,
          child: Tile(
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    IconChip(
                      icon: o.icon,
                      size: 28,
                      color: selected ? accent : Palette.text2,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        o.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Palette.text,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Center(child: _thumb(o.value)),
                const SizedBox(height: 4),
                // no line cap: the hint wraps at any text scale, never cut off
                Text(
                  o.hint,
                  style: TextStyle(fontSize: 12, color: Palette.text2),
                ),
                if (o.recommended) ...[
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    decoration: BoxDecoration(color: Palette.fg.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(999)),
                    child: Text(S.pbEditConsigliato, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Palette.text2)),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _thumb(EditTreatment t) {
    final future = widget.thumbnail?.call(t);
    return SizedBox(
      width: 40,
      height: 40,
      child: Checkerboard(
        cell: 6,
        child: future == null
            ? Center(
                child: Icon(
                  Icons.image_outlined,
                  size: 26,
                  color: Palette.text3,
                ),
              )
            : FutureBuilder<Uint8List>(
                future: future,
                builder: (context, snap) {
                  if (snap.hasData) {
                    return Padding(
                      padding: const EdgeInsets.all(4),
                      child: IconImage(bytes: snap.data),
                    );
                  }
                  if (snap.hasError) {
                    return Center(
                      child: Icon(
                        Icons.broken_image_outlined,
                        size: 24,
                        color: Palette.text3,
                      ),
                    );
                  }
                  return const Center(
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  );
                },
              ),
      ),
    );
  }
}
