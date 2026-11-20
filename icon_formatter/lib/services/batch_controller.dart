import '../widgets/common.dart' show ImageStamps;
import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../app/state.dart';
import '../l10n/strings.dart';
import '../src/rust/api/engine.dart';
import 'platform_service.dart';
import 'progress_throttle.dart';

/// Wraps the Rust batch stream: progress, results per item, cancellation.
/// The UI stays responsive because all work happens on Rust worker threads.
/// Notes the Rust cut-out cache adds to each result (batch.rs NOTE_CACHE_HIT/MISS).
const _cacheHitNote = 'cut:cache-hit';
const _cacheMissNote = 'cut:cache-miss';

class BatchController extends ChangeNotifier {
  final Map<String, ItemResult> results = {};
  int done = 0;
  int total = 0;
  int errors = 0;
  /// Items re-composed from a saved cut-out, and items cut again, in this run.
  int cacheHits = 0;
  int cacheMisses = 0;
  bool running = false;
  bool cancelled = false;
  String? fatal;

  /// Non-error note about this run (e.g. a cut-out provider that fell back).
  String? notice;

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
    cacheHits = 0;
    cacheMisses = 0;
    running = true;
    cancelled = false;
    fatal = null;
    phase = null;
    notifyListeners();
    final completer = Completer<void>();
    final uiThrottle = ProgressThrottle(Duration(milliseconds: Platform.isAndroid ? 250 : 80));
    // Android: a notification with progress while a long batch runs
    final notify = Platform.isAndroid && items.length > 8;
    var lastPush = DateTime.fromMillisecondsSinceEpoch(0);
    ImageStamps.busy++;
    // a throw before the stream starts must not leave `running` set for good
    try {
      if (notify) unawaited(PlatformService.processingStart(items.length));
      _sub = runBatch(items: items, settings: settings, threads: AppState.I.threads, cancel: token).listen(
        (ev) {
          final raw = ev.result;
          final hit = raw.notes.contains(_cacheHitNote);
          final miss = raw.notes.contains(_cacheMissNote);
          if (hit) cacheHits++;
          if (miss) cacheMisses++;
          // the cache markers are counted above and not shown as notes
          final r = hit || miss
              ? ItemResult(
                  id: raw.id,
                  name: raw.name,
                  ok: raw.ok,
                  error: raw.error,
                  output: raw.output,
                  ambiguous: raw.ambiguous,
                  confidence: raw.confidence,
                  method: raw.method,
                  notes: [for (final n in raw.notes) if (n != _cacheHitNote && n != _cacheMissNote) n],
                )
              : raw;
          results[r.id] = r;
          final out = r.output;
          if (out != null) ImageStamps.bump(out);
          done = ev.done;
          total = ev.total;
          if (!r.ok) errors++;
          // throttle rebuilds: every rebuild repaints the grid under the glass
          // bars (blur), so on phones a few refreshes per second are enough
          final now = DateTime.now();
          if (uiThrottle.allow(now, force: ev.done == ev.total)) notifyListeners();
          if (notify && (ev.done == ev.total || now.difference(lastPush).inMilliseconds >= 500)) {
            lastPush = now;
            unawaited(PlatformService.processingProgress(ev.done, ev.total));
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
    } catch (e) {
      fatal = e.toString();
    } finally {
      if (notify) unawaited(PlatformService.processingStop());
      ImageStamps.busy--;
      running = false;
      cancelled = token.isCancelled();
      _token = null;
      if (cacheHits + cacheMisses > 0) {
        final summary = S.ux2bCacheSummary(cacheHits, cacheMisses);
        notice = notice == null ? summary : '$notice $summary';
      }
      notifyListeners();
    }
    // once per batch, not per item
    unawaited(AppState.I.pruneCutouts());
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

  /// Cancels the running batch or pre-pass. Idle calls are ignored: a flag set
  /// with nothing to stop would stay set and block the next processing.
  void cancel() {
    if (!running) return;
    _token?.cancel();
    cancelled = true;
    notifyListeners();
  }

  /// Called before every new processing: drops a cancel left from an earlier run.
  void clearCancel() => cancelled = false;

  void setNotice(String? text) {
    notice = text;
    notifyListeners();
  }

  /// Hides the finished progress strip; results stay available.
  void dismissProgress() {
    if (running) return;
    done = total = errors = 0;
    fatal = null;
    notice = null;
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
