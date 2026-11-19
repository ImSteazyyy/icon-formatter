import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:icon_formatter/services/pack2_logic.dart';

void main() {
  test('fingerprint is stable and changes with the bytes', () {
    final a = Uint8List.fromList([1, 2, 3, 4]);
    expect(pack2Fingerprint(a), pack2Fingerprint(Uint8List.fromList([1, 2, 3, 4])));
    expect(pack2Fingerprint(a), isNot(pack2Fingerprint(Uint8List.fromList([1, 2, 3, 5]))));
    expect(pack2Fingerprint(a), isNot(pack2Fingerprint(Uint8List.fromList([1, 2, 3]))));
    expect(pack2Fingerprint(Uint8List(0)), startsWith('0:'));
  });

  test('a change counts only when a fingerprint was stored', () {
    expect(pack2FingerprintChanged(null, 'x'), isFalse);
    expect(pack2FingerprintChanged('', 'x'), isFalse);
    expect(pack2FingerprintChanged('x', 'x'), isFalse);
    expect(pack2FingerprintChanged('x', 'y'), isTrue);
  });

  test('coverage counts and rounds the percentage down', () {
    final c = pack2Coverage([true, false, true]);
    expect((c.done, c.total, c.percent), (2, 3, 66));
    expect(pack2Coverage(const []).percent, 0);
    expect(pack2Coverage([true, true]).percent, 100);
  });

  test('an alias replaces the entry of the same component, order kept', () {
    final out = pack2LastWins<String>([('a', 'own a'), ('b', 'own b'), ('a', 'alias to a')]);
    expect(out, ['alias to a', 'own b']);
  });
}
