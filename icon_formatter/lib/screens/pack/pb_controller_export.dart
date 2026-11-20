part of 'pb_controller.dart';

/// Export and device apply.
extension PbControllerExport on PackBuilderController {
  /// Android: builds the pack APK on the phone, installs it and (with
  /// Shizuku) selects it in the system launcher. Returns the user message.
  Future<String?> applyOnDevice({String name = 'Icon Formatter Pack', Future<bool> Function()? confirmReplace}) async {
    name = AppState.I.export.packNameOr(name);
    _set(S.dpCompilazione, running: true);
    try {
      final dir = await _buildPackDir(name);
      if (dir == null) {
        _set(S.pbNienteDaEsportare, running: false);
        return null;
      }
      final accent = '#${(AppState.I.export.packAccentOr(AppState.I.appearance.accentColor.toARGB32()) & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';
      var built = await PlatformService.devicePackBuild(dir, name, accent);
      var apk = built['apk'] as String;
      final n = (built['count'] as num).toInt();
      var v = built['version'] as String? ?? '';
      final shizuku = await PlatformService.shizukuState() == 'granted';
      _set(S.dpInstallazione, running: true);
      try {
        try {
          await PlatformService.devicePackInstall(apk, shizuku: shizuku);
        } catch (e) {
          // Android still remembers a newer number of our pack (removed with
          // "keep data", or installed for another user): the native side
          // noted it, one rebuild with the next number installs in place
          if (!'$e'.contains('VERSION_RETRY')) rethrow;
          built = await PlatformService.devicePackBuild(dir, name, accent);
          apk = built['apk'] as String;
          v = built['version'] as String? ?? '';
          await PlatformService.devicePackInstall(apk, shizuku: shizuku);
        }
      } catch (e) {
        // the installed pack was signed on another phone: it cannot be
        // updated in place; replaced only if the user agrees
        if (!'$e'.contains('SIGNATURE_MISMATCH')) rethrow;
        if (confirmReplace == null || !await confirmReplace()) {
          _set(S.dpFirmaDiversa, running: false);
          return S.dpFirmaDiversa;
        }
        _set(S.dpSostituzione, running: true);
        await PlatformService.devicePackUninstall();
        await PlatformService.devicePackInstall(apk, shizuku: shizuku);
      }
      if (!shizuku) {
        _set(S.dpConfermaSistema, running: false);
        return S.dpConfermaSistema;
      }
      final info = await PlatformService.devicePackInfo();
      if (info['launcher'] == null) {
        _set(S.dpInstallato(n, v), running: false);
        return S.dpNoLauncher;
      }
      _set(S.dpApplicazione, running: true);
      final r = await PlatformService.devicePackApply();
      final msg = r['verified'] == true ? S.dpFatto(n, v) : S.dpNonVerificato;
      if (r['verified'] == true) _log(S.packLogApplicato(n, v));
      _set(msg, running: false);
      return msg;
    } catch (e) {
      _set(S.errore(e), running: false);
      rethrow;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  /// Android: builds the pack APK on the phone (signed, not installed) and
  /// opens the share sheet, e.g. to move it to another phone.
  Future<void> shareApk({String name = 'Icon Formatter Pack'}) async {
    name = AppState.I.export.packNameOr(name);
    _set(S.dpCompilazione, running: true);
    try {
      final dir = await _buildPackDir(name);
      if (dir == null) {
        _set(S.pbNienteDaEsportare, running: false);
        return;
      }
      final accent = '#${(AppState.I.export.packAccentOr(AppState.I.appearance.accentColor.toARGB32()) & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';
      final built = await PlatformService.devicePackBuild(dir, name, accent);
      final v = built['version'] as String? ?? '';
      final out = p.join(await AppPaths.I.workDir('share'), 'IconFormatter-Pack-$v.apk');
      await File(built['apk'] as String).copy(out);
      _set(S.pbApkPronto(v), running: false);
      await ExportService.share([out], text: 'Icon Formatter Pack $v');
    } catch (e) {
      _set(S.errore(e), running: false);
      rethrow;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  /// After a hand edit: the pack on the phone is rebuilt and re-applied when
  /// it is installed and Shizuku is ready. Returns the message, or null.
  Future<String?> refreshDevicePack() async {
    if (!Platform.isAndroid) return null;
    final info = await PlatformService.devicePackInfo();
    if (info['installed'] != true || info['shizuku'] != 'granted') return null;
    return applyOnDevice();
  }

  /// [onlyChanged]: only the icons changed since the last export (calendars
  /// are left out, they have no per-icon state).
  Future<ExportResult?> export({required bool zip, bool onlyChanged = false}) async {
    final all = rows.where((r) => !r.excluded && r.generatedId != null).toList();
    final ok = onlyChanged ? all.where(_changedSince).toList() : all;
    if (ok.isEmpty) return null;
    final dir = await AppPaths.I.workDir('iconpack');
    final apps = [...await _packEntries(ok), if (!onlyChanged) ..._calendarApps];
    final res = await buildIconPack(apps: apps, outDir: dir, packName: 'Icon Formatter', zipPath: null);
    final base = onlyChanged ? 'IconFormatter-pack-modificate' : 'IconFormatter-pack';
    // a ZIP is named with the pack name, version and date; a folder keeps its name
    final name = zip ? exportFileName(packName: AppState.I.export.packNameOr(base), version: appVersion, date: DateTime.now(), ext: '') : base;
    final saved = await ExportService.exportDir(res.outDir, name: name, zip: zip);
    if (saved != null) {
      final snap = AppState.I.packExportSnapshot;
      final now = {for (final r in all) r.original.key: _sig(r)};
      var added = 0, changed = 0;
      if (snap != null) {
        for (final e in now.entries) {
          final old = snap[e.key];
          if (old == null) {
            added++;
          } else if (old != e.value) {
            changed++;
          }
        }
      }
      final removed = snap == null ? 0 : snap.keys.where((k) => !now.containsKey(k)).length;
      _log(onlyChanged
          ? S.packLogEsportataSolo(res.icons)
          : snap == null
              ? S.packLogEsportataPrima(res.icons)
              : S.packLogEsportata(res.icons, added, changed, removed));
      final next = onlyChanged ? {...?snap, for (final r in ok) r.original.key: _sig(r)} : now;
      AppState.I.update(() => AppState.I.packExportSnapshot = next);
    }
    _set(S.pbEsportate(res.icons));
    return saved;
  }
}
