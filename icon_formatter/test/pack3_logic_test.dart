import 'package:flutter_test/flutter_test.dart';
import 'package:icon_formatter/services/pack3_logic.dart';
import 'package:icon_formatter/services/pack_mapping_import.dart';
import 'package:icon_formatter/services/pack_suggest.dart';

String identity(String k) => k;

void main() {
  group('packEntryFor', () {
    test('component is package/activity, drawable from the package', () {
      final e = packEntryFor(
        package: 'com.x.app',
        activity: '.Main',
        label: 'X',
        drawableOf: identity,
      );
      expect(e.component, 'com.x.app/.Main');
      expect(e.drawable, 'com.x.app');
      expect(e.label, 'X');
    });

    test('package only: component is the package', () {
      final e = packEntryFor(
        package: 'com.x.app',
        activity: '',
        label: 'X',
        drawableOf: identity,
      );
      expect(e.component, 'com.x.app');
    });

    test('no package: drawable from the label, empty component', () {
      final e = packEntryFor(
        package: '',
        activity: '',
        label: 'Foto',
        drawableOf: identity,
      );
      expect(e.component, '');
      expect(e.drawable, 'Foto');
    });

    test('nothing to name: empty drawable, drawer not called', () {
      var called = false;
      final e = packEntryFor(
        package: '',
        activity: '',
        label: '',
        drawableOf: (k) {
          called = true;
          return k;
        },
      );
      expect(e.drawable, '');
      expect(called, isFalse);
    });
  });

  group('freeCandidates', () {
    test('drops icons used by other rows and the own icon', () {
      final icons = [
        const CandidateIcon(id: 'a'),
        const CandidateIcon(id: 'b'),
        const CandidateIcon(id: 'c'),
        const CandidateIcon(id: 'd'),
      ];
      final free = freeCandidates(icons: icons, usedIds: {'b'}, ownId: 'c');
      expect([for (final c in free) c.id], ['a', 'd']);
    });
  });

  group('mappingSourceEntries', () {
    test(
      'builds component and lowercase drawable, skips icons without package',
      () {
        final out = mappingSourceEntries([
          (package: 'com.x', activity: '.Main', drawable: 'X_Icon'),
          (package: 'com.y', activity: '', drawable: 'Y'),
          (package: '', activity: '', drawable: 'loose'),
        ]);
        expect(out.length, 2);
        expect(out[0].component, 'com.x/.Main');
        expect(out[0].drawable, 'x_icon');
        expect(out[1].component, 'com.y');
      },
    );

    test('feeds importMappingsDetailed: exact component wins over package', () {
      final source = mappingSourceEntries([
        (package: 'com.x', activity: '.Main', drawable: 'exact'),
        (package: 'com.x', activity: '.Other', drawable: 'other'),
      ]);
      final out = importMappingsDetailed(
        source: source,
        installed: const [
          InstalledAppInfo(package: 'com.x', label: 'X', activity: '.Main'),
        ],
      );
      expect(out['com.x']!.drawable, 'exact');
      expect(out['com.x']!.match, MappingMatch.component);
    });
  });

  group('suggestIcons glue', () {
    test('a name match is ranked first among free candidates', () {
      final free = freeCandidates(
        icons: const [
          CandidateIcon(id: 'x1', label: 'Calendar', package: 'com.cal'),
          CandidateIcon(id: 'x2', label: 'Zebra', package: 'com.zebra'),
        ],
        usedIds: const {},
      );
      final picks = suggestIcons(
        label: 'Calendar',
        package: 'com.google.calendar',
        candidates: free,
      );
      expect(picks, isNotEmpty);
      expect(picks.first.candidate.id, 'x1');
    });
  });
}
