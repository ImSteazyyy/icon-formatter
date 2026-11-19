/// Plain-text block for a problem report: versions, settings and counts only.
class DiagnosticsInput {
  const DiagnosticsInput({
    required this.appVersion,
    required this.os,
    required this.locale,
    required this.style,
    required this.theme,
    required this.glassQuality,
    required this.threads,
    required this.counts,
    this.shizuku,
    this.iconPackActive,
    this.redact = const [],
  });

  final String appVersion;

  /// OS name and version, as free text (scrubbed of paths and [redact]).
  final String os;
  final String locale;
  final String style;
  final String theme;
  final String glassQuality;

  /// 0 = automatic.
  final int threads;

  /// Shizuku state on Android; null elsewhere.
  final String? shizuku;

  /// Whether a launcher icon pack is active; null elsewhere. The name is never shown.
  final bool? iconPackActive;

  /// Item counts, e.g. {'bases': 3}.
  final Map<String, int> counts;

  /// Names to remove from free text, e.g. the user name of the account.
  final List<String> redact;
}

final _pathRe = RegExp(r'[A-Za-z]:\\\S*|(?:/[\w.\-]+){2,}');

/// Drops file paths and the listed names from a free-text value.
String _scrub(String value, List<String> redact) {
  var out = value.replaceAll(_pathRe, '[path]');
  for (final r in redact) {
    if (r.isNotEmpty) out = out.replaceAll(RegExp(RegExp.escape(r), caseSensitive: false), '[name]');
  }
  return out;
}

// English on purpose: this text is pasted into GitHub issues, so labels stay fixed.
String buildDiagnostics(DiagnosticsInput d) {
  final keys = d.counts.keys.toList()..sort();
  final lines = [
    'Icon Formatter ${_scrub(d.appVersion, d.redact)}',
    'OS: ${_scrub(d.os, d.redact)}',
    'Locale: ${_scrub(d.locale, d.redact)}',
    'Style: ${_scrub(d.style, d.redact)}',
    'Theme: ${_scrub(d.theme, d.redact)}',
    'Glass quality: ${_scrub(d.glassQuality, d.redact)}',
    'Threads: ${d.threads == 0 ? 'automatic' : d.threads}',
    if (d.shizuku != null) 'Shizuku: ${_scrub(d.shizuku!, d.redact)}',
    if (d.iconPackActive != null) 'Icon pack active: ${d.iconPackActive! ? 'yes' : 'no'}',
    for (final k in keys) 'Count $k: ${d.counts[k]}',
  ];
  return lines.join('\n');
}
