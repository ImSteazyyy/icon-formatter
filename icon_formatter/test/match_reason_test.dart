import 'package:flutter_test/flutter_test.dart';
import 'package:icon_formatter/l10n/strings.dart';
import 'package:icon_formatter/screens/pack_builder_screen.dart';

void main() {
  test('match reasons from the core are translated', () {
    S.current = stringsFor('en');
    expect(matchReasonText('package · somiglianza 87%'), 'same package · similarity 87%');
    expect(matchReasonText('nome app · somiglianza 5%'), 'same name · similarity 5%');
    expect(matchReasonText('solo somiglianza visiva 64%'), 'visual similarity only 64%');
    expect(matchReasonText('altro'), 'altro');
  });
}
