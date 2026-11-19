import 'package:flutter_test/flutter_test.dart';
import 'package:icon_formatter/src/rust/api/engine.dart' show LucentShape;
import 'package:icon_formatter/workspace/studio_history.dart';

void main() {
  final t0 = DateTime(2026, 1, 1, 12);

  test('plate shape and colour are part of the look', () {
    const none = ItemCorrection();
    expect(
      none.sameLook(const ItemCorrection(shape: LucentShape.circle)),
      isFalse,
    );
    expect(none.sameLook(const ItemCorrection(backdrop: 0x66FFFFFF)), isFalse);
    expect(
      const ItemCorrection(
        shape: LucentShape.circle,
        backdrop: 1,
      ).sameLook(const ItemCorrection(shape: LucentShape.circle, backdrop: 1)),
      isTrue,
    );
    expect(
      const ItemCorrection(backdrop: 1)
          .sameAs(const ItemCorrection(backdrop: 1, excluded: true)),
      isFalse,
    );
  });

  test('undo restores the plate shape and colour, redo puts them back', () {
    final h = StudioHistory<Map<String, ItemCorrection>>();
    const before = {'a': ItemCorrection()};
    const after = {
      'a': ItemCorrection(shape: LucentShape.original, backdrop: 0xFF112233),
    };
    h.push('shape:1:a', before, after, t0);

    final u = h.undo()!;
    expect(u['a']!.shape, isNull);
    expect(u['a']!.backdrop, isNull);
    final r = h.redo()!;
    expect(r['a']!.shape, LucentShape.original);
    expect(r['a']!.backdrop, 0xFF112233);
  });

  test(
    'a backdrop colour change is one undo step, merged within the window',
    () {
      final h = StudioHistory<Map<String, ItemCorrection>>();
      h.push(
        'backdrop:1:a',
        {'a': const ItemCorrection()},
        {'a': const ItemCorrection(backdrop: 1)},
        t0,
      );
      h.push(
        'backdrop:1:a',
        {'a': const ItemCorrection(backdrop: 1)},
        {'a': const ItemCorrection(backdrop: 2)},
        t0.add(const Duration(milliseconds: 300)),
      );
      final u = h.undo()!;
      expect(u['a']!.backdrop, isNull);
      expect(h.canUndo, isFalse);
    },
  );
}
