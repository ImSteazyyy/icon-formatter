part of '../state.dart';

/// Backup JSON, restore and automatic backup reminders.
extension AppStateBackup on AppState {
  /// Backup file text: look, styles, presets and defaults (no AI settings).
  String backupJson() => const JsonEncoder.withIndent(' ').convert(toJson()..remove('localAi')..remove('backupReminder')..remove('lastSeenBuild')..remove('autoBackupDir')..remove('watchDir')..remove('showFps'));

  void _fromJson(Map<String, dynamic> j) {
    appearance.load((j['appearance'] as Map?)?.cast() ?? {});
    // v1 used the olive/gold accent as default: move untouched defaults to v2
    if ((j['version'] as num? ?? 1) < 2 && appearance.accent == Appearance.legacyAccent) {
      appearance.accent = Appearance.defaultAccent;
    }
    export.load((j['export'] as Map?)?.cast() ?? {});
    glass.load((j['glass'] as Map?)?.cast() ?? {});
    lucent.load((j['lucent'] as Map?)?.cast() ?? {});
    look.load((j['look'] as Map?)?.cast() ?? {});
    // v3: the Lightnt plate is the reference squircle (the clipping edge)
    if ((j['version'] as num? ?? 1) < 3) lucent.shape = LucentShape.squircle;
    localAi.load((j['localAi'] as Map?)?.cast() ?? {});
    final ps = (j['presets'] as List?)?.map((e) => StylePreset.fromJson((e as Map).cast(), defaultTranslucent)).toList();
    if (ps != null && ps.isNotEmpty) {
      // the built-ins come from code (a saved copy keeps its edits); the older
      // built-ins (nothing, liquid, ...) are dropped, their users fall back below
      final builtIns = builtInPresets(defaultTranslucent);
      final saved = {for (final p in ps) p.id: p};
      presets = [
        for (final b in builtIns) saved[b.id] ?? b,
        ...ps.where((p) => !p.builtIn && !builtIns.any((b) => b.id == p.id)),
      ];
    }
    activePresetId = migratePresetId(j['activePresetId'] as String?, presets.map((e) => e.id));
    bases = ((j['bases'] as List?) ?? [])
        .map((e) => BaseIcon.fromJson((e as Map).cast(), defaultPlacement))
        .where((b) => File(b.path).existsSync())
        .toList();
    selectedBaseId = j['selectedBaseId'] as String?;
    segment = segmentFromJson((j['segment'] as Map?)?.cast() ?? {}, defaultSegment);
    packSegment = segmentFromJson((j['packSegment'] as Map?)?.cast() ?? {}, defaultSegment);
    scaleMul = (j['scaleMul'] as num?)?.toDouble() ?? scaleMul;
    offsetX = (j['offsetX'] as num?)?.toDouble() ?? offsetX;
    offsetY = (j['offsetY'] as num?)?.toDouble() ?? offsetY;
    useBaseCalibrationForTranslucent = j['useBaseCalibrationForTranslucent'] as bool? ?? false;
    translucentSize = (j['translucentSize'] as num?)?.toInt() ?? translucentSize;
    threads = (j['threads'] as num?)?.toInt() ?? threads;
    keepCutouts = j['keepCutouts'] as bool? ?? keepCutouts;
    onlineIconsEnabled = j['onlineIconsEnabled'] as bool? ?? false;
    cutoutLimitMb = (j['cutoutLimitMb'] as num?)?.toInt() ?? cutoutLimitMb;
    bgProvider = BgProvider.values.firstWhere((b) => b.name == j['bgProvider'], orElse: () => BgProvider.local);
    autoSendToPack = j['autoSendToPack'] as bool? ?? false;
    setupDone = j['setupDone'] as bool? ?? false;
    packMode = StudioMode.values.firstWhere((m) => m.name == j['packMode'], orElse: () => packMode);
    packPresetId = migratePresetId(j['packPresetId'] as String?, presets.map((e) => e.id));
    processedPackages = ((j['processedPackages'] as List?) ?? []).cast<String>().toSet();
    packCorrections = ((j['packCorrections'] as Map?) ?? {}).map((k, v) => MapEntry(k as String, (v as Map).cast<String, dynamic>()));
    seenGuides = ((j['seenGuides'] as List?) ?? []).cast<String>().toSet();
    tourDone = j['tourDone'] as bool? ?? false;
    final br = (j['backupReminder'] as Map?)?.cast<String, dynamic>() ?? {};
    backupChanges = (br['changes'] as num?)?.toInt() ?? backupChanges;
    lastBackupMs = (br['lastBackupMs'] as num?)?.toInt() ?? lastBackupMs;
    snoozeUntilMs = (br['snoozeUntilMs'] as num?)?.toInt() ?? snoozeUntilMs;
    packLog = ((j['packLog'] as List?) ?? []).cast<Map>().map((e) => e.cast<String, dynamic>()).toList();
    packProfiles = ((j['packProfiles'] as List?) ?? []).cast<Map>().map((e) => e.cast<String, dynamic>()).toList();
    appLists = appListsFromJson(j['appLists']);
    packExportSnapshot = (j['packExportSnapshot'] as Map?)?.cast<String, String>();
    packFingerprints = ((j['packFingerprints'] as Map?) ?? {}).cast<String, String>();
    lastSeenBuild = j['lastSeenBuild'] as String? ?? lastSeenBuild;
    autoBackupDir = j['autoBackupDir'] as String? ?? autoBackupDir;
    checkUpdates = j['checkUpdates'] as bool? ?? true;
    showFps = j['showFps'] as bool? ?? showFps;
    watchDir = j['watchDir'] as String? ?? watchDir;
  }

