import 'dart:typed_data';

/// Cheap fingerprint of an icon file: its length and an FNV-1a hash of the bytes.
String pack2Fingerprint(Uint8List bytes) {
  var h = 0x811c9dc5;
  for (final b in bytes) {
    h = ((h ^ b) * 0x01000193) & 0xffffffff;
  }
  return '${bytes.length}:${h.toRadixString(16)}';
}

/// True only when a fingerprint was stored and the icon has changed since.
bool pack2FingerprintChanged(String? stored, String now) => stored != null && stored.isNotEmpty && stored != now;

/// Covered entries out of the total, and the percentage rounded down.
({int done, int total, int percent}) pack2Coverage(Iterable<bool> covered) {
  var done = 0, total = 0;
  for (final c in covered) {
    total++;
    if (c) done++;
  }
  return (done: done, total: total, percent: total == 0 ? 0 : done * 100 ~/ total);
}

/// One entry per key, in the order of first appearance: a later entry with the
/// same key replaces the earlier one (an alias replaces the app's own icon).
List<T> pack2LastWins<T>(Iterable<(String, T)> keyed) {
  final out = <String, T>{};
  for (final (k, v) in keyed) {
    out[k] = v;
  }
  return out.values.toList();
}
