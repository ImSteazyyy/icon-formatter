import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../app/state.dart';
import '../l10n/strings.dart';
import 'common.dart';

/// Frame times kept for the monitor: fps and worst time look at the last second,
/// the guard at the last three seconds.
class FrameStats {
  FrameStats({this.keepUs = 3000000});

  /// How long a frame stays in the window (microseconds).
  final int keepUs;
  final List<_Frame> _frames = [];

  /// Records one finished frame. [atUs] is the raster finish time, [workUs] build + raster,
  /// [spanUs] the whole frame from vsync to finish (what the user sees as a late frame).
  void add({required int atUs, required int workUs, required int spanUs}) {
    _frames.add(_Frame(atUs, workUs, spanUs));
    final cut = atUs - keepUs;
    var drop = 0;
    while (drop < _frames.length && _frames[drop].atUs < cut) {
      drop++;
    }
    if (drop > 0) _frames.removeRange(0, drop);
  }

  void clear() => _frames.clear();

  List<_Frame> _within(int nowUs, int windowUs) {
    final from = nowUs - windowUs;
    return [for (final f in _frames) if (f.atUs >= from) f];
  }

  /// Frames finished in the last second.
  int fps(int nowUs) => _within(nowUs, 1000000).length;

  /// Longest build + raster time in the last second, in milliseconds (0 if none).
  double worstMs(int nowUs) {
    var worst = 0;
    for (final f in _within(nowUs, 1000000)) {
      if (f.workUs > worst) worst = f.workUs;
    }
    return worst / 1000;
  }

  /// Share (0 to 100) of frames in the last second whose span is over [budgetMs].
  double jankPercent(int nowUs, double budgetMs) {
    final frames = _within(nowUs, 1000000);
    if (frames.isEmpty) return 0;
    final late = frames.where((f) => f.spanUs / 1000 > budgetMs).length;
    return late * 100 / frames.length;
  }

  /// Frame span percentile (0 to 1) in milliseconds over the last [windowUs]; null if no frames.
  double? spanPercentileMs(int nowUs, double p, {int windowUs = 3000000}) {
    final spans = [for (final f in _within(nowUs, windowUs)) f.spanUs]..sort();
    if (spans.isEmpty) return null;
    final i = (p * (spans.length - 1)).round().clamp(0, spans.length - 1);
    return spans[i] / 1000;
  }
}

class _Frame {
  const _Frame(this.atUs, this.workUs, this.spanUs);
  final int atUs;
  final int workUs;
  final int spanUs;
}

/// Frame monitor (Settings > System > Show FPS). It exists only while shown:
/// the timings callback is registered in initState and removed in dispose.
class FpsOverlay extends StatefulWidget {
  const FpsOverlay({super.key});

  @override
  State<FpsOverlay> createState() => _FpsOverlayState();
}

class _FpsOverlayState extends State<FpsOverlay> {
  final _stats = FrameStats();
  Timer? _refresh;
  // raster finish of the last frame: the clock the window is measured against
  int _lastAtUs = 0;

  double? get _hz {
    final r = PlatformDispatcher.instance.views.first.display.refreshRate;
    return r > 0 ? r : null;
  }

  double get _budgetMs => 1000 / (_hz ?? 60);

  void _onTimings(List<FrameTiming> timings) {
    if (timings.isEmpty) return;
    for (final t in timings) {
      _lastAtUs = t.timestampInMicroseconds(FramePhase.rasterFinish);
      _stats.add(
        atUs: _lastAtUs,
        workUs: t.buildDuration.inMicroseconds + t.rasterDuration.inMicroseconds,
        spanUs: t.totalSpan.inMicroseconds,
      );
    }
    // the guard: premium glass whose 3 s p95 frame stays over twice the budget is flagged, never switched
    final st = AppState.I;
    final p95 = _stats.spanPercentileMs(_lastAtUs, 0.95);
    st.fpsStruggling.value = st.glass.premium && p95 != null && _stats.fps(_lastAtUs) >= 30 && p95 > 2 * _budgetMs;
  }

  @override
  void initState() {
    super.initState();
    SchedulerBinding.instance.addTimingsCallback(_onTimings);
    _refresh = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    SchedulerBinding.instance.removeTimingsCallback(_onTimings);
    _refresh?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final now = _lastAtUs;
    final hz = _hz;
    final fps = _stats.fps(now);
    final worst = _stats.worstMs(now);
    final jank = _stats.jankPercent(now, _budgetMs);
    final style = const TextStyle(color: Colors.white, fontSize: 11, height: 1.25, fontFeatures: [FontFeature.tabularFigures()]);
    return Align(
      alignment: Alignment.topRight,
      child: SafeArea(
        child: IgnorePointer(
          child: Container(
            margin: const EdgeInsets.all(6),
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
            decoration: BoxDecoration(color: const Color(0xCC000000), borderRadius: BorderRadius.circular(6)),
            child: Text(
              '$fps fps  ${hz == null ? '' : '${hz.round()} Hz  '}max ${worst.toStringAsFixed(1)} ms\njank ${jank.toStringAsFixed(0)}%',
              style: style,
            ),
          ),
        ),
      ),
    );
  }
}

/// Settings switch for the monitor; persisted in AppState (not part of the backup).
class SettingsFpsSwitch extends StatelessWidget {
  const SettingsFpsSwitch({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppState.I,
      builder: (context, _) {
        final st = AppState.I;
        return SettingSwitch(
          key: const ValueKey('settings-show-fps'),
          icon: Icons.speed_rounded,
          title: S.fpsMostra,
          subtitle: S.fpsMostraSub,
          value: st.showFps,
          onChanged: (v) => st.update(() => st.showFps = v),
        );
      },
    );
  }
}
