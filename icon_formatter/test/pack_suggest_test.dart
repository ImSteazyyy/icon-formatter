import 'package:flutter_test/flutter_test.dart';
import 'package:icon_formatter/services/pack_suggest.dart';

CandidateIcon c(
  String id, {
  String label = '',
  String pkg = '',
  String file = '',
  int? colour,
}) => CandidateIcon(
  id: id,
  label: label,
  package: pkg,
  file: file,
  colour: colour,
);

void main() {
  test('no candidates or max 0 returns empty', () {
    expect(
      suggestIcons(
        label: 'Gmail',
        package: 'com.google.android.gm',
        candidates: const [],
      ),
      isEmpty,
    );
    expect(
      suggestIcons(
        label: 'Gmail',
        package: '',
        candidates: [c('a', label: 'Gmail')],
        max: 0,
      ),
      isEmpty,
    );
  });

  test('exact label ranks first with score 1', () {
    final r = suggestIcons(
      label: 'Gmail',
      package: '',
      candidates: [
        c('a', label: 'Maps'),
        c('b', label: 'Gmail'),
      ],
    );
    expect(r.first.candidate.id, 'b');
    expect(r.first.score, closeTo(1, 1e-9));
  });

  test('case, punctuation and unicode are normalised', () {
    final r = suggestIcons(
      label: 'Café-Maps!',
      package: '',
      candidates: [
        c('a', label: 'cafe maps'),
        c('b', label: 'Nothing'),
      ],
    );
    expect(r.first.candidate.id, 'a');
    expect(r.first.score, greaterThan(0.5));
  });

  test('same package beats a similar name from another package', () {
    final r = suggestIcons(
      label: 'Docs',
      package: 'com.google.android.apps.docs',
      candidates: [
        c('other', label: 'Docs', pkg: 'com.foo.docx'),
        c('same', label: 'Docs', pkg: 'com.google.android.apps.docs'),
      ],
    );
    expect(r.first.candidate.id, 'same');
  });

  test('file name stem is used when label is empty', () {
    final r = suggestIcons(
      label: 'Telegram',
      package: '',
      candidates: [
        c('a', file: 'C:/icons/telegram.png'),
        c('b', file: 'x/zz.png'),
      ],
    );
    expect(r.first.candidate.id, 'a');
    expect(r.first.score, closeTo(1, 1e-9));
  });

  test('empty label and package but colour only ranks by colour', () {
    final r = suggestIcons(
      label: '',
      package: '',
      colour: 0xFFFF0000,
      candidates: [c('blue', colour: 0xFF0000FF), c('red', colour: 0xFFFF0000)],
    );
    expect(r.map((s) => s.candidate.id), ['red', 'blue']);
    expect(r.first.score, closeTo(1, 1e-9));
    expect(r.last.score, lessThan(0.25));
  });

  test('no information at all gives no suggestion', () {
    expect(
      suggestIcons(
        label: '',
        package: '',
        candidates: [c('a', label: 'x')],
      ),
      isEmpty,
    );
  });

  test('colour breaks ties between equal names', () {
    final r = suggestIcons(
      label: 'Chat',
      package: '',
      colour: 0xFF00AA00,
      candidates: [
        c('far', label: 'Chat', colour: 0xFF0000FF),
        c('near', label: 'Chat', colour: 0xFF00AA00),
      ],
    );
    expect(r.first.candidate.id, 'near');
    expect(r.first.score, greaterThan(r.last.score));
  });

  test('colour is ignored unless both sides have one', () {
    final withColour = suggestIcons(
      label: 'Chat',
      package: '',
      colour: 0xFF000000,
      candidates: [c('a', label: 'Chat')],
    );
    final withoutColour = suggestIcons(
      label: 'Chat',
      package: '',
      candidates: [c('a', label: 'Chat')],
    );
    expect(withColour.single.score, closeTo(withoutColour.single.score, 1e-9));
  });

  test('max limits the result and ties are ordered by id', () {
    final r = suggestIcons(
      label: 'Notes',
      package: '',
      max: 2,
      candidates: [
        c('c', label: 'Notes'),
        c('a', label: 'Notes'),
        c('b', label: 'Notes'),
      ],
    );
    expect(r.map((s) => s.candidate.id), ['a', 'b']);
  });

  test('zero-score candidates are dropped', () {
    final r = suggestIcons(
      label: 'Abc',
      package: '',
      candidates: [c('x', label: 'Qqq')],
    );
    expect(r, isEmpty);
  });

  test('scores stay in 0..1', () {
    final r = suggestIcons(
      label: 'Map',
      package: 'com.map.app',
      colour: 0xFFFFFFFF,
      max: 10,
      candidates: [
        c('a', label: 'Map', pkg: 'com.map.app', colour: 0xFFFFFFFF),
        c('b', label: 'Mapp', pkg: 'com.map', colour: 0xFF000000),
      ],
    );
    for (final s in r) {
      expect(s.score, inInclusiveRange(0, 1));
    }
  });

  test('handles very long names without problems', () {
    final long = 'x' * 5000;
    final r = suggestIcons(
      label: long,
      package: '',
      candidates: [
        c('a', label: long),
        c('b', label: 'short'),
      ],
    );
    expect(r.first.candidate.id, 'a');
    expect(r.first.score, closeTo(1, 1e-9));
  });

  test('large candidate list is fast enough', () {
    final list = [
      for (var i = 0; i < 5000; i++)
        c('id$i', label: 'App number $i', pkg: 'com.app$i'),
    ];
    final sw = Stopwatch()..start();
    final r = suggestIcons(
      label: 'App number 4321',
      package: 'com.app4321',
      candidates: list,
    );
    sw.stop();
    expect(r.first.candidate.id, 'id4321');
    expect(sw.elapsed, lessThan(const Duration(seconds: 2)));
  });
}
