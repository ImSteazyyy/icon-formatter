// Consistency checks over the entries of a pack. Pure: no I/O, no Flutter.

/// One row of a pack mapping (component -> drawable), with its package and label.
class PackEntryInfo {
  const PackEntryInfo({
    required this.component,
    required this.package,
    required this.label,
    required this.drawable,
  });

  final String component;
  final String package;
  final String label;
  final String drawable;
}

enum ConflictKind {
  sharedDrawable,
  duplicateComponent,
  emptyDrawable,
  emptyPackage,
}

enum ConflictSeverity { info, warning }

class PackConflict {
  const PackConflict({
    required this.kind,
    required this.severity,
    required this.entries,
    this.drawable = '',
    this.component = '',
    this.packages = const [],
    this.drawables = const [],
  });

  final ConflictKind kind;
  final ConflictSeverity severity;

  /// Indexes into the input list, ascending.
  final List<int> entries;

  /// sharedDrawable: the drawable used by several packages.
  final String drawable;

  /// duplicateComponent, emptyDrawable, emptyPackage: the component.
  final String component;

  /// sharedDrawable: distinct packages, sorted.
  final List<String> packages;

  /// duplicateComponent: distinct non-empty drawables, sorted.
  final List<String> drawables;
}

/// Reports shared drawables, components declared with different drawables and
/// entries with an empty drawable or package. Output order is deterministic.
List<PackConflict> findConflicts(List<PackEntryInfo> entries) {
  final out = <PackConflict>[];
  final byDrawable = <String, List<int>>{};
  final byComponent = <String, List<int>>{};

  for (var i = 0; i < entries.length; i++) {
    final e = entries[i];
    if (e.drawable.isEmpty) {
      out.add(
        PackConflict(
          kind: ConflictKind.emptyDrawable,
          severity: ConflictSeverity.warning,
          component: e.component,
          entries: [i],
        ),
      );
    }
    if (e.package.isEmpty) {
      out.add(
        PackConflict(
          kind: ConflictKind.emptyPackage,
          severity: ConflictSeverity.warning,
          component: e.component,
          entries: [i],
        ),
      );
    }
    if (e.drawable.isNotEmpty && e.package.isNotEmpty) {
      byDrawable.putIfAbsent(e.drawable, () => []).add(i);
    }
    if (e.component.isNotEmpty) {
      byComponent.putIfAbsent(e.component, () => []).add(i);
    }
  }

  byDrawable.forEach((drawable, idx) {
    final packages = {for (final i in idx) entries[i].package}.toList()..sort();
    if (packages.length < 2) return;
    final family = packages.map(_family).toSet().length == 1;
    out.add(
      PackConflict(
        kind: ConflictKind.sharedDrawable,
        severity: family ? ConflictSeverity.info : ConflictSeverity.warning,
        drawable: drawable,
        packages: packages,
        entries: idx,
      ),
    );
  });

  byComponent.forEach((component, idx) {
    final drawables = {
      for (final i in idx)
        if (entries[i].drawable.isNotEmpty) entries[i].drawable,
    }.toList()..sort();
    if (drawables.length < 2) return;
    out.add(
      PackConflict(
        kind: ConflictKind.duplicateComponent,
        severity: ConflictSeverity.warning,
        component: component,
        drawables: drawables,
        entries: idx,
      ),
    );
  });

  out.sort((a, b) {
    final k = a.kind.index.compareTo(b.kind.index);
    if (k != 0) return k;
    final s = _sortKey(a).compareTo(_sortKey(b));
    if (s != 0) return s;
    return a.entries.first.compareTo(b.entries.first);
  });
  return out;
}

String _sortKey(PackConflict c) =>
    c.kind == ConflictKind.sharedDrawable ? c.drawable : c.component;

/// Package family: the first two dot segments (com.google.android.gm -> com.google).
String _family(String pkg) => pkg.toLowerCase().split('.').take(2).join('.');
