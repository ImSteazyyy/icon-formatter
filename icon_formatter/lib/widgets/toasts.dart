import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../app/theme.dart';
import '../l10n/strings.dart';
import 'liquid_glass.dart' show NothingColors;

/// How a notice reads: a plain confirmation, a warning, or a real error.
enum ToastKind { info, warning, error }

/// One notice: a short message and at most one action.
class Toast {
  Toast(
    this.message, {
    this.kind = ToastKind.info,
    this.actionLabel,
    this.onAction,
  });

  static int _next = 0;
  final int id = _next++;
  final String message;
  final ToastKind kind;
  final String? actionLabel;
  final VoidCallback? onAction;

  /// Time on screen: 3 s for a plain confirmation, 6 s when it has an action,
  /// is a warning or an error.
  Duration get lifetime => actionLabel == null && kind == ToastKind.info
      ? const Duration(seconds: 3)
      : const Duration(seconds: 6);
}

/// The notices of the app: ONE slot, shown just above the bottom bar. A new
/// notice replaces the one on screen; the same notice again only restarts its
/// timer. Nothing here changes the work that produced a notice.
class Toasts {
  Toasts._();

  /// The notice on screen, or null.
  static final ValueNotifier<Toast?> current = ValueNotifier(null);

  /// Space the bottom bar takes (set by the shell): the notice floats above it.
  static final ValueNotifier<double> bottomInset = ValueNotifier(0);

  static Timer? _timer;

  static void show(
    String message, {
    ToastKind kind = ToastKind.info,
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    final now = current.value;
    if (now != null &&
        now.message == message &&
        now.kind == kind &&
        now.actionLabel == actionLabel) {
      _arm(now);
      return;
    }
    final t = Toast(
      message,
      kind: kind,
      actionLabel: actionLabel,
      onAction: onAction,
    );
    current.value = t;
    _arm(t);
  }

  static void _arm(Toast t) {
    _timer?.cancel();
    _timer = Timer(t.lifetime, dismiss);
  }

  /// Removes the notice: after its time, on a section change, or when a sheet,
  /// dialog or page opens.
  static void dismiss() {
    _timer?.cancel();
    _timer = null;
    if (current.value != null) current.value = null;
  }
}

/// Clears the notice and closes the keyboard whenever a sheet, dialog, menu
/// or page opens over the current screen (a search field must not keep the
/// keyboard open under it).
class NoticeRouteObserver extends NavigatorObserver {
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (previousRoute == null) return; // the first route: nothing to clear
    Toasts.dismiss();
    FocusManager.instance.primaryFocus?.unfocus();
  }
}

/// Puts the notice above the app's pages, dialogs included, at the bottom
/// centre: above the bottom bar, or above the keyboard when it is open.
class ToastHost extends StatelessWidget {
  const ToastHost({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    return Material(
      type: MaterialType.transparency,
      child: Stack(
      children: [
        child,
        // transparent where there is no notice: taps reach the page under it
        Positioned.fill(
          child: Align(
            alignment: Alignment.bottomCenter,
            child: ValueListenableBuilder<double>(
              valueListenable: Toasts.bottomInset,
              builder: (context, inset, _) => Padding(
                padding: EdgeInsets.fromLTRB(
                  16,
                  0,
                  16,
                  math.max(inset, keyboard) + 8,
                ),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 440),
                  child: ValueListenableBuilder<Toast?>(
                    valueListenable: Toasts.current,
                    builder: (context, t, _) => AnimatedSwitcher(
                      duration: const Duration(milliseconds: 220),
                      switchInCurve: Curves.easeOutCubic,
                      switchOutCurve: Curves.easeInCubic,
                      transitionBuilder: (child, anim) => FadeTransition(
                        opacity: anim,
                        child: SlideTransition(
                          position: Tween(
                            begin: const Offset(0, 0.3),
                            end: Offset.zero,
                          ).animate(anim),
                          child: child,
                        ),
                      ),
                      child: t == null
                          ? const SizedBox.shrink(key: ValueKey('no-toast'))
                          : _ToastView(key: ValueKey(t.id), toast: t),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    ));
  }
}

class _ToastView extends StatefulWidget {
  const _ToastView({super.key, required this.toast});
  final Toast toast;

  @override
  State<_ToastView> createState() => _ToastViewState();
}

class _ToastViewState extends State<_ToastView> {
  // how far the notice has been dragged sideways
  double _dx = 0;

  void _leave() => Toasts.dismiss();

  @override
  Widget build(BuildContext context) {
    final t = widget.toast;
    // neutral for a plain confirmation; red only for a real error, yellow for a warning
    final (icon, color) = switch (t.kind) {
      ToastKind.error => (Icons.error_outline_rounded, Palette.danger),
      ToastKind.warning => (Icons.warning_amber_rounded, Palette.warn),
      ToastKind.info => (Icons.check_circle_outline_rounded, Palette.selection),
    };
    final radius = BorderRadius.circular(18);
    final card = ClipRRect(
      borderRadius: radius,
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 32, sigmaY: 32),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: NothingColors.navPill,
            borderRadius: radius,
            border: Border.all(color: Palette.fg.withValues(alpha: 0.14)),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 6, 8),
            child: Row(
              children: [
                Icon(icon, size: 20, color: color),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    t.message,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: Palette.text,
                    ),
                  ),
                ),
                if (t.actionLabel != null)
                  TextButton(
                    onPressed: () {
                      _leave();
                      t.onAction?.call();
                    },
                    child: Text(
                      t.actionLabel!,
                      style: TextStyle(
                        color: Palette.text,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                if (t.kind == ToastKind.error)
                  // no Tooltip here: this host sits above the Navigator, where there is no Overlay
                  Semantics(
                    button: true,
                    tooltip: S.chiudi,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: _leave,
                      child: Padding(
                        padding: const EdgeInsets.all(8),
                        child: Icon(
                          Icons.close_rounded,
                          size: 18,
                          color: Palette.text2,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
    return Semantics(
      liveRegion: true,
      hint: S.scorriPerChiudereAvviso,
      child: GestureDetector(
        // a sideways drag past the middle, or a quick flick, removes it; a quick
        // downward flick too
        onHorizontalDragUpdate: (d) => setState(() => _dx += d.delta.dx),
        onHorizontalDragEnd: (d) {
          if (_dx.abs() > 80 || (d.primaryVelocity ?? 0).abs() > 600) {
            _leave();
          } else {
            setState(() => _dx = 0);
          }
        },
        onVerticalDragEnd: (d) {
          if ((d.primaryVelocity ?? 0) > 200) _leave();
        },
        child: Transform.translate(offset: Offset(_dx, 0), child: card),
      ),
    );
  }
}
