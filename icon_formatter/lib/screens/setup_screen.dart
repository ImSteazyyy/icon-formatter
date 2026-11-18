import 'package:flutter/material.dart';

import '../app/state.dart';
import '../app/theme.dart';
import '../l10n/strings.dart';
import '../services/platform_service.dart';
import '../widgets/common.dart';

/// First launch (Android): language, automatic updates (notification
/// permission) and Shizuku, which stays optional. Shown once.
class SetupScreen extends StatefulWidget {
  const SetupScreen({super.key});

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> with WidgetsBindingObserver {
  String shizuku = 'missing';
  bool autoSync = false;
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

  // back from Shizuku or from the permission screen: read the state again
  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    try {
      final st = await PlatformService.shizukuState();
      final sync = await PlatformService.autoSyncStatus();
      if (!mounted) return;
      setState(() {
        shizuku = st;
        autoSync = sync['enabled'] == true;
      });
    } catch (_) {}
  }

  Future<void> _setAutoSync(bool on) async {
    setState(() => busy = true);
    try {
      final r = await PlatformService.autoSyncSetEnabled(on);
      if (mounted) setState(() => autoSync = r['enabled'] == true);
    } catch (_) {
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  String get _shizukuText => switch (shizuku) {
        'granted' => S.dpShizukuOk,
        'denied' => S.dpShizukuNegato,
        'stopped' => S.dpShizukuFermo,
        'old' => S.dpShizukuVecchio,
        _ => S.dpShizukuMancante,
      };

  @override
  Widget build(BuildContext context) {
    final st = AppState.I;
    final a = st.appearance;
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
          children: [
            Center(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: Image.asset('assets/branding/app_icon.png', width: 88, height: 88, filterQuality: FilterQuality.medium),
              ),
            ),
            const SizedBox(height: 16),
            LargeHeader(S.setupBenvenuto, subtitle: S.setupSub),
            ...sectioned([
              SectionTitle(S.lingua),
              ChoiceRows<String>(
                options: [('', S.linguaSistema), for (final e in appLanguages.entries) (e.key, e.value)],
                value: a.language,
                onChanged: (v) => st.update(() => a.language = v),
              ),
              SectionTitle(S.setupAuto),
              SettingSwitch(
                icon: Icons.notifications_none_rounded,
                title: S.setupAuto,
                subtitle: S.setupAutoSub,
                value: autoSync,
                onChanged: busy ? null : _setAutoSync,
              ),
              SectionTitle(S.setupShizuku),
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text(S.setupShizukuSub, style: TextStyle(fontSize: 13.5, color: Palette.text2, height: 1.35)),
                const SizedBox(height: 10),
                Row(children: [
                  Icon(shizuku == 'granted' ? Icons.check_circle_rounded : Icons.info_outline_rounded,
                      size: 18, color: shizuku == 'granted' ? Palette.ok : Palette.text3),
                  const SizedBox(width: 8),
                  Expanded(child: Text(_shizukuText, style: TextStyle(fontSize: 13, color: Palette.text))),
                ]),
                if (shizuku == 'stopped' || shizuku == 'denied') ...[
                  const SizedBox(height: 12),
                  Row(children: [
                    if (shizuku == 'stopped')
                      Expanded(
                        child: OutlinedButton(onPressed: () => PlatformService.openShizuku(), child: Text(S.dpApriShizuku)),
                      ),
                    if (shizuku == 'denied')
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () async {
                            await PlatformService.shizukuRequest();
                            await _refresh();
                          },
                          child: Text(S.dpConcedi),
                        ),
                      ),
                  ]),
                ],
              ]),
            ]),
            const SizedBox(height: 8),
            FilledButton(
              key: const ValueKey('setup-start'),
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(54)),
              onPressed: () => st.update(() => st.setupDone = true),
              child: Text(S.setupInizia, style: const TextStyle(fontSize: 16)),
            ),
          ],
        ),
      ),
    );
  }
}
