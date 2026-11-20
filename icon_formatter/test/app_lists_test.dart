import 'package:flutter_test/flutter_test.dart';
import 'package:icon_formatter/services/app_lists.dart';

void main() {
  group('AppList JSON', () {
    test('toJson writes sorted packages', () {
      final l = AppList(id: 'x1', name: 'Social', packages: {'com.b', 'com.a'});
      expect(l.toJson(), {
        'id': 'x1',
        'name': 'Social',
        'packages': ['com.a', 'com.b'],
      });
    });

    test('round trip keeps id, name and packages', () {
      final l = AppList(id: 'x1', name: 'Mail', packages: {'com.a'});
      final back = AppList.fromJson(l.toJson());
      expect(back.id, 'x1');
      expect(back.name, 'Mail');
      expect(back.packages, {'com.a'});
    });

    test('missing fields fall back to empty values and a new id', () {
      final l = AppList.fromJson(const {});
      expect(l.id, isNotEmpty);
      expect(l.name, '');
      expect(l.packages, isEmpty);
    });

    test('wrong types are ignored', () {
      final l = AppList.fromJson({
        'id': 42,
        'name': ['x'],
        'packages': 'com.a',
      });
      expect(l.id, isNotEmpty);
      expect(l.name, '');
      expect(l.packages, isEmpty);
    });

    test('non-string packages and blanks are dropped, duplicates merged', () {
      final l = AppList.fromJson({
        'id': 'a',
        'name': '  Trim  ',
        'packages': ['com.a', 7, null, '', '  ', 'com.a', ' com.b ', {}],
      });
      expect(l.name, 'Trim');
      expect(l.packages, {'com.a', 'com.b'});
    });

    test('empty id string gets a new id', () {
      expect(AppList.fromJson({'id': ''}).id, isNotEmpty);
    });

    test('unicode name round trips', () {
      final l = AppList.fromJson({'id': 'u', 'name': 'Most loved ✨'});
      expect(l.name, 'Most loved ✨');
    });
  });

  group('newListId', () {
    test('returns an id not in taken', () {
      final first = newListId(const []);
      final second = newListId([first]);
      expect(second, isNot(first));
      expect(newListId([first, second]), isNot(anyOf(first, second)));
    });
  });

  group('appListsFromJson', () {
    test('non-list values give empty result', () {
      expect(appListsFromJson(null), isEmpty);
      expect(appListsFromJson('nope'), isEmpty);
      expect(appListsFromJson({'a': 1}), isEmpty);
    });

    test('skips non-map entries and keeps the first of duplicate ids', () {
      final lists = appListsFromJson([
        {'id': 'a', 'name': 'First'},
        'junk',
        null,
        {'id': 'a', 'name': 'Second'},
        {'id': 'b', 'name': 'Third'},
      ]);
      expect(lists.map((l) => l.name), ['First', 'Third']);
    });

    test('listsToJson round trips through appListsFromJson', () {
      final lists = [
        AppList(id: 'a', name: 'A', packages: {'p'}),
        AppList(id: 'b', name: 'B'),
      ];
      final back = appListsFromJson(listsToJson(lists));
      expect(back.map((l) => l.id), ['a', 'b']);
      expect(back.first.packages, {'p'});
    });
  });

  group('AppListOps', () {
    test('uniqueName returns the name when free and trims it', () {
      final lists = <AppList>[];
      expect(lists.uniqueName('  Work  '), 'Work');
    });

    test('uniqueName adds a counter on clashes, case-insensitively', () {
      final lists = [
        AppList(id: '1', name: 'Work'),
        AppList(id: '2', name: 'work (2)'),
      ];
      expect(lists.uniqueName('WORK'), 'WORK (3)');
    });

    test('uniqueName ignores the list being renamed', () {
      final lists = [AppList(id: '1', name: 'Work')];
      expect(lists.uniqueName('Work', exceptId: '1'), 'Work');
    });

    test('blank name falls back to list', () {
      expect(<AppList>[].uniqueName('   '), 'list');
    });

    test('addList appends with a unique id and name', () {
      final lists = <AppList>[];
      final a = lists.addList(name: 'Games', packages: {'com.g'});
      final b = lists.addList(name: 'Games');
      expect(lists, hasLength(2));
      expect(a.id, isNot(b.id));
      expect(b.name, 'Games (2)');
      expect(a.packages, {'com.g'});
      expect(b.packages, isEmpty);
    });

    test('addList copies the packages set', () {
      final lists = <AppList>[];
      final src = {'com.a'};
      final l = lists.addList(name: 'X', packages: src);
      src.add('com.b');
      expect(l.packages, {'com.a'});
    });

    test('findList returns null for unknown ids', () {
      final lists = [AppList(id: '1', name: 'A')];
      expect(lists.findList('1')?.name, 'A');
      expect(lists.findList('nope'), isNull);
    });

    test('renameList renames, refuses blank names and unknown ids', () {
      final lists = [AppList(id: '1', name: 'A'), AppList(id: '2', name: 'B')];
      expect(lists.renameList('1', 'C'), isTrue);
      expect(lists.findList('1')!.name, 'C');
      expect(lists.renameList('1', '   '), isFalse);
      expect(lists.findList('1')!.name, 'C');
      expect(lists.renameList('zzz', 'X'), isFalse);
    });

    test('renameList to a taken name gets a unique suffix', () {
      final lists = [AppList(id: '1', name: 'A'), AppList(id: '2', name: 'B')];
      expect(lists.renameList('1', 'b'), isTrue);
      expect(lists.findList('1')!.name, 'b (2)');
    });

    test('renameList to its own name keeps it', () {
      final lists = [AppList(id: '1', name: 'A')];
      expect(lists.renameList('1', 'A'), isTrue);
      expect(lists.findList('1')!.name, 'A');
    });

    test('deleteList removes only the matching list', () {
      final lists = [AppList(id: '1', name: 'A'), AppList(id: '2', name: 'B')];
      expect(lists.deleteList('1'), isTrue);
      expect(lists.map((l) => l.id), ['2']);
      expect(lists.deleteList('1'), isFalse);
    });
  });
}
