import 'dart:convert';

import 'package:sqflite/sqflite.dart';

/// One icon of the Pack builder: a source (original), a generated icon or a
/// calendar day. The `rows` table keeps these; corrections and the rest live
/// in their own tables (see [PackDb]).
class PackRecord {
  const PackRecord({
    required this.kind,
    required this.id,
    required this.path,
    this.label = '',
    this.package = '',
    this.activity = '',
    this.file = '',
    this.calendarDay = 0,
    this.isSystem = false,
    this.isFresh = false,
  });

  /// 'original', 'generated' or 'calendar'.
  final String kind;
  final String id;
  final String path;
  final String label;
  final String package;
  final String activity;
  final String file;
  final int calendarDay;
  final bool isSystem;

  /// Flag bit 2: an app added this session, rendered from its own launcher icon.
  final bool isFresh;

  /// Ids are unique per kind only.
  String get rowKey => '$kind\u0001$id';

  /// Same rule as PbIcon.key in the Pack builder.
  String get dbKey =>
      package.isNotEmpty ? 'pkg:$package' : 'file:${file.toLowerCase()}';

  /// Every field the builder keeps: a different signature means the row changed.
  String get signature =>
      '$path\u0001$label\u0001$package\u0001$activity\u0001$file\u0001$calendarDay\u0001${isSystem ? 1 : 0}${isFresh ? 'fresh' : ''}';

  /// Same keys as the entries of pack_builder.json.
  Map<String, Object?> toJson() => {
    'id': id,
    'label': label,
    'package': package,
    'activity': activity,
    'file': file,
    'path': path,
    if (calendarDay > 0) 'calendarDay': calendarDay,
    if (isFresh) 'fresh': true,
  };

  /// Null when the JSON entry has no path (such entries were never saved).
  static PackRecord? fromJson(String kind, Map m) {
    final path = m['path'] as String?;
    if (path == null) return null;
    return PackRecord(
      kind: kind,
      id: m['id'] as String,
      path: path,
      label: m['label'] as String? ?? '',
      package: m['package'] as String? ?? '',
      activity: m['activity'] as String? ?? '',
      file: m['file'] as String? ?? '',
      calendarDay: (m['calendarDay'] as num?)?.toInt() ?? 0,
      isFresh: m['fresh'] == true,
    );
  }

  static PackRecord fromRow(Map<String, Object?> r) => PackRecord(
    kind: r['kind'] as String,
    id: r['id'] as String,
    path: r['path'] as String,
    label: r['label'] as String,
    package: r['package'] as String,
    activity: r['activity'] as String,
    file: r['file'] as String,
    calendarDay: r['calendar_day'] as int,
    isSystem: ((r['flags'] as int) & 1) != 0,
    isFresh: ((r['flags'] as int) & 2) != 0,
  );
}

/// Everything the Pack builder keeps between runs. Used both for the SQLite
/// store and for the JSON store, so the two can be compared.
class PackContent {
  PackContent({
    this.generated = const [],
    this.originals = const [],
    this.calendars = const [],
    Map<String, Map<String, String?>>? custom,
    Map<String, Map<String, dynamic>>? corrections,
    Map<String, String>? fingerprints,
    this.exportSnapshot,
    List<Map<String, dynamic>>? log,
    List<Map<String, dynamic>>? profiles,
    this.cleaned = false,
  }) : custom = custom ?? {},
       corrections = corrections ?? {},
       fingerprints = fingerprints ?? {},
       log = log ?? [],
       profiles = profiles ?? [];

  /// The maps kept by AppState (state.json, or the SQLite store).
  PackContent.maps({
    required Map<String, Map<String, dynamic>> corrections,
    required List<Map<String, dynamic>> log,
    required List<Map<String, dynamic>> profiles,
    required Map<String, String>? exportSnapshot,
    required Map<String, String> fingerprints,
  }) : this(
         corrections: corrections,
         log: log,
         profiles: profiles,
         exportSnapshot: exportSnapshot,
         fingerprints: fingerprints,
       );

