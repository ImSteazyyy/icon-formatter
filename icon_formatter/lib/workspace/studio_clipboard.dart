import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';

/// Image file paths copied as text (one per line, optionally quoted or as
/// file:// URIs). The app has no image clipboard, so only existing files count.
Future<List<String>> clipboardImagePaths() async {
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
