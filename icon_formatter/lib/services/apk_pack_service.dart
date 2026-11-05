import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../app/state.dart';
import '../app/storage.dart';
import '../l10n/strings.dart';
import '../src/rust/api/engine.dart';

/// Builds an installable icon pack APK (Windows only) from a pack folder
/// produced by `buildIconPack`, using the bundled Android project template
/// (assets/iconpack_template.zip) and the local Android SDK + JDK.
class ApkPackService {
  /// Android SDK folder, or null when not found.
  static String? sdkDir() {
    final env = Platform.environment;
    final c = <String?>[
      env['ANDROID_HOME'],
      env['ANDROID_SDK_ROOT'],
      if (env['LOCALAPPDATA'] != null) p.join(env['LOCALAPPDATA']!, 'Android', 'Sdk'),
    ];
    for (final d in c) {
      if (d != null && d.isNotEmpty && Directory(p.join(d, 'platforms')).existsSync()) return d;
    }
    return null;
  }

  static bool get javaAvailable {
    final jh = Platform.environment['JAVA_HOME'];
    if (jh != null && File(p.join(jh, 'bin', 'java.exe')).existsSync()) return true;
    try {
      return Process.runSync('where', ['java'], runInShell: true).exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  static bool get available => Platform.isWindows && sdkDir() != null && javaAvailable;

  /// Returns the built APK path. [log] receives progress lines.
  static Future<String> build({required String packDir, required String name, void Function(String)? log}) async {
    final sdk = sdkDir();
    if (sdk == null) throw Exception(S.apkSdkMancante);
    final work = await AppPaths.I.workDir('apkpack');
    final zip = p.join(work, 'template.zip');
    final data = await rootBundle.load('assets/iconpack_template.zip');
    await File(zip).writeAsBytes(data.buffer.asUint8List());
    final info = await openPack(input: zip, workDir: work);
    final root = info.root;
    final main = p.join(root, 'app', 'src', 'main');

    // pack content: res/* and assets/* plus mapping.json for the in-app list
    Future<void> copyTree(String from, String to) async {
      final src = Directory(from);
      if (!await src.exists()) return;
      await for (final e in src.list(recursive: true)) {
        if (e is File) {
          final dst = File(p.join(to, p.relative(e.path, from: from)));
          await dst.parent.create(recursive: true);
          await e.copy(dst.path);
        }
      }
    }

    await copyTree(p.join(packDir, 'res'), p.join(main, 'res'));
    await copyTree(p.join(packDir, 'assets'), p.join(main, 'assets'));
    final mapping = File(p.join(packDir, 'mapping.json'));
    if (await mapping.exists()) await mapping.copy(p.join(main, 'assets', 'mapping.json'));
    await File(p.join(root, 'local.properties')).writeAsString('sdk.dir=${sdk.replaceAll('\\', '/')}\n');

    // one pack app: every build updates it (1.0, 1.1, ...), never a new one
    const id = 'com.iconformatter.pack';
    final vFile = File(p.join(AppPaths.I.root.path, 'pack_version.txt'));
    final code = (int.tryParse(await vFile.exists() ? (await vFile.readAsString()).trim() : '') ?? 0) + 1;
    final versionName = '${1 + (code - 1) ~/ 10}.${(code - 1) % 10}';
    final accent = AppState.I.appearance.accent & 0xFFFFFF;
    log?.call(S.apkCompilazione);
    final r = await Process.run(
      p.join(root, 'gradlew.bat'),
      [
        'assembleRelease',
        '--no-daemon',
        '-q',
        '-PpackId=$id',
        '-PpackName=$name',
        '-PpackAccent=#${accent.toRadixString(16).padLeft(6, '0')}',
        '-PpackVersionCode=$code',
        '-PpackVersionName=$versionName',
      ],
      workingDirectory: root,
      runInShell: true,
    );
    final apk = p.join(root, 'app', 'build', 'outputs', 'apk', 'release', 'app-release.apk');
    if (r.exitCode != 0 || !await File(apk).exists()) {
      final err = '${r.stdout}\n${r.stderr}'.trim();
      throw Exception(S.apkFallita(err.length > 600 ? err.substring(err.length - 600) : err));
    }
    await vFile.writeAsString('$code');
    return apk;
  }
}
