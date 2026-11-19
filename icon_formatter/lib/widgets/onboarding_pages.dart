import 'dart:io' show Platform;

import 'package:flutter/material.dart';

import '../app/models.dart';
import '../app/state.dart';
import '../app/theme.dart';
import '../l10n/strings.dart';
import '../services/platform_service.dart';
import '../widgets/common.dart';
import '../widgets/liquid_glass.dart';
import '../widgets/theme_reveal.dart';

enum OnboardingPage { welcome, theme, permissions, language, done }

/// Body of one tour page. Static pages are plain widgets, no blur or shaders.
class OnboardingPageBody extends StatelessWidget {
  const OnboardingPageBody({super.key, required this.page});

  final OnboardingPage page;

  @override
  Widget build(BuildContext context) => switch (page) {
    OnboardingPage.welcome => const _Welcome(),
    OnboardingPage.theme => const _ThemePage(),
    OnboardingPage.permissions => const OnboardingPermissions(),
    OnboardingPage.language => const _LanguagePage(),
    OnboardingPage.done => const _DonePage(),
  };
}

class _PageList extends StatelessWidget {
  const _PageList({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
    children: children,
  );
}

class _Welcome extends StatelessWidget {
  const _Welcome();

  @override
  Widget build(BuildContext context) => _PageList(
    children: [
      const SizedBox(height: 40),
      Center(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: Image.asset(
            'assets/branding/app_icon.png',
            width: 96,
            height: 96,
            filterQuality: FilterQuality.medium,
          ),
        ),
      ),
      const SizedBox(height: 24),
      Text(
        'Icon Formatter',
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 30,
          fontWeight: FontWeight.w700,
          color: Palette.text,
        ),
      ),
      const SizedBox(height: 10),
      Text(
        S.tourBenvenutoSub,
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 16, color: Palette.text2, height: 1.35),
      ),
    ],
  );
}

class _ThemePage extends StatelessWidget {
  const _ThemePage();

  @override
  Widget build(BuildContext context) {
    final st = AppState.I;
    final a = st.appearance;
    void pick(UiStyle v) => ThemeReveal.run(() => st.update(() => a.style = v));
    return _PageList(
      children: [
        LargeHeader(S.stileApp, subtitle: S.tourStileSub),
        Row(
          children: [
            Expanded(
              child: _StyleCard(
                glass: false,
                selected: a.style == UiStyle.nothing,
                label: S.stileNothing,
                desc: S.tourStileNothing,
                onTap: () => pick(UiStyle.nothing),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _StyleCard(
                glass: true,
                selected: a.style == UiStyle.glass,
                label: S.stileVetro,
                desc: S.tourStileVetro,
                onTap: () => pick(UiStyle.glass),
              ),
            ),
          ],
        ),
        const SizedBox(height: 22),
        SectionTitle(S.comodoTema),
        // same choice as Settings; the theme spreads from the touch
        ChoiceRows<ThemeChoice>(
          options: [
            (ThemeChoice.system, S.comodoTemaSistema),
            (ThemeChoice.light, S.comodoTemaChiaro),
            (ThemeChoice.dark, S.comodoTemaScuro),
          ],
          value: a.themeChoice,
          onChanged: (v) => ThemeReveal.run(
            () => st.update(() {
              a.themeChoice = v;
              a.syncLight();
            }),
          ),
        ),
      ],
    );
  }
}

class _StyleCard extends StatelessWidget {
  const _StyleCard({
    required this.glass,
    required this.selected,
    required this.label,
    required this.desc,
    required this.onTap,
  });

  final bool glass;
  final bool selected;
  final String label;
  final String desc;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: selected,
    label: label,
    child: GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Palette.card,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected
                ? Palette.text
                : Palette.text3.withValues(alpha: 0.25),
            width: selected ? 2 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _StyleMock(
              glass: glass,
              accent: Color(AppState.I.appearance.accent),
            ),
            const SizedBox(height: 10),
            Text(
              label,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: Palette.text,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              desc,
              style: TextStyle(fontSize: 12, color: Palette.text2, height: 1.3),
            ),
          ],
        ),
      ),
    ),
  );
}

/// Static drawing of a style: a header, two icon tiles and a pill button.
class _StyleMock extends StatelessWidget {
  const _StyleMock({required this.glass, required this.accent});

