import 'setup_screen.dart';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app/models.dart';
import '../app/state.dart';
import '../app/theme.dart';
import '../l10n/strings.dart';
import '../services/diagnostics.dart';
import '../services/extra2_auto_backup.dart';
import '../services/platform_service.dart';
import '../services/update_check.dart';
import '../widgets/common.dart';
import '../widgets/liquid_glass.dart';
import '../widgets/theme_reveal.dart';
import 'settings_whats_new.dart';

/// Automatic backup: the switch asks for a folder; the folder stays until the switch goes off.
class SettingsAutoBackupTile extends StatelessWidget {
  const SettingsAutoBackupTile({super.key});

  Future<void> _pick(BuildContext context) async {
    final dir = await FilePicker.platform.getDirectoryPath(dialogTitle: S.extra2BkAutoCartella);
    if (dir == null) return;
    final ok = await folderWritable(dir);
    if (!context.mounted) return;
    if (ok) {
      AppState.I.update(() => AppState.I.autoBackupDir = dir);
    } else {
      showMsg(context, S.extra2BkAutoNonScrivibile, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppState.I,
      builder: (context, _) {
        final st = AppState.I;
        final dir = st.autoBackupDir;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SettingSwitch(
              key: const ValueKey('settings-auto-backup'),
              icon: Icons.autorenew_rounded,
              title: S.extra2BkAutoTitolo,
              subtitle: S.extra2BkAutoSub,
              value: dir != null,
              onChanged: (v) {
                if (v) {
                  _pick(context);
                } else {
                  st.update(() => st.autoBackupDir = null);
                }
              },
            ),
            if (dir != null)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.folder_outlined),
                title: Text(S.extra2BkAutoCartella),
                subtitle: Text(dir),
                onTap: () => _pick(context),
              ),
          ],
        );
      },
    );
  }
}

/// A newer release found at start: a card at the top of Settings until dismissed.
class SettingsUpdateCard extends StatelessWidget {
  const SettingsUpdateCard({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<UpdateInfo?>(
      valueListenable: AppState.I.newRelease,
      builder: (context, info, _) {
        if (info == null) return const SizedBox.shrink();
        return Column(
          children: [
            Glass(
              key: const ValueKey('settings-update'),
              radius: AppState.I.appearance.radius + 8,
              padding: const EdgeInsets.fromLTRB(16, 8, 4, 8),
              child: Row(children: [
                Icon(Icons.system_update_alt_rounded, size: 22, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 14),
                Expanded(child: Text(S.wireNuovaVersione(info.version), style: TextStyle(fontSize: 14.5, color: Palette.text))),
                TextButton(
                  onPressed: () => launchUrl(Uri.parse(info.url), mode: LaunchMode.externalApplication),
                  child: Text(S.apri),
                ),
                IconButton(
                  tooltip: S.chiudi,
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => AppState.I.newRelease.value = null,
                ),
              ]),
            ),
            const SizedBox(height: 14),
          ],
        );
      },
    );
  }
}

/// Settings > System: the start-up check for a newer release (on by default).
class SettingsUpdateSwitch extends StatelessWidget {
  const SettingsUpdateSwitch({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppState.I,
      builder: (context, _) {
        final st = AppState.I;
        return SettingSwitch(
          key: const ValueKey('settings-check-updates'),
          icon: Icons.system_update_alt_rounded,
          title: S.wireControllaAggiornamenti,
          subtitle: S.wireControllaAggiornamentiSub,
          value: st.checkUpdates,
          onChanged: (v) => st.update(() => st.checkUpdates = v),
        );
      },
    );
  }
}

/// Settings > System: the folder whose new images the Studio imports.
class SettingsWatchFolderTile extends StatelessWidget {
  const SettingsWatchFolderTile({super.key});

  Future<void> _pick(BuildContext context) async {
    final dir = await FilePicker.platform.getDirectoryPath(dialogTitle: S.wireScegliCartella);
    if (dir == null || !context.mounted) return;
    try {
      // usable by dart:io only: Android content paths are refused here
      await Directory(dir).list(followLinks: false).take(1).toList();
      AppState.I.update(() => AppState.I.watchDir = dir);
    } catch (_) {
      if (context.mounted) showMsg(context, S.wireCartellaNonLeggibile, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppState.I,
      builder: (context, _) {
        final dir = AppState.I.watchDir;
        return ListTile(
          key: const ValueKey('settings-watch-dir'),
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.folder_open_rounded),
          title: Text(S.wireCartellaOsservata),
          subtitle: Text(dir ?? S.wireCartellaOsservataSub),
          onTap: () => _pick(context),
          trailing: dir == null
              ? null
              : IconButton(
                  tooltip: S.wireRimuoviCartella,
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => AppState.I.update(() => AppState.I.watchDir = null),
                ),
        );
      },
    );
  }
}

/// "Copia info": a plain-text block for a problem report, on the clipboard.
class SettingsDiagnosticsTile extends StatelessWidget {
  const SettingsDiagnosticsTile({super.key, required this.version});

  final String version;

