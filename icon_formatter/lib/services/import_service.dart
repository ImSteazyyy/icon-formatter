import 'dart:io';

import 'package:file_picker/file_picker.dart';

import '../app/storage.dart';
import '../src/rust/api/engine.dart';
import 'platform_service.dart';

/// Picks images, folders or ZIPs and expands them into a flat image list.
/// Sources are only read; ZIPs/SAF folders are copied into the cache.
class ImportService {
  static const exts = ['png', 'jpg', 'jpeg', 'webp'];

  static Future<List<PackImage>> pickFiles() async {
    final r = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      type: FileType.custom,
      allowedExtensions: [...exts, 'zip'],
      dialogTitle: 'Importa icone (PNG, JPG, WEBP o ZIP)',
    );
    if (r == null) return [];
    final paths = r.files.map((f) => f.path).whereType<String>().toList();
    return expand(paths);
  }

  static Future<List<PackImage>> pickZip() async {
    final r = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['zip'], dialogTitle: 'Importa ZIP');
    final path = r?.files.single.path;
    if (path == null) return [];
    return expand([path]);
  }

  /// Folder import: native dialog on Windows, SAF tree copy on Android.
  static Future<String?> pickFolder() async {
    if (Platform.isAndroid) {
      final tree = await PlatformService.pickTree();
      if (tree == null) return null;
      final dir = await AppPaths.I.workDir('saf');
      await PlatformService.copyTreeToDir(tree, dir);
      return dir;
    }
    return FilePicker.platform.getDirectoryPath(dialogTitle: 'Importa cartella di icone');
  }

  static Future<List<PackImage>> pickFolderImages() async {
    final dir = await pickFolder();
    if (dir == null) return [];
    return expand([dir]);
  }

  static Future<List<PackImage>> expand(List<String> paths) async {
    if (paths.isEmpty) return [];
    final work = await AppPaths.I.workDir('import');
    return collectImages(inputs: paths, workDir: work);
  }
}
