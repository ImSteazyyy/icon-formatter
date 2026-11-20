import 'package:flutter/material.dart';

import '../app/theme.dart';

/// The one empty state of the app: an icon, a short title, an optional
/// one-line hint and an optional action. Use it wherever a list, a preview or
/// an option has nothing to show (for example "No icon selected").
///
/// Texts wrap instead of being cut, so keep [title] and [hint] short; the
/// widget never truncates them.
class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.title, this.hint, this.action});

  final IconData icon;
  final String title;
  final String? hint;

  /// Usually a button ("Add icons"). Shown below the texts.
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 320),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ExcludeSemantics(child: Icon(icon, size: 40, color: Palette.text3)),
              const SizedBox(height: 12),
              Text(
                title,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Palette.text),
              ),
              if (hint != null) ...[
                const SizedBox(height: 4),
                Text(hint!, textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: Palette.text2)),
              ],
              if (action != null) ...[const SizedBox(height: 16), action!],
            ],
          ),
        ),
      ),
    );
  }
}
