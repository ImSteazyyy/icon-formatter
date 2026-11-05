import 'dart:io';

import 'package:http/http.dart' as http;

import '../app/models.dart';
import '../app/state.dart';
import '../src/rust/api/engine.dart';

/// Downloads / removes the optional local segmentation models.
class AiModelService {
  /// Streams the model to `<models>/<id>.onnx.part`, then renames it.
  /// [progress] receives 0..1. Throws on HTTP or size mismatch.
  static Future<void> download(AiModelInfo m, void Function(double) progress, {bool Function()? cancelled}) async {
    final dest = File(AppState.I.modelPath(m));
    await dest.parent.create(recursive: true);
    final part = File('${dest.path}.part');
    final client = http.Client();
    try {
      final res = await client.send(http.Request('GET', Uri.parse(m.url)));
      if (res.statusCode != 200) throw HttpException('HTTP ${res.statusCode}');
      final total = res.contentLength ?? m.bytes;
      final sink = part.openWrite();
      var got = 0;
      try {
        await for (final chunk in res.stream) {
          if (cancelled?.call() ?? false) throw const HttpException('annullato');
          sink.add(chunk);
          got += chunk.length;
          progress(total > 0 ? got / total : 0);
        }
      } finally {
        await sink.close();
      }
      if (got != m.bytes) throw HttpException('dimensione inattesa ($got byte)');
      if (await dest.exists()) await dest.delete();
      await part.rename(dest.path);
    } catch (_) {
      if (await part.exists()) await part.delete();
      rethrow;
    } finally {
      client.close();
    }
  }

  static Future<void> delete(AiModelInfo m) async {
    await aiUnloadModel();
    final f = File(AppState.I.modelPath(m));
    if (await f.exists()) await f.delete();
  }
}
