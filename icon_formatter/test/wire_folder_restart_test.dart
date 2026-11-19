import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:icon_formatter/services/folder_watch.dart';

void main() {
  late Directory dir;

  setUp(() => dir = Directory.systemTemp.createTempSync('wire_folder_test'));
  tearDown(() => dir.deleteSync(recursive: true));

  FolderWatch fast() => FolderWatch(
    interval: const Duration(milliseconds: 30),
    settle: Duration.zero,
  );

  test('after a stop, a restart on the same folder reports only new images', () async {
    File('${dir.path}/a.png').writeAsBytesSync([1]);
    final w = fast();
    final got = <String>[];
    w.start(dir.path, got.addAll);
    await Future<void>.delayed(const Duration(milliseconds: 100));
    w.stop();

    // added while the watch was stopped (app paused or tab hidden)
    File('${dir.path}/b.png').writeAsBytesSync([2]);
    w.start(dir.path, got.addAll);
    await Future<void>.delayed(const Duration(milliseconds: 150));
    w.stop();

    expect(got.length, 1);
    expect(got.single.endsWith('b.png'), isTrue);
  });

  test('a restart on another folder seeds it again and reports nothing old', () async {
    File('${dir.path}/a.png').writeAsBytesSync([1]);
    final other = Directory.systemTemp.createTempSync('wire_folder_other');
    addTearDown(() => other.deleteSync(recursive: true));
    final w = fast();
    final got = <String>[];
    w.start(dir.path, got.addAll);
    await Future<void>.delayed(const Duration(milliseconds: 100));
    w.stop();

    File('${other.path}/c.png').writeAsBytesSync([3]);
    w.start(other.path, got.addAll);
    await Future<void>.delayed(const Duration(milliseconds: 150));
    w.stop();

    expect(got, isEmpty);
  });
}
