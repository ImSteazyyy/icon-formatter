import 'dart:typed_data';

/// 32-bit FNV-1a of the bytes. Not cryptographic: it only tells identical
/// files apart, and it is checked only between files of the same size.
int studioHash(Uint8List bytes) {
  var h = 0x811c9dc5;
  for (final b in bytes) {
    h = ((h ^ b) * 0x01000193) & 0xffffffff;
  }
  return h;
}

/// For each item after the first one with the same fingerprint, the id of
/// that first item. [prints] is (id, fingerprint) in list order.
Map<String, String> studioDuplicates(List<MapEntry<String, String>> prints) {
  final first = <String, String>{};
  final dups = <String, String>{};
  for (final e in prints) {
    final orig = first[e.value];
    if (orig == null) {
      first[e.value] = e.key;
    } else {
      dups[e.key] = orig;
    }
  }
  return dups;
}
