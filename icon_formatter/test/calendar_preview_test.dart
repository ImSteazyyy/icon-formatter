import 'package:flutter_test/flutter_test.dart';
import 'package:icon_formatter/services/calendar_preview.dart';

void main() {
  test('crosses the month end', () {
    expect(calendarPreviewDays(today: DateTime(2026, 1, 28)), [28, 29, 30, 31, 1, 2, 3]);
  });

  test('leap year February', () {
    expect(calendarPreviewDays(today: DateTime(2024, 2, 28), count: 3), [28, 29, 1]);
  });

  test('crosses the year end', () {
    expect(calendarPreviewDays(today: DateTime(2026, 12, 30), count: 4), [30, 31, 1, 2]);
  });
}
