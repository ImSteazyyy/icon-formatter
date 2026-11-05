import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';

import '../app/state.dart';
import '../app/storage.dart';
import '../src/rust/api/engine.dart';
import 'platform_service.dart';
import '../l10n/strings.dart';

class ExportResult {
  ExportResult(this.message, {this.location});

  final String message;
  final String? location;
}

/// Exports never overwrite: existing names get a " (n)" suffix.
class ExportService {
  /// Copies [files] (already rendered PNGs) into a staging folder using the
  /// naming pattern. Returns the staging folder.
  static Future<String> stage(Map<String, String> filesByStem, int size) async {
    final dir = await AppPaths.I.workDir('stage');
    final ex = AppState.I.export;
    for (final e in filesByStem.entries) {
      final dest = uniquePath(p.join(dir, ex.fileName(e.key, size)));
      await File(e.value).copy(dest);
    }
    return dir;
  }

  /// Exports a whole folder (folder or ZIP depending on [zip]).
  static Future<ExportResult?> exportDir(String dir, {required String name, required bool zip}) async {
    if (Platform.isAndroid) {
      if (zip) {
        final z = p.join(await AppPaths.I.workDir('zip'), '$name.zip');
        await zipDirectory(dir: dir, zipPath: z);
        final bytes = await File(z).readAsBytes();
        final saved = await FilePicker.platform.saveFile(dialogTitle: S.salvaZip, fileName: '$name.zip', bytes: bytes);
        if (saved == null) return null;
        return ExportResult(S.zipSalvato, location: saved);
      }
      final tree = await PlatformService.pickTree();
      if (tree == null) return null;
      final n = await PlatformService.writeDirToTree(tree, dir, subfolder: name);
      return ExportResult(S.fileSalvatiNellaCartellaScelta(n));
    }
    // Windows / desktop: native folder dialog
    final target = await FilePicker.platform.getDirectoryPath(
      dialogTitle: S.scegliCartellaDestinazione,
      initialDirectory: AppState.I.export.destination,
    );
    if (target == null) return null;
    AppState.I.update(() => AppState.I.export.destination = target);
    if (zip) {
      final z = uniquePath(p.join(target, '$name.zip'));
      final n = await zipDirectory(dir: dir, zipPath: z);
      return ExportResult(S.zipCreatoFile(n), location: z);
    }
    final out = uniquePath(p.join(target, name));
    final n = await _copyDir(Directory(dir), Directory(out));
    return ExportResult(S.fileEsportati(n), location: out);
  }

  static Future<int> _copyDir(Directory src, Directory dst) async {
    await dst.create(recursive: true);
    var n = 0;
    await for (final e in src.list(recursive: true)) {
      if (e is File) {
        final rel = p.relative(e.path, from: src.path);
        final dest = uniquePath(p.join(dst.path, rel));
        await Directory(p.dirname(dest)).create(recursive: true);
        await e.copy(dest);
        n++;
      }
    }
    return n;
  }

  /// Saves a single PNG.
  static Future<ExportResult?> saveSingle(Uint8List png, String fileName) async {
    if (Platform.isAndroid) {
      final saved = await FilePicker.platform.saveFile(dialogTitle: S.salvaPng, fileName: fileName, bytes: png);
      return saved == null ? null : ExportResult(S.pngSalvato, location: saved);
    }
    final path = await FilePicker.platform.saveFile(
      dialogTitle: S.salvaPng,
      fileName: fileName,
      type: FileType.custom,
      allowedExtensions: ['png'],
      initialDirectory: AppState.I.export.destination,
    );
    if (path == null) return null;
    var target = path.toLowerCase().endsWith('.png') ? path : '$path.png';
    // The OS dialog already asked about replacing an existing file; we still
    // refuse to touch the original sources by writing a new file only.
    await File(target).writeAsBytes(png);
    AppState.I.update(() => AppState.I.export.destination = p.dirname(target));
    return ExportResult(S.pngSalvato, location: target);
  }

  /// Android Share Sheet (also works on Windows where supported).
  static Future<void> share(List<String> files, {String? text}) async {
    await SharePlus.instance.share(ShareParams(files: files.map((f) => XFile(f)).toList(), text: text));
  }

  /// Zips a folder into the cache and shares it.
  static Future<void> shareDirAsZip(String dir, String name) async {
    final z = p.join(await AppPaths.I.workDir('share'), '$name.zip');
    await zipDirectory(dir: dir, zipPath: z);
    await share([z]);
  }
}
