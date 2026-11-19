import 'package:flutter_test/flutter_test.dart';
import 'package:icon_formatter/services/pack_source_filter.dart';

void main() {
  // a phone pack as exported: drawables, the human-readable copies in icons/,
  // calendar days and a template image that no appfilter item names
  final rels = [
    'res/drawable-nodpi/com_a.png',
    'res/drawable-nodpi/com_a_2.png',
    'res/drawable-nodpi/calendar_com_cal_1.png',
    'res/drawable-nodpi/calendar_com_cal_2.png',
    'res/drawable-nodpi/com_cal.png',
    'res/drawable-nodpi/app_icon.png',
    'icons/Chilly (com.a).png',
    'icons/Cal (com.cal).png',
    'res/drawable-nodpi/com_b.png',
  ];
  final comp = {
    'com_a': ('com.a', 'com.a.Main'),
    'com_a_2': ('com.a', 'com.a.Main'),
    'com_cal': ('com.cal', 'com.cal.Main'),
    'com_b': ('com.b', ''),
  };

  test('a plain folder keeps every image', () {
    expect(packIconIndexes(rels, const {}), [for (var i = 0; i < rels.length; i++) i]);
  });

  test('a pack keeps one icon per app, no copies, no calendar days', () {
    final keep = packIconIndexes(rels, comp);
    expect([for (final i in keep) rels[i]], [
      'res/drawable-nodpi/com_a.png',
      'res/drawable-nodpi/com_cal.png',
      'res/drawable-nodpi/com_b.png',
    ]);
  });

  test('stems and separators are normalised', () {
    final keep = packIconIndexes(['res\\drawable-nodpi\\COM_B.PNG'], {'com_b': ('com.b', '')});
    expect(keep, [0]);
  });
}
