import 'package:flutter_test/flutter_test.dart';
import 'package:icon_formatter/services/pack_naming.dart';

final _d = DateTime(2026, 11, 19);

void main() {
  test('builds the standard name', () {
    expect(
      exportFileName(packName: 'MioPack', version: '1.2', date: _d),
      'MioPack_1.2_2026-11-19.zip',
    );
  });

  test('spaces become underscores', () {
    expect(
      exportFileName(packName: 'Mio  Pack', version: '1.2', date: _d),
      'Mio_Pack_1.2_2026-11-19.zip',
    );
  });

  test('forbidden characters and control characters are replaced', () {
    expect(
      exportFileName(packName: 'a<b>:c"d/e\\f|g?h*i', version: '1.0', date: _d),
      'a_b_c_d_e_f_g_h_i_1.0_2026-11-19.zip',
    );
    expect(
      exportFileName(packName: 'x\x01y\x1f', version: '1.0', date: _d),
      'x_y_1.0_2026-11-19.zip',
    );
  });

  test('forbidden characters in the version are replaced too', () {
    expect(
      exportFileName(packName: 'P', version: '1/2', date: _d),
      'P_1_2_2026-11-19.zip',
    );
  });

  test('empty or blank pack name falls back to Pack', () {
    expect(
      exportFileName(packName: '', version: '1.2', date: _d),
      'Pack_1.2_2026-11-19.zip',
    );
    expect(
      exportFileName(packName: '   ', version: '1.2', date: _d),
      'Pack_1.2_2026-11-19.zip',
    );
    expect(
      exportFileName(packName: '...', version: '1.2', date: _d),
      'Pack_1.2_2026-11-19.zip',
    );
  });

  test('empty version is left out', () {
    expect(
      exportFileName(packName: 'P', version: '', date: _d),
      'P_2026-11-19.zip',
    );
  });

  test('extension is optional and leading dots are removed', () {
    expect(
      exportFileName(packName: 'P', version: '1', date: _d, ext: '.zip'),
      'P_1_2026-11-19.zip',
    );
    expect(
      exportFileName(packName: 'P', version: '1', date: _d, ext: ''),
      'P_1_2026-11-19',
    );
    expect(
      exportFileName(packName: 'P', version: '1', date: _d, ext: 'apk'),
      'P_1_2026-11-19.apk',
    );
  });

  test('date is zero padded', () {
    expect(
      exportFileName(packName: 'P', version: '1', date: DateTime(2026, 1, 5)),
      'P_1_2026-01-05.zip',
    );
  });

  test('unicode names are kept', () {
    expect(
      exportFileName(packName: 'Pâck ñ', version: '1', date: _d),
      'Pâck_ñ_1_2026-11-19.zip',
    );
  });

  test(
    'long pack name is capped at 80 characters and keeps version and date',
    () {
      final name = exportFileName(
        packName: 'a' * 200,
        version: '1.2',
        date: _d,
      );
      expect(name.length, 80);
      expect(name.endsWith('_1.2_2026-11-19.zip'), isTrue);
    },
  );

  test('very long unicode names are cut by characters, not code units', () {
    final name = exportFileName(packName: '😀' * 200, version: '1', date: _d);
    expect(name.runes.length, lessThanOrEqualTo(80));
    expect(name.endsWith('_1_2026-11-19.zip'), isTrue);
  });

  test('huge version and extension still give a bounded, non-empty name', () {
    final name = exportFileName(
      packName: 'P',
      version: 'v' * 200,
      date: _d,
      ext: 'x' * 30,
    );
    expect(name.isNotEmpty, isTrue);
    expect(name.runes.length, lessThanOrEqualTo(80));
    expect(name.endsWith('.xxxxxxxxxx'), isTrue);
  });
}
