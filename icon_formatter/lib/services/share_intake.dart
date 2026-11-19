import 'dart:io';

import 'package:flutter/services.dart';

const _channel = MethodChannel('icon_formatter/native');

/// Images shared to the app from the Android share sheet. MainActivity copies
/// them to the cache folder; each call returns the new paths once and clears
/// them. Call at start and on resume. Empty list on other platforms or errors.
Future<List<String>> takeSharedImages() async {
  if (!Platform.isAndroid) return const [];
  try {
    return (await _channel.invokeListMethod<String>('takeSharedImages')) ??
        const [];
  } catch (_) {
    return const [];
  }
}
