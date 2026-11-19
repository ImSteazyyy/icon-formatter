import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:icon_formatter/src/rust/api/engine.dart';
import 'package:icon_formatter/workspace/studio_duplicates.dart';
import 'package:icon_formatter/workspace/studio_list.dart';
import 'package:icon_formatter/workspace/workspace_controller.dart';

WorkItem _item(String id, {String? label, bool excluded = false, bool modified = false, bool? ok}) {
  final it = WorkItem(id: id, name: id, rel: '$id.png', label: label);
  it.excluded = excluded;
  if (modified) it.matchPlate = true;
  if (ok != null) {
    it.result = ItemResult(id: id, name: id, ok: ok, ambiguous: false, confidence: 1, method: 'm', notes: const []);
  }
  return it;
}

List<String> _ids(List<WorkItem> l) => [for (final i in l) i.id];

void main() {
  final items = [
    _item('c'),
    _item('a', modified: true),
    _item('b', ok: false),
    _item('d', excluded: true),
    _item('e', label: 'Zeta app'),
  ];

  test('default order and no filter keep the import order', () {
    expect(_ids(studioArrange(items)), ['c', 'a', 'b', 'd', 'e']);
  });

  test('filters: modified, errors, excluded', () {
    expect(_ids(studioArrange(items, filter: StudioFilter.modified)), ['a']);
    expect(_ids(studioArrange(items, filter: StudioFilter.errors)), ['b']);
    expect(_ids(studioArrange(items, filter: StudioFilter.excluded)), ['d']);
  });

  test('sort by name uses the app label when there is one', () {
    expect(_ids(studioArrange(items, sort: StudioSort.name)), ['a', 'b', 'c', 'd', 'e']);
    final apps = [_item('x', label: 'Mail'), _item('y', label: 'agenda')];
    expect(_ids(studioArrange(apps, sort: StudioSort.name)), ['y', 'x']);
  });

  test('sort by state: errors, corrected, plain, excluded last; ties keep import order', () {
    expect(_ids(studioArrange(items, sort: StudioSort.state)), ['b', 'a', 'c', 'e', 'd']);
  });

  test('search matches name, label and path, and combines with the filter', () {
    expect(_ids(studioArrange(items, query: '  ZETA ')), ['e']);
    expect(_ids(studioArrange(items, query: 'a', filter: StudioFilter.modified)), ['a']);
    expect(studioArrange(items, query: 'nothing'), isEmpty);
    expect(studioArrange([], sort: StudioSort.state), isEmpty);
  });

  test('duplicates: the first item with a fingerprint is kept, the later ones point to it', () {
    final d = studioDuplicates([const MapEntry('a', '5:1'), const MapEntry('b', '5:1'), const MapEntry('c', '7:2'), const MapEntry('d', '5:1')]);
    expect(d, {'b': 'a', 'd': 'a'});
    expect(studioDuplicates([]), isEmpty);
  });

  test('the hash is 32-bit FNV-1a and tells identical bytes apart', () {
    expect(studioHash(Uint8List.fromList([97])), 0xe40c292c);
    expect(studioHash(Uint8List(0)), 0x811c9dc5);
    expect(studioHash(Uint8List.fromList([1, 2, 3])), studioHash(Uint8List.fromList([1, 2, 3])));
    expect(studioHash(Uint8List.fromList([1, 2, 3])) == studioHash(Uint8List.fromList([1, 2, 4])), isFalse);
  });
}