  final List<PackRecord> generated;
  final List<PackRecord> originals;
  final List<PackRecord> calendars;
  final Map<String, Map<String, String?>> custom;
  final Map<String, Map<String, dynamic>> corrections;
  final Map<String, String> fingerprints;

  /// Original key -> icon file at the last export; null = never exported.
  final Map<String, String>? exportSnapshot;
  final List<Map<String, dynamic>> log;
  final List<Map<String, dynamic>> profiles;

  /// The JSON file was written by an older build: its sources need the one-time cleanup.
  final bool cleaned;
}

/// Lists the differences between two contents, or null when they match.
/// Rows are compared in order (their order is the order of the builder lists).
String? packMismatch(PackContent a, PackContent b) {
  final la = _canonical(a), lb = _canonical(b);
  if (la.length != lb.length) return 'lines ${la.length} vs ${lb.length}';
  for (var i = 0; i < la.length; i++) {
    if (la[i] != lb[i]) return 'line $i: ${_short(la[i])} vs ${_short(lb[i])}';
  }
  return null;
}

String _short(String s) => s.length > 120 ? '${s.substring(0, 120)}...' : s;

List<String> _canonical(PackContent c) {
  final rows = <String>[];
  void addRows(String tag, List<PackRecord> list) {
    for (var i = 0; i < list.length; i++) {
      rows.add('$tag\u0002$i\u0002${list[i].rowKey}\u0002${list[i].signature}');
    }
  }

  addRows('o', c.originals);
  addRows('g', c.generated);
  addRows('c', c.calendars);
  final other = <String>[
    for (final e in c.custom.entries)
      'u\u0002${e.key}\u0002${jsonEncode(e.value)}',
    for (final e in c.corrections.entries)
      'k\u0002${e.key}\u0002${jsonEncode(e.value)}',
    for (final e in c.fingerprints.entries)
      'f\u0002${e.key}\u0002${jsonEncode(e.value)}',
    if (c.exportSnapshot != null) 's\u0002${jsonEncode(c.exportSnapshot)}',
    for (var i = 0; i < c.log.length; i++)
      'l\u0002$i\u0002${jsonEncode(c.log[i])}',
    for (var i = 0; i < c.profiles.length; i++)
      'p\u0002$i\u0002${jsonEncode(c.profiles[i])}',
  ]..sort();
  return [...rows, ...other];
}

/// The pack.db file. Every write is a small statement, so one change touches
/// only its own row.
class PackDb {
  PackDb(this.db);

  final Database db;

  static const schemaVersion = 1;

  /// Tables with one JSON value per key (correction, custom icon, fingerprint).
  static const kvTables = ['corrections', 'custom', 'fingerprints'];

  /// Ordered lists (pack log, saved correction sets).
  static const listTables = ['log', 'profiles'];

  /// Row writes since open (tests use it to check that one change writes one row).
  int rowWrites = 0;

