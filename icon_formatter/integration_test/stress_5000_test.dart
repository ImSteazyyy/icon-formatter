// Stress test: writes N distinct 512x512 synthetic icons into the app cache,
// imports them through the Studio, taps "Elabora tutte" and records every 100
// finished icons: elapsed time, RSS and janky frames. Skipped unless enabled:
//
//   flutter test integration_test/stress_5000_test.dart -d emulator-5554 \
//     --dart-define=STRESS=true --dart-define=STRESS_N=500 \
//     --dart-define=STRESS_BUDGET_MB=1536
//
// Results: printed (tag E2E_STRESS) and written to <app cache>/stress_results.txt.
// On Android the file is also copied to /sdcard/Download/iconformatter_stress_results.txt.
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icon_formatter/app/storage.dart';
import 'package:icon_formatter/l10n/strings.dart';
import 'package:icon_formatter/services/import_service.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;

import 'e2e_support.dart';

const _enabled = bool.fromEnvironment('STRESS');
const _limit = int.fromEnvironment('STRESS_N', defaultValue: 5000);
const _budgetMb = int.fromEnvironment('STRESS_BUDGET_MB', defaultValue: 1536);
const _step = 100;

/// A frame longer than this misses the 60 Hz budget.
const _jankMicros = 16667;

void _report(String line, File? file) {
  debugPrint('E2E_STRESS $line');
  file?.writeAsStringSync('$line\n', mode: FileMode.append, flush: true);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'stress: import, Elabora tutte and per-100 metrics',
    skip: !_enabled,
    timeout: const Timeout(Duration(minutes: 120)),
    (tester) async {
      await pumpApp(tester);
      await openTab(tester, [S.studio]);

      final sinkFile = File(p.join(AppPaths.I.cache.path, 'stress_results.txt'))..createSync(recursive: true)..writeAsStringSync('');
      final dir = p.join(AppPaths.I.cache.path, 'stress_in');
      final tGen = DateTime.now();
      await tester.runAsync(() => writeSyntheticIcons(dir, _limit));
      final genS = DateTime.now().difference(tGen).inMilliseconds / 1000;
      _report('STRESS limit=$_limit budget_mb=$_budgetMb step=$_step dir=$dir generate_s=${genS.toStringAsFixed(1)}', sinkFile);
      _report('items | elapsed_s | per_100_s | rss_mb | frames | janky | janky_pct | worst_frame_ms | errors', sinkFile);

      // frame timings of the whole run (the live binding reports real frames)
      final frames = <FrameTiming>[];
      void onTimings(List<FrameTiming> t) => frames.addAll(t);
      SchedulerBinding.instance.addTimingsCallback(onTimings);

      final c = studioController(tester);
      final imgs = await tester.runAsync(() => ImportService.expand([dir]));
      final take = imgs!.take(_limit).toList();
      _report('imported=${imgs.length} used=${take.length}', sinkFile);
      expect(take, hasLength(_limit), reason: 'Import found ${imgs.length} of $_limit icons in $dir');

      final tImport = DateTime.now();
      c.addPaths(take);
      await pumpFor(tester, const Duration(milliseconds: 500));
      _report('import_and_list_ms=${DateTime.now().difference(tImport).inMilliseconds}', sinkFile);

      var peakRss = ProcessInfo.currentRss;
      var nextCheckpoint = _step;
      var tLast = DateTime.now();
      var framesAtLast = 0;
      final rows = <String>[];

      await tapText(tester, S.elaboraTutte);
      final tRun = DateTime.now();

      void checkpoint(int done) {
        final now = DateTime.now();
        final elapsed = now.difference(tRun).inMilliseconds / 1000;
        final window = now.difference(tLast).inMilliseconds / 1000;
        final rss = ProcessInfo.currentRss;
        if (rss > peakRss) peakRss = rss;
        final win = frames.sublist(framesAtLast);
        final janky = win.where((f) => f.totalSpan.inMicroseconds > _jankMicros).length;
        final worst = win.isEmpty ? 0 : win.map((f) => f.totalSpan.inMicroseconds).reduce((a, b) => a > b ? a : b) / 1000;
        final errors = c.batch.results.values.where((r) => !r.ok).length;
        final pct = win.isEmpty ? 0 : janky * 100 / win.length;
        final line = '$done | ${elapsed.toStringAsFixed(1)} | ${window.toStringAsFixed(1)} | '
            '${rss ~/ (1024 * 1024)} | ${win.length} | $janky | ${pct.toStringAsFixed(1)} | ${worst.toStringAsFixed(1)} | $errors';
        rows.add(line);
        _report(line, sinkFile);
        tLast = now;
        framesAtLast = frames.length;
      }

      await pumpUntil(
        tester,
        () {
          final done = c.batch.results.length;
          while (done >= nextCheckpoint && nextCheckpoint <= take.length) {
            checkpoint(nextCheckpoint);
            nextCheckpoint += _step;
          }
          return !c.batch.running && done >= take.length;
        },
        timeout: const Duration(minutes: 80),
        what: 'all ${take.length} icons processed (done: ${c.batch.results.length})',
      );
      final total = DateTime.now().difference(tRun);
      final finalRss = ProcessInfo.currentRss;
      if (finalRss > peakRss) peakRss = finalRss;
      SchedulerBinding.instance.removeTimingsCallback(onTimings);

      final allFrames = frames.length;
      final janky = frames.where((f) => f.totalSpan.inMicroseconds > _jankMicros).length;
      final errors = c.batch.results.values.where((r) => !r.ok).length;
      _report('SUMMARY items=${take.length} total_s=${(total.inMilliseconds / 1000).toStringAsFixed(1)} '
          'per_100_s=${(total.inMilliseconds / take.length * 100 / 1000).toStringAsFixed(1)} '
          'peak_rss_mb=${peakRss ~/ (1024 * 1024)} end_rss_mb=${finalRss ~/ (1024 * 1024)} '
          'frames=$allFrames janky=$janky janky_pct=${allFrames == 0 ? 0 : (janky * 100 / allFrames).toStringAsFixed(1)} '
          'errors=$errors allowed_flutter_errors=${allowedErrorHits.length} budget_mb=$_budgetMb', sinkFile);

      if (Platform.isAndroid) {
        try {
          File('/sdcard/Download/iconformatter_stress_results.txt').writeAsStringSync(sinkFile.readAsStringSync());
        } catch (e) {
          debugPrint('E2E_STRESS could not copy results to Download: $e');
        }
      }

      expect(peakRss ~/ (1024 * 1024), lessThanOrEqualTo(_budgetMb), reason: 'Peak RSS exceeded the $_budgetMb MB budget');
      expect(errors, 0, reason: '$errors icons finished with an error');
    },
  );
}
