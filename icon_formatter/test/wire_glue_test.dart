import 'package:flutter_test/flutter_test.dart';
import 'package:icon_formatter/app/state.dart';
import 'package:icon_formatter/l10n/strings.dart';

void main() {
  test('update check is on by default and the watched folder is off', () {
    final st = AppState.I;
    expect(st.checkUpdates, isTrue);
    expect(st.watchDir, isNull);
    expect(st.newRelease.value, isNull);
  });

  test('the ignored-apps label counts the apps', () {
    expect(S.wireAppIgnorate, isNotEmpty);
    expect(S.wireAppIgnorateN(3), contains('3'));
  });
}
