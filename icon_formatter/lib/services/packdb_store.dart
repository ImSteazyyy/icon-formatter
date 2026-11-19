import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../app/storage.dart';
import 'packdb_db.dart';
import 'pack_source_filter.dart';

/// Where the Pack builder keeps its lists: pack.db (SQLite) or the JSON file.
/// The builder and AppState talk only to this interface.
abstract class PackStore {
  /// The store in use. Starts as the JSON store and is replaced at boot.
  static PackStore I = JsonPackStore();

  /// Why SQLite is not in use (or was switched off), for the pack log.
  static String? fallbackReason;

  /// Called after a switch to the JSON store, so that the owners write all their data again.
  static final List<void Function()> onFallback = [];

  /// True when the pack maps (corrections, log, profiles, fingerprints, export
  /// snapshot) live here and state.json leaves them out.
  bool get ownsMaps;

  /// The stored content, read at start (icon lists and maps).
  PackContent readAll();

  /// Saves the icon lists and the custom icons of [c].
  Future<void> writeIcons(PackContent c);

  /// Saves the maps of [c].
  Future<void> writeMaps(PackContent c);
}

/// pack_builder.json, as before: the whole file is written at each change.
class JsonPackStore extends PackStore {
  JsonPackStore({this.path, bool Function(String)? exists})
    : _exists = exists ?? ((f) => File(f).existsSync());

  final String? path;
  final bool Function(String) _exists;

  String get file => path ?? p.join(AppPaths.I.root.path, 'pack_builder.json');

  @override
  bool get ownsMaps => false;

  @override
  PackContent readAll() {
    final f = File(file);
    if (!f.existsSync()) return PackContent();
    try {
      return parsePackJson(f.readAsStringSync(), _exists);
    } catch (_) {
      // a damaged file only loses the builder lists
      return PackContent();
    }
  }

  @override
  Future<void> writeIcons(PackContent c) async {
    final f = File(file);
    final tmp = File('${f.path}.tmp');
    await tmp.writeAsString(jsonEncode(packJsonOf(c)));
    await tmp.rename(f.path);
  }

  @override
  Future<void> writeMaps(PackContent c) async {}
}

/// Map of the JSON file of the builder (same keys and order as before).
Map<String, Object?> packJsonOf(PackContent c) => {
  'generated': [for (final g in c.generated) g.toJson()],
  'originals': [for (final o in c.originals) o.toJson()],
  'custom': c.custom,
  'cleanV': 1,
  'calendars': [for (final g in c.calendars) g.toJson()],
};

/// Reads pack_builder.json. Entries whose file is gone are left out, and the
/// sources saved by an older build are cleaned once (see [PackContent.cleaned]).
PackContent parsePackJson(String text, bool Function(String) exists) {
  final j = jsonDecode(text) as Map;
  List<PackRecord> read(String kind, String name) {
    final out = <PackRecord>[];
    for (final m in (j[name] as List?) ?? const []) {
      final r = PackRecord.fromJson(kind, m as Map);
      if (r != null && exists(r.path)) out.add(r);
    }
    return out;
  }

  var originals = read('original', 'originals');
  var cleaned = false;
  // an older build saved the icons of a pack as sources (days, copies, template images, repeats)
  if ((j['cleanV'] as num?)?.toInt() != 1) {
    final keep = savedSourceIndexes([
      for (final o in originals)
        (file: o.file, package: o.package, activity: o.activity),
    ]);
    originals = [for (final i in keep) originals[i]];
    cleaned = true;
  }
  final custom = <String, Map<String, String?>>{};
  ((j['custom'] as Map?) ?? {}).forEach((k, v) {
    final m = (v as Map).cast<String, String?>();
    if (m['path'] != null && exists(m['path']!)) custom[k as String] = m;
  });
  return PackContent(
    generated: read('generated', 'generated'),
    originals: originals,
    calendars: read('calendar', 'calendars'),
    custom: custom,
    cleaned: cleaned,
  );
}

/// pack.db. Writes are diffed against what was last stored: a change writes
/// its own row, nothing else. A failed write switches to the JSON store.
class SqlitePackStore extends PackStore {
  SqlitePackStore(
    this.pdb,
    PackContent initial, {
    required this.jsonPath,
    required this.offMarker,
  }) : _initial = initial,
       _rows = {
         for (final r in [
           ...initial.originals,
           ...initial.generated,
           ...initial.calendars,
         ])
           r.rowKey: r,
       },
       _custom = {
         for (final e in initial.custom.entries) e.key: jsonEncode(e.value),
       },
       _corrections = {
         for (final e in initial.corrections.entries)
           e.key: jsonEncode(e.value),
       },
       _fingerprints = {
         for (final e in initial.fingerprints.entries)
           e.key: jsonEncode(e.value),
       },
       _snapshot = initial.exportSnapshot == null
           ? null
           : jsonEncode(initial.exportSnapshot),
       _log = jsonEncode(initial.log),
       _profiles = jsonEncode(initial.profiles);

