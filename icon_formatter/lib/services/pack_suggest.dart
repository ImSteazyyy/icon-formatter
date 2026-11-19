import 'dart:math' as math;

/// Ranks icon candidates for an app by name, package and dominant colour.
/// Pure: no I/O, no Flutter, independent of the Rust matcher.

class CandidateIcon {
  const CandidateIcon({
    required this.id,
    this.label = '',
    this.package = '',
    this.file = '',
    this.colour,
  });

  final String id;
  final String label;
  final String package;
  final String file;

  /// Dominant colour as ARGB, when known.
  final int? colour;
}

class Suggestion {
  const Suggestion({required this.candidate, required this.score});

  final CandidateIcon candidate;

  /// 0..1, higher is closer.
  final double score;
}

/// Top [max] candidates with a score above zero, best first. Ties go to the
/// smaller id, so the order is stable. [colour] is the app's dominant colour
/// (ARGB), used only when both sides have one.
List<Suggestion> suggestIcons({
  required String label,
  required String package,
  required List<CandidateIcon> candidates,
  int max = 3,
  int? colour,
}) {
  if (max <= 0 || candidates.isEmpty) return [];
  final name = _normalise(label);
  final pkg = _packageTokens(package);
  final scored = <Suggestion>[];
  for (final c in candidates) {
    final s = _score(name, pkg, package, colour, c);
    if (s > 0) scored.add(Suggestion(candidate: c, score: s));
  }
  scored.sort((a, b) {
    final d = b.score.compareTo(a.score);
    return d != 0 ? d : a.candidate.id.compareTo(b.candidate.id);
  });
  return scored.length > max ? scored.sublist(0, max) : scored;
}

final _nonWord = RegExp(r'[^\p{L}\p{N}]+', unicode: true);
const _generic = {
  'com',
  'org',
  'net',
  'io',
  'android',
  'apps',
  'app',
  'mobile',
  'activity',
  'main',
};

/// Lower-case words separated by single spaces.
String _normalise(String s) => s.toLowerCase().replaceAll(_nonWord, ' ').trim();

/// Package segments without generic words ("com.google.android.gm" -> "google gm").
String _packageTokens(String pkg) =>
    _normalise(pkg)
        .split(' ')
        .where((t) => t.isNotEmpty && !_generic.contains(t))
        .join(' ');

/// File stem without folder or extension, normalised.
String _stem(String file) {
  final name = file.replaceAll('\\', '/').split('/').last;
  final dot = name.lastIndexOf('.');
  return _normalise(dot > 0 ? name.substring(0, dot) : name);
}

double _score(
  String name,
  String pkgTokens,
  String rawPackage,
  int? colour,
  CandidateIcon c,
) {
  var sum = 0.0;
  var weight = 0.0;

  if (name.isNotEmpty) {
    var best = 0.0;
    for (final cand in [_normalise(c.label), _stem(c.file)]) {
      if (cand.isEmpty) continue;
      best = math.max(
        best,
        math.max(_jaroWinkler(name, cand), _dice(name, cand)),
      );
    }
    sum += 0.7 * best;
    weight += 0.7;
  }

  if (rawPackage.isNotEmpty && c.package.isNotEmpty) {
    final same = rawPackage.toLowerCase() == c.package.toLowerCase();
    final pkgScore = same ? 1.0 : _dice(pkgTokens, _packageTokens(c.package));
    sum += 0.3 * pkgScore;
    weight += 0.3;
  }

  final colourScore = colour != null && c.colour != null
      ? _colourCloseness(colour, c.colour!)
      : null;
  if (weight == 0) return colourScore ?? 0;
  final base = sum / weight;
  if (colourScore == null) return base.clamp(0.0, 1.0);
  return (0.85 * base + 0.15 * colourScore).clamp(0.0, 1.0);
}

/// 1 for identical colours, 0 for black against white.
double _colourCloseness(int a, int b) {
  final dr = ((a >> 16) & 0xff) - ((b >> 16) & 0xff);
  final dg = ((a >> 8) & 0xff) - ((b >> 8) & 0xff);
  final db = (a & 0xff) - (b & 0xff);
  final dist = math.sqrt((dr * dr + dg * dg + db * db).toDouble());
  return 1 - dist / (255 * math.sqrt(3));
}

/// Jaro-Winkler similarity 0..1 over code points.
double _jaroWinkler(String s1, String s2) {
  if (s1 == s2) return 1;
  final a = s1.runes.toList();
  final b = s2.runes.toList();
  if (a.isEmpty || b.isEmpty) return 0;
  final window = math.max(0, math.max(a.length, b.length) ~/ 2 - 1);
  final matchedA = List<bool>.filled(a.length, false);
  final matchedB = List<bool>.filled(b.length, false);
  var matches = 0;
  for (var i = 0; i < a.length; i++) {
    final from = math.max(0, i - window);
    final to = math.min(i + window + 1, b.length);
    for (var j = from; j < to; j++) {
      if (!matchedB[j] && a[i] == b[j]) {
        matchedA[i] = true;
        matchedB[j] = true;
        matches++;
        break;
      }
    }
  }
  if (matches == 0) return 0;
  var transpositions = 0;
  var k = 0;
  for (var i = 0; i < a.length; i++) {
    if (!matchedA[i]) continue;
    while (!matchedB[k]) {
      k++;
    }
    if (a[i] != b[k]) transpositions++;
    k++;
  }
  final m = matches.toDouble();
  final jaro = (m / a.length + m / b.length + (m - transpositions / 2) / m) / 3;
  var prefix = 0;
  final limit = math.min(4, math.min(a.length, b.length));
  while (prefix < limit && a[prefix] == b[prefix]) {
    prefix++;
  }
  return jaro + prefix * 0.1 * (1 - jaro);
}

/// Sorensen-Dice over character bigrams, 0..1.
double _dice(String a, String b) {
  if (a.isEmpty || b.isEmpty) return 0;
  if (a == b) return 1;
  if (a.length < 2 || b.length < 2) return 0;
  final counts = <String, int>{};
  for (var i = 0; i < a.length - 1; i++) {
    final g = a.substring(i, i + 2);
    counts[g] = (counts[g] ?? 0) + 1;
  }
  var common = 0;
  for (var i = 0; i < b.length - 1; i++) {
    final g = b.substring(i, i + 2);
    final n = counts[g];
    if (n != null && n > 0) {
      common++;
      counts[g] = n - 1;
    }
  }
  return 2 * common / ((a.length - 1) + (b.length - 1));
}
