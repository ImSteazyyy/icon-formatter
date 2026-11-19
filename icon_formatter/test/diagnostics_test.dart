import 'package:flutter_test/flutter_test.dart';
import 'package:icon_formatter/services/diagnostics.dart';

void main() {
  DiagnosticsInput input({String os = 'Windows 11', List<String> redact = const []}) => DiagnosticsInput(
        appVersion: '1.0.0',
        os: os,
        locale: 'it-IT',
        style: 'nothing',
        theme: 'system',
        glassQuality: 'balanced',
        threads: 0,
        counts: const {'bases': 3, 'presets': 2},
        shizuku: null,
        iconPackActive: null,
        redact: redact,
      );

  test('no Windows path or user name leaks into the report', () {
    final text = buildDiagnostics(input(os: r'Windows 11 C:\Users\andre\AppData\Local', redact: const ['andre']));
    expect(text, isNot(contains('andre')));
    expect(text, isNot(contains(r'C:\')));
    expect(text, isNot(contains('Users')));
    expect(text, isNot(contains('AppData')));
    expect(text, contains('[path]'));
  });

  test('unix paths and user names are scrubbed too', () {
    final text = buildDiagnostics(input(os: 'Linux /home/andre/icons', redact: const ['andre']));
    expect(text, isNot(contains('andre')));
    expect(text, isNot(contains('/home')));
  });

  test('report carries versions, settings and counts only', () {
    final text = buildDiagnostics(input());
    expect(text, contains('Icon Formatter 1.0.0'));
    expect(text, contains('Style: nothing'));
    expect(text, contains('Threads: automatic'));
    expect(text, contains('Count bases: 3'));
    expect(text, contains('Count presets: 2'));
    expect(text, isNot(contains('Shizuku')));
    expect(text, isNot(contains('Icon pack active')));
  });

  test('Android fields appear when given', () {
    final text = buildDiagnostics(DiagnosticsInput(
      appVersion: '1.0.0',
      os: 'Android 14',
      locale: 'en',
      style: 'glass',
      theme: 'dark',
      glassQuality: 'quality',
      threads: 4,
      counts: const {},
      shizuku: 'granted',
      iconPackActive: true,
    ));
    expect(text, contains('Threads: 4'));
    expect(text, contains('Shizuku: granted'));
    expect(text, contains('Icon pack active: yes'));
  });
}
