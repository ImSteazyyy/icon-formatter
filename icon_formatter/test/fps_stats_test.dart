import 'package:flutter_test/flutter_test.dart';
import 'package:icon_formatter/widgets/fps_overlay.dart';

void main() {
  // one frame every [gapUs] microseconds, each taking [workUs] build+raster and [spanUs] in total
  void feed(FrameStats s, {required int from, required int count, required int gapUs, required int workUs, required int spanUs}) {
    for (var i = 0; i < count; i++) {
      s.add(atUs: from + i * gapUs, workUs: workUs, spanUs: spanUs);
    }
  }

  test('fps counts the frames of the last second only', () {
    final s = FrameStats();
    feed(s, from: 0, count: 120, gapUs: 8333, workUs: 4000, spanUs: 8000);
    final now = 120 * 8333;
    expect(s.fps(now), closeTo(120, 1));
  });

  test('worst build + raster time is in milliseconds', () {
    final s = FrameStats();
    feed(s, from: 0, count: 10, gapUs: 8333, workUs: 4000, spanUs: 8000);
    s.add(atUs: 90000, workUs: 21500, spanUs: 22000);
    expect(s.worstMs(90000), closeTo(21.5, 1e-9));
  });

  test('jank is the share of frames whose span is over the budget', () {
    final s = FrameStats();
    feed(s, from: 0, count: 8, gapUs: 8333, workUs: 4000, spanUs: 8000);
    feed(s, from: 8 * 8333, count: 2, gapUs: 8333, workUs: 12000, spanUs: 18000);
    // budget at 120 Hz is 8.33 ms: 2 of 10 frames are late
    expect(s.jankPercent(9 * 8333, 1000 / 120), closeTo(20, 1e-9));
  });

  test('empty window gives zeros and no percentile', () {
    final s = FrameStats();
    expect(s.fps(1000000), 0);
    expect(s.worstMs(1000000), 0);
    expect(s.jankPercent(1000000, 16.6), 0);
    expect(s.spanPercentileMs(1000000, 0.95), isNull);
  });

  test('p95 over three seconds picks the slow tail', () {
    final s = FrameStats();
    // 100 frames at 10 ms span, 10 at 30 ms, spread across the window
    feed(s, from: 0, count: 100, gapUs: 25000, workUs: 5000, spanUs: 10000);
    feed(s, from: 100 * 25000, count: 10, gapUs: 25000, workUs: 5000, spanUs: 30000);
    final now = 110 * 25000;
    expect(s.spanPercentileMs(now, 0.95), closeTo(30, 1e-9));
    expect(s.spanPercentileMs(now, 0.5), closeTo(10, 1e-9));
  });

  test('frames older than the kept window are dropped', () {
    final s = FrameStats(keepUs: 1000000);
    feed(s, from: 0, count: 5, gapUs: 100000, workUs: 1000, spanUs: 1000);
    s.add(atUs: 5000000, workUs: 1000, spanUs: 1000);
    expect(s.spanPercentileMs(5000000, 0.5), closeTo(1, 1e-9));
    expect(s.fps(5000000), 1);
  });
}
