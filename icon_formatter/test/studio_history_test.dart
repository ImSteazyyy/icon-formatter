import 'package:flutter_test/flutter_test.dart';
import 'package:icon_formatter/workspace/studio_history.dart';

void main() {
  final t0 = DateTime(2026, 1, 1, 12);

  test('undo returns the before state, redo the after state', () {
    final h = StudioHistory<int>();
    expect(h.canUndo, isFalse);
    expect(h.undo(), isNull);
    h.push('a', 1, 2, t0);
    expect(h.canUndo, isTrue);
    expect(h.undo(), 1);
    expect(h.canRedo, isTrue);
    expect(h.redo(), 2);
    expect(h.canRedo, isFalse);
  });

  test('a new change clears the redo steps', () {
    final h = StudioHistory<int>();
    h.push('a', 1, 2, t0);
    h.undo();
    h.push('b', 1, 3, t0);
    expect(h.canRedo, isFalse);
    expect(h.undo(), 1);
  });

  test('same tag within the window is one step', () {
    final h = StudioHistory<int>();
    h.push('pl:x', 1, 2, t0);
    h.push('pl:x', 2, 3, t0.add(const Duration(milliseconds: 300)));
    h.push('pl:x', 3, 4, t0.add(const Duration(milliseconds: 600)));
    expect(h.undo(), 1);
    expect(h.canUndo, isFalse);
    expect(h.redo(), 4);
  });

  test('a later push with the same tag starts a new step', () {
    final h = StudioHistory<int>();
    h.push('pl:x', 1, 2, t0);
    h.push('pl:x', 2, 3, t0.add(const Duration(seconds: 5)));
    expect(h.undo(), 2);
    expect(h.undo(), 1);
  });

  test('other tags are never merged', () {
    final h = StudioHistory<int>();
    h.push('pl:x', 1, 2, t0);
    h.push('seg:x', 2, 3, t0);
    expect(h.undo(), 2);
    expect(h.undo(), 1);
  });

  test('the stack keeps the last 30 steps', () {
    final h = StudioHistory<int>();
    for (var i = 0; i < 40; i++) {
      h.push('k$i', i, i + 1, t0);
    }
    var n = 0;
    while (h.undo() != null) {
      n++;
    }
    expect(n, 30);
  });

  test('an item correction compares the flags and the override objects', () {
    const a = ItemCorrection(matchPlate: true);
    // no overrides on either side: null is identical to null
    expect(a.sameLook(const ItemCorrection(matchPlate: true)), isTrue);
    expect(a.sameLook(const ItemCorrection()), isFalse);
    // the exclusion is part of sameAs, not of sameLook
    expect(a.sameLook(const ItemCorrection(matchPlate: true, excluded: true)), isTrue);
    expect(a.sameAs(const ItemCorrection(matchPlate: true, excluded: true)), isFalse);
  });
}
