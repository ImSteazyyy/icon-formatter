import 'package:flutter_test/flutter_test.dart';
import 'package:icon_formatter/services/pack_conflicts.dart';

PackEntryInfo e(
  String component,
  String pkg,
  String drawable, {
  String label = '',
}) => PackEntryInfo(
  component: component,
  package: pkg,
  label: label,
  drawable: drawable,
);

void main() {
  test('empty input has no conflicts', () {
    expect(findConflicts(const []), isEmpty);
  });

  test('clean pack has no conflicts', () {
    final r = findConflicts([
      e('a/.A', 'com.a', 'da'),
      e('b/.B', 'com.b', 'db'),
    ]);
    expect(r, isEmpty);
  });

  test('shared drawable across one app family is info', () {
    final r = findConflicts([
      e('com.google.android.gm/.Main', 'com.google.android.gm', 'mail'),
      e(
        'com.google.android.apps.docs/.Main',
        'com.google.android.apps.docs',
        'mail',
      ),
    ]);
    expect(r, hasLength(1));
    expect(r.single.kind, ConflictKind.sharedDrawable);
    expect(r.single.severity, ConflictSeverity.info);
    expect(r.single.drawable, 'mail');
    expect(r.single.packages, [
      'com.google.android.apps.docs',
      'com.google.android.gm',
    ]);
    expect(r.single.entries, [0, 1]);
  });

  test('shared drawable across unrelated apps is warning', () {
    final r = findConflicts([
      e('x/.A', 'com.whatsapp', 'chat'),
      e('y/.B', 'com.facebook.orca', 'chat'),
    ]);
    expect(r.single.severity, ConflictSeverity.warning);
    expect(r.single.kind, ConflictKind.sharedDrawable);
  });

  test('same package with same drawable twice is not a conflict', () {
    final r = findConflicts([
      e('com.a/.One', 'com.a', 'x'),
      e('com.a/.Two', 'com.a', 'x'),
    ]);
    expect(r, isEmpty);
  });

  test('duplicate component with different drawables', () {
    final r = findConflicts([
      e('com.a/.Main', 'com.a', 'one'),
      e('com.a/.Main', 'com.a', 'two'),
      e('com.a/.Main', 'com.a', 'one'),
    ]);
    final dup = r
        .where((c) => c.kind == ConflictKind.duplicateComponent)
        .toList();
    expect(dup, hasLength(1));
    expect(dup.single.component, 'com.a/.Main');
    expect(dup.single.drawables, ['one', 'two']);
    expect(dup.single.entries, [0, 1, 2]);
    expect(dup.single.severity, ConflictSeverity.warning);
  });

  test('duplicate component with the same drawable is not reported', () {
    final r = findConflicts([
      e('com.a/.Main', 'com.a', 'one'),
      e('com.a/.Main', 'com.a', 'one'),
    ]);
    expect(r.where((c) => c.kind == ConflictKind.duplicateComponent), isEmpty);
  });

  test('empty drawable and empty package are reported per entry', () {
    final r = findConflicts([
      e('a/.A', 'com.a', ''),
      e('b/.B', '', 'db'),
      e('c/.C', '', ''),
    ]);
    final empties = r
        .where((c) => c.kind == ConflictKind.emptyDrawable)
        .toList();
    final pkgs = r.where((c) => c.kind == ConflictKind.emptyPackage).toList();
    expect(empties.map((c) => c.entries.single), [0, 2]);
    expect(pkgs.map((c) => c.entries.single), [1, 2]);
    expect(empties.first.component, 'a/.A');
  });

  test('entry with empty package does not count for shared drawable', () {
    final r = findConflicts([e('a/.A', '', 'x'), e('b/.B', 'com.b', 'x')]);
    expect(r.where((c) => c.kind == ConflictKind.sharedDrawable), isEmpty);
    expect(r.where((c) => c.kind == ConflictKind.emptyPackage), hasLength(1));
  });

  test('empty component is not used for duplicate detection', () {
    final r = findConflicts([e('', 'com.a', 'x'), e('', 'com.a', 'y')]);
    expect(r.where((c) => c.kind == ConflictKind.duplicateComponent), isEmpty);
  });

  test('unicode names are compared as given', () {
    final r = findConflicts([
      e('ü/.A', 'com.ü', 'icona'),
      e('ü/.A', 'com.ü', 'icona2'),
    ]);
    expect(r.single.kind, ConflictKind.duplicateComponent);
    expect(r.single.component, 'ü/.A');
  });

  test('output order is deterministic: by kind, then key', () {
    final input = [
      e('z/.Z', 'com.z', ''),
      e('m/.M', 'com.m', 'd1'),
      e('m/.M', 'com.m', 'd2'),
      e('a/.A', 'com.p1', 'shared'),
      e('b/.B', 'com.p2', 'shared'),
      e('', '', 'nothing'),
    ];
    String describe(PackConflict c) =>
        '${c.kind.name} ${c.drawable}|${c.component}|${c.entries}';
    final expected = [
      'sharedDrawable shared||[3, 4]',
      'duplicateComponent |m/.M|[1, 2]',
      'emptyDrawable |z/.Z|[0]',
      'emptyPackage ||[5]',
    ];
    expect(findConflicts(input).map(describe).toList(), expected);
  });

  test('large input stays fast and correct', () {
    final input = [
      for (var i = 0; i < 5000; i++) e('c$i/.A', 'com.app$i', 'd$i'),
    ];
    input.add(e('c0/.A', 'com.app0', 'other'));
    final r = findConflicts(input);
    expect(
      r
          .where((c) => c.kind == ConflictKind.duplicateComponent)
          .single
          .component,
      'c0/.A',
    );
    expect(r, hasLength(1));
  });
}
