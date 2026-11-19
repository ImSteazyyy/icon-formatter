import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

/// Problems the quality check can find on a generated icon.
enum PbProblem { nearlyEmpty, tooSmall, offCentre, tooDark, lowContrast }

/// WCAG contrast ratio (1 to 21) between two sRGB colours, channels 0..255.
double packContrastRatio(List<double> a, List<double> b) {
  final la = _relLum(a), lb = _relLum(b);
  final hi = math.max(la, lb), lo = math.min(la, lb);
  return (hi + 0.05) / (lo + 0.05);
}

double _relLum(List<double> c) {
  double lin(double v) {
    final s = v / 255;
    return s <= 0.03928 ? s / 12.92 : math.pow((s + 0.055) / 1.055, 2.4).toDouble();
  }

  return 0.2126 * lin(c[0]) + 0.7152 * lin(c[1]) + 0.0722 * lin(c[2]);
}

/// Cheap checks on a straight-alpha RGBA image (4 bytes per pixel, row by
/// row). With an opaque plate the symbol is the pixels that differ from it.
List<PbProblem> packCheckPixels(Uint8List rgba, int width, int height) {
  final n = width * height;
  if (n == 0 || rgba.length < n * 4) return const [];
  var opaque = 0;
  for (var i = 0; i < n; i++) {
    if (rgba[i * 4 + 3] >= 128) opaque++;
  }
  // a plate covers almost the whole canvas; its colour is the corner pixel
  final plate = opaque > n * 0.9 ? [rgba[0], rgba[1], rgba[2]] : null;
  bool inSymbol(int i) {
    if (rgba[i * 4 + 3] < 128) return false;
    if (plate == null) return true;
    final d = (rgba[i * 4] - plate[0]).abs() + (rgba[i * 4 + 1] - plate[1]).abs() + (rgba[i * 4 + 2] - plate[2]).abs();
    return d > 24;
  }

  var count = 0;
  var sx = 0.0, sy = 0.0, lum = 0.0;
  var sr = 0.0, sg = 0.0, sb = 0.0;
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final i = y * width + x;
      if (!inSymbol(i)) continue;
      count++;
      sx += x;
      sy += y;
      sr += rgba[i * 4];
      sg += rgba[i * 4 + 1];
      sb += rgba[i * 4 + 2];
      lum += 0.299 * rgba[i * 4] + 0.587 * rgba[i * 4 + 1] + 0.114 * rgba[i * 4 + 2];
    }
  }
  if (count < n * 0.02) return const [PbProblem.nearlyEmpty];
  final found = <PbProblem>[];
  if (count < n * 0.08) found.add(PbProblem.tooSmall);
  final side = math.max(width, height);
  final dx = sx / count - (width - 1) / 2, dy = sy / count - (height - 1) / 2;
  if (math.sqrt(dx * dx + dy * dy) / side > 0.12) found.add(PbProblem.offCentre);
  if (plate != null && lum / count < 38 && 0.299 * plate[0] + 0.587 * plate[1] + 0.114 * plate[2] < 90) {
    found.add(PbProblem.tooDark);
  }
  // opaque plates only: the symbol's mean colour against the plate's corners
  if (plate != null) {
    var pr = 0, pg = 0, pb = 0;
    for (final i in [0, width - 1, n - width, n - 1]) {
      pr += rgba[i * 4];
      pg += rgba[i * 4 + 1];
      pb += rgba[i * 4 + 2];
    }
    final ratio = packContrastRatio([sr / count, sg / count, sb / count], [pr / 4, pg / 4, pb / 4]);
    if (ratio < 1.6) found.add(PbProblem.lowContrast);
  }
  return found;
}

/// Decodes a PNG to straight RGBA, scaled to [maxSide] wide (for the check).
Future<({Uint8List rgba, int width, int height})> packDecodeRgba(Uint8List png, {int maxSide = 128}) async {
  final codec = await ui.instantiateImageCodec(png, targetWidth: maxSide);
  try {
    final frame = await codec.getNextFrame();
    final img = frame.image;
    try {
      final data = await img.toByteData(format: ui.ImageByteFormat.rawStraightRgba);
      return (rgba: data!.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes), width: img.width, height: img.height);
    } finally {
      img.dispose();
    }
  } finally {
    codec.dispose();
  }
}
