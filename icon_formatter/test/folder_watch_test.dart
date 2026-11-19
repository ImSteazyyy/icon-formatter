import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:icon_formatter/services/folder_watch.dart';

void main() {
  late Directory dir;

  setUp(() => dir = Directory.systemTemp.createTempSync('folder_watch_test'));
  tearDown(() => dir.deleteSync(recursive: true));

  Future<void> waitUntil(bool Function() ok) async {
    for (var i = 0; i < 100 && !ok(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
  }

  FolderWatch fast() => FolderWatch(
    interval: const Duration(milliseconds: 30),
    settle: Duration.zero,
  );

  test('reports only images that appear after start', () async {
    File('${dir.path}/old.png').writeAsBytesSync([1]);
    final w = fast();
    final got = <String>[];
    w.start(dir.path, got.addAll);
    await Future<void>.delayed(const Duration(milliseconds: 100));

    File('${dir.path}/new.jpg').writeAsBytesSync([2]);
    File('${dir.path}/notes.txt').writeAsStringSync('x');
    await waitUntil(() => got.isNotEmpty);
    w.stop();

    expect(got.length, 1);
    expect(got.single.endsWith('new.jpg'), isTrue);
  });

  test('reports existing files when asked', () async {
    File('${dir.path}/old.webp').writeAsBytesSync([1]);
    final w = fast();
    final got = <String>[];
    w.start(dir.path, got.addAll, reportExisting: true);
    await waitUntil(() => got.isNotEmpty);
    w.stop();

    expect(got.single.endsWith('old.webp'), isTrue);
  });

  test('a changed file is reported again', () async {
    final f = File('${dir.path}/a.png')..writeAsBytesSync([1]);
    final w = fast();
    final got = <String>[];
    w.start(dir.path, got.addAll);
    await Future<void>.delayed(const Duration(milliseconds: 100));

    f.writeAsBytesSync([1, 2, 3]);
    await waitUntil(() => got.isNotEmpty);
    w.stop();

    expect(got.length, 1);
  });

  test('stop cancels the scans', () async {
    final w = fast();
    final got = <String>[];
    w.start(dir.path, got.addAll);
    expect(w.isRunning, isTrue);
    w.stop();
    expect(w.isRunning, isFalse);

    File('${dir.path}/later.png').writeAsBytesSync([3]);
    await Future<void>.delayed(const Duration(milliseconds: 150));
    expect(got, isEmpty);
  });

  test('a missing folder is ignored', () async {
    final w = fast();
    final got = <String>[];
    w.start('${dir.path}/does_not_exist', got.addAll);
    await Future<void>.delayed(const Duration(milliseconds: 100));
    w.stop();

    expect(got, isEmpty);
  });
}