  final PackDb pdb;
  final PackContent _initial;
  final String jsonPath;
  final String offMarker;

  // what the database holds, as last written
  Map<String, PackRecord> _rows;
  Map<String, String> _custom;
  Map<String, String> _corrections;
  Map<String, String> _fingerprints;
  String? _snapshot;
  String _log;
  String _profiles;

  Future<void> _queue = Future.value();
  bool _failed = false;

  @override
  bool get ownsMaps => true;

  @override
  PackContent readAll() => _initial;

  @override
  Future<void> writeIcons(PackContent c) => _run(() async {
    final cur = <String, PackRecord>{
      for (final r in [...c.originals, ...c.generated, ...c.calendars])
        r.rowKey: r,
    };
    final up = [
      for (final r in cur.values)
        if (_rows[r.rowKey]?.signature != r.signature) r,
    ];
    final del = [
      for (final r in _rows.values)
        if (!cur.containsKey(r.rowKey)) r,
    ];
    final now = DateTime.now().millisecondsSinceEpoch;
    for (var i = 0; i < up.length; i += 200) {
      final part = up.sublist(i, math.min(i + 200, up.length));
      await pdb.db.transaction((t) => pdb.upsertRows(t, part, now));
    }
    if (del.isNotEmpty) await pdb.db.transaction((t) => pdb.deleteRows(t, del));
    _rows = cur;
    final custom = {
      for (final e in c.custom.entries) e.key: jsonEncode(e.value),
    };
    await _syncKv('custom', _custom, custom);
    _custom = custom;
  });

  @override
  Future<void> writeMaps(PackContent c) => _run(() async {
    final cor = {
      for (final e in c.corrections.entries) e.key: jsonEncode(e.value),
    };
    await _syncKv('corrections', _corrections, cor);
    _corrections = cor;
    final fp = {
      for (final e in c.fingerprints.entries) e.key: jsonEncode(e.value),
    };
    await _syncKv('fingerprints', _fingerprints, fp);
    _fingerprints = fp;
    final logJ = jsonEncode(c.log);
    if (logJ != _log) {
      await pdb.db.transaction((t) => pdb.replaceList(t, 'log', c.log));
      _log = logJ;
    }
    final profJ = jsonEncode(c.profiles);
    if (profJ != _profiles) {
      await pdb.db.transaction(
        (t) => pdb.replaceList(t, 'profiles', c.profiles),
      );
      _profiles = profJ;
    }
    final snapJ = c.exportSnapshot == null
        ? null
        : jsonEncode(c.exportSnapshot);
    if (snapJ != _snapshot) {
      await pdb.db.transaction((t) => pdb.setMeta(t, 'export_snapshot', snapJ));
      _snapshot = snapJ;
    }
  });

  Future<void> _syncKv(
    String table,
    Map<String, String> shadow,
    Map<String, String> cur,
  ) async {
    final up = {
      for (final e in cur.entries)
        if (shadow[e.key] != e.value) e.key: e.value,
    };
    final keys = up.keys.toList();
    for (var i = 0; i < keys.length; i += 200) {
      final part = {for (final k in keys.skip(i).take(200)) k: up[k]!};
      await pdb.db.transaction((t) => pdb.upsertKv(t, table, part));
    }
    final del = [
      for (final k in shadow.keys)
        if (!cur.containsKey(k)) k,
    ];
    if (del.isNotEmpty) {
      await pdb.db.transaction((t) => pdb.deleteKv(t, table, del));
    }
  }

  /// Runs the writes one after another. A failure switches to the JSON store
  /// (the shadows stay as they were, so nothing is lost from memory).
  Future<void> _run(Future<void> Function() op) {
    _queue = _queue.then((_) async {
      if (_failed) return;
      try {
        await op();
      } catch (e, st) {
        _fail(e, st);
      }
    });
    return _queue;
  }

  void _fail(Object e, StackTrace st) {
    debugPrint('pack.db write failed, using pack_builder.json: $e\n$st');
    _failed = true;
    try {
      File(offMarker).writeAsStringSync('$e');
    } catch (_) {}
    unawaited(pdb.close().catchError((_) {}));
    PackStore.I = JsonPackStore(path: jsonPath);
    PackStore.fallbackReason = 'write error, pack_builder.json in use: $e';
    for (final f in List.of(PackStore.onFallback)) {
      f();
    }
  }
}

