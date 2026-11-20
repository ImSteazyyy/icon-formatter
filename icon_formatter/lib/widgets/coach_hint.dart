import 'package:flutter/material.dart';

import '../app/state.dart';
import '../app/theme.dart';
import '../l10n/strings.dart';
import 'common.dart';
import 'tour2_visibility.dart';
import 'toasts.dart';

/// First-run hints: one small card per section, shown the first time the
/// section is open and dismissed for good. The "seen" flags are the
/// [AppState.seenGuides] entries `coach-<section>`, so they survive restarts
/// and backups. Existing users, who have no flags yet, see each hint once.
class CoachHintLayer extends StatelessWidget {
  const CoachHintLayer({
    super.key,
    required this.tabId,
    required this.bottom,
    required this.child,
  });

  /// Section id as the shell names it: studio, builder (Pack) or apps.
  final String tabId;

  /// Height the floating bars take at the bottom; the card sits above them.
  final double bottom;

  final Widget child;

  static String? textFor(String tabId) => switch (tabId) {
    'studio' => S.ux1a2CoachStudio,
    'builder' => S.ux1a2CoachPack,
    'apps' => S.ux1a2CoachApps,
    _ => null,
  };

  static String keyFor(String tabId) => 'coach-$tabId';

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([AppState.I, ProgressStrip.live]),
      builder: (context, _) => ValueListenableBuilder<bool>(
        valueListenable: tourOpen,
        builder: (context, tour, _) => ValueListenableBuilder<Toast?>(
          // a notice takes the slot above the bar; the hint returns after it
          valueListenable: Toasts.current,
          builder: (context, toast, _) {
            final text = textFor(tabId);
            final show =
                !tour &&
                toast == null &&
                ProgressStrip.live.value == 0 &&
                text != null &&
                !AppState.I.seenGuides.contains(keyFor(tabId));
            return Stack(
              fit: StackFit.expand,
              children: [
                child,
                if (show)
                  Positioned(
                    left: 16,
                    right: 16,
                    bottom: bottom + 12,
                    child: _CoachCard(tabId: tabId, text: text),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _CoachCard extends StatelessWidget {
  const _CoachCard({required this.tabId, required this.text});

  final String tabId;
  final String text;

  void _dismiss() => AppState.I.update(
    () => AppState.I.seenGuides.add(CoachHintLayer.keyFor(tabId)),
  );

  @override
  Widget build(BuildContext context) {
    final st = AppState.I;
    // Material: a Text with no Material above it is drawn with the yellow debug underline
    return Material(
      type: MaterialType.transparency,
      child: Semantics(
      container: true,
      key: ValueKey('coach-card-$tabId'),
      child: Glass(
        radius: st.appearance.radius + 6,
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
        child: Row(
          children: [
            Icon(Icons.lightbulb_outline_rounded, size: 22, color: Palette.text2),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                text,
                style: TextStyle(fontSize: 14, height: 1.3, color: Palette.text),
              ),
            ),
            TextButton(
              key: ValueKey('coach-ok-$tabId'),
              onPressed: _dismiss,
              style: TextButton.styleFrom(foregroundColor: Palette.text),
              child: Text(S.ux1a2CoachOk),
            ),
          ],
        ),
      ),
    ),
    );
  }
}
