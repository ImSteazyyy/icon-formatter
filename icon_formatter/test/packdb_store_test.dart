import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icon_formatter/services/packdb_db.dart';
import 'package:icon_formatter/services/packdb_store.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Map<String, dynamic> _icon(
  String id, {
  String path = '/x.png',
  String pkg = '',
  String file = '',
}) => {
  'id': id,
  'label': 'Label $id',
  'package': pkg,
  'activity': '',
  'file': file,
  'path': path,
};

String _json({
  required int originals,
  int generated = 0,
  int calendars = 0,
  bool clean = true,
  String? dupId,
  String path = '/x.png',
}) {
  final orig = [
    for (var i = 0; i < originals; i++) _icon(dupId ?? 'o$i', pkg: 'com.app$i', path: path),
  ];
  return jsonEncode({
    'generated': [
      for (var i = 0; i < generated; i++) _icon('g$i', pkg: 'com.app$i', path: path),
    ],
    'originals': orig,
    'custom': {
      'pkg:com.app0': {'path': '/c.png', 'prev': null},
    },
    if (clean) 'cleanV': 1,
    'calendars': [
      for (var i = 0; i < calendars; i++)
        {..._icon('d$i', pkg: 'com.cal'), 'calendarDay': i + 1},
    ],
  });
}

PackContent _maps({int n = 2}) => PackContent.maps(
  corrections: {
    for (var i = 0; i < n; i++)
      'pkg:com.app$i': {
        'excluded': i == 1,
        'verified': true,
        'alias': ['pkg:com.other$i'],
        'variants': ['/v1.png', '/v2.png'],
        'variant': '/v2.png',
        'label': 'Nome $i',
      },
  },
  log: [
    {'date': '2026-11-19T10:00:00', 'text': 'Create 2 icons'},
  ],
  profiles: [
    {'name': 'Profilo', 'date': '2026-11-19', 'corrections': {}},
  ],
  exportSnapshot: {'pkg:com.app0': '/out/a.png'},
  fingerprints: {'pkg:com.app0': 'abc123'},
);

void _resetStore() {
  PackStore.I = JsonPackStore(
    path: '/nonexistent/pack_builder.json',
    exists: (_) => false,
  );
  PackStore.fallbackReason = null;
  PackStore.onFallback.clear();
}

