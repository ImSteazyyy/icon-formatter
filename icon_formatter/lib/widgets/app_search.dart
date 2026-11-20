import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../app/theme.dart';
import '../l10n/strings.dart';
import 'common.dart';
import 'liquid_glass.dart';

/// The one search field of the app (Studio, Your apps, Pack and every list).
///
/// A floating frosted pill of [kButtonHeight] with a search icon, the text and
/// a clear (x) button while there is text. The optional filter is a separate
/// [kButtonHeight] pill next to the field (never inside it), with a dot in
/// [Palette.selection] while a filter is active.
///
/// Usage: put it in a [SliverPinnedSearch] with `framed: false` (the field
/// already floats), or in any Row/Column. Keep [controller] owned by the caller
/// and let [onChanged] filter the list. [onClear] runs after the field is cleared.
class AppSearchField extends StatefulWidget {
  const AppSearchField({
    super.key,
    required this.controller,
    required this.hint,
    required this.onChanged,
    this.onClear,
    this.onFilter,
    this.filterOn = false,
    this.filterTooltip,
    this.fieldKey,
    this.filterKey,
  });

  final TextEditingController controller;
  final String hint;
  final ValueChanged<String> onChanged;
  final VoidCallback? onClear;

  /// Opens the filter / sort sheet. Null hides the filter button.
  final VoidCallback? onFilter;

  /// True while a filter or a sort other than the default is active (dot).
  final bool filterOn;
  final String? filterTooltip;
  final Key? fieldKey;
  final Key? filterKey;

  @override
  State<AppSearchField> createState() => _AppSearchFieldState();
}

class _AppSearchFieldState extends State<AppSearchField> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_redraw);
  }

  @override
  void didUpdateWidget(covariant AppSearchField old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller.removeListener(_redraw);
      widget.controller.addListener(_redraw);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_redraw);
    super.dispose();
  }

  // the clear button follows the text
  void _redraw() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final w = widget;
    final field = _frosted(
      SizedBox(
        height: kButtonHeight,
        child: TextField(
          key: w.fieldKey,
          controller: w.controller,
          onChanged: w.onChanged,
          decoration: _plainDecoration().copyWith(
            prefixIcon: const Icon(Icons.search, size: 20),
            suffixIcon: w.controller.text.isEmpty
                ? null
                : IconButton(
                    tooltip: S.cancellaRicerca,
                    icon: const Icon(Icons.close_rounded, size: 20),
                    onPressed: () {
                      w.controller.clear();
                      w.onChanged('');
                      w.onClear?.call();
                    },
                  ),
          ),
        ),
      ),
    );
    if (w.onFilter == null) return field;
    return Row(
      children: [
        Expanded(child: field),
        const SizedBox(width: 8),
        _FilterButton(key: w.filterKey, tooltip: w.filterTooltip ?? w.hint, on: w.filterOn, onTap: w.onFilter!),
      ],
    );
  }

  /// The field's own look inside the pill: no border, no fill.
  InputDecoration _plainDecoration() => InputDecoration(
    hintText: widget.hint,
    isDense: true,
    border: InputBorder.none,
    enabledBorder: InputBorder.none,
    focusedBorder: InputBorder.none,
    filled: false,
    contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
    hintStyle: TextStyle(color: Palette.text3),
  );
}

/// Frosted pill shared by the search field and the filter button: the same
/// surface as the pinned search of [SliverPinnedSearch].
Widget _frosted(Widget child) {
  return ClipRRect(
    borderRadius: BorderRadius.circular(kButtonHeight / 2),
    child: BackdropFilter(
      filter: ui.ImageFilter.blur(sigmaX: 32, sigmaY: 32),
      child: ColoredBox(
        color: NothingColors.navPill,
        child: Material(type: MaterialType.transparency, child: child),
      ),
    ),
  );
}

class _FilterButton extends StatelessWidget {
  const _FilterButton({super.key, required this.tooltip, required this.on, required this.onTap});
  final String tooltip;
  final bool on;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        selected: on,
        label: tooltip,
        excludeSemantics: true,
        child: SizedBox(
          width: kButtonHeight,
          height: kButtonHeight,
          child: _frosted(
            InkWell(
              customBorder: const CircleBorder(),
              onTap: onTap,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // sort and filter: its own icon, not the Customize one (tune)
                  Icon(Icons.filter_list_rounded, color: on ? Palette.selection : Palette.text),
                  if (on)
                    Positioned(
                      top: 10,
                      right: 10,
                      child: Container(
                        width: 7,
                        height: 7,
                        decoration: BoxDecoration(color: Palette.selection, shape: BoxShape.circle),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
