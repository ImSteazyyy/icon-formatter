import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/state.dart';
import '../../app/theme.dart';
import '../../l10n/strings.dart';
import '../../services/platform_service.dart';
import '../../widgets/ignored_apps_sheet.dart';
import '../../widgets/refresh_time_row.dart';
import '../../widgets/common.dart';
import '../../widgets/pack_rows.dart';
import '../../widgets/liquid_glass.dart';
import 'pb_controller.dart';

/// Android: automatic change detection and launcher refresh helpers.
class AutoSyncCard extends StatefulWidget {
  const AutoSyncCard({super.key, required this.builder});
  final PackBuilderController builder;

  @override
  State<AutoSyncCard> createState() => _AutoSyncCardState();
}

class _AutoSyncCardState extends State<AutoSyncCard> {
  Map<String, dynamic> st = {};
  bool busy = false;

  @override
  void initState() {
    super.initState();
    _load(PlatformService.autoSyncStatus);
  }

  Future<void> _load(Future<Map<String, dynamic>> Function() f) async {
    setState(() => busy = true);
    try {
      final r = await f();
      if (mounted) setState(() => st = r);
    } catch (e) {
      if (mounted) showMsg(context, S.errore(e), error: true);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  /// Apps the automatic check leaves out; saved on the native side.
  Future<void> _editIgnored() async {
    setState(() => busy = true);
    try {
      final apps = await PlatformService.listApps();
      if (!mounted) return;
      final picked = await showIgnoredAppsSheet(context, current: ((st['ignored'] as List?) ?? const []).cast<String>(), apps: apps);
      if (picked == null || !mounted) return;
      await PlatformService.autoSyncIgnoredSet(picked);
      await _load(PlatformService.autoSyncStatus);
    } catch (e) {
      if (mounted) showMsg(context, S.errore(e), error: true);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  /// "Aggiorna giorno": today's day into the installed pack now.
  Future<void> _refreshCalendar() async {
    setState(() => busy = true);
    try {
      final r = await PlatformService.calendarRefreshNow();
      if (!mounted) return;
      final msg = switch (r['state']) {
        'updated' => S.calAggiornato(r['changed'] ?? 0),
        'current' => S.calGiaOggi,
        'no_shizuku' => S.calServeShizuku,
        'error' => S.errore(r['message'] ?? ''),
        _ => S.calNessuno,
      };
      showMsg(context, msg, error: r['state'] == 'error' || r['state'] == 'no_shizuku');
      await _load(PlatformService.autoSyncStatus);
    } catch (e) {
      if (mounted) showMsg(context, S.errore(e), error: true);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  /// "Check every": the check interval, picked from a short list.
  Future<void> _pickInterval() async {
    final current = (st['intervalHours'] as num?)?.toInt() ?? 6;
    final h = await showAppSheet<int>(
      context: context,
      builder: (ctx) => SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 4, 22, 8),
              child: Align(alignment: Alignment.centerLeft, child: Text(S.asOgni, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: Palette.text))),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 22),
              child: ChoiceRows<int>(options: [for (final v in const [6, 12, 24]) (v, S.asOre(v))], value: current, onChanged: (v) => Navigator.pop(ctx, v)),
            ),
          ],
        ),
      ),
    );
    if (h == null || !mounted) return;
    await _load(() => PlatformService.autoSyncScheduleSet(h, st['onlyCharging'] == true));
  }

  @override
  Widget build(BuildContext context) {
    final pending = ((st['pending'] as List?) ?? []).cast<Map>();
    final last = (st['lastCheck'] as num?)?.toInt() ?? 0;
    final hasCal = (st['calendar'] as Map?)?['has'] == true;
    final ignored = ((st['ignored'] as List?) ?? const []).cast<String>();
    final enabled = st['enabled'] == true;
    final daily = st['calendarDaily'] != false;
    final charging = st['onlyCharging'] == true;
    final interval = (st['intervalHours'] as num?)?.toInt() ?? 6;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(padding: const EdgeInsets.only(left: 6), child: SectionTitle(S.asSezione, top: 0, bottom: 8)),
        SettingsCard(
          children: [
            PackRow(
              icon: Icons.sync_rounded,
              title: S.asControlloAuto,
              subtitle: last == 0 ? S.asMai : S.asUltimo(DateTime.fromMillisecondsSinceEpoch(last).toLocal().toString().substring(0, 16)),
              onTap: busy ? null : () => _load(() => PlatformService.autoSyncSetEnabled(!enabled)),
              trailing: Switch(key: const ValueKey('autosync-switch'), value: enabled, onChanged: busy ? null : (v) => _load(() => PlatformService.autoSyncSetEnabled(v))),
            ),
            PackRow(
              key: const ValueKey('autosync-interval'),
              icon: Icons.timer_outlined,
              title: S.asOgni,
              onTap: busy ? null : _pickInterval,
              trailing: PackValue(S.asOre(interval), chevron: true),
            ),
            PackRow(
              icon: Icons.battery_charging_full_rounded,
              title: S.asSoloInCarica,
              onTap: busy ? null : () => _load(() => PlatformService.autoSyncScheduleSet(interval, !charging)),
              trailing: Switch(key: const ValueKey('autosync-charging'), value: charging, onChanged: busy ? null : (v) => _load(() => PlatformService.autoSyncScheduleSet(interval, v))),
            ),
          ],
        ),
        // the pack has calendar apps: today's day, every morning
        if (hasCal) ...[
          const SizedBox(height: 20),
          Padding(padding: const EdgeInsets.only(left: 6), child: SectionTitle(S.calGiornaliero, top: 0, bottom: 8)),
          SettingsCard(
            children: [
              PackRow(
                icon: Icons.today_rounded,
                title: S.calAggiornamentoGiornaliero,
                subtitle: S.calGiornalieroInfo,
                onTap: busy ? null : () => _load(() => PlatformService.calendarDailySet(!daily)),
                trailing: Switch(key: const ValueKey('calendar-daily-switch'), value: daily, onChanged: busy ? null : (v) => _load(() => PlatformService.calendarDailySet(v))),
              ),
              RefreshTimeRow(status: st, busy: busy, load: _load),
            ],
          ),
        ],
        const SizedBox(height: 12),
        // actions: two to a row, equal; the quiet row of ignored apps below
        ButtonRows(
          children: [
            if (hasCal) ToolButton(key: const ValueKey('calendar-refresh-now'), icon: Icons.today_rounded, label: S.calAggiornaOra, onTap: busy ? null : _refreshCalendar),
            ToolButton(key: const ValueKey('autosync-check'), icon: Icons.refresh_rounded, label: S.asControllaOra, onTap: busy ? null : () => _load(PlatformService.autoSyncCheckNow)),
            if (pending.isNotEmpty && pending.every((m) => m['change'] == 'disinstallata'))
              ToolButton(
                icon: Icons.done_all_rounded,
                label: S.asSegnaViste,
                onTap: busy
                    ? null
                    : () async {
                        await PlatformService.autoSyncClear();
                        await _load(PlatformService.autoSyncStatus);
                      },
              ),
            if (pending.any((m) => m['change'] != 'disinstallata'))
              ToolButton(
                icon: Icons.auto_fix_high_outlined,
                label: S.asRielabora(pending.where((m) => m['change'] != 'disinstallata').length),
                onTap: busy || widget.builder.busy
                    ? null
                    : () async {
                        final comps = pending.where((m) => m['change'] != 'disinstallata').map((m) => m['component'] as String).toSet();
                        await widget.builder.addInstalledComponents(comps);
                        // only the apps the change check named are rendered again
                        await widget.builder.generateFromOriginals(only: widget.builder.rowsOfComponents(comps));
                        await PlatformService.autoSyncClear(pending.map((m) => m['component'] as String).toList());
                        await _load(PlatformService.autoSyncStatus);
                        // with Shizuku the refreshed pack is re-applied right away
                        final info = await PlatformService.devicePackInfo();
                        if (info['shizuku'] == 'granted' && info['installed'] == true) {
                          final msg = await widget.builder.applyOnDevice();
                          if (context.mounted && msg != null) showMsg(context, msg);
                        }
                      },
              ),
          ],
        ),
        const SizedBox(height: 8),
        SettingsCard(
          children: [
            PackRow(
              key: const ValueKey('autosync-ignored'),
              icon: Icons.visibility_off_outlined,
              title: ignored.isEmpty ? S.wireAppIgnorate : S.wireAppIgnorateN(ignored.length),
              onTap: busy ? null : _editIgnored,
              trailing: Icon(Icons.chevron_right_rounded, color: Palette.text3),
            ),
          ],
        ),
        if (pending.isNotEmpty) ...[
          const SizedBox(height: 10),
          for (final m in pending.take(6)) Text('· ${m['label']} — ${m['change']}', style: TextStyle(fontSize: 12, color: Palette.text2)),
          if (pending.length > 6) Text(S.asAltre(pending.length - 6), style: TextStyle(fontSize: 11, color: Palette.text3)),
        ],
      ],
    );
  }
}

