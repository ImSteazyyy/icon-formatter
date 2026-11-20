import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:icon_formatter/services/pack_online_icons.dart';

/// Fake provider: records the packages it was asked for, never touches the network.
class _FakeProvider implements OnlineIconProvider {
  _FakeProvider({this.on = true});

  final bool on;
  final List<String> asked = [];

  @override
  String get name => 'fake';

  @override
  bool get enabled => on;

  @override
  Future<Uint8List?> fetchPng(String package) async {
    asked.add(package);
    return Uint8List.fromList([137, 80, 78, 71]);
  }
}

void main() {
  test('an enabled provider returns its icon for one valid package', () async {
    final p = _FakeProvider();
    final s = OnlineIconService(p);
    final png = await s.fetchForUserAction('com.example.app');
    expect(png, isNotNull);
    expect(p.asked, ['com.example.app']);
  });

  test('a disabled provider is never called', () async {
    final p = _FakeProvider(on: false);
    final s = OnlineIconService(p);
    expect(await s.fetchForUserAction('com.example.app'), isNull);
    expect(p.asked, isEmpty);
  });

  test('invalid package names are rejected before any request', () async {
    final p = _FakeProvider();
    final s = OnlineIconService(p);
    for (final bad in ['', 'nodots', 'com..example', 'com.example/../x', 'com.example?q=1', ' com.example']) {
      expect(await s.fetchForUserAction(bad), isNull, reason: bad);
    }
    expect(p.asked, isEmpty);
  });

  test('requests are throttled: a second tap inside the gap is ignored', () async {
    var now = DateTime(2026, 1, 1, 12);
    final p = _FakeProvider();
    final s = OnlineIconService(p, clock: () => now, minGap: const Duration(seconds: 2));
    expect(await s.fetchForUserAction('com.a.one'), isNotNull);
    now = now.add(const Duration(seconds: 1));
    expect(await s.fetchForUserAction('com.a.two'), isNull);
    now = now.add(const Duration(seconds: 2));
    expect(await s.fetchForUserAction('com.a.three'), isNotNull);
    expect(p.asked, ['com.a.one', 'com.a.three']);
  });

  test('the Play listing provider ships disabled and refuses to fetch', () async {
    const p = PlayListingIconProvider();
    expect(p.enabled, isFalse);
    expect(await OnlineIconService(p).fetchForUserAction('com.example.app'), isNull);
    expect(() => p.fetchPng('com.example.app'), throwsA(isA<OnlineIconException>()));
  });
}
