import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:icon_formatter/services/pack_quality.dart';

/// Builds a w*h RGBA image filled with [bg] (alpha 0 when null) and paints
/// a square of [side] pixels at (x, y) with [fg].
Uint8List _img(int w, int h, {List<int>? bg, required int side, int x = -1, int y = -1, List<int> fg = const [255, 255, 255, 255]}) {
  final out = Uint8List(w * h * 4);
  for (var i = 0; i < w * h; i++) {
    if (bg != null) out.setRange(i * 4, i * 4 + 4, bg);
  }
  final ox = x < 0 ? (w - side) ~/ 2 : x;
  final oy = y < 0 ? (h - side) ~/ 2 : y;
  for (var yy = oy; yy < oy + side; yy++) {
    for (var xx = ox; xx < ox + side; xx++) {
      out.setRange((yy * w + xx) * 4, (yy * w + xx) * 4 + 4, fg);
    }
  }
  return out;
}

void main() {
  test('transparent canvas is nearly empty', () {
    expect(packCheckPixels(_img(100, 100, side: 0), 100, 100), [PbProblem.nearlyEmpty]);
  });

  test('empty input is not a crash', () {
    expect(packCheckPixels(Uint8List(0), 0, 0), isEmpty);
  });

  test('small centred symbol is too small', () {
    // 20x20 = 4% of the canvas
    expect(packCheckPixels(_img(100, 100, side: 20), 100, 100), [PbProblem.tooSmall]);
  });

  test('centred symbol of normal size is fine', () {
    expect(packCheckPixels(_img(100, 100, side: 60), 100, 100), isEmpty);
  });

  test('symbol in a corner is off centre', () {
    expect(packCheckPixels(_img(100, 100, side: 60, x: 0, y: 0), 100, 100), [PbProblem.offCentre]);
  });

  test('dark symbol on a dark plate is too dark', () {
    final plate = [0, 0, 0, 255];
    // the same dark symbol is also low contrast against the plate
    expect(packCheckPixels(_img(100, 100, bg: plate, side: 60, fg: [20, 20, 20, 255]), 100, 100), [PbProblem.tooDark, PbProblem.lowContrast]);
  });

  test('light symbol on a dark plate is fine', () {
    final plate = [0, 0, 0, 255];
    expect(packCheckPixels(_img(100, 100, bg: plate, side: 60), 100, 100), isEmpty);
  });

  test('dark symbol on a light plate is fine', () {
    final plate = [255, 255, 255, 255];
    expect(packCheckPixels(_img(100, 100, bg: plate, side: 60, fg: [10, 10, 10, 255]), 100, 100), isEmpty);
  });

  test('pale symbol on a white plate has low contrast', () {
    final plate = [255, 255, 255, 255];
    expect(packCheckPixels(_img(100, 100, bg: plate, side: 60, fg: [230, 230, 230, 255]), 100, 100), [PbProblem.lowContrast]);
  });

  test('translucent plate skips the contrast check', () {
    final plate = [255, 255, 255, 100];
    expect(packCheckPixels(_img(100, 100, bg: plate, side: 60, fg: [230, 230, 230, 255]), 100, 100), isEmpty);
  });

  test('contrast ratio of black on white is 21, of a colour with itself 1', () {
    expect(packContrastRatio([0, 0, 0], [255, 255, 255]), closeTo(21, 0.01));
    expect(packContrastRatio([120, 60, 200], [120, 60, 200]), closeTo(1, 0.0001));
  });
}
