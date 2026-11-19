import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:icon_formatter/services/update_check.dart';

http.Response _release(String tag, {String body = '', int status = 200}) =>
    http.Response(
      jsonEncode({
        'tag_name': tag,
        'html_url': 'https://example.com/r',
        'body': body,
      }),
      status,
    );

void main() {
  group('isNewer', () {
    test('compares numbers, not text', () {
      expect(isNewer('v1.0.1', '1.0.0'), isTrue);
      expect(isNewer('1.0.0', '1.0.1'), isFalse);
      expect(isNewer('1.10.0', '1.9.0'), isTrue);
      expect(isNewer('2.0.0', '1.9.9+10002'), isTrue);
    });

    test('missing parts count as zero', () {
      expect(isNewer('1.0', '1.0.0'), isFalse);
      expect(isNewer('1.0.0', '1.0'), isFalse);
      expect(isNewer('1.0.1', '1'), isTrue);
    });

    test('build number after + breaks ties', () {
      expect(isNewer('1.0.0', '1.0.0+10002'), isFalse);
      expect(isNewer('1.0.0+10003', '1.0.0+10002'), isTrue);
      expect(isNewer('1.0.0+10002', '1.0.0+10003'), isFalse);
      expect(isNewer('v1.0.0+10002', '1.0.0+10002'), isFalse);
    });

    test('pre-releases are older than the release', () {
      expect(isNewer('1.1.0-beta.1', '1.0.0'), isTrue);
      expect(isNewer('1.0.0', '1.0.0-rc.1'), isTrue);
      expect(isNewer('1.0.0-rc.1', '1.0.0'), isFalse);
      expect(isNewer('1.0.0-rc.2', '1.0.0-rc.1'), isTrue);
    });

    test('garbage is never newer', () {
      expect(isNewer('garbage', '1.0.0'), isFalse);
      expect(isNewer('', '1.0.0'), isFalse);
    });
  });

  group('checkForUpdate', () {
    setUp(clearUpdateCacheForTests);

    test('returns a newer release with notes cut to 600 characters', () async {
      final client = MockClient(
        (_) async => _release('v1.1.0', body: 'x' * 700),
      );
      final u = await checkForUpdate(
        currentVersion: '1.0.0+10002',
        client: client,
      );
      expect(u?.version, '1.1.0');
      expect(u?.url, 'https://example.com/r');
      expect(u?.notes.length, 600);
    });

    test('null when the release is not newer', () async {
      final client = MockClient((_) async => _release('v1.0.0'));
      expect(
        await checkForUpdate(currentVersion: '1.0.0+10002', client: client),
        isNull,
      );
    });

    test('null on error, bad status or bad body, never throws', () async {
      expect(
        await checkForUpdate(
          currentVersion: '1.0.0',
          client: MockClient((_) async => throw Exception('offline')),
        ),
        isNull,
      );
      expect(
        await checkForUpdate(
          currentVersion: '1.0.0',
          client: MockClient((_) async => _release('v2.0.0', status: 500)),
        ),
        isNull,
      );
      expect(
        await checkForUpdate(
          currentVersion: '1.0.0',
          client: MockClient((_) async => http.Response('<html>', 200)),
        ),
        isNull,
      );
    });

    test('a release is cached in memory: no second request', () async {
      var calls = 0;
      final first = MockClient((_) async {
        calls++;
        return _release('v2.0.0');
      });
      await checkForUpdate(currentVersion: '1.0.0', client: first);
      final second = MockClient((_) async {
        calls++;
        return _release('v3.0.0');
      });
      final u = await checkForUpdate(currentVersion: '1.0.0', client: second);
      expect(calls, 1);
      expect(u?.version, '2.0.0');
    });

    test('failed requests are not cached', () async {
      await checkForUpdate(
        currentVersion: '1.0.0',
        client: MockClient((_) async => _release('', status: 500)),
      );
      final u = await checkForUpdate(
        currentVersion: '1.0.0',
        client: MockClient((_) async => _release('v2.0.0')),
      );
      expect(u?.version, '2.0.0');
    });
  });
}
