import 'dart:async';
import 'dart:io';

/// Watches a folder for new image files. A timer scans it only between
/// [start] and [stop]; nothing runs while stopped.
class FolderWatch {
  FolderWatch({
    this.interval = const Duration(seconds: 20),
    this.cap = 2000,
    this.settle = const Duration(seconds: 2),
  });

  final Duration interval;

  /// Most directory entries read per scan.
  final int cap;

  /// Files modified this recently may still be written: they are picked up on a later scan.
  final Duration settle;

  Timer? _timer;
  String? _path;
  void Function(List<String> paths)? _onNew;
  bool _reportExisting = false;
  bool _seeding = false;
  bool _busy = false;
  int _gen = 0;
  Map<String, String> _seen = {};

  /// Folder the remembered [_seen] belongs to; kept across [stop].
  String? _seenPath;

  bool get isRunning => _timer != null;

  /// Starts watching [path]; [onNew] gets the paths of new image files (png, jpg, jpeg, webp).
  /// Files already in the folder are only remembered, unless [reportExisting] is true.
  void start(
    String path,
    void Function(List<String> paths) onNew, {
    bool reportExisting = false,
  }) {
    stop();
    // same folder as before a stop: only files new since then are reported
    if (_seenPath != path) {
      _seen = {};
      _seenPath = null;
    }
    _path = path;
    _onNew = onNew;
    _reportExisting = reportExisting;
    _seeding = !reportExisting && _seenPath == null;
    _timer = Timer.periodic(interval, (_) => _scan());
    unawaited(_scan());
  }

  /// Cancels the timer and forgets the folder (not the files seen in it).
  /// Safe to call when not started.
  void stop() {
    _timer?.cancel();
    _timer = null;
    _path = null;
    _onNew = null;
    _busy = false;
    _gen++;
  }

  Future<void> _scan() async {
    final path = _path;
    if (_busy || path == null) return;
    _busy = true;
    final gen = _gen;
    final seen = <String, String>{};
    final found = <String>[];
    try {
      var n = 0;
      final now = DateTime.now();
      await for (final e in Directory(path).list(followLinks: false)) {
        if (++n > cap) break;
        if (e is! File || !_isImage(e.path)) continue;
        final st = await e.stat();
        if (st.type != FileSystemEntityType.file) continue;
        if (now.difference(st.modified) < settle) continue;
        final stamp = '${st.size}:${st.modified.millisecondsSinceEpoch}';
        seen[e.path] = stamp;
        if (_seen[e.path] != stamp) found.add(e.path);
      }
      if (gen != _gen) return;
      _seen = seen;
      _seenPath = path;
      if (_seeding) {
        _seeding = false;
        if (!_reportExisting) return;
      }
      final cb = _onNew;
      if (found.isNotEmpty && cb != null) cb(found);
    } catch (_) {
      // unreadable folder or a callback error: try again on the next scan
    } finally {
      if (gen == _gen) _busy = false;
    }
  }

  static bool _isImage(String p) {
    final l = p.toLowerCase();
    return l.endsWith('.png') ||
        l.endsWith('.jpg') ||
        l.endsWith('.jpeg') ||
        l.endsWith('.webp');
  }
}
