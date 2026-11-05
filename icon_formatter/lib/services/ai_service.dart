import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import '../app/models.dart';
import '../app/state.dart';
import '../l10n/strings.dart';

class AiException implements Exception {
  AiException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Static provider information shown in Settings. Prices change: the UI
/// presents them as indicative and links the official pricing page.
class AiProviderInfo {
  const AiProviderInfo(this.name, this.defaultModel, this.defaultBaseUrl, this.costNote, this.pricingUrl);

  final String name;
  final String defaultModel;
  final String defaultBaseUrl;
  final String costNote;
  final String pricingUrl;
}

const aiProviders = {
  AiProviderKind.openai: AiProviderInfo(
    S.openaiImagesApi,
    'gpt-image-1',
    'https://api.openai.com',
    S.indicativoCirca0010,
    'https://openai.com/api/pricing/',
  ),
  AiProviderKind.gemini: AiProviderInfo(
    S.googleGemini,
    'gemini-2.5-flash-image',
    'https://generativelanguage.googleapis.com',
    S.indicativoCirca004Usd,
    'https://ai.google.dev/gemini-api/docs/pricing',
  ),
  AiProviderKind.openaiCompatible: AiProviderInfo(
    S.compatibileOpenaiEndpointPersonalizzato,
    'gpt-image-1',
    'https://',
    S.costiLimitiDipendonoDalServizio,
    '',
  ),
};

/// Theme presets for AI icon theming.
const aiThemes = <String, String>{
  S.nothingTranslucent:
      'Restyle the icon background as neutral dark grey smoked frosted glass, with a subtle thin light rim and soft reflections, '
          'no purple, blue or teal cast. Keep the logo/glyph exactly as it is, same colours and proportions.',
  S.monocromaticoChiaro:
      'Turn the glyph into a clean single-colour off-white version on a dark charcoal squircle, preserving the exact silhouette.',
  S.pastelloMorbido: 'Recolour the icon with soft pastel tones while keeping the glyph silhouette and identity unchanged.',
  S.neonNotturno: 'Give the glyph a restrained neon accent on a deep graphite background, keeping the shape identical.',
  'Personalizzato': '',
};

class AiService {
  static const _storage = FlutterSecureStorage();

  static String _keyName(AiProviderKind k) => 'ai_api_key_${k.name}';

  static Future<String?> readKey(AiProviderKind k) => _storage.read(key: _keyName(k));

  static Future<void> writeKey(AiProviderKind k, String? v) async {
    if (v == null || v.isEmpty) {
      await _storage.delete(key: _keyName(k));
    } else {
      await _storage.write(key: _keyName(k), value: v);
    }
  }

  static Future<bool> isConfigured() async {
    final k = await readKey(AppState.I.ai.provider);
    return k != null && k.isNotEmpty && AppState.I.ai.model.isNotEmpty;
  }

  static String _base(AiConfig c) {
    var b = c.baseUrl.trim();
    if (b.isEmpty || b == 'https://') b = aiProviders[c.provider]!.defaultBaseUrl;
    while (b.endsWith('/')) {
      b = b.substring(0, b.length - 1);
    }
    return b;
  }

  /// Verifies key/endpoint/model with a cheap metadata call (no generation).
  static Future<String> testConnection() async {
    final c = AppState.I.ai;
    final key = await readKey(c.provider);
    if (key == null || key.isEmpty) throw AiException(S.apiKeyMancante);
    final base = _base(c);
    late http.Response r;
    try {
      if (c.provider == AiProviderKind.gemini) {
        r = await http
            .get(Uri.parse('$base/v1beta/models/${c.model}'), headers: {'x-goog-api-key': key})
            .timeout(const Duration(seconds: 20));
      } else {
        r = await http
            .get(Uri.parse('$base/v1/models'), headers: {'Authorization': S.bearer(key)})
            .timeout(const Duration(seconds: 20));
      }
    } catch (e) {
      throw AiException(S.connessioneNonRiuscita(e));
    }
    if (r.statusCode != 200) throw AiException(_errorText(r));
    if (c.provider != AiProviderKind.gemini) {
      final ids = ((jsonDecode(r.body)['data'] as List?) ?? []).map((e) => e['id']).toSet();
      if (ids.isNotEmpty && !ids.contains(c.model)) {
        return S.connessioneOkMaModelloNon(c.model);
      }
    }
    return S.connessioneOkModello(aiProviders[c.provider]!.name, c.model);
  }

