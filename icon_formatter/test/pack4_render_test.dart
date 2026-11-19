import 'package:flutter_test/flutter_test.dart';
import 'package:icon_formatter/services/pack_source_filter.dart';

void main() {
  test('a bulk render skips pack icons, Studio icons and finished rows', () {
    expect(renderOnBulk(originalId: 'app:com.a', hasStudioIcon: false, rowFinished: false), isTrue);
    // icons of an opened or adopted pack (Android "pk", Windows "pko")
    expect(renderOnBulk(originalId: 'pk123_0', hasStudioIcon: false, rowFinished: false), isFalse);
    expect(renderOnBulk(originalId: 'pko123_0', hasStudioIcon: false, rowFinished: false), isFalse);
    // already made in the Studio
    expect(renderOnBulk(originalId: 'app:com.a', hasStudioIcon: true, rowFinished: false), isFalse);
    // a row whose icon came from a pack
    expect(renderOnBulk(originalId: 'app:com.a', hasStudioIcon: false, rowFinished: true), isFalse);
  });
}