/// Android: install the pack and select it in the system launcher through
/// Shizuku (DevicePack.kt). Without Shizuku: system installer + manual pick.
class LauncherApplyCard extends StatefulWidget {
  const LauncherApplyCard({super.key, required this.builder});
  final PackBuilderController builder;

  @override
  State<LauncherApplyCard> createState() => _LauncherApplyCardState();
}

class _LauncherApplyCardState extends State<LauncherApplyCard> with WidgetsBindingObserver {
  Map<String, dynamic> info = {};
  bool busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // changes made in the Shizuku app (start, permission) show up on return
  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    try {
      final r = await PlatformService.devicePackInfo();
      if (!mounted) return;
      setState(() => info = r);
      // the pack was uninstalled since the last look: say so once
      if (r['removed'] == true) showMsg(context, r['selectorReset'] == true ? S.dpRimossoRipristinato : S.dpRimosso);
    } catch (_) {}
  }

  Future<void> _do(Future<String?> Function() f) async {
    setState(() => busy = true);
    try {
      final msg = await f();
      if (mounted && msg != null) showMsg(context, msg);
    } catch (e) {
      if (mounted) showMsg(context, S.errore(e), error: true);
    } finally {
      if (mounted) setState(() => busy = false);
      await _refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    final sh = info['shizuku'] as String? ?? 'missing';
    final launcher = info['launcher'];
    final installed = info['version'] != null;
    final (stateText, stateColor, stateIcon) = switch (sh) {
      'granted' => (S.dpShizukuOk, Palette.ok, Icons.check_circle_outline_rounded),
      'denied' => (S.dpShizukuPermesso, Palette.warn, Icons.warning_amber_rounded),
      'stopped' => (S.dpShizukuNonAttivo, Palette.warn, Icons.warning_amber_rounded),
      'old' => (S.dpShizukuVecchioBreve, Palette.danger, Icons.warning_amber_rounded),
      _ => (S.dpShizukuNonInstallato, Palette.text2, Icons.info_outline_rounded),
    };
    final hasRows = widget.builder.rows.any((r) => !r.excluded && r.generatedId != null);
    final working = busy || widget.builder.busy;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Tile(
        key: const ValueKey('launcher-apply-card'),
        radius: AppState.I.appearance.radius + 6,
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // header like the other step cards: centred, number badge and title
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 32,
                  height: 32,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: Palette.selection.withValues(alpha: 0.16), shape: BoxShape.circle),
                  child: Text('3', style: TextStyle(color: Palette.text, fontWeight: FontWeight.w700)),
                ),
                const SizedBox(width: 12),
                Flexible(child: Text(S.dpTitolo, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Palette.text))),
              ],
            ),
            const SizedBox(height: 14),
            // status rows: Shizuku, pack, launcher; the icon says ok or attention
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
              decoration: BoxDecoration(color: Palette.fg.withValues(alpha: 0.05), borderRadius: BorderRadius.circular(14)),
              child: Column(
                children: [
                  PackRow(key: const ValueKey('shizuku-state'), icon: stateIcon, iconColor: stateColor, title: stateText),
                  Divider(height: 1, thickness: 1, color: Palette.fg.withValues(alpha: 0.06)),
                  PackRow(
                    icon: installed ? Icons.check_circle_outline_rounded : Icons.info_outline_rounded,
                    iconColor: installed ? Palette.ok : Palette.text2,
                    title: S.dpInfoPack,
                    trailing: PackMuted(installed ? S.dpInfoVersione(info['version']) : S.dpInfoNonInstallato),
                  ),
                  Divider(height: 1, thickness: 1, color: Palette.fg.withValues(alpha: 0.06)),
                  PackRow(
                    icon: launcher != null ? Icons.check_circle_outline_rounded : Icons.warning_amber_rounded,
                    iconColor: launcher != null ? Palette.ok : Palette.warn,
                    title: S.dpInfoLauncher,
                    trailing: PackMuted(launcher ?? S.dpInfoNonTrovato),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            if (info['state'] == 'residual') ...[
              const SizedBox(height: 6),
              Text(
                S.dpResiduo(info['residualVersion']),
                key: const ValueKey('dp-residual'),
                style: TextStyle(fontSize: 12, color: Palette.warn),
              ),
            ],
            const SizedBox(height: 10),
            WideColumn(
              children: [
                if (sh == 'granted')
                  FilledButton.icon(
                    key: const ValueKey('dp-apply'),
                    icon: const Icon(Icons.auto_awesome_outlined, size: 18),
                    label: Text(S.dpApplica),
                    onPressed: working || !hasRows
                        ? null
                        : () => _do(() => widget.builder.applyOnDevice(confirmReplace: () => confirm(context, S.dpSostituireTitolo, S.dpSostituireTesto, ok: S.dpSostituisci))),
                  )
                else
                  FilledButton.tonalIcon(
                    key: const ValueKey('dp-install'),
                    icon: const Icon(Icons.download_rounded, size: 18),
                    label: Text(S.dpSoloInstalla),
                    onPressed: working || !hasRows
                        ? null
                        : () => _do(() => widget.builder.applyOnDevice(confirmReplace: () => confirm(context, S.dpSostituireTitolo, S.dpSostituireTesto, ok: S.dpSostituisci))),
                  ),
                if (sh == 'denied') OutlinedButton(onPressed: PlatformService.shizukuRequest, child: Text(S.dpConcedi)),
                if (sh == 'stopped' || sh == 'old') OutlinedButton(onPressed: PlatformService.openShizuku, child: Text(S.dpApriShizuku)),
                if (sh == 'granted' && info['state'] == 'residual')
                  OutlinedButton.icon(
                    key: const ValueKey('dp-cleanup'),
                    icon: const Icon(Icons.cleaning_services_outlined, size: 18),
                    label: Text(S.dpPulisciResidui),
                    onPressed: working ? null : () => _do(() async => await PlatformService.devicePackCleanup() ? S.dpResiduiPuliti : S.dpResiduiRimasti),
                  ),
                if (sh == 'granted' && info['installed'] == true)
                  OutlinedButton(onPressed: working ? null : () => _do(() async => S.dpRipristinato(await PlatformService.devicePackRestore())), child: Text(S.dpRipristina)),
                TextButton(
                  onPressed: () async {
                    if (!await PlatformService.openLauncherPicker()) await PlatformService.openHomeSettings();
                  },
                  child: Text(S.dpScegliManuale),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
