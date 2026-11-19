// Saved "selection lists" of apps (sets of packages). Plain Dart: the caller
// persists them with [listsToJson] and [appListsFromJson].

class AppList {
  AppList({required this.id, required this.name, Set<String>? packages})
    : packages = packages ?? <String>{};

  final String id;
  String name;
  final Set<String> packages;

  /// Packages are written sorted, so the JSON is stable.
  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'packages': packages.toList()..sort(),
  };

  /// Tolerant: missing or wrong-typed fields fall back to empty values. A
  /// missing id gets a new one; non-string packages are dropped.
  factory AppList.fromJson(Map<Object?, Object?> json) {
    final rawId = json['id'];
    final rawName = json['name'];
    final rawPackages = json['packages'];
    final packages = rawPackages is List
        ? {
            for (final p in rawPackages)
              if (p is String && p.trim().isNotEmpty) p.trim(),
          }
        : <String>{};
    return AppList(
      id: rawId is String && rawId.isNotEmpty ? rawId : newListId(const []),
      name: rawName is String ? rawName.trim() : '',
      packages: packages,
    );
  }
}

/// A new id that is not in [taken].
String newListId(Iterable<String> taken) {
  final used = taken.toSet();
  final base = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
  var id = base;
  var n = 0;
  while (used.contains(id)) {
    n++;
    id = '$base-$n';
  }
  return id;
}

/// Lists from a stored JSON value. Anything that is not a list is ignored,
/// entries that are not maps are skipped, and repeated ids keep the first.
List<AppList> appListsFromJson(Object? json) {
  if (json is! List) return [];
  final seen = <String>{};
  final out = <AppList>[];
  for (final item in json) {
    if (item is! Map) continue;
    final list = AppList.fromJson(item);
    if (seen.add(list.id)) out.add(list);
  }
  return out;
}

List<Map<String, Object?>> listsToJson(List<AppList> lists) => [
  for (final l in lists) l.toJson(),
];

/// Helpers on the list of saved lists. Named so they do not clash with
/// List.add, which takes an AppList.
extension AppListOps on List<AppList> {
  AppList? findList(String id) {
    for (final l in this) {
      if (l.id == id) return l;
    }
    return null;
  }

  /// [name] trimmed, or "list" when empty, with " (2)", " (3)"... appended
  /// when another list already uses it (case-insensitive). [exceptId] is the
  /// list being renamed, so it does not clash with itself.
  String uniqueName(String name, {String? exceptId}) {
    final trimmed = name.trim();
    final base = trimmed.isEmpty ? 'list' : trimmed;
    final taken = {
      for (final l in this)
        if (l.id != exceptId) l.name.toLowerCase(),
    };
    if (!taken.contains(base.toLowerCase())) return base;
    for (var n = 2; ; n++) {
      final candidate = '$base ($n)';
      if (!taken.contains(candidate.toLowerCase())) return candidate;
    }
  }

  /// Appends a new list with a unique name and returns it.
  AppList addList({required String name, Set<String> packages = const {}}) {
    final list = AppList(
      id: newListId(map((l) => l.id)),
      name: uniqueName(name),
      packages: {...packages},
    );
    add(list);
    return list;
  }

  /// Renames the list. False when the id is unknown or the name is blank.
  bool renameList(String id, String name) {
    final list = findList(id);
    if (list == null || name.trim().isEmpty) return false;
    list.name = uniqueName(name, exceptId: id);
    return true;
  }

  /// Removes the list. False when the id is unknown.
  bool deleteList(String id) {
    final before = length;
    removeWhere((l) => l.id == id);
    return length < before;
  }
}
