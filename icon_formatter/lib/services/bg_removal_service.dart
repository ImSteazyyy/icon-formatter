import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import '../app/storage.dart';
import '../l10n/strings.dart';

/// Background removal provider. Local (Rust, offline) is the default; the
/// cloud option is used only when the user selects it and saves an API key.
enum BgProvider { local, localAi, removeBg }

String bgProviderLabel(BgProvider b) => switch (b) {
      BgProvider.local => S.localeRustOfflineGratuita,
      BgProvider.localAi => S.aiLocaleOffline,
      BgProvider.removeBg => S.removeBgCloudCrediti,
    };

class BgRemovalException implements Exception {
  BgRemovalException(this.message);

  final String message;

  @override
  String toString() => message;
}

class BgRemovalService {
  static const _storage = FlutterSecureStorage();
  static const _keyName = 'bg_api_key_removebg';
  static const pricingUrl = 'https://www.remove.bg/pricing';
  static const costNote = S.removeBgConsuma1Credito;

  /// Cache: source key -> cutout PNG path (one API call per image).
  static final Map<String, String> _cache = {};

  static Future<String?> readKey() => _storage.read(key: _keyName);

  static Future<void> writeKey(String? v) async {
    if (v == null || v.isEmpty) {
      await _storage.delete(key: _keyName);
    } else {
      await _storage.write(key: _keyName, value: v);
    }
  }

  /// Free call: returns the remaining credits of the account.
  static Future<String> testConnection() async {
    final key = await readKey();
    if (key == null || key.isEmpty) throw BgRemovalException(S.apiKeyMancante);
    final r = await http
        .get(Uri.parse('https://api.remove.bg/v1.0/account'), headers: {'X-Api-Key': key})
        .timeout(const Duration(seconds: 20));
    if (r.statusCode != 200) throw BgRemovalException(_error(r));
    final j = jsonDecode(r.body);
    final credits = j['data']?['attributes']?['credits'];
    final total = credits?['total'];
    final free = j['data']?['attributes']?['api']?['free_calls'];
    return S.connessioneOkCreditiChiamateGratuite(total ?? '?', free ?? '?');
  }

  static String _error(http.Response r) {
    try {
      final e = (jsonDecode(r.body)['errors'] as List).first;
      return S.errore3(r.statusCode, e['title'], e['detail'] != null ? ' (${e['detail']})' : '');
    } catch (_) {
      return S.erroreHttp(r.statusCode);
    }
  }

  /// Returns the path of a transparent PNG cutout, calling the API once per
  /// source (results are cached for the session).
  static Future<String> cutout({required String cacheKey, String? path, Uint8List? bytes}) async {
    final hit = _cache[cacheKey];
    if (hit != null && File(hit).existsSync()) return hit;
    final key = await readKey();
    if (key == null || key.isEmpty) {
      throw BgRemovalException(S.removeBgSelezionatoMaSenza);
    }
    final data = bytes ?? await File(path!).readAsBytes();
    final req = http.MultipartRequest('POST', Uri.parse('https://api.remove.bg/v1.0/removebg'))
      ..headers['X-Api-Key'] = key
      ..fields['size'] = 'auto'
      ..fields['format'] = 'png'
      ..files.add(http.MultipartFile.fromBytes('image_file', data, filename: 'icon.png'));
    final r = await http.Response.fromStream(await req.send().timeout(const Duration(minutes: 2)));
    if (r.statusCode != 200) throw BgRemovalException(_error(r));
    final dir = await AppPaths.I.workDir('removebg');
    final out = p.join(dir, 'cutout.png');
    await File(out).writeAsBytes(r.bodyBytes);
    _cache[cacheKey] = out;
    return out;
  }
}
