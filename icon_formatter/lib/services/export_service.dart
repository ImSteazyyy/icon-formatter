import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';

import '../app/state.dart';
import '../app/storage.dart';
import '../src/rust/api/engine.dart';
import 'extra_contact_sheet.dart';
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

  /// Saves a single PNG.
  static Future<ExportResult?> saveSingle(Uint8List png, String fileName) async {
    final saved = await FilePicker.platform.saveFile(dialogTitle: S.salvaPng, fileName: fileName, bytes: png);
    return saved == null ? null : ExportResult(S.pngSalvato, location: saved);
  }

  /// Android Share Sheet.
  static Future<void> share(List<String> files, {String? text}) async {
    await SharePlus.instance.share(ShareParams(files: files.map((f) => XFile(f)).toList(), text: text));
  }

  /// Zips a folder into the cache and shares it.
  static Future<void> shareDirAsZip(String dir, String name) async {
    final z = p.join(await AppPaths.I.workDir('share'), '$name.zip');
    await zipDirectory(dir: dir, zipPath: z);
    await share([z]);
  }

  /// Contact sheet PNGs of the generated icons (names under each, up to 400
  /// icons, 96 per sheet). Writes to the cache and returns the first sheet's
  /// path, or null when there is nothing to draw.
  static Future<String?> exportContactSheet(List<({String name, Uint8List png})> icons) async {
    if (icons.isEmpty) return null;
    final dir = await AppPaths.I.workDir('sheet');
    final pages = contactSheetPages(icons.length);
    String? first;
    var start = 0;
    for (var i = 0; i < pages.length; i++) {
      final png = await renderContactSheet(icons.sublist(start, start + pages[i]));
      start += pages[i];
      if (png == null) continue;
      final path = p.join(dir, 'contact_sheet_${i + 1}.png');
      await File(path).writeAsBytes(png);
      first ??= path;
    }
    return first;
  }
}