void main() {
  setUpAll(sqfliteFfiInit);

  late Directory root;
  setUp(() {
    root = Directory.systemTemp.createTempSync('packdb_test_');
  });
  tearDown(() async {
    final cur = PackStore.I;
    if (cur is SqlitePackStore) await cur.pdb.close();
    _resetStore();
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  String jsonPath() => '${root.path}${Platform.pathSeparator}pack_builder.json';
  String statePath() => '${root.path}${Platform.pathSeparator}state.json';

  test('schema is created with the version row and the tables', () async {
    final pdb = await PackDb.open(inMemoryDatabasePath, databaseFactoryFfi);
    final tables = (await pdb.db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table'",
    )).map((r) => r['name']).toSet();
    expect(
      tables,
      containsAll([
        'schema_version',
        'meta',
        'rows',
        'corrections',
        'custom',
        'fingerprints',
        'log',
        'profiles',
      ]),
    );
    expect(
      (await pdb.db.rawQuery('SELECT version FROM schema_version'))
          .single['version'],
      PackDb.schemaVersion,
    );
    await pdb.close();
  });

  test('migration imports the JSON and the maps, verifies them and keeps the JSON untouched', () async {
    final text = _json(originals: 3, generated: 2, calendars: 1);
    File(jsonPath()).writeAsStringSync(text);
    File(statePath()).writeAsStringSync('{"version":3}');
    final fromState = _maps();

    final out = await packStoreBoot(
      fromState,
      root: root.path,
      stateFile: statePath(),
      exists: (_) => true,
      factory: databaseFactoryFfi,
    );

    expect(PackStore.I, isA<SqlitePackStore>());
    expect(PackStore.I.ownsMaps, isTrue);
    expect(out.corrections['pkg:com.app0']!['variants'], [
      '/v1.png',
      '/v2.png',
    ]);
    expect(out.corrections['pkg:com.app0']!['alias'], ['pkg:com.other0']);
    expect(out.exportSnapshot, {'pkg:com.app0': '/out/a.png'});
    final read = PackStore.I.readAll();
    expect(read.originals.map((r) => r.id).toList(), ['o0', 'o1', 'o2']);
    expect(read.generated.map((r) => r.id).toList(), ['g0', 'g1']);
    expect(read.calendars.single.calendarDay, 1);
    expect(read.custom.keys.toList(), ['pkg:com.app0']);
    expect(
      File(jsonPath()).readAsStringSync(),
      text,
      reason: 'the JSON file must not change',
    );
    expect(File('${jsonPath()}.bak').existsSync(), isTrue);
    expect(File('${statePath()}.bak').existsSync(), isTrue);
  });

  test('a second start uses the stored data without importing again', () async {
    File(jsonPath()).writeAsStringSync(_json(originals: 2));
    await packStoreBoot(
      _maps(),
      root: root.path,
      stateFile: statePath(),
      exists: (_) => true,
      factory: databaseFactoryFfi,
    );
    await PackStore.I.writeIcons(PackStore.I.readAll());
    // the JSON now holds other content: the database wins once migrated
    File(jsonPath()).writeAsStringSync(_json(originals: 9));
    final out = await packStoreBoot(
      PackContent(),
      root: root.path,
      stateFile: statePath(),
      exists: (_) => true,
      factory: databaseFactoryFfi,
    );
    expect(PackStore.I.readAll().originals.length, 2);
    expect(out.corrections.length, 2);
  });

  test(
    'a verification mismatch rolls back and falls back to the JSON store',
    () async {
      // two sources with one id: the database keeps one row, so the read-back differs
      File(jsonPath()).writeAsStringSync(_json(originals: 2, dupId: 'same'));
      final fromState = _maps();
      final out = await packStoreBoot(
        fromState,
        root: root.path,
        stateFile: statePath(),
        exists: (_) => true,
        factory: databaseFactoryFfi,
      );

      expect(PackStore.I, isA<JsonPackStore>());
      expect(PackStore.I.ownsMaps, isFalse);
      expect(PackStore.fallbackReason, contains('verification failed'));
      expect(
        identical(out.corrections, fromState.corrections),
        isTrue,
        reason: 'state maps are used as they are',
      );
      final pdb = await PackDb.open(
        root.path + Platform.pathSeparator + 'pack.db',
        databaseFactoryFfi,
      );
      expect(
        await pdb.getMeta(pdb.db, 'migrated'),
        isNull,
        reason: 'the flag is set only after a verified import',
      );
      await pdb.close();
      expect(File(jsonPath()).readAsStringSync(), contains('same'));
    },
  );

  test('a corrupt JSON file falls back without crashing', () async {
    File(jsonPath()).writeAsStringSync('{not json');
    final fromState = _maps();
    final out = await packStoreBoot(
      fromState,
      root: root.path,
      stateFile: statePath(),
      exists: (_) => true,
      factory: databaseFactoryFfi,
    );
    expect(PackStore.I, isA<JsonPackStore>());
    expect(out.log.length, 1);
  });

  test('upsert, delete and load of 5000 rows; a single change writes one row', () async {
    final pdb = await PackDb.open(inMemoryDatabasePath, databaseFactoryFfi);
    final recs = [
      for (var i = 0; i < 5000; i++)
        PackRecord(
          kind: 'original',
          id: 'o$i',
          path: '/p/$i.png',
          package: 'com.app$i',
          label: 'App $i',
        ),
    ];
    final sw = Stopwatch()..start();
    await pdb.db.transaction((t) async {
      await pdb.upsertRows(
        t,
        recs,
        1,
        seqs: [for (var i = 0; i < recs.length; i++) i],
      );
    });
    final insertMs = sw.elapsedMilliseconds;

    // the store writes only the changed row
    final store = SqlitePackStore(
      pdb,
      PackContent(originals: recs),
      jsonPath: jsonPath(),
      offMarker: '${root.path}${Platform.pathSeparator}pack.db.off',
    );
    final before = pdb.rowWrites;
    final changed = [
      for (final r in recs)
        if (r.id == 'o42')
          PackRecord(
            kind: 'original',
            id: 'o42',
            path: '/p/new.png',
            package: 'com.app42',
            label: 'Renamed',
          )
        else
          r,
    ];
    await store.writeIcons(PackContent(originals: changed));
    expect(pdb.rowWrites - before, 1);

    sw
      ..reset()
      ..start();
    final loaded = await pdb.loadContent(pdb.db, (_) => true);
    final loadMs = sw.elapsedMilliseconds;
    expect(loaded.originals.length, 5000);
    expect(loaded.originals[42].label, 'Renamed');
    expect(loaded.originals[41].label, 'App 41');
    expect(loadMs, lessThan(1000));

    await store.writeIcons(PackContent(originals: changed.sublist(0, 4999)));
    expect((await pdb.loadContent(pdb.db, (_) => true)).originals.length, 4999);
    // ignore the timing noise of the test host; the numbers are for the report
    debugPrint(
      'pack.db benchmark: insert 5000 rows $insertMs ms, load 5000 rows $loadMs ms',
    );
    await pdb.close();
  });

  test('benchmark: JSON decode and full encode against SQLite read and one-row write (5000 rows)', () async {
    final icon = File('${root.path}/icon.png')..writeAsBytesSync([0]);
    final json = _json(originals: 5000, path: icon.path);
    final swJ = Stopwatch()..start();
    final fromJson = parsePackJson(json, (_) => true);
    final jsonDecodeMs = swJ.elapsedMilliseconds;

    final pdb = await PackDb.open(inMemoryDatabasePath, databaseFactoryFfi);
    await pdb.db.transaction((t) => pdb.upsertRows(t, fromJson.originals, 1, seqs: [for (var i = 0; i < 5000; i++) i]));
    final swS = Stopwatch()..start();
    await pdb.loadContent(pdb.db, (_) => true);
    final sqlReadMs = swS.elapsedMilliseconds;

    final swE = Stopwatch()..start();
    for (final r in fromJson.originals) {
      File(r.path).existsSync();
    }
    final statMs = swE.elapsedMilliseconds;

    final swW = Stopwatch()..start();
    final full = jsonEncode(packJsonOf(fromJson));
    final fullEncodeMs = swW.elapsedMilliseconds;
    final store = SqlitePackStore(pdb, fromJson, jsonPath: jsonPath(), offMarker: '${root.path}/pack.db.off');
    final swO = Stopwatch()..start();
    await store.writeIcons(PackContent(
      originals: [
        for (final r in fromJson.originals)
          if (r.id == 'o7') PackRecord(kind: 'original', id: 'o7', path: r.path, package: r.package, label: 'x') else r,
      ],
    ));
    final oneRowMs = swO.elapsedMilliseconds;
    debugPrint('BENCH 5000 rows: JSON decode $jsonDecodeMs ms (${json.length} bytes), SQLite read $sqlReadMs ms, '
        'existsSync x5000 (both stores) $statMs ms, JSON full encode $fullEncodeMs ms (${full.length} bytes), '
        'SQLite one-row sync $oneRowMs ms (diff in memory, one row written)');
    expect(pdb.rowWrites, 5000 + 1);
    await pdb.close();
  });

  test('corrections, variants, aliases, log, profiles and export snapshot round trip', () async {
    final pdb = await PackDb.open(inMemoryDatabasePath, databaseFactoryFfi);
    final store = SqlitePackStore(
      pdb,
      PackContent(),
      jsonPath: jsonPath(),
      offMarker: '${root.path}${Platform.pathSeparator}pack.db.off',
    );
    final maps = _maps(n: 3);
    await store.writeMaps(maps);
    final back = await pdb.loadContent(pdb.db, (_) => true);
    expect(packMismatch(maps, back), isNull);
    expect(back.corrections['pkg:com.app2']!['variant'], '/v2.png');

    // change one correction, drop one: only those rows are touched
    final changed = _maps(n: 3)..corrections.remove('pkg:com.app0');
    changed.corrections['pkg:com.app1']!['label'] = 'Nuovo';
    await store.writeMaps(changed);
    final after = await pdb.loadContent(pdb.db, (_) => true);
    expect(after.corrections.keys.toSet(), {'pkg:com.app1', 'pkg:com.app2'});
    expect(after.corrections['pkg:com.app1']!['label'], 'Nuovo');
    await pdb.close();
  });

  test(
    'a write error switches to the JSON store and leaves the marker file',
    () async {
      final pdb = await PackDb.open(inMemoryDatabasePath, databaseFactoryFfi);
      final store = SqlitePackStore(
        pdb,
        PackContent(),
        jsonPath: jsonPath(),
        offMarker: '${root.path}${Platform.pathSeparator}pack.db.off',
      );
      PackStore.I = store;
      var called = 0;
      PackStore.onFallback.add(() => called++);
      await pdb.close(); // every later write fails
      await store.writeMaps(_maps());
      expect(PackStore.I, isA<JsonPackStore>());
      expect(called, 1);
      expect(
        File('${root.path}${Platform.pathSeparator}pack.db.off').existsSync(),
        isTrue,
      );
      expect(PackStore.fallbackReason, contains('pack_builder.json'));
    },
  );

  test('old state compatibility: a JSON without cleanV is cleaned, missing keys read as empty', () {
    final c = parsePackJson(_json(originals: 2, clean: false), (_) => true);
    expect(c.cleaned, isTrue);
    final bare = parsePackJson('{}', (_) => true);
    expect(bare.originals, isEmpty);
    expect(bare.custom, isEmpty);
    expect(bare.cleaned, isTrue);
    expect(PackContent().corrections, isEmpty);
  });

  test('a boot slower than the timeout falls back to the JSON store', () async {
    File(jsonPath()).writeAsStringSync(_json(originals: 2));
    final fromState = _maps();
    final out = await packStoreBoot(fromState, root: root.path, stateFile: statePath(), exists: (_) => true, factory: databaseFactoryFfi, timeout: Duration.zero);
    expect(PackStore.I, isA<JsonPackStore>());
    expect(PackStore.fallbackReason, contains('did not open'));
    expect(identical(out.corrections, fromState.corrections), isTrue);
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(PackStore.I, isA<JsonPackStore>(), reason: 'a late boot must not replace the fallback');
  });

  test('sources whose files do not exist migrate as an empty list and verify', () async {
    File(jsonPath()).writeAsStringSync(_json(originals: 3, generated: 2));
    final out = await packStoreBoot(_maps(), root: root.path, stateFile: statePath(), exists: (_) => false, factory: databaseFactoryFfi);
    expect(PackStore.I, isA<SqlitePackStore>());
    expect(PackStore.I.readAll().originals, isEmpty);
    expect(out.corrections.length, 2);
  });

  test('relative icon paths are stored and read back as written', () async {
    File(jsonPath()).writeAsStringSync(_json(originals: 2, path: 'seed/icon1.png'));
    await packStoreBoot(_maps(), root: root.path, stateFile: statePath(), exists: (_) => true, factory: databaseFactoryFfi);
    expect(PackStore.I.readAll().originals.map((r) => r.path).toSet(), {'seed/icon1.png'});
  });
}
