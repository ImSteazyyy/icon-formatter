import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:icon_formatter/services/extra2_auto_backup.dart';

void main() {
  late Directory dir;

  setUp(() => dir = Directory.systemTemp.createTempSync('ifbk_test'));
  tearDown(() => dir.deleteSync(recursive: true));

  test('keeps the last 3 stamped copies and touches nothing else', () async {
    File('${dir.path}/icon-formatter-backup-notes.json').writeAsStringSync('mine');
    File('${dir.path}/other.json').writeAsStringSync('mine');

    for (var i = 0; i < 5; i++) {
      expect(await writeAutoBackup(dir.path, 'backup $i', now: DateTime(2026, 1, 1, 10, i)), isTrue);
    }

    final names = dir.listSync().map((e) => e.uri.pathSegments.last).toSet();
    expect(names, {
      'icon-formatter-backup.json',
      'icon-formatter-backup-notes.json',
      'other.json',
      'icon-formatter-backup-20260101-1002.json',
      'icon-formatter-backup-20260101-1003.json',
      'icon-formatter-backup-20260101-1004.json',
    });
    expect(File('${dir.path}/icon-formatter-backup.json').readAsStringSync(), 'backup 4');
  });

  test('a folder that cannot be written reports false without throwing', () async {
    expect(await folderWritable(dir.path), isTrue);
    expect(await folderWritable('${dir.path}/missing'), isFalse);
    expect(await writeAutoBackup('${dir.path}/missing', 'x'), isFalse);
  });

  test('backupStamp is zero padded', () {
    expect(backupStamp(DateTime(2026, 3, 4, 7, 5)), '20260304-0705');
  });
}
