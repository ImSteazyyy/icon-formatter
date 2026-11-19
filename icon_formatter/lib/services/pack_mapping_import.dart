// Reads the component -> drawable mappings of another icon pack and matches
// them to installed apps. Pure: the XML is passed in as a string.

/// One `<item component=".." drawable=".."/>` of another pack.
class AppFilterEntry {
  const AppFilterEntry({
    required this.component,
    required this.drawable,
    this.label = '',
  });

  /// Raw component, e.g. "ComponentInfo{com.x/.Main}" or "com.x/.Main".
  final String component;
  final String drawable;

  /// App label, when the source knows it (empty for plain appfilter.xml).
  final String label;
}

/// An installed app, as the mapping import needs it.
class InstalledAppInfo {
  const InstalledAppInfo({
    required this.package,
    required this.label,
    this.activity = '',
  });

  final String package;
  final String label;

  /// Launch activity, short (".Main") or full ("com.x.Main").
  final String activity;
}

/// How an installed app was matched, strongest first.
enum MappingMatch { component, package, label }

class ImportedMapping {
  const ImportedMapping({
    required this.drawable,
    required this.match,
    required this.component,
  });

  final String drawable;
  final MappingMatch match;

  /// Source component that matched (empty for a label match without one).
  final String component;
}

/// Installed package -> drawable name. See [importMappingsDetailed] for how
/// each app matched.
Map<String, String> importMappings({
  required List<AppFilterEntry> source,
  required List<InstalledAppInfo> installed,
}) {
  return {
    for (final e in importMappingsDetailed(
      source: source,
      installed: installed,
    ).entries)
      e.key: e.value.drawable,
  };
}

/// Installed package -> match details. Each app is matched once: by exact
/// component, then by package, then by label. The first source entry wins.
Map<String, ImportedMapping> importMappingsDetailed({
  required List<AppFilterEntry> source,
  required List<InstalledAppInfo> installed,
}) {
  final byComponent = <String, AppFilterEntry>{};
  final byPackage = <String, AppFilterEntry>{};
  final byLabel = <String, AppFilterEntry>{};
  for (final e in source) {
    if (e.drawable.isEmpty) continue;
    final parts = _parseComponent(e.component);
    if (parts == null) continue;
    final (pkg, activity) = parts;
    if (activity.isNotEmpty) byComponent.putIfAbsent('$pkg/$activity', () => e);
    byPackage.putIfAbsent(pkg, () => e);
    final label = _key(e.label.isNotEmpty ? e.label : _lastSegment(pkg));
    if (label.isNotEmpty) byLabel.putIfAbsent(label, () => e);
  }

  final out = <String, ImportedMapping>{};
  for (final app in installed) {
    if (app.package.isEmpty || out.containsKey(app.package)) continue;
    final activity = _expandActivity(app.package, app.activity);
    final byExact = activity.isEmpty
        ? null
        : byComponent['${app.package}/$activity'];
    if (byExact != null) {
      out[app.package] = ImportedMapping(
        drawable: byExact.drawable,
        match: MappingMatch.component,
        component: byExact.component,
      );
      continue;
    }
    final byPkg = byPackage[app.package];
    if (byPkg != null) {
      out[app.package] = ImportedMapping(
        drawable: byPkg.drawable,
        match: MappingMatch.package,
        component: byPkg.component,
      );
      continue;
    }
    final name = _key(app.label);
    final byName = name.isEmpty ? null : byLabel[name];
    if (byName != null) {
      out[app.package] = ImportedMapping(
        drawable: byName.drawable,
        match: MappingMatch.label,
        component: byName.component,
      );
    }
  }
  return out;
}

final _comment = RegExp(r'<!--[\s\S]*?(?:-->|$)');
final _itemTag = RegExp(r'''<item\b((?:[^>"']|"[^"]*"|'[^']*')*)>''');
final _attr = RegExp(r'''([A-Za-z_:][\w:.-]*)\s*=\s*(?:"([^"]*)"|'([^']*)')''');
final _entity = RegExp(r'&(#x[0-9a-fA-F]+|#[0-9]+|amp|lt|gt|quot|apos);');
final _nonWord = RegExp(r'[^\p{L}\p{N}]+', unicode: true);

/// Tolerant reader for the `<item component=".." drawable=".."/>` lines of an
/// appfilter.xml. Comments and `<calendar>` entries are skipped, items without
/// a drawable are dropped, and malformed input yields what could be read.
List<AppFilterEntry> parseAppFilter(String xml) {
  final out = <AppFilterEntry>[];
  for (final m in _itemTag.allMatches(xml.replaceAll(_comment, ''))) {
    final attrs = <String, String>{};
    for (final a in _attr.allMatches(m.group(1) ?? '')) {
      attrs[a.group(1)!] = _unescape(a.group(2) ?? a.group(3) ?? '');
    }
    final drawable = attrs['drawable'] ?? '';
    if (drawable.isEmpty) continue;
    out.add(
      AppFilterEntry(component: attrs['component'] ?? '', drawable: drawable),
    );
  }
  return out;
}

/// "ComponentInfo{pkg/.Act}" or "pkg/.Act" -> (pkg, expanded activity).
/// A component without "/" is a package only (activity empty).
(String, String)? _parseComponent(String raw) {
  var s = raw.trim();
  if (s.startsWith('ComponentInfo{') && s.endsWith('}')) {
    s = s.substring('ComponentInfo{'.length, s.length - 1);
  }
  final slash = s.indexOf('/');
  final pkg = (slash < 0 ? s : s.substring(0, slash)).trim();
  if (pkg.isEmpty) return null;
  final act = slash < 0 ? '' : s.substring(slash + 1).trim();
  return (pkg, _expandActivity(pkg, act));
}

String _expandActivity(String pkg, String activity) {
  if (activity.isEmpty) return '';
  return activity.startsWith('.') ? '$pkg$activity' : activity;
}

String _lastSegment(String pkg) => pkg.split('.').last;

/// Lower-case letters and digits only, so "Gmail" and "gmail" compare equal.
String _key(String s) => s.toLowerCase().replaceAll(_nonWord, '');

String _unescape(String s) {
  if (!s.contains('&')) return s;
  return s.replaceAllMapped(_entity, (m) {
    final e = m.group(1)!;
    switch (e) {
      case 'amp':
        return '&';
      case 'lt':
        return '<';
      case 'gt':
        return '>';
      case 'quot':
        return '"';
      case 'apos':
        return "'";
    }
    final code = e.startsWith('#x')
        ? int.tryParse(e.substring(2), radix: 16)
        : int.tryParse(e.substring(1));
    if (code == null || code > 0x10ffff) return m.group(0)!;
    return String.fromCharCodes([code]);
  });
}
