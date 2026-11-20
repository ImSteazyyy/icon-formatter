import 'package:flutter/material.dart';

import '../app/theme.dart';
import 'liquid_glass.dart';
import 'common.dart';

/// Row of a settings card in the Pack tab: icon chip, one-line title, optional
/// one-line subtitle, trailing control. Same proportions as [SettingSwitch], so
/// it reads as a sibling of the Settings rows.
class PackRow extends StatelessWidget {
  const PackRow({super.key, required this.icon, required this.title, this.subtitle, this.trailing, this.onTap, this.iconColor});

  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;

  /// Tint of the icon chip (status); the accent when null.
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    final body = Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          // Nothing style: a neutral chip, red stays for real accents and errors
          IconChip(icon: icon, color: iconColor ?? (nothingStyle ? Palette.text2 : null)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 15, color: Palette.text)),
                // two lines at most: a long hint wraps instead of being cut mid-word
                if (subtitle != null) Text(subtitle!, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: Palette.text2)),
              ],
            ),
          ),
          if (trailing != null) ...[const SizedBox(width: 10), trailing!],
        ],
      ),
    );
    // the ink paints on this transparent Material, above the card's fill
    // one node for screen readers: the title labels the switch or value inside
    return Material(type: MaterialType.transparency, child: InkWell(borderRadius: BorderRadius.circular(12), onTap: onTap, child: MergeSemantics(child: body)));
  }
}

/// Value of a row that opens a choice or a picker: a neutral pill (no accent),
/// with a chevron when tapping it changes the value.
class PackValue extends StatelessWidget {
  const PackValue(this.text, {super.key, this.chevron = false});

  final String text;
  final bool chevron;

  @override
  Widget build(BuildContext context) => Flexible(
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(color: Palette.fg.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(10)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: Palette.text))),
          if (chevron) ...[const SizedBox(width: 4), Icon(Icons.unfold_more_rounded, size: 16, color: Palette.text2)],
        ],
      ),
    ),
  );
}

/// Plain muted value at the right end of a status row ("Versione 1.2").
class PackMuted extends StatelessWidget {
  const PackMuted(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Flexible(
    child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.right, style: TextStyle(fontSize: 13, color: Palette.text2)),
  );
}
