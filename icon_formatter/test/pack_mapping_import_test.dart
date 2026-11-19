import 'package:flutter_test/flutter_test.dart';
import 'package:icon_formatter/services/pack_mapping_import.dart';

void main() {
  group('parseAppFilter', () {
    test('reads standard items', () {
      const xml = '''
<?xml version="1.0" encoding="utf-8"?>
<resources>
  <iconback img1="iconback" />
  <item component="ComponentInfo{com.a/com.a.Main}" drawable="a_icon"/>
  <item component="ComponentInfo{com.b/.Settings}" drawable="b_icon" />
</resources>''';
      final r = parseAppFilter(xml);
      expect(r.map((e) => e.component), [
        'ComponentInfo{com.a/com.a.Main}',
        'ComponentInfo{com.b/.Settings}',
      ]);
      expect(r.map((e) => e.drawable), ['a_icon', 'b_icon']);
    });

    test('ignores comments and calendar entries', () {
      const xml = '''
<!-- <item component="ComponentInfo{x/.Y}" drawable="hidden"/> -->
<calendar component="ComponentInfo{com.cal/.Main}" prefix="cal_" />
<item component="ComponentInfo{com.a/.Main}" drawable="real"/>
<itemset x="y" />''';
      final r = parseAppFilter(xml);
      expect(r, hasLength(1));
      expect(r.single.drawable, 'real');
    });

    test('drops items without a drawable and keeps the rest', () {
      const xml =
          '<item component="ComponentInfo{a/.B}"/><item component="ComponentInfo{c/.D}" drawable="ok"/>';
      expect(parseAppFilter(xml).map((e) => e.drawable), ['ok']);
    });

    test(
      'accepts single quotes, unescapes entities and any attribute order',
      () {
        const xml =
            "<item drawable='x&amp;y' component='ComponentInfo{a/.B&gt;C}'/>";
        final r = parseAppFilter(xml).single;
        expect(r.drawable, 'x&y');
        expect(r.component, 'ComponentInfo{a/.B>C}');
      },
    );

    test('numeric entities are decoded, invalid ones are kept', () {
      const xml =
          '<item component="a/.b" drawable="&#65;&#x42;&#xZZ;&#99999999;"/>';
      expect(parseAppFilter(xml).single.drawable, 'AB&#xZZ;&#99999999;');
    });

    test('empty and malformed input never throw', () {
      expect(parseAppFilter(''), isEmpty);
      expect(parseAppFilter('not xml at all'), isEmpty);
      expect(parseAppFilter('<item component="a/.B" drawable="x"'), isEmpty);
      expect(
        parseAppFilter(
          '<item component="a/.B" drawable="x"/><item component="c" drawable="y"',
        ),
        hasLength(1),
      );
      expect(
        parseAppFilter('<!-- never closed <item component="a" drawable="x"/>'),
        isEmpty,
      );
    });

    test('unicode values are kept', () {
      const xml =
          '<item component="ComponentInfo{com.ü/.Ö}" drawable="icona_ñ"/>';
      final r = parseAppFilter(xml).single;
      expect(r.component, 'ComponentInfo{com.ü/.Ö}');
      expect(r.drawable, 'icona_ñ');
    });
  });

  group('importMappings', () {
    const src = [
      AppFilterEntry(
        component: 'ComponentInfo{com.a/com.a.Main}',
        drawable: 'a_icon',
      ),
      AppFilterEntry(
        component: 'ComponentInfo{com.b/.Settings}',
        drawable: 'b_settings',
      ),
      AppFilterEntry(
        component: 'ComponentInfo{com.b/.Home}',
        drawable: 'b_home',
      ),
      AppFilterEntry(
        component: 'ComponentInfo{com.c/.Main}',
        drawable: 'c_icon',
        label: 'Gamma',
      ),
    ];

    test('empty inputs give empty map', () {
      expect(importMappings(source: const [], installed: const []), isEmpty);
      expect(importMappings(source: src, installed: const []), isEmpty);
      expect(
        importMappings(
          source: const [],
          installed: const [InstalledAppInfo(package: 'com.a', label: 'A')],
        ),
        isEmpty,
      );
    });

    test('exact component match wins over package match', () {
      final d = importMappingsDetailed(
        source: src,
        installed: const [
          InstalledAppInfo(package: 'com.b', label: 'B', activity: '.Home'),
        ],
      );
      expect(d['com.b']!.drawable, 'b_home');
      expect(d['com.b']!.match, MappingMatch.component);
      expect(d['com.b']!.component, 'ComponentInfo{com.b/.Home}');
    });

    test('full and short activity names are equivalent', () {
      final d = importMappingsDetailed(
        source: src,
        installed: const [
          InstalledAppInfo(
            package: 'com.a',
            label: 'A',
            activity: 'com.a.Main',
          ),
        ],
      );
      expect(d['com.a']!.match, MappingMatch.component);
      expect(d['com.a']!.drawable, 'a_icon');
    });

    test(
      'package match when the activity differs, first source entry wins',
      () {
        final d = importMappingsDetailed(
          source: src,
          installed: const [
            InstalledAppInfo(package: 'com.b', label: 'B', activity: '.Other'),
          ],
        );
        expect(d['com.b']!.match, MappingMatch.package);
        expect(d['com.b']!.drawable, 'b_settings');
      },
    );

    test('label fallback when the package is unknown', () {
      final d = importMappingsDetailed(
        source: src,
        installed: const [InstalledAppInfo(package: 'com.zz', label: 'gamma!')],
      );
      expect(d['com.zz']!.match, MappingMatch.label);
      expect(d['com.zz']!.drawable, 'c_icon');
      expect(d['com.zz']!.component, 'ComponentInfo{com.c/.Main}');
    });

    test(
      'label fallback uses the package tail when no source label exists',
      () {
        final d = importMappingsDetailed(
          source: const [
            AppFilterEntry(component: 'org.x.telegram/.Main', drawable: 't'),
          ],
          installed: const [
            InstalledAppInfo(package: 'org.other', label: 'Telegram'),
          ],
        );
        expect(d['org.other']!.match, MappingMatch.label);
      },
    );

    test('no match leaves the app out', () {
      final r = importMappings(
        source: src,
        installed: const [InstalledAppInfo(package: 'com.none', label: 'None')],
      );
      expect(r, isEmpty);
    });

    test('empty package or label never matches by accident', () {
      final r = importMappings(
        source: const [
          AppFilterEntry(component: '', drawable: 'x'),
          AppFilterEntry(component: 'ComponentInfo{/.Q}', drawable: 'y'),
        ],
        installed: const [
          InstalledAppInfo(package: '', label: ''),
          InstalledAppInfo(package: 'com.q', label: ''),
        ],
      );
      expect(r, isEmpty);
    });

    test('duplicate installed package is reported once', () {
      final r = importMappingsDetailed(
        source: src,
        installed: const [
          InstalledAppInfo(package: 'com.a', label: 'A'),
          InstalledAppInfo(package: 'com.a', label: 'A2'),
        ],
      );
      expect(r.keys, ['com.a']);
    });

    test('importMappings returns installed package -> drawable', () {
      final r = importMappings(
        source: src,
        installed: const [
          InstalledAppInfo(package: 'com.a', label: 'A'),
          InstalledAppInfo(package: 'com.c', label: 'C', activity: '.Main'),
        ],
      );
      expect(r, {'com.a': 'a_icon', 'com.c': 'c_icon'});
    });

    test('source entries with empty drawable are ignored', () {
      final r = importMappings(
        source: const [
          AppFilterEntry(component: 'ComponentInfo{com.a/.Main}', drawable: ''),
        ],
        installed: const [InstalledAppInfo(package: 'com.a', label: 'A')],
      );
      expect(r, isEmpty);
    });

    test('unicode labels match ignoring case and punctuation', () {
      final r = importMappingsDetailed(
        source: const [
          AppFilterEntry(component: 'x.y/.Z', drawable: 'd', label: 'Café Ü'),
        ],
        installed: const [InstalledAppInfo(package: 'other', label: 'CAFÉ ü!')],
      );
      expect(r.values.single.match, MappingMatch.label);
    });
  });

  test('round trip: parsed XML feeds the mapping', () {
    const xml =
        '<item component="ComponentInfo{com.a/.Main}" drawable="a_icon"/>';
    final r = importMappings(
      source: parseAppFilter(xml),
      installed: const [
        InstalledAppInfo(package: 'com.a', label: 'A', activity: '.Main'),
      ],
    );
    expect(r, {'com.a': 'a_icon'});
  });
}
