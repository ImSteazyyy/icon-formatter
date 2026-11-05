import '../widgets/common.dart' show ImageStamps;
import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../app/state.dart';
import '../src/rust/api/engine.dart';

/// Wraps the Rust batch stream: progress, results per item, cancellation.
/// The UI stays responsive because all work happens on Rust worker threads.
class BatchController extends ChangeNotifier {
  final Map<String, ItemResult> results = {};
  int done = 0;
  int total = 0;
  int errors = 0;
  bool running = false;
  bool cancelled = false;
  String? fatal;

  /// Label of the current phase (e.g. cloud background removal).
  String? phase;
  CancelToken? _token;
  StreamSubscription<BatchProgress>? _sub;

  Future<void> run(List<BatchItem> items, ProcessSettings settings) async {
    if (running) return;
    final token = CancelToken();
    _token = token;
    for (final i in items) {
      results.remove(i.id);
    }
    done = 0;
    total = items.length;
    errors = 0;
    running = true;
    cancelled = false;
    fatal = null;
    phase = null;
    notifyListeners();
    final completer = Completer<void>();
    var lastNotify = DateTime.now();
    ImageStamps.busy++;
    _sub = runBatch(items: items, settings: settings, threads: AppState.I.threads, cancel: token).listen(
      (ev) {
        results[ev.result.id] = ev.result;
        final out = ev.result.output;
        if (out != null) ImageStamps.bump(out);
        done = ev.done;
        total = ev.total;
        if (!ev.result.ok) errors++;
        // throttle rebuilds: every rebuild repaints the grid under the glass
        // bars (blur), so on phones a few refreshes per second are enough
        final now = DateTime.now();
        if (now.difference(lastNotify).inMilliseconds > (Platform.isAndroid ? 250 : 80) || ev.done == ev.total) {
          lastNotify = now;
          notifyListeners();
        }
      },
      onError: (Object e) {
        fatal = e.toString();
        if (!completer.isCompleted) completer.complete();
      },
      onDone: () {
        if (!completer.isCompleted) completer.complete();
      },
      cancelOnError: true,
    );
    await completer.future;
    ImageStamps.busy--;
    running = false;
    cancelled = token.isCancelled();
    _token = null;
    notifyListeners();
  }

  /// Progress of a pre-processing phase run outside Rust (cloud calls).
  void external({required String phase, required int done, required int total, required int errors, required bool running}) {
    this.phase = phase;
    this.done = done;
    this.total = total;
    this.errors = errors;
    this.running = running;
    if (running && done == 0) cancelled = false;
    notifyListeners();
  }

  bool get cancelRequested => cancelled;

  void cancel() {
    _token?.cancel();
    cancelled = true;
    notifyListeners();
  }

  /// Hides the finished progress strip; results stay available.
  void dismissProgress() {
    if (running) return;
    done = total = errors = 0;
    fatal = null;
    notifyListeners();
  }

  void clear() {
    results.clear();
    done = total = errors = 0;
    fatal = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _token?.cancel();
    _sub?.cancel();
    super.dispose();
  }
}
