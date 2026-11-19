import 'dart:convert';
import 'dart:math' show max;

import 'package:http/http.dart' as http;

/// A newer release on GitHub.
class UpdateInfo {
  const UpdateInfo({
    required this.version,
    required this.url,
    required this.notes,
  });

  /// Without the leading "v", e.g. 1.0.1.
  final String version;
  final String url;

  /// First 600 characters of the release notes.
  final String notes;
}

const _latestUrl =
    'https://api.github.com/repos/ImSteazyyy/icon-formatter/releases/latest';
const _fallbackUrl =
    'https://github.com/ImSteazyyy/icon-formatter/releases/latest';
const _ttl = Duration(hours: 12);
const _timeout = Duration(seconds: 6);

class _Release {
  const _Release(this.version, this.url, this.notes);
  final String version;
  final String url;
  final String notes;
}

_Release? _cache;
DateTime? _cachedAt;

/// Latest GitHub release when it is newer than [currentVersion], else null.
/// Never throws: any error (offline, timeout, bad response) gives null.
/// The release is cached in memory for 12 h; only ask when the user asks, or
/// at most once per app start.
Future<UpdateInfo?> checkForUpdate({
  required String currentVersion,
  http.Client? client,
}) async {
  try {
    final now = DateTime.now();
    var rel = _cache;
    if (rel == null || _cachedAt == null || now.difference(_cachedAt!) > _ttl) {
      rel = await _fetch(client);
      if (rel == null) return null;
      _cache = rel;
      _cachedAt = now;
    }
    if (!isNewer(rel.version, currentVersion)) return null;
    return UpdateInfo(version: rel.version, url: rel.url, notes: rel.notes);
  } catch (_) {
    return null;
  }
}

/// Forgets the cached release (tests).
void clearUpdateCacheForTests() {
  _cache = null;
  _cachedAt = null;
}

Future<_Release?> _fetch(http.Client? injected) async {
  final c = injected ?? http.Client();
  try {
    final res = await c
        .get(
          Uri.parse(_latestUrl),
          headers: {
            'Accept': 'application/vnd.github+json',
            'User-Agent': 'IconFormatter',
          },
        )
        .timeout(_timeout);
    if (res.statusCode != 200) return null;
    final j = jsonDecode(res.body);
    if (j is! Map) return null;
    final tag = j['tag_name'];
    if (tag is! String || tag.trim().isEmpty) return null;
    final html = j['html_url'];
    final body = j['body'];
    final text = body is String ? body : '';
    return _Release(
      tag.trim().replaceFirst(RegExp(r'^[vV]'), ''),
      html is String && html.isNotEmpty ? html : _fallbackUrl,
      text.length > 600 ? text.substring(0, 600) : text,
    );
  } catch (_) {
    return null;
  } finally {
    if (injected == null) c.close();
  }
}

/// True when [latest] is a newer release than [current]. Accepts `v1.2.3`,
/// `1.0.0+10002` (the part after + is the build number) and pre-release tags
/// such as `1.1.0-beta.1`. Missing parts count as 0.
bool isNewer(String latest, String current) {
  final a = _Ver.parse(latest);
  final b = _Ver.parse(current);
  final n = max(a.core.length, b.core.length);
  for (var i = 0; i < n; i++) {
    final x = i < a.core.length ? a.core[i] : 0;
    final y = i < b.core.length ? b.core[i] : 0;
    if (x != y) return x > y;
  }
  // same numbers: a pre-release is older than the release itself
  if (a.pre.isNotEmpty != b.pre.isNotEmpty) return b.pre.isNotEmpty;
  if (a.pre != b.pre) return a.pre.compareTo(b.pre) > 0;
  return (a.build ?? 0) > (b.build ?? 0);
}

class _Ver {
  _Ver(this.core, this.pre, this.build);

  final List<int> core;
  final String pre;
  final int? build;

  static _Ver parse(String s) {
    var t = s.trim().replaceFirst(RegExp(r'^[vV]'), '');
    int? build;
    final plus = t.indexOf('+');
    if (plus >= 0) {
      build = int.tryParse(t.substring(plus + 1).trim());
      t = t.substring(0, plus);
    }
    var pre = '';
    final dash = t.indexOf('-');
    if (dash >= 0) {
      pre = t.substring(dash + 1);
      t = t.substring(0, dash);
    }
    final core = [for (final p in t.split('.')) int.tryParse(p.trim()) ?? 0];
    return _Ver(core, pre, build);
  }
}
