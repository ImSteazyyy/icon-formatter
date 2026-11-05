import 'dart:io';

import 'package:flutter/services.dart';

/// App installed on the device (Android only).
class InstalledApp {
  InstalledApp({
    required this.label,
    required this.package,
    required this.activity,
    required this.isSystem,
    required this.isAdaptive,
    required this.hasMonochrome,
  });

  final String label;
  final String package;
  final String activity;
  final bool isSystem;
  final bool isAdaptive;
  final bool hasMonochrome;

  String get key => '$package/$activity';

  static InstalledApp fromMap(Map m) => InstalledApp(
        label: m['label'] as String? ?? '',
        package: m['package'] as String,
        activity: m['activity'] as String? ?? '',
        isSystem: m['isSystem'] as bool? ?? false,
        isAdaptive: m['isAdaptive'] as bool? ?? false,
        hasMonochrome: m['hasMonochrome'] as bool? ?? false,
      );
}

/// Native Android integration (Kotlin, see MainActivity.kt).
class PlatformService {
  static const _ch = MethodChannel('icon_formatter/native');

  static bool get isAndroid => Platform.isAndroid;

  /// Launcher apps visible to this app (queries <intent MAIN/LAUNCHER>).
  static Future<List<InstalledApp>> listApps({bool includeSystem = true}) async {
    final r = await _ch.invokeListMethod<Map>('listApps', {'includeSystem': includeSystem});
    return (r ?? []).map(InstalledApp.fromMap).toList();
  }

  /// PNG icons for apps. When [glyphOnly] is true and the icon is adaptive
  /// with a transparent foreground, only the foreground layer is rendered.
  /// Missing icons come back as null.
  static Future<List<Uint8List?>> getIcons(List<InstalledApp> apps, {int size = 432, bool glyphOnly = true}) async {
    final r = await _ch.invokeListMethod<Object?>('getIcons', {
      'items': apps.map((a) => {'package': a.package, 'activity': a.activity}).toList(),
      'size': size,
      'glyphOnly': glyphOnly,
    });
    return (r ?? []).map((e) => e is Uint8List ? e : null).toList();
  }

  /// Storage Access Framework: lets the user pick a folder. Returns a tree URI.
  static Future<String?> pickTree() => _ch.invokeMethod<String>('pickTree');

  /// Copies the content of a local directory into a SAF tree. Existing names
  /// are never overwritten (a numeric suffix is added). Returns files written.
  static Future<int> writeDirToTree(String treeUri, String srcDir, {String? subfolder}) async =>
      (await _ch.invokeMethod<int>('writeDirToTree', {'treeUri': treeUri, 'srcDir': srcDir, 'subfolder': subfolder})) ?? 0;

  /// Copies a SAF tree into a local folder (used to import folders on Android).
  static Future<int> copyTreeToDir(String treeUri, String destDir) async =>
      (await _ch.invokeMethod<int>('copyTreeToDir', {'treeUri': treeUri, 'destDir': destDir})) ?? 0;

  // ---------------------------------------------------------- automation

  static Future<Map<String, dynamic>> autoSyncStatus() async =>
      ((await _ch.invokeMethod<Map>('autoSyncStatus')) ?? {}).cast<String, dynamic>();

  static Future<Map<String, dynamic>> autoSyncSetEnabled(bool on) async =>
      ((await _ch.invokeMethod<Map>('autoSyncSetEnabled', {'enabled': on})) ?? {}).cast<String, dynamic>();

  static Future<Map<String, dynamic>> autoSyncCheckNow() async =>
      ((await _ch.invokeMethod<Map>('autoSyncCheckNow')) ?? {}).cast<String, dynamic>();

  static Future<void> autoSyncClear([List<String>? components]) => _ch.invokeMethod('autoSyncClear', {'components': components});

  /// "builder" when the app was opened from the change notification.
  static Future<String?> takeLaunchAction() => _ch.invokeMethod<String>('takeLaunchAction');

  static Future<bool> openHomeSettings() async => (await _ch.invokeMethod<bool>('openHomeSettings')) ?? false;
}
