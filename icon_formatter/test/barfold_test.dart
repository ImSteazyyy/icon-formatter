import 'package:flutter_test/flutter_test.dart';
import 'package:icon_formatter/widgets/barfold_geometry.dart';

/// Rectangle in dp from the bottom edge (y grows upwards).
class _Box {
  const _Box(this.l, this.r, this.b, this.t);
  final double l, r, b, t;

  /// Touching edges do not count as overlap.
  bool overlaps(_Box o) => l < o.r && o.l < r && b < o.t && o.b < t;
}

// Real constants: Nothing tab bar (12 dp inset, 70 open, 50 folded), action
// bar open at (navCovered 94 - 4) = 90 and folded at 12, jump buttons open at
// navCovered + 116 = 210 and folded at 74 (right 18). The action bar height
// (50) and jump button size are the folded values assumed for the check.
const _actionH = 50.0;
const _jumpW = 44.0;
const _jumpH = 96.0;

({_Box nav, _Box action, _Box jump}) _rects(double t, double screenW) {
  final maxW = screenW - 24;
  final nav = _Box(12, 12 + BarFold.navWidth(t, maxW), 12, 12 + BarFold.navHeight(t));
  final actionB = BarFold.actionBottom(t, 90, 12);
  final action = _Box(BarFold.actionLeft(t, 12, BarFold.actionFoldLeft), screenW - 12, actionB, actionB + _actionH);
  final jumpB = BarFold.jumpBottom(t, 210, 74);
  final jump = _Box(screenW - 18 - _jumpW, screenW - 18, jumpB, jumpB + _jumpH);
  return (nav: nav, action: action, jump: jump);
}

void _expectClear(double t, double screenW, String path) {
  final r = _rects(t, screenW);
  expect(r.action.overlaps(r.nav), isFalse, reason: '$path: action bar hits tab bar at t=$t, width $screenW');
  expect(r.jump.overlaps(r.nav), isFalse, reason: '$path: jump buttons hit tab bar at t=$t, width $screenW');
  expect(r.jump.overlaps(r.action), isFalse, reason: '$path: jump buttons hit action bar at t=$t, width $screenW');
}

void main() {
  final samples = [for (var i = 0; i < 200; i++) i / 199];

  test('the bars never overlap while folding (200 samples, t 0 to 1)', () {
    for (final w in [360.0, 411.0]) {
      for (final t in samples) {
        _expectClear(t, w, 'fold');
      }
    }
  });

  test('the bars never overlap while unfolding (200 samples, t 1 to 0)', () {
    for (final w in [360.0, 411.0]) {
      for (final t in samples.reversed) {
        _expectClear(t, w, 'unfold');
      }
    }
  });

  test('reversing mid-way retraces the same clear path', () {
    // fold to 0.5, back to 0.2, down to 0.9 again, then open; each leg 40 steps
    final legs = [
      for (var i = 0; i <= 40; i++) i / 40,
      for (var i = 0; i <= 40; i++) 1 - 0.3 * i / 40,
      for (var i = 0; i <= 40; i++) 0.2 + 0.7 * i / 40,
      for (var i = 0; i <= 40; i++) 0.9 - 0.9 * i / 40,
    ];
    for (final t in legs) {
      _expectClear(t, 360, 'zigzag');
    }
  });

  test('the end points keep the current open and folded geometry', () {
    final open = _rects(0, 360);
    expect(open.nav.b, 12);
    expect(open.nav.t, 82);
    expect(open.nav.r, 348);
    expect(open.action.b, 90);
    expect(open.action.l, 12);
    expect(open.jump.b, 210);

    final folded = _rects(1, 360);
    expect(folded.nav.r, 62, reason: 'folded button is 50 dp from the 12 dp edge');
    expect(folded.nav.t, 62);
    expect(folded.action.b, 12);
    expect(folded.action.l, 70);
    expect(folded.jump.b, 74);
  });
}
