import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../app/state.dart';
import 'barfold_geometry.dart';

/// The app has one look: the "Nothing style" (solid black and grey surfaces,
/// frosted floating bars). Kept as a constant so the call sites that read it
/// keep their Nothing branch.
const bool nothingStyle = true;

/// Nothing style surfaces (from the darkest to the lightest).
class NothingColors {
  // light: the Nothing light surfaces (#F2F2F2 page, white cards)
  static bool get _light => AppState.I.appearance.light;
  static Color get bg => _light ? const Color(0xFFF2F2F2) : const Color(0xFF000000);
  static Color get card => _light ? const Color(0xFFFCFCFC) : const Color(0xFF141414);
  static Color get raised => _light ? const Color(0xFFE9E9E9) : const Color(0xFF1C1C1C);
  static Color get control => _light ? const Color(0xFFE3E3E3) : const Color(0xFF292929);
  static Color get tertiary => _light ? const Color(0xFFC8C8C8) : const Color(0xFF323232);

  /// The "on" pill (active filter, done step, switch track): white on
  /// black, near black on light.
  static Color get on => _light ? const Color(0xFF1C1C1C) : const Color(0xFFF2F2F2);

  /// Text and icons on [on].
  static Color get onOn => _light ? Colors.white : Colors.black;

  /// Blurred pill of the bottom bar and of the notices.
  static Color get navPill => _light ? const Color(0x99FFFFFF) : const Color(0x8C2E2E2E);
}

/// Space at the bottom covered by floating bars (Android phone layout).
/// Scrollable pages add it as bottom padding so content scrolls under the
/// bars instead of being cut off.
class GlassInsets extends InheritedWidget {
  const GlassInsets({super.key, required this.bottom, this.folded = false, this.fold, required super.child});

  final double bottom;

  /// The bottom bar is folded into its round button.
  final bool folded;

  /// The shared fold progress (0 open, 1 folded), see barfold_geometry.dart.
  final Animation<double>? fold;

  static double of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<GlassInsets>()?.bottom ?? 0;

  static bool foldedOf(BuildContext context) => context.dependOnInheritedWidgetOfExactType<GlassInsets>()?.folded ?? false;

  /// The fold progress for the slots; they rebuild per tick, not this widget.
  static Animation<double> foldOf(BuildContext context) {
    final w = context.getInheritedWidgetOfExactType<GlassInsets>();
    return w?.fold ?? AlwaysStoppedAnimation(w?.folded ?? false ? 1.0 : 0.0);
  }

  @override
  bool updateShouldNotify(GlassInsets old) => old.bottom != bottom || old.folded != folded || old.fold != fold;
}

/// Where a floating action bar sits over the bottom bar. With the bar open
/// it stands above it; with the bar folded it drops down next to the round
/// button left, at the bottom edge (the bar is out of the way).
class FloatingBarSlot extends StatelessWidget {
  const FloatingBarSlot({super.key, required this.child, this.side = 12});

  final Widget child;

  /// Gap to the screen edges when the bar is open.
  final double side;

  @override
  Widget build(BuildContext context) {
    final under = GlassInsets.of(context);
    final inset = MediaQuery.of(context).viewPadding.bottom;
    final fold = GlassInsets.foldOf(context);
    // one timeline with the tab bar and the jump buttons (barfold_geometry.dart);
    // the child is built once, only the position is rebuilt per tick
    return AnimatedBuilder(
      animation: fold,
      child: child,
      builder: (context, child) => Positioned(
        left: BarFold.actionLeft(fold.value, side, BarFold.actionFoldLeft),
        right: side,
        // folded: 12 dp from the bottom edge, next to the 50 dp round button
        bottom: BarFold.actionBottom(fold.value, under - 4, inset + 12), // the nav box includes 12dp of top padding
        child: child!,
      ),
    );
  }
}

/// A solid card, or a frosted pill when [live] (floating chrome such as the
/// action bar and the menus: the content moving behind it shows through blurred).
class LiquidGlass extends StatelessWidget {
  const LiquidGlass({super.key, required this.child, this.radius = 28, this.padding = EdgeInsets.zero, this.dark = false, this.live = false});

  final Widget child;
  final double radius;
  final EdgeInsetsGeometry padding;

  /// Darker "control" surface instead of the card colour.
  final bool dark;

  /// Floating over content that moves: blurs what is behind it.
  final bool live;

  @override
  Widget build(BuildContext context) {
    if (live) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 32, sigmaY: 32),
          child: Container(padding: padding, color: NothingColors.navPill, child: child),
        ),
      );
    }
    return Container(
      padding: padding,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(color: dark ? NothingColors.control : NothingColors.card, borderRadius: BorderRadius.circular(radius)),
      child: child,
    );
  }
}

/// Status bar height for sheets that start at the top edge; the system can report 0 there, so a 28 dp floor applies.
double _statusBarInset(BuildContext context) {
  final top = MediaQuery.viewPaddingOf(context).top;
  return top > 28 ? top : 28;
}

/// Bottom sheet that floats like the bars: away from the screen edges,
/// every corner rounded, a solid body and its own grab handle.
Future<T?> showAppSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool isScrollControlled = false,
  bool showDragHandle = true,
  /// Keeps the top edge of the sheet under the status bar (tall sheets).
  bool belowStatusBar = false,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: isScrollControlled,
    backgroundColor: Colors.transparent,
    elevation: 0,
    showDragHandle: false,
    builder: (ctx) {
      final theme = Theme.of(ctx).bottomSheetTheme;
      final r = AppState.I.appearance.radius + 12;
      final bottom = MediaQuery.of(ctx).viewPadding.bottom;
      return Padding(
        padding: EdgeInsets.fromLTRB(12, belowStatusBar ? _statusBarInset(context) : 0, 12, 12 + bottom),
        child: Material(
          color: theme.backgroundColor,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(r)),
          clipBehavior: Clip.antiAlias,
          child: MediaQuery.removePadding(
            context: ctx,
            removeBottom: true,
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              if (showDragHandle)
                Center(
                  child: Container(
                    margin: const EdgeInsets.symmetric(vertical: 10),
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.35), borderRadius: BorderRadius.circular(2)),
                  ),
                ),
              Flexible(child: builder(ctx)),
            ]),
          ),
        ),
      );
    },
  );
}

/// Dialogs and sheets: the screen behind is dimmed and blurred.
Future<T?> showAppDialog<T>({required BuildContext context, required WidgetBuilder builder, bool barrierDismissible = true}) {
  return showDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    barrierColor: Colors.black.withValues(alpha: 0.35),
    builder: (ctx) => BackdropFilter(
      filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
      child: builder(ctx),
    ),
  );
}
