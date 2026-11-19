// Export file names that work on Windows and Android. Pure.

final _forbidden = RegExp(r'[<>:"/\\|?*\x00-\x1f]');
final _edges = RegExp(r'^[_.\s]+|[_.\s]+$');

/// "MioPack_1.2_2026-11-19.zip". The name is capped at 80 characters.
String exportFileName({
  required String packName,
  required String version,
  required DateTime date,
  String ext = 'zip',
}) {
  String two(int n) => n.toString().padLeft(2, '0');
  final stamp =
      '${date.year.toString().padLeft(4, '0')}-${two(date.month)}-${two(date.day)}';
  final tail =
      '_${[_safe(version), stamp].where((p) => p.isNotEmpty).join('_')}';

  final extPart = _safe(ext.replaceFirst(RegExp(r'^\.+'), ''))
      .replaceAll('.', '');
  final extStr = extPart.isEmpty ? '' : '.${_cut(extPart, 10)}';
  final maxStem = 80 - extStr.runes.length;

  var base = _trim(_safe(packName));
  if (base.isEmpty) base = 'Pack';
  final room = maxStem - tail.runes.length;
  final stem = room >= 1 ? '${_cut(base, room)}$tail' : _cut(tail, maxStem);
  final clean = _trim(_safe(stem));
  return '${clean.isEmpty ? 'Pack' : clean}$extStr';
}

/// Replaces forbidden characters, turns spaces into "_" and collapses runs of "_".
String _safe(String s) => s
    .replaceAll(_forbidden, '_')
    .replaceAll(RegExp(r'\s+'), '_')
    .replaceAll(RegExp(r'_+'), '_');

String _trim(String s) => s.replaceAll(_edges, '');

String _cut(String s, int max) =>
    max <= 0 ? '' : String.fromCharCodes(s.runes.take(max));