  Future<void> _copy(BuildContext context) async {
    final st = AppState.I;
    final a = st.appearance;
    final env = Platform.environment;
    String? shizuku;
    bool? pack;
    if (Platform.isAndroid) {
      try {
        shizuku = await PlatformService.shizukuState();
      } catch (_) {}
      try {
        pack = (await PlatformService.activeIconPack()) != null;
      } catch (_) {}
    }
    final text = buildDiagnostics(DiagnosticsInput(
      appVersion: version,
      os: '${Platform.operatingSystem} ${Platform.operatingSystemVersion}',
      locale: '${a.languageCode} / ${WidgetsBinding.instance.platformDispatcher.locale.toLanguageTag()}',
      style: a.style.name,
      theme: '${a.themeChoice.name} (${a.light ? 'light' : 'dark'})',
      glassQuality: st.glass.quality.name,
      threads: st.threads,
      shizuku: shizuku,
      iconPackActive: pack,
      counts: {
        'presets': st.presets.length,
        'bases': st.bases.length,
        'packCorrections': st.packCorrections.length,
        'processedPackages': st.processedPackages.length,
      },
      redact: [for (final k in ['USERNAME', 'USER', 'COMPUTERNAME']) if (env[k] != null) env[k]!],
    ));
    await Clipboard.setData(ClipboardData(text: text));
    if (context.mounted) showMsg(context, S.extra2DiagCopiata);
  }

  @override
  Widget build(BuildContext context) {
    return ListTile(
      key: const ValueKey('settings-diagnostics'),
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.bug_report_outlined),
      title: Text(S.extra2DiagTitolo),
      subtitle: Text(S.extra2DiagSub),
      onTap: () => _copy(context),
    );
  }
}

/// Desktop shortcuts list in Settings › Sistema.
class SettingsShortcutsTile extends StatelessWidget {
  const SettingsShortcutsTile({super.key});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      key: const ValueKey('settings-shortcuts'),
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.keyboard_outlined),
      title: Text(S.extra2ScorTitolo),
      subtitle: Text(S.extra2ScorTileSub),
      onTap: () => showShortcutsSheet(context),
    );
  }
}

/// Light / dark switch used by the Ctrl+Shift+T shortcut (same call as the theme choice).
void toggleLightDark() {
  final st = AppState.I;
  final a = st.appearance;
  ThemeReveal.run(() => st.update(() {
        a.themeChoice = a.light ? ThemeChoice.dark : ThemeChoice.light;
        a.syncLight();
      }));
}

Future<void> showShortcutsSheet(BuildContext context) {
  return showAppSheet<void>(
    context: context,
    builder: (ctx) => Padding(
      padding: const EdgeInsets.fromLTRB(22, 4, 22, 26),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(S.extra2ScorTitolo, style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700, color: Palette.text)),
          const SizedBox(height: 6),
          Text(S.extra2ScorSub, style: TextStyle(fontSize: 13, color: Palette.text2)),
          const SizedBox(height: 14),
          _ShortcutRow(keys: 'Ctrl + 1 … 4', text: S.extra2ScorTab),
          _ShortcutRow(keys: 'Ctrl + ,', text: S.extra2ScorImp),
          _ShortcutRow(keys: 'Ctrl + Shift + T', text: S.extra2ScorTema),
        ],
      ),
    ),
  );
}

class _ShortcutRow extends StatelessWidget {
  const _ShortcutRow({required this.keys, required this.text});

  final String keys;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(
          width: 150,
          child: Text(keys, style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: Palette.text)),
        ),
        Expanded(child: Text(text, style: TextStyle(fontSize: 13.5, color: Palette.text2))),
      ]),
    );
  }
}

/// "Novità" in Settings › Info: reopens the notes of this version.
class SettingsWhatsNewTile extends StatelessWidget {
  const SettingsWhatsNewTile({super.key});

  @override
  Widget build(BuildContext context) {
    final st = AppState.I;
    return Glass(
      key: const ValueKey('settings-whats-new'),
      radius: st.appearance.radius + 8,
      padding: EdgeInsets.zero,
      child: InkWell(
        borderRadius: BorderRadius.circular(st.appearance.radius + 8),
        onTap: () => showWhatsNew(context),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(children: [
            Icon(Icons.new_releases_outlined, size: 26, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 16),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(S.extra2NovitaTitolo, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Palette.text)),
                const SizedBox(height: 2),
                Text(S.extra2NovitaSub, style: TextStyle(fontSize: 13, color: Palette.text2)),
              ]),
            ),
            Icon(Icons.chevron_right_rounded, size: 20, color: Palette.text3),
          ]),
        ),
      ),
    );
  }
}

/// "Rivedi il tour": opens the first-run tour again.
class SettingsTourTile extends StatelessWidget {
  const SettingsTourTile({super.key});

  @override
  Widget build(BuildContext context) {
    final st = AppState.I;
    return Glass(
      key: const ValueKey('settings-tour'),
      radius: st.appearance.radius + 8,
      padding: EdgeInsets.zero,
      child: InkWell(
        borderRadius: BorderRadius.circular(st.appearance.radius + 8),
        onTap: () => OnboardingScreen.show(context),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(children: [
            Icon(Icons.tour_outlined, size: 26, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 16),
            Expanded(child: Text(S.tourRivedi, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Palette.text))),
            Icon(Icons.chevron_right_rounded, size: 20, color: Palette.text3),
          ]),
        ),
      ),
    );
  }
}