  static Future<PackDb> open(String path, DatabaseFactory factory) async {
    final db = await factory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 1,
        onConfigure: (d) async {
          await d.rawQuery('PRAGMA journal_mode=WAL');
        },
        onCreate: (d, _) => _createSchema(d),
      ),
    );
    try {
      final v = await db.rawQuery('SELECT version FROM schema_version');
      if (v.length != 1 || v.first['version'] != schemaVersion) {
        throw StateError(
          'pack.db schema ${v.isEmpty ? 'missing' : v.first['version']} is not supported',
        );
      }
    } catch (_) {
      await db.close();
      rethrow;
    }
    return PackDb(db);
  }

  static Future<void> _createSchema(Database d) async {
    await d.execute('CREATE TABLE schema_version (version INTEGER NOT NULL)');
    await d.insert('schema_version', {'version': schemaVersion});
    await d.execute('CREATE TABLE meta (k TEXT PRIMARY KEY, v TEXT)');
    await d.execute(
      'CREATE TABLE rows (kind TEXT NOT NULL, id TEXT NOT NULL, seq INTEGER NOT NULL, key TEXT NOT NULL, package TEXT NOT NULL, activity TEXT NOT NULL, label TEXT NOT NULL, file TEXT NOT NULL, path TEXT NOT NULL, calendar_day INTEGER NOT NULL, flags INTEGER NOT NULL, updated_ms INTEGER NOT NULL, PRIMARY KEY (kind, id))',
    );
    await d.execute('CREATE INDEX rows_key ON rows (key)');
    await d.execute('CREATE INDEX rows_package ON rows (package)');
    for (final t in kvTables) {
      await d.execute(
        'CREATE TABLE $t (key TEXT PRIMARY KEY, json TEXT NOT NULL)',
      );
    }
    for (final t in listTables) {
      await d.execute(
        'CREATE TABLE $t (pos INTEGER PRIMARY KEY, json TEXT NOT NULL)',
      );
    }
  }

  Future<void> close() => db.close();

  Future<String?> getMeta(DatabaseExecutor e, String k) async {
    final r = await e.query('meta', where: 'k = ?', whereArgs: [k]);
    return r.isEmpty ? null : r.first['v'] as String?;
  }

  Future<void> setMeta(DatabaseExecutor e, String k, String? v) async {
    if (v == null) {
      await e.delete('meta', where: 'k = ?', whereArgs: [k]);
    } else {
      await e.insert('meta', {
        'k': k,
        'v': v,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
  }

  // An upsert keeps the position (seq) of a row that already exists.
  static const _upsertRow =
      'INSERT INTO rows (kind, id, seq, key, package, activity, label, file, path, calendar_day, flags, updated_ms) '
      'VALUES (?, ?, COALESCE(?, (SELECT COALESCE(MAX(seq), 0) + 1 FROM rows)), ?, ?, ?, ?, ?, ?, ?, ?, ?) '
      'ON CONFLICT (kind, id) DO UPDATE SET key = excluded.key, package = excluded.package, activity = excluded.activity, '
      'label = excluded.label, file = excluded.file, path = excluded.path, calendar_day = excluded.calendar_day, '
      'flags = excluded.flags, updated_ms = excluded.updated_ms';

  /// [seqs] fixes the position of each row (migration); null appends it.
  Future<void> upsertRows(
    DatabaseExecutor e,
    List<PackRecord> recs,
    int nowMs, {
    List<int>? seqs,
  }) async {
    if (recs.isEmpty) return;
    final b = e.batch();
    for (var i = 0; i < recs.length; i++) {
      final r = recs[i];
      b.rawInsert(_upsertRow, [
        r.kind,
        r.id,
        seqs?[i],
        r.dbKey,
        r.package,
        r.activity,
        r.label,
        r.file,
        r.path,
        r.calendarDay,
        (r.isSystem ? 1 : 0) | (r.isFresh ? 2 : 0),
        nowMs,
      ]);
    }
    rowWrites += recs.length;
    await b.commit(noResult: true);
  }

  Future<void> deleteRows(DatabaseExecutor e, List<PackRecord> recs) async {
    if (recs.isEmpty) return;
    final b = e.batch();
    for (final r in recs) {
      b.delete('rows', where: 'kind = ? AND id = ?', whereArgs: [r.kind, r.id]);
    }
    await b.commit(noResult: true);
  }

  Future<void> upsertKv(
    DatabaseExecutor e,
    String table,
    Map<String, String> items,
  ) async {
    if (items.isEmpty) return;
    final b = e.batch();
    items.forEach(
      (k, v) => b.insert(table, {
        'key': k,
        'json': v,
      }, conflictAlgorithm: ConflictAlgorithm.replace),
    );
    await b.commit(noResult: true);
  }

  Future<void> deleteKv(
    DatabaseExecutor e,
    String table,
    Iterable<String> keys,
  ) async {
    final b = e.batch();
    for (final k in keys) {
      b.delete(table, where: 'key = ?', whereArgs: [k]);
    }
    await b.commit(noResult: true);
  }

  Future<void> replaceList(
    DatabaseExecutor e,
    String table,
    List<Map<String, dynamic>> items,
  ) async {
    await e.delete(table);
    if (items.isEmpty) return;
    final b = e.batch();
    for (var i = 0; i < items.length; i++) {
      b.insert(table, {'pos': i, 'json': jsonEncode(items[i])});
    }
    await b.commit(noResult: true);
  }

  Future<List<Map<String, dynamic>>> readList(
    DatabaseExecutor e,
    String table,
  ) async {
    final r = await e.query(table, orderBy: 'pos');
    return [
      for (final x in r)
        (jsonDecode(x['json'] as String) as Map).cast<String, dynamic>(),
    ];
  }

  /// Everything stored. Icon records whose file is gone are left out, as the
  /// JSON reader does; they stay in the database.
  Future<PackContent> loadContent(
    DatabaseExecutor e,
    bool Function(String) exists,
  ) async {
    final byKind = <String, List<PackRecord>>{
      'original': [],
      'generated': [],
      'calendar': [],
    };
    for (final r in await e.query('rows', orderBy: 'seq')) {
      final rec = PackRecord.fromRow(r);
      if (exists(rec.path)) byKind[rec.kind]!.add(rec);
    }
    final custom = <String, Map<String, String?>>{};
    for (final x in await readKvRaw(e, 'custom')) {
      final m = (jsonDecode(x.value) as Map).cast<String, String?>();
      if (m['path'] != null && exists(m['path']!)) custom[x.key] = m;
    }
    final corrections = <String, Map<String, dynamic>>{
      for (final x in await readKvRaw(e, 'corrections'))
        x.key: (jsonDecode(x.value) as Map).cast<String, dynamic>(),
    };
    final fingerprints = <String, String>{
      for (final x in await readKvRaw(e, 'fingerprints'))
        x.key: jsonDecode(x.value) as String,
    };
    final snap = await getMeta(e, 'export_snapshot');
    return PackContent(
      generated: byKind['generated']!,
      originals: byKind['original']!,
      calendars: byKind['calendar']!,
      custom: custom,
      corrections: corrections,
      fingerprints: fingerprints,
      exportSnapshot: snap == null
          ? null
          : (jsonDecode(snap) as Map).cast<String, String>(),
      log: await readList(e, 'log'),
      profiles: await readList(e, 'profiles'),
    );
  }

  Future<List<({String key, String value})>> readKvRaw(
    DatabaseExecutor e,
    String table,
  ) async {
    final r = await e.query(table);
    return [
      for (final x in r) (key: x['key'] as String, value: x['json'] as String),
    ];
  }

  /// Empties every table, then stores [src] and reads it back. Run it in a
  /// transaction: a mismatch throws and nothing is kept.
  Future<void> importAll(PackContent src, int nowMs) =>
      db.transaction((t) async {
        await clearData(t);
        await upsertRows(
          t,
          src.originals,
          nowMs,
          seqs: [for (var i = 0; i < src.originals.length; i++) i],
        );
        await upsertRows(
          t,
          src.generated,
          nowMs,
          seqs: [for (var i = 0; i < src.generated.length; i++) i],
        );
        await upsertRows(
          t,
          src.calendars,
          nowMs,
          seqs: [for (var i = 0; i < src.calendars.length; i++) i],
        );
        await upsertKv(t, 'custom', {
          for (final e in src.custom.entries) e.key: jsonEncode(e.value),
        });
        await upsertKv(t, 'corrections', {
          for (final e in src.corrections.entries) e.key: jsonEncode(e.value),
        });
        await upsertKv(t, 'fingerprints', {
          for (final e in src.fingerprints.entries) e.key: jsonEncode(e.value),
        });
        await replaceList(t, 'log', src.log);
        await replaceList(t, 'profiles', src.profiles);
        if (src.exportSnapshot != null)
          await setMeta(t, 'export_snapshot', jsonEncode(src.exportSnapshot));
        final back = await loadContent(t, (_) => true);
        final diff = packMismatch(src, back);
        if (diff != null) throw StateError('verification failed: $diff');
        await setMeta(t, 'migrated', '1');
      });

  Future<void> clearData(DatabaseExecutor e) async {
    await e.delete('rows');
    for (final t in [...kvTables, ...listTables]) {
      await e.delete(t);
    }
    await e.delete('meta');
  }
}
