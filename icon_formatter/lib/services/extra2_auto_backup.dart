import 'dart:io';

import 'package:path/path.dart' as p;

/// Only these names are ever pruned: the timestamped copies this app writes.
final _stampedRe = RegExp(r'^icon-formatter-backup-\d{8}-\d{4}\.json$');

String _two(int n) => n.toString().padLeft(2, '0');

String backupStamp(DateTime t) => '${t.year}${_two(t.month)}${_two(t.day)}-${_two(t.hour)}${_two(t.minute)}';

/// Whether the app can write in [dir] (a probe file is created and removed).
Future<bool> folderWritable(String dir) async {
  try {
    final f = File(p.join(dir, '.icon-formatter-probe'));
    await f.writeAsString('ok');
    await f.delete();
    return true;
  } catch (_) {
    return false;
  }
}

/// Writes the latest backup and a timestamped copy into [dir], keeping the
/// last [keep] copies. Returns false on any failure; never throws.
Future<bool> writeAutoBackup(String dir, String text, {DateTime? now, int keep = 3}) async {
  try {
    await File(p.join(dir, 'icon-formatter-backup.json')).writeAsString(text);
    await File(p.join(dir, 'icon-formatter-backup-${backupStamp(now ?? DateTime.now())}.json')).writeAsString(text);
    final names = <String>[];
    await for (final e in Directory(dir).list()) {
      final n = p.basename(e.path);
      if (_stampedRe.hasMatch(n)) names.add(n);
    }
    names.sort();
    if (names.length > keep) {
      for (final n in names.sublist(0, names.length - keep)) {
        await File(p.join(dir, n)).delete();
      }
    }
    return true;
  } catch (_) {
    return false;
  }
}
