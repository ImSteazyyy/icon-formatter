import 'dart:io' show Platform;

import 'package:flutter/material.dart';

import '../app/state.dart';
import '../app/theme.dart';
import '../l10n/strings.dart';
import '../services/platform_service.dart';
import '../widgets/common.dart';

enum OnboardingPage { permissions, language, done }

/// Body of one tour page. Static pages are plain widgets, no blur or shaders.
class OnboardingPageBody extends StatelessWidget {
  const OnboardingPageBody({super.key, required this.page, this.onStep});

  final OnboardingPage page;

  /// Called with a section id when a step of the last page is tapped.
  final ValueChanged<String>? onStep;

  // No const instances here: a const page would keep its old texts after the
  // language changes, because Flutter skips rebuilding identical widgets.
  @override
  Widget build(BuildContext context) => switch (page) {
    OnboardingPage.permissions => OnboardingPermissions(),
    OnboardingPage.language => _LanguagePage(),
    OnboardingPage.done => _DonePage(onStep: onStep ?? (_) {}),
  };
}

/// One tour page: the content is centred in the free height and scrolls
/// only when the screen is too short for it, so nothing overflows.
class _TourPage extends StatelessWidget {
  const _TourPage({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) => SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: box.maxHeight - 16),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: children,
            ),
          ),
        ),
      ),
    ),
  );
}

/// The illustration area of a page: a soft card holding one drawing.
class _ArtCard extends StatelessWidget {
  const _ArtCard({required this.child, this.height = 180});

  final Widget child;
  final double height;

  @override
  Widget build(BuildContext context) => Container(
    height: height,
    alignment: Alignment.center,
    margin: const EdgeInsets.only(bottom: 24),
    decoration: BoxDecoration(
      color: Palette.card,
      borderRadius: BorderRadius.circular(32),
      border: Border.all(color: Palette.text3.withValues(alpha: 0.18)),
    ),
    child: child,
  );
}

class _LanguagePage extends StatelessWidget {
  const _LanguagePage();

  @override
  Widget build(BuildContext context) {
    final st = AppState.I;
    final a = st.appearance;
    return _TourPage(
      children: [
        _ArtCard(
          height: 140,
          child: Icon(Icons.translate_rounded, size: 64, color: Palette.text2),
        ),
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

/// Last page: three concrete first steps. Each one closes the tour and opens
/// its section (Studio twice, then Pack).
class _DonePage extends StatelessWidget {
  const _DonePage({required this.onStep});

  final ValueChanged<String> onStep;

  @override
  Widget build(BuildContext context) => _TourPage(
    children: [
      _ArtCard(
        height: 120,
        child: Icon(Icons.check_circle_rounded, size: 64, color: Palette.ok),
      ),
      LargeHeader(S.tourFineTitolo, subtitle: S.ux1a2PassiSub),
      SettingsCard(
        children: [
          _StepRow(
            key: const ValueKey('tour-step-studio'),
            number: 1,
            text: S.ux1a2Step1,
            onTap: () => onStep('studio'),
          ),
          _StepRow(
            key: const ValueKey('tour-step-process'),
            number: 2,
            text: S.ux1a2Step2(S.elaboraTutte),
            onTap: () => onStep('studio'),
          ),
          _StepRow(
            key: const ValueKey('tour-step-pack'),
            number: 3,
            text: S.ux1a2Step3,
            onTap: () => onStep('builder'),
          ),
        ],
      ),
    ],
  );
}

/// One tappable first step: number, text and a chevron.
class _StepRow extends StatelessWidget {
  const _StepRow({
    super.key,
    required this.number,
    required this.text,
    required this.onTap,
  });

  final int number;
  final String text;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    borderRadius: BorderRadius.circular(12),
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          CircleAvatar(
            radius: 13,
            backgroundColor: Palette.text.withValues(alpha: 0.08),
            child: Text(
              '$number',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: Palette.text,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: TextStyle(fontSize: 15, color: Palette.text),
            ),
          ),
          Icon(Icons.chevron_right_rounded, color: Palette.text3),
        ],
      ),
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
  Widget build(BuildContext context) => _TourPage(
    children: [
      _ArtCard(
        height: 140,
        child: Icon(
          Icons.verified_user_outlined,
          size: 64,
          color: Palette.text2,
        ),
      ),
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