  final bool glass;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final tile = glass
        ? Colors.white.withValues(alpha: 0.16)
        : NothingColors.card;
    final ink = glass ? Colors.white : NothingColors.on;
    Widget tileBox(IconData icon) => Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: tile,
        borderRadius: BorderRadius.circular(glass ? 12 : 8),
        border: glass
            ? Border.all(color: Colors.white.withValues(alpha: 0.3))
            : null,
      ),
      child: Icon(icon, size: 18, color: ink),
    );
    return AspectRatio(
      aspectRatio: 1.3,
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: glass ? null : NothingColors.bg,
          gradient: glass
              ? LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    accent.withValues(alpha: 0.85),
                    const Color(0xFF1B1B26),
                  ],
                )
              : null,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 60,
              height: 8,
              decoration: BoxDecoration(
                color: ink,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                tileBox(Icons.apps_rounded),
                const SizedBox(width: 8),
                tileBox(Icons.brush_outlined),
              ],
            ),
            const Spacer(),
            Container(
              width: 56,
              height: 20,
              decoration: BoxDecoration(
                color: glass ? accent : Color(Appearance.nothingRed),
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LanguagePage extends StatelessWidget {
  const _LanguagePage();

  @override
  Widget build(BuildContext context) {
    final st = AppState.I;
    final a = st.appearance;
    return _PageList(
      children: [
        LargeHeader(S.lingua, subtitle: S.tourLinguaSub),
        ChoiceRows<String>(
          options: [
            ('', S.linguaSistema),
            for (final e in appLanguages.entries) (e.key, e.value),
          ],
          value: a.language,
          onChanged: (v) => st.update(() => a.language = v),
        ),
      ],
    );
  }
}

class _DonePage extends StatelessWidget {
  const _DonePage();

  @override
  Widget build(BuildContext context) => _PageList(
    children: [
      LargeHeader(S.tourFineTitolo, subtitle: S.tourFineSub),
      SettingsCard(
        children: [_Tip(S.tourFine1), _Tip(S.tourFine2), _Tip(S.tourFine3)],
      ),
    ],
  );
}

class _Tip extends StatelessWidget {
  const _Tip(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 10),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.check_rounded, size: 18, color: Palette.ok),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: TextStyle(fontSize: 14, color: Palette.text, height: 1.35),
          ),
        ),
      ],
    ),
  );
}

/// Optional permissions, read again when the app comes back to the foreground.
class OnboardingPermissions extends StatefulWidget {
  const OnboardingPermissions({super.key});

  @override
  State<OnboardingPermissions> createState() => _OnboardingPermissionsState();
}

class _OnboardingPermissionsState extends State<OnboardingPermissions>
    with WidgetsBindingObserver {
  bool notif = false;
  String shizuku = 'missing';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (Platform.isAndroid) _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    try {
      final sync = await PlatformService.autoSyncStatus();
      final sh = await PlatformService.shizukuState();
      if (!mounted) return;
      setState(() {
        notif = sync['enabled'] == true;
        shizuku = sh;
      });
    } catch (_) {}
  }

  // same call as the old setup screen: enabling automatic updates asks for notifications
  Future<void> _allowNotif() async {
    try {
      final r = await PlatformService.autoSyncSetEnabled(true);
      if (mounted) setState(() => notif = r['enabled'] == true);
    } catch (_) {}
  }

  String get _shizukuText => switch (shizuku) {
    'granted' => S.dpShizukuOk,
    'denied' => S.dpShizukuNegato,
    'stopped' => S.dpShizukuFermo,
    'old' => S.dpShizukuVecchio,
    _ => S.dpShizukuMancante,
  };

  Widget? get _shizukuAction => switch (shizuku) {
    'stopped' => OutlinedButton(
      onPressed: () => PlatformService.openShizuku(),
      child: Text(S.dpApriShizuku),
    ),
    'denied' => OutlinedButton(
      onPressed: () async {
        await PlatformService.shizukuRequest();
        await _refresh();
      },
      child: Text(S.dpConcedi),
    ),
    _ => null,
  };

  @override
  Widget build(BuildContext context) => _PageList(
    children: [
      LargeHeader(S.tourPermessi, subtitle: S.tourPermSub),
      SettingsCard(
        children: [
          _PermRow(
            icon: Icons.notifications_none_rounded,
            title: S.tourNotifiche,
            desc: S.tourNotificheDesc,
            ok: notif,
            status: notif ? S.tourStatoConcesso : S.tourStatoNonConcesso,
            action: notif
                ? null
                : OutlinedButton(
                    onPressed: _allowNotif,
                    child: Text(S.tourConcedi),
                  ),
          ),
          _PermRow(
            icon: Icons.system_update_alt_rounded,
            title: S.tourSorgenti,
            desc: S.tourSorgentiDesc,
            status: S.tourStatoInfo,
          ),
          _PermRow(
            icon: Icons.terminal_rounded,
            title: S.setupShizuku,
            desc: S.tourShizukuDesc,
            ok: shizuku == 'granted',
            status: _shizukuText,
            action: _shizukuAction,
          ),
        ],
      ),
    ],
  );
}

class _PermRow extends StatelessWidget {
  const _PermRow({
    required this.icon,
    required this.title,
    required this.desc,
    required this.status,
    this.ok = false,
    this.action,
  });

  final IconData icon;
  final String title;
  final String desc;
  final String status;
  final bool ok;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 22, color: Palette.text2),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: Palette.text,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          desc,
          style: TextStyle(fontSize: 13, color: Palette.text2, height: 1.35),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Icon(
              ok ? Icons.check_circle_rounded : Icons.info_outline_rounded,
              size: 16,
              color: ok ? Palette.ok : Palette.text3,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                status,
                style: TextStyle(fontSize: 13, color: Palette.text),
              ),
            ),
            ?action,
          ],
        ),
      ],
    ),
  );
}
