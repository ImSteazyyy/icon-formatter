import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../app/models.dart';
import '../app/state.dart';
import '../src/rust/api/engine.dart';

/// Live thumbnail of a preset: the same engine call as the Studio preview
/// (previewBytes, which runs off the UI isolate), on a sample icon drawn in
/// Dart, so no third-party artwork is shipped. One render per distinct look
/// (preset id + values), cached; a tile only asks when it is built, so the
/// strip renders lazily.
final Map<String, Future<Uint8List?>> _thumbCache = {};
Future<Uint8List>? _sample;

/// Sample icon: a rounded plate with a disc (a plain shape, no brand art).
Future<Uint8List> _sampleIcon() => _sample ??= _drawSample();

Future<Uint8List> _drawSample() async {
  final rec = ui.PictureRecorder();
  final canvas = Canvas(rec, const Rect.fromLTWH(0, 0, 256, 256));
  canvas.drawRRect(
    RRect.fromRectAndRadius(const Rect.fromLTWH(36, 36, 184, 184), const Radius.circular(48)),
    Paint()..color = const Color(0xFFE03C31),
  );
  canvas.drawCircle(const Offset(128, 128), 56, Paint()..color = const Color(0xFFFFFFFF));
  final img = await rec.endRecording().toImage(256, 256);
  final data = await img.toByteData(format: ui.ImageByteFormat.png);
  return data!.buffer.asUint8List();
}

/// PNG of [pr] rendered on the sample icon at 96 px, or null when the engine
/// cannot render it (the tile then shows a neutral placeholder).
Future<Uint8List?> presetThumb(StylePreset pr) {
  // the Lucent look and the procedural params both count: the four built-ins share params
  final key = '${pr.id}|${jsonEncode(pr.values)}';
  return _thumbCache.putIfAbsent(key, () async {
    try {
      final base = AppState.I.settingsFor(StudioMode.preset, presetId: pr.id);
      final s = ProcessSettings(
        size: 96,
        background: base.background,
        placement: base.placement,
        segment: base.segment,
        ai: base.ai,
        effects: base.effects,
        cutCacheDir: base.cutCacheDir,
      );
      final r = await previewBytes(bytes: await _sampleIcon(), settings: s);
      return r.png;
    } catch (_) {
      return null;
    }
  });
}

/// The thumbnail of a preset; shows a plate while it renders.
class PresetThumb extends StatelessWidget {
  const PresetThumb({super.key, required this.preset});
  final StylePreset preset;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List?>(
      future: presetThumb(preset),
      builder: (context, snap) {
        final png = snap.data;
        if (png == null) {
          return const Center(child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)));
        }
        return Image.memory(png, fit: BoxFit.contain, gaplessPlayback: true, filterQuality: FilterQuality.medium);
      },
    );
  }
}
