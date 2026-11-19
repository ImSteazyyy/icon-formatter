import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

import '../app/storage.dart';

/// Image files on the clipboard. Windows: the files copied in Explorer and a
/// copied bitmap (screenshot), read by PowerShell, which Flutter cannot do.
/// Other systems: file paths written as text (no image clipboard here).
Future<List<String>> clipboardImagePaths() async {
  if (Platform.isWindows) {
    try {
      return await _windowsClipboard();
    } catch (_) {
      return [];
    }
  }
  final text = (await Clipboard.getData(Clipboard.kTextPlain))?.text ?? '';
  final out = <String>[];
  for (final line in const LineSplitter().convert(text)) {
    var s = line.trim();
    if (s.length >= 2 && s.startsWith('"') && s.endsWith('"')) s = s.substring(1, s.length - 1);
    if (s.startsWith('file://')) s = Uri.tryParse(s)?.toFilePath() ?? s;
    if (s.isNotEmpty && File(s).existsSync()) out.add(s);
  }
  return out;
}

/// Runs in Windows PowerShell with -STA (the clipboard needs it). Output: one
/// path per line. A copied bitmap is saved as PNG in the work folder.
const _windowsScript = r'''
Add-Type -AssemblyName System.Windows.Forms, System.Drawing
try {
  if ([System.Windows.Forms.Clipboard]::ContainsFileDropList()) {
    [System.Windows.Forms.Clipboard]::GetFileDropList() | ForEach-Object { $_ }
  } elseif ([System.Windows.Forms.Clipboard]::ContainsImage()) {
    $img = [System.Windows.Forms.Clipboard]::GetImage()
    $p = Join-Path $env:ICONFORMATTER_DIR ('Appunti_' + [DateTime]::Now.Ticks + '.png')
    $img.Save($p, [System.Drawing.Imaging.ImageFormat]::Png)
    $img.Dispose()
    $p
  }
} catch {}
''';

Future<List<String>> _windowsClipboard() async {
  final dir = await AppPaths.I.workDir('clipboard');
  // -EncodedCommand: UTF-16LE base64, so no quoting of the script is needed
  final bytes = <int>[];
  for (final u in _windowsScript.codeUnits) {
    bytes
      ..add(u & 0xff)
      ..add(u >> 8);
  }
  final r = await Process.run(
    'powershell',
    ['-NoProfile', '-NonInteractive', '-STA', '-EncodedCommand', base64.encode(bytes)],
    environment: {'ICONFORMATTER_DIR': dir},
    stdoutEncoding: utf8,
  ).timeout(const Duration(seconds: 20));
  final out = <String>[];
  for (final line in const LineSplitter().convert(r.stdout as String)) {
    final s = line.trim();
    if (s.isNotEmpty && File(s).existsSync()) out.add(s);
  }
  return out;
}
