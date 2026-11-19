import 'package:flutter_test/flutter_test.dart';
import 'package:icon_formatter/services/pack_source_filter.dart';

void main() {
  final comp = {
    'com_cal': ('com.cal', 'com.cal.Main'),
    'com_a': ('com.a', 'com.a.Main'),
    'ic_9gag': ('9gag', ''),
  };

  test('sanitizeDrawableKey follows the Rust rule', () {
    expect(sanitizeDrawableKey('com.Example'), 'com_example');
    expect(sanitizeDrawableKey('9gag'), 'ic_9gag');
    expect(sanitizeDrawableKey('a..b'), 'a_b');
  });

  test('calendar days of a pack are tied to their app', () {
    final rels = [
      'res/drawable-nodpi/calendar_com_cal_1.png',
      'res/drawable-nodpi/calendar_com_cal_31.png',
      'res/drawable-nodpi/calendar_com_cal_32.png',
      'res/drawable-nodpi/calendar_ic_9gag_4.png',
      'res/drawable-nodpi/calendar_unknown_4.png',
      'icons/calendar_com_cal_2.png',
      'res/drawable-nodpi/com_cal.png',
    ];
    final days = packCalendarDays(rels, comp);
    expect([for (final d in days) (rels[d.index], d.day, d.package)], [
      ('res/drawable-nodpi/calendar_com_cal_1.png', 1, 'com.cal'),
      ('res/drawable-nodpi/calendar_com_cal_31.png', 31, 'com.cal'),
      ('res/drawable-nodpi/calendar_ic_9gag_4.png', 4, '9gag'),
    ]);
    expect(packCalendarDays(rels, const {}), isEmpty);
  });

  test('days group into one entry per app, sorted, one per day', () {
    final days = [
      (pkg: 'com.cal', day: 5, tag: 'b'),
      (pkg: 'com.cal', day: 1, tag: 'a'),
      (pkg: 'com.cal', day: 5, tag: 'dup'),
      (pkg: 'com.other', day: 2, tag: 'c'),
      (pkg: '', day: 3, tag: 'nopkg'),
      (pkg: 'com.cal', day: 40, tag: 'bad'),
    ];
    final g = groupCalendarDays(days, packageOf: (d) => d.pkg, dayOf: (d) => d.day);
    expect(g.keys.toSet(), {'com.cal', 'com.other'});
    expect([for (final d in g['com.cal']!) d.day], [1, 5]);
    expect(g['com.cal']!.last.day, 5);
    expect(g['com.other']!.single.tag, 'c');
  });

  test('saved sources of an old build: keep the real ones only', () {
    final items = [
      (file: 'calendar_com_cal_3.png', package: '', activity: ''),
      (file: 'Chilly (com.a).png', package: '', activity: ''),
      (file: 'app_icon_s.png', package: '', activity: ''),
      (file: 'com_a.png', package: 'com.a', activity: 'com.a.Main'),
      (file: 'com_a_2.png', package: 'com.a', activity: 'com.a.Main'),
      (file: 'photo.png', package: '', activity: ''),
      (file: 'com_b.png', package: 'com.b', activity: ''),
    ];
    expect(savedSourceIndexes(items), [3, 5, 6]);
  });
}