  Map<String, dynamic> toJson() => {
        'version': 3,
        'appearance': appearance.toJson(),
        'export': export.toJson(),
        'glass': glass.toJson(),
        'lucent': lucent.toJson(),
        'look': look.toJson(),
        'localAi': localAi.toJson(),
        'presets': presets.map((e) => e.toJson()).toList(),
        'activePresetId': activePresetId,
        'bases': bases.map((e) => e.toJson()).toList(),
        'selectedBaseId': selectedBaseId,
        'segment': segmentToJson(segment),
        'packSegment': segmentToJson(packSegment),
        'scaleMul': scaleMul,
        'offsetX': offsetX,
        'offsetY': offsetY,
        'useBaseCalibrationForTranslucent': useBaseCalibrationForTranslucent,
        'translucentSize': translucentSize,
        'threads': threads,
        'keepCutouts': keepCutouts,
        'onlineIconsEnabled': onlineIconsEnabled,
        'cutoutLimitMb': cutoutLimitMb,
        'bgProvider': bgProvider.name,
        'autoSendToPack': autoSendToPack,
      'setupDone': setupDone,
        'packMode': packMode.name,
        'packPresetId': packPresetId,
        'processedPackages': processedPackages.toList(),
        'packCorrections': packCorrections,
        'packLog': packLog,
        'packProfiles': packProfiles,
        'appLists': listsToJson(appLists),
        'packExportSnapshot': packExportSnapshot,
        'packFingerprints': packFingerprints,
        'seenGuides': seenGuides.toList(),
        'tourDone': tourDone,
        'backupReminder': {'changes': backupChanges, 'lastBackupMs': lastBackupMs, 'snoozeUntilMs': snoozeUntilMs},
        'lastSeenBuild': lastSeenBuild,
        'autoBackupDir': autoBackupDir,
        'checkUpdates': checkUpdates,
        'showFps': showFps,
        'watchDir': watchDir,
      };

  /// Backup saved: the reminder starts counting again from zero.
  void markBackupMade() => update(() {
        backupChanges = 0;
        lastBackupMs = DateTime.now().millisecondsSinceEpoch;
        snoozeUntilMs = 0;
      });

  /// "Later": no reminder for seven days.
  void snoozeBackupReminder() => update(() => snoozeUntilMs = DateTime.now().add(const Duration(days: 7)).millisecondsSinceEpoch);

  /// Automatic backup once the reminder threshold is reached. A failure waits
  /// for another full threshold of changes before the next try.
  void _maybeAutoBackup() {
    final dir = autoBackupDir;
    if (dir == null || _autoBackupRunning || backupChanges < kBackupReminderChanges || backupChanges < _autoBackupRetryAt) return;
    _autoBackupRunning = true;
    writeAutoBackup(dir, backupJson()).then((ok) {
      _autoBackupRunning = false;
      if (ok) {
        _autoBackupRetryAt = 0;
        autoBackupFailed.value = false;
        markBackupMade();
      } else {
        _autoBackupRetryAt = backupChanges + kBackupReminderChanges;
        autoBackupFailed.value = true;
      }
    });
  }
}
