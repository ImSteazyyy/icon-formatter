import 'package:flutter_test/flutter_test.dart';
import 'package:icon_formatter/app/models.dart';

const _day = 24 * 60 * 60 * 1000;
const _now = 1000000000000;

void main() {
  bool due({int changes = 40, int lastBackupMs = 0, int snoozeUntilMs = 0}) =>
      backupReminderDue(changes: changes, lastBackupMs: lastBackupMs, snoozeUntilMs: snoozeUntilMs, nowMs: _now);

  test('below the threshold there is no reminder', () {
    expect(due(changes: kBackupReminderChanges - 1), isFalse);
  });

  test('never backed up and enough changes: reminder', () {
    expect(due(), isTrue);
  });

  test('a recent backup suppresses the reminder', () {
    expect(due(lastBackupMs: _now - 5 * _day), isFalse);
  });

  test('a backup older than 30 days brings it back', () {
    expect(due(lastBackupMs: _now - 31 * _day), isTrue);
  });

  test('a snooze hides the reminder until it ends', () {
    expect(due(snoozeUntilMs: _now + _day), isFalse);
    expect(due(snoozeUntilMs: _now - 1), isTrue);
  });
}
