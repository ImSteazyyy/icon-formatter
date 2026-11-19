import 'package:flutter/animation.dart';

/// One choreographed fold for the bottom bars (Android phone layout).
///
/// [t] is the fold progress shared by every moving part: 0 = open, 1 = folded.
/// Each part reads its own window of [t], so the geometry is a pure function
/// of [t]. Folding and unfolding walk the same path backwards, and a reversal
/// from any point stays on that path, so the parts never cross.
///
/// Folding: the tab bar shrinks first (t 0 to 0.65). The action bar slides
/// right above it (t 0 to 0.6) and only then drops beside the folded button
/// (t 0.6 to 1). The jump buttons follow the action bar (t 0.65 to 1).
///
/// Coordinates are in dp from the bottom edge (bottom values include the
/// system inset, as the callers pass them).
class BarFold {
  BarFold._();

  /// Open tab bar height (d + 10) and the folded round button.
  static const navOpenH = 70.0;
  static const navFoldedSize = 50.0;

  /// Folded action bar: left edge next to the round button (12 + 50 + 8).
  static const actionFoldLeft = 70.0;

  static double _win(double t, double a, double b) => ((t - a) / (b - a)).clamp(0.0, 1.0);

  static double _lerp(double a, double b, double p) => a + (b - a) * p;

  /// Tab bar (Nothing style): the width goes from [maxW] to the round button.
  static double navWidth(double t, double maxW) =>
      _lerp(maxW, navFoldedSize, Curves.easeInOutCubic.transform(_win(t, 0, 0.65)));

  static double navHeight(double t) =>
      _lerp(navOpenH, navFoldedSize, Curves.easeInOutCubic.transform(_win(t, 0, 0.65)));

  /// Action bar: moves to the right of the folded button, above the bar.
  static double actionLeft(double t, double open, double folded) =>
      _lerp(open, folded, Curves.easeOutCubic.transform(_win(t, 0, 0.6)));

  /// Action bar: drops down once it has cleared the tab bar on the x axis.
  static double actionBottom(double t, double open, double folded) =>
      _lerp(open, folded, Curves.easeInOutCubic.transform(_win(t, 0.6, 1)));

  /// Jump buttons: follow the action bar, never ahead of it.
  static double jumpBottom(double t, double open, double folded) =>
      _lerp(open, folded, Curves.easeInOutCubic.transform(_win(t, 0.65, 1)));
}
