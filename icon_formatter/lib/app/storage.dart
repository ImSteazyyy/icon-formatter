import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../l10n/strings.dart';

/// App folders. Everything the app writes lives here or in a destination the
/// user chose explicitly; source files are never modified.
class AppPaths {
  AppPaths._(this.root, this.cache);

  final Directory root;
  final Directory cache;

  static late AppPaths I;

  static Future<AppPaths> init() async {
    final support = await getApplicationSupportDirectory();
    final tmp = await getTemporaryDirectory();
    final root = Directory(p.join(support.path, 'IconFormatter'));
    final cache = Directory(p.join(tmp.path, 'IconFormatterCache'));
    await root.create(recursive: true);
    await cache.create(recursive: true);
    I = AppPaths._(root, cache);
    await Directory(I.bases).create(recursive: true);
    await Directory(I.outputs).create(recursive: true);
    await Directory(I.models).create(recursive: true);
    return I;
  }

  String get bases => p.join(root.path, 'bases');
  String get outputs => p.join(root.path, 'outputs');

  /// Downloaded local AI models.
  String get models => p.join(root.path, 'models');
  String get stateFile => p.join(root.path, 'state.json');

  /// Fresh unique work folder in the cache.
  Future<String> workDir(String tag) async {
    final d = Directory(p.join(cache.path, '${tag}_${DateTime.now().microsecondsSinceEpoch}'));
    await d.create(recursive: true);
    return d.path;
  }

  /// Fresh output session folder.
  Future<String> outputSession(String tag) async {
    final d = Directory(p.join(outputs, '${tag}_${DateTime.now().millisecondsSinceEpoch}'));
    await d.create(recursive: true);
    return d.path;
  }

  Future<int> cacheSize() async => _size(cache);
  Future<int> outputsSize() async => _size(Directory(outputs));

  Future<int> _size(Directory d) async {
    var total = 0;
    if (!await d.exists()) return 0;
    await for (final e in d.list(recursive: true, followLinks: false)) {
      if (e is File) total += await e.length();
    }
    return total;
  }

  Future<void> clearCache() async {
    if (await cache.exists()) {
      await for (final e in cache.list()) {
        await e.delete(recursive: true);
      }
    }
  }

  Future<void> clearOutputs() async {
    final d = Directory(outputs);
    if (await d.exists()) {
      await for (final e in d.list()) {
        await e.delete(recursive: true);
      }
    }
  }
}

/// Returns a path that does not exist yet by appending " (n)".
String uniquePath(String path) {
  if (!File(path).existsSync() && !Directory(path).existsSync()) return path;
  final dir = p.dirname(path);
  final ext = p.extension(path);
  final stem = p.basenameWithoutExtension(path);
  for (var i = 1;; i++) {
    final c = p.join(dir, '$stem ($i)$ext');
    if (!File(c).existsSync() && !Directory(c).existsSync()) return c;
  }
}

String formatBytes(int b) {
  if (b < 1024) return '$b B';
  if (b < 1024 * 1024) return S.kb((b / 1024).toStringAsFixed(1));
  return S.mb((b / 1024 / 1024).toStringAsFixed(1));
}