  static String _errorText(http.Response r) {
    try {
      final j = jsonDecode(r.body);
      final m = j['error'] is Map ? j['error']['message'] : j['error'] ?? j['message'];
      return S.errore2(r.statusCode, m);
    } catch (_) {
      return S.erroreHttp(r.statusCode);
    }
  }

  static String buildPrompt({required String theme, String? custom, String? comment, required bool regeneration}) {
    final base = StringBuffer()
      ..writeln('You are editing an app launcher icon. Output a single square app icon, centred, PNG.')
      ..writeln('Preserve the identity of the logo: same glyph shape, proportions and recognisable colours.')
      ..writeln(S.doNotAddTextGlow)
      ..writeln(S.theme(theme.isEmpty ? (custom ?? '') : theme));
    if (custom != null && custom.isNotEmpty && theme.isNotEmpty) base.writeln(S.additionalInstructions(custom));
    if (regeneration) {
      base
        ..writeln('The first image is the original icon, the second image is the previous result.')
        ..writeln('Start from the previous result and apply only this change: ${comment?.isNotEmpty == true ? comment : 'improve fidelity to the original logo'}.');
    }
    return base.toString();
  }

  /// Generates a themed icon. [references]: original first, then previous result.
  static Future<Uint8List> generate({required List<Uint8List> references, required String prompt}) async {
    final c = AppState.I.ai;
    final key = await readKey(c.provider);
    if (key == null || key.isEmpty) throw AiException(S.aiNonConfigurataInserisciApi);
    final base = _base(c);
    if (c.provider == AiProviderKind.gemini) {
      final body = {
        'contents': [
          {
            'parts': [
              {'text': prompt},
              for (final r in references) {'inline_data': {'mime_type': 'image/png', 'data': base64Encode(r)}},
            ],
          }
        ],
        'generationConfig': {
          'responseModalities': ['IMAGE', 'TEXT'],
        },
      };
      final r = await http
          .post(Uri.parse('$base/v1beta/models/${c.model}:generateContent'),
              headers: {'x-goog-api-key': key, 'Content-Type': 'application/json'}, body: jsonEncode(body))
          .timeout(const Duration(minutes: 3));
      if (r.statusCode != 200) throw AiException(_errorText(r));
      final j = jsonDecode(r.body);
      for (final cand in (j['candidates'] as List? ?? [])) {
        for (final part in (cand['content']?['parts'] as List? ?? [])) {
          final d = part['inlineData'] ?? part['inline_data'];
          if (d != null && d['data'] != null) return base64Decode(d['data'] as String);
        }
      }
      throw AiException(S.providerNonHaRestituitoImmagine);
    }
    final req = http.MultipartRequest('POST', Uri.parse('$base/v1/images/edits'))
      ..headers['Authorization'] = S.bearer(key)
      ..fields['model'] = c.model
      ..fields['prompt'] = prompt
      ..fields['size'] = '1024x1024'
      ..fields['n'] = '1';
    if (c.model.startsWith('gpt-image')) {
      req.fields['quality'] = c.quality;
      req.fields['background'] = 'transparent';
      req.fields['output_format'] = 'png';
    }
    for (var i = 0; i < references.length; i++) {
      req.files.add(http.MultipartFile.fromBytes(references.length > 1 ? S.image : 'image', references[i], filename: S.refPng(i)));
    }
    final streamed = await req.send().timeout(const Duration(minutes: 3));
    final r = await http.Response.fromStream(streamed);
    if (r.statusCode != 200) throw AiException(_errorText(r));
    final data = (jsonDecode(r.body)['data'] as List?) ?? [];
    if (data.isEmpty) throw AiException(S.providerNonHaRestituitoImmagine);
    final b64 = data.first['b64_json'] as String?;
    if (b64 != null) return base64Decode(b64);
    final url = data.first['url'] as String?;
    if (url != null) {
      final img = await http.get(Uri.parse(url));
      if (img.statusCode == 200) return img.bodyBytes;
    }
    throw AiException(S.rispostaDelProviderSenzaImmagine);
  }
}