/// Chooses the store at start. Returns the maps to use (the SQLite ones, or
/// [fromState] unchanged when the JSON store is used). Never throws.
///
/// SQLite is used when pack.db is migrated. A first start with the new build
/// imports pack_builder.json and the maps of state.json in one transaction,
/// verifies the read-back, and only then sets the migrated flag. The JSON files
/// are never modified; a copy of each is kept as .bak after a verified migration.
/// A boot that takes longer than this falls back to the JSON store, so a slow
/// or stuck database never keeps the app on its splash screen.
const packDbBootTimeout = Duration(seconds: 5);

bool _bootAbandoned = false;

Future<PackContent> packStoreBoot(
  PackContent fromState, {
  required String root,
  required String stateFile,
  required bool Function(String) exists,
  DatabaseFactory? factory,
  Duration timeout = packDbBootTimeout,
}) async {
  final jsonPath = p.join(root, 'pack_builder.json');
  PackStore.fallbackReason = null;
  PackStore.I = JsonPackStore(path: jsonPath, exists: exists);
  _bootAbandoned = false;
  try {
    return await _bootSqlite(
      fromState,
      root: root,
      stateFile: stateFile,
      exists: exists,
      factory: factory,
    ).timeout(timeout);
  } on TimeoutException {
    _bootAbandoned = true;
    debugPrint(
      'pack boot: pack.db not ready after ${timeout.inSeconds} s, using pack_builder.json',
    );
    PackStore.fallbackReason =
        'SQLite did not open in ${timeout.inSeconds} s, pack_builder.json in use';
    PackStore.I = JsonPackStore(path: jsonPath, exists: exists);
    return fromState;
  }
}

Future<PackContent> _bootSqlite(
  PackContent fromState, {
  required String root,
  required String stateFile,
  required bool Function(String) exists,
  DatabaseFactory? factory,
}) async {
  final sw = Stopwatch()..start();
  final jsonPath = p.join(root, 'pack_builder.json');
  final offMarker = p.join(root, 'pack.db.off');
  if (File(offMarker).existsSync()) {
    PackStore.fallbackReason =
        'SQLite switched off after a write error (pack.db.off)';
    return fromState;
  }
  PackDb? pdb;
  try {
    pdb = await PackDb.open(
      p.join(root, 'pack.db'),
      factory ?? _defaultFactory(),
    );
    debugPrint('pack boot: opened pack.db ${sw.elapsedMilliseconds} ms');
    if (await pdb.getMeta(pdb.db, 'migrated') != '1') {
      await _migrate(pdb, jsonPath, fromState, exists);
      debugPrint('pack boot: migrated ${sw.elapsedMilliseconds} ms');
      _backup(jsonPath);
      _backup(stateFile);
    }
    final content = await pdb.loadContent(pdb.db, exists);
    debugPrint(
      'pack boot: loaded ${content.originals.length} sources, ${content.corrections.length} corrections, ${sw.elapsedMilliseconds} ms',
    );
    if (_bootAbandoned) {
      // the timeout already chose the JSON store: this database is not used
      await pdb.close();
      return fromState;
    }
    PackStore.I = SqlitePackStore(
      pdb,
      content,
      jsonPath: jsonPath,
      offMarker: offMarker,
    );
    return content;
  } catch (e) {
    debugPrint('pack.db not used: $e');
    PackStore.fallbackReason = 'SQLite not used, pack_builder.json in use: $e';
    await pdb?.close();
    PackStore.I = JsonPackStore(path: jsonPath, exists: exists);
    return fromState;
  }
}

Future<void> _migrate(
  PackDb pdb,
  String jsonPath,
  PackContent fromState,
  bool Function(String) exists,
) async {
  final f = File(jsonPath);
  final src = f.existsSync()
      ? parsePackJson(await f.readAsString(), exists)
      : PackContent();
  final all = PackContent(
    generated: src.generated,
    originals: src.originals,
    calendars: src.calendars,
    custom: src.custom,
    cleaned: src.cleaned,
    corrections: fromState.corrections,
    log: fromState.log,
    profiles: fromState.profiles,
    exportSnapshot: fromState.exportSnapshot,
    fingerprints: fromState.fingerprints,
  );
  await pdb.importAll(all, DateTime.now().millisecondsSinceEpoch);
  debugPrint(
    'pack: migrated to pack.db (${all.originals.length} sources, ${all.generated.length} icons, ${all.corrections.length} corrections)',
  );
}

void _backup(String file) {
  try {
    final src = File(file);
    final bak = File('$file.bak');
    if (src.existsSync() && !bak.existsSync()) src.copySync(bak.path);
  } catch (e) {
    debugPrint('backup of $file failed: $e');
  }
}

DatabaseFactory _defaultFactory() {
  if (Platform.isAndroid || Platform.isIOS) return databaseFactory;
  sqfliteFfiInit();
  return databaseFactoryFfi;
}
