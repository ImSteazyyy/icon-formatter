import 'package:flutter_test/flutter_test.dart';
import 'package:icon_formatter/services/progress_throttle.dart';

void main() {
  test('first event passes, then one per interval', () {
    final t = ProgressThrottle(const Duration(milliseconds: 250));
    final t0 = DateTime(2026, 1, 1, 12);
    expect(t.allow(t0), isTrue);
    expect(t.allow(t0.add(const Duration(milliseconds: 100))), isFalse);
    expect(t.allow(t0.add(const Duration(milliseconds: 249))), isFalse);
    expect(t.allow(t0.add(const Duration(milliseconds: 250))), isTrue);
  });

  test('5000 events in a burst give about 4 per second, the last one forced', () {
    final t = ProgressThrottle(const Duration(milliseconds: 250));
    final t0 = DateTime(2026, 1, 1);
    var fired = 0;
    for (var i = 0; i < 5000; i++) {
      final now = t0.add(Duration(milliseconds: i * 10)); // 100 events per second
      if (t.allow(now, force: i == 4999)) fired++;
    }
    // 50 seconds of events at 4 per second, plus the forced final one
    expect(fired, inInclusiveRange(199, 202));
  });

  test('reset lets the next event through at once', () {
    final t = ProgressThrottle(const Duration(seconds: 10));
    final t0 = DateTime(2026, 1, 1);
    expect(t.allow(t0), isTrue);
    expect(t.allow(t0.add(const Duration(milliseconds: 1))), isFalse);
    t.reset();
    expect(t.allow(t0.add(const Duration(milliseconds: 2))), isTrue);
  });
}
