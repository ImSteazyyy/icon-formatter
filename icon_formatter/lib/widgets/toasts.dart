import 'dart:async';

import 'package:flutter/material.dart';

import '../app/state.dart';
import '../app/theme.dart';
import '../l10n/strings.dart';

/// One notice shown at the top of the app.
class Toast {
  Toast(this.message, {this.error = false, this.actionLabel, this.onAction}) : id = _next++;
  static int _next = 0;

  final int id;
  final String message;
  final bool error;
  final String? actionLabel;
  final VoidCallback? onAction;
}

/// Notices at the top of the screen. Each one leaves by itself after a few
/// seconds or with a horizontal swipe; removing a notice never touches the
/// work that produced it (it is only a message).
class Toasts {
  Toasts._();

  static final ValueNotifier<List<Toast>> items = ValueNotifier(const []);
  static final Map<int, Timer> _timers = {};
  static const _max = 3;

  static Toast show(String message, {bool error = false, String? actionLabel, VoidCallback? onAction, Duration? duration}) {
    final t = Toast(message, error: error, actionLabel: actionLabel, onAction: onAction);
    var list = [...items.value, t];
    // oldest notices make room for new ones
    while (list.length > _max) {
      _timers.remove(list.first.id)?.cancel();
      list = list.sublist(1);
    }
    items.value = list;
    _timers[t.id] = Timer(duration ?? Duration(seconds: error ? 7 : (actionLabel != null ? 6 : 4)), () => dismiss(t.id));
    return t;
  }

  static void dismiss(int id) {
    _timers.remove(id)?.cancel();
    if (items.value.any((t) => t.id == id)) items.value = items.value.where((t) => t.id != id).toList();
  }

  static void clear() {
    for (final t in _timers.values) {
      t.cancel();
    }
    _timers.clear();
    items.value = const [];
  }
}

/// Puts the notices above everything (dialogs and sheets included), under
/// the status bar.
class ToastHost extends StatelessWidget {
  const ToastHost({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).viewPadding.top;
    return Stack(children: [
      child,
      Positioned(
        top: top + 8,
        left: 0,
        right: 0,
        child: ValueListenableBuilder<List<Toast>>(
          valueListenable: Toasts.items,
          builder: (context, list, _) => Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                for (final t in list) _ToastView(key: ValueKey('toast-${t.id}'), toast: t),
              ]),
            ),
          ),
        ),
      ),
    ]);
  }
}

class _ToastView extends StatefulWidget {
  const _ToastView({super.key, required this.toast});
  final Toast toast;

  @override
  State<_ToastView> createState() => _ToastViewState();
}

class _ToastViewState extends State<_ToastView> with SingleTickerProviderStateMixin {
  late final AnimationController _in = AnimationController(
    vsync: this,
    duration: Duration(milliseconds: AppState.I.appearance.animations ? 260 : 0),
  )..forward();

  @override
  void dispose() {
    _in.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.toast;
    final accent = Theme.of(context).colorScheme.primary;
    final curve = CurvedAnimation(parent: _in, curve: Curves.easeOutCubic);
    final card = Material(
      type: MaterialType.transparency,
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
        decoration: BoxDecoration(
          color: t.error ? const Color(0xF23A2422) : const Color(0xF2242329),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          boxShadow: const [BoxShadow(color: Color(0x66000000), blurRadius: 18, offset: Offset(0, 6))],
        ),
        child: Row(children: [
          Icon(t.error ? Icons.error_outline_rounded : Icons.check_circle_outline_rounded, size: 20, color: t.error ? Palette.danger : accent),
          const SizedBox(width: 10),
          Expanded(child: Text(t.message, style: const TextStyle(fontSize: 13.5, color: Palette.text))),
          if (t.actionLabel != null)
            TextButton(
              onPressed: () {
                Toasts.dismiss(t.id);
                t.onAction?.call();
              },
              child: Text(t.actionLabel!, style: TextStyle(color: accent, fontWeight: FontWeight.w700)),
            )
          else
            const SizedBox(width: 8),
        ]),
      ),
    );
    return SizeTransition(
      sizeFactor: curve,
      alignment: Alignment.topCenter,
      child: FadeTransition(
        opacity: curve,
        child: SlideTransition(
          position: Tween(begin: const Offset(0, -0.4), end: Offset.zero).animate(curve),
          child: Semantics(
            hint: S.scorriPerChiudereAvviso,
            child: Dismissible(
              key: ValueKey('toast-d-${t.id}'),
              direction: DismissDirection.horizontal,
              resizeDuration: const Duration(milliseconds: 180),
              onDismissed: (_) => Toasts.dismiss(t.id),
              child: card,
            ),
          ),
        ),
      ),
    );
  }
}
