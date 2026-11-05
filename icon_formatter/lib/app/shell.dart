import 'dart:io';

import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import '../screens/ai_screen.dart';
import '../screens/bases_screen.dart';
import '../screens/installed_apps_screen.dart';
import '../screens/pack_builder_screen.dart';
import '../services/platform_service.dart';
import '../screens/pack_screen.dart';
import '../screens/settings_screen.dart';
import '../screens/studio_screen.dart';
import '../widgets/common.dart';
import '../widgets/liquid_glass.dart';
import '../widgets/title_bar.dart';
import 'state.dart';
import 'theme.dart';
import '../l10n/strings.dart';

class _Dest {
  const _Dest(this.id, this.label, this.icon, [this.shortLabel]);

  final String id;
  final String label;
  final IconData icon;
  final String? shortLabel;

  /// Compact label for the phone tab bar.
  String get short => shortLabel ?? label;
}

/// Destinations. "apps" exists only on Android.
List<_Dest> get _dests => [
      const _Dest('studio', S.studio, Icons.auto_awesome_mosaic_outlined),
      const _Dest('ai', S.aiTheme, Icons.auto_awesome_outlined, 'AI'),
      const _Dest('builder', S.pbTitolo, Icons.dashboard_customize_outlined, S.pack),
      if (!Platform.isAndroid) const _Dest('pack', S.packCleanup, Icons.cleaning_services_outlined),
      if (Platform.isAndroid) const _Dest('apps', S.app, Icons.apps_rounded),
      if (!Platform.isAndroid) const _Dest('bases', S.baseIcons, Icons.crop_square_rounded),
      const _Dest('settings', S.impostazioni, Icons.settings_outlined, S.opzioni),
    ];

class Shell extends StatefulWidget {
  const Shell({super.key});

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  int index = 0;
  final _navKey = GlobalKey();
  double _navCovered = 90;
  final _settingsKey = GlobalKey<SettingsScreenState>();
  late final List<_Dest> dests = _dests;
  late final List<Widget> pages;

  @override
  void initState() {
    super.initState();
    if (Platform.isAndroid) {
      // opened from the "icon pack da aggiornare" notification
      PlatformService.takeLaunchAction().then((a) {
        final i = dests.indexWhere((d) => d.id == a);
        if (a != null && i >= 0 && mounted) setState(() => index = i);
      });
    }
    pages = [
      for (final d in dests)
        switch (d.id) {
          'studio' => StudioScreen(onOpenBases: _openBases, onOpenPack: () => _go('builder')),
          'ai' => AiScreen(onOpenSettings: () => _openSettings(SettingsCat.ai)),
          'pack' => PackScreen(onOpenBases: _openBases),
          'builder' => const PackBuilderScreen(),
          'apps' => InstalledAppsScreen(onOpenBases: _openBases),
          'bases' => const BasesScreen(),
          _ => SettingsScreen(key: _settingsKey),
        },
    ];
  }

  void _go(String id) => setState(() => index = dests.indexWhere((d) => d.id == id));

  void _openBases() {
    if (dests.any((d) => d.id == 'bases')) {
      _go('bases');
    } else {
      _openSettings(SettingsCat.bases);
    }
  }

  void _openSettings(SettingsCat c) {
    _go('settings');
    WidgetsBinding.instance.addPostFrameCallback((_) => _settingsKey.currentState?.open(c));
  }

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    final stack = IndexedStack(index: index, children: pages);
    if (Platform.isAndroid && w < 840) {
      // Floating liquid-glass navigation: content scrolls underneath it.
      const navH = 64.0;
      // real height of the floating bar (measured after layout)
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final h = _navKey.currentContext?.size?.height;
        if (h != null && (h - _navCovered).abs() > 0.5 && mounted) setState(() => _navCovered = h);
      });
      final inset = MediaQuery.of(context).viewPadding.bottom;
      final covered = _navCovered + inset;
      final accent = Theme.of(context).colorScheme.primary;
      return Scaffold(
        body: Backdrop(
          child: Stack(children: [
            Positioned.fill(
              child: GlassInsets(bottom: covered, child: SafeArea(bottom: false, child: stack)),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: inset,
              // nav redraws on every settings change (glass, accent, shadows)
              child: ListenableBuilder(listenable: AppState.I, builder: (context, _) => Stack(children: [
                // "Profondità": soft shadow under the floating pill
                if (AppState.I.glass.depth)
                  Positioned(
                    left: 12,
                    right: 12,
                    top: 12,
                    height: navH,
                    child: IgnorePointer(
                      child: DecoratedBox(decoration: BoxDecoration(borderRadius: BorderRadius.circular(navH / 2), boxShadow: glassDepthShadows(navH / 2))),
                    ),
                  ),
                GlassTabBar.bottom(
                key: _navKey,
                barHeight: navH,
                horizontalPadding: 12,
                verticalPadding: 12,
                selectedIndex: index,
                onTabSelected: (i) => setState(() => index = i),
                settings: navGlassSettings(),
                quality: appGlassQuality,
                // dark grey lens tinted with a desaturated pink-lilac accent
                indicatorColor: Color.lerp(const Color(0xFF26252B), HSLColor.fromColor(accent).withSaturation(0.28).toColor(), 0.42)!.withValues(alpha: 0.62),
                selectedIconColor: Color.lerp(Colors.white, accent, 0.22),
                selectedLabelColor: Color.lerp(Colors.white, accent, 0.22),
                unselectedIconColor: const Color(0xFFBDBAC4),
                unselectedLabelColor: const Color(0xFFBDBAC4),
                labelFontSize: 11,
                selectedLabelStyle: TextStyle(fontWeight: FontWeight.w700, shadows: glassTextShadows()),
                unselectedLabelStyle: TextStyle(fontWeight: FontWeight.w600, shadows: glassTextShadows()),
                interactionGlowColor: accent.withValues(alpha: 0.35),
                indicatorSettings: appGlassSettings(dark: true, chromatic: 1.0),
                tabs: [
                  for (final d in dests)
                    GlassTab(icon: Icon(d.icon, shadows: glassTextShadows()), label: d.short),
                ],
              ),
                // glossy rim over the pill (barHeight 64, padding 12)
                const Positioned(
                  left: 12,
                  right: 12,
                  top: 12,
                  height: navH,
                  child: IgnorePointer(child: GlossOverlay(radius: navH / 2, child: SizedBox.expand())),
                ),
              ])),
            ),
          ]),
        ),
      );
    }
    if (Platform.isAndroid) {
      return Scaffold(
        body: Backdrop(
          child: SafeArea(
            child: Row(children: [
              NavigationRail(
                backgroundColor: Colors.transparent,
                selectedIndex: index,
                labelType: NavigationRailLabelType.all,
                onDestinationSelected: (i) => setState(() => index = i),
                destinations: [for (final d in dests) NavigationRailDestination(icon: Icon(d.icon), label: Text(d.label))],
              ),
              Expanded(child: stack),
            ]),
          ),
        ),
      );
    }
    // Windows / desktop: sidebar
    return Scaffold(
      body: Backdrop(
        child: Column(children: [
          const AppTitleBar(),
          Expanded(child: Row(children: [
          Container(
            width: 220,
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 16),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.02),
              border: Border(right: BorderSide(color: Colors.white.withValues(alpha: 0.06))),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const SizedBox(height: 4),
              for (var i = 0; i < dests.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: _SideItem(
                    d: dests[i],
                    selected: i == index,
                    onTap: () => setState(() => index = i),
                  ),
                ),
              const Spacer(),
              ListenableBuilder(
                listenable: AppState.I,
                builder: (context, _) {
                  final b = AppState.I.selectedBase;
                  return Glass(
                    padding: const EdgeInsets.all(10),
                    child: Row(children: [
                      SizedBox(width: 30, height: 30, child: b == null ? const SizedBox() : IconImage(path: b.path)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          const Text(S.baseAttivo, style: TextStyle(fontSize: 10, color: Palette.text3)),
                          Text(b?.name ?? 'nessuno', overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
                        ]),
                      ),
                    ]),
                  );
                },
              ),
            ]),
          ),
          Expanded(child: stack),
          ])),
        ]),
      ),
    );
  }
}

class _SideItem extends StatelessWidget {
  const _SideItem({required this.d, required this.selected, required this.onTap});

  final _Dest d;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: AnimatedContainer(
          duration: Duration(milliseconds: AppState.I.appearance.animations ? 160 : 0),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            color: selected ? accent.withValues(alpha: 0.12) : Colors.transparent,
            border: Border.all(color: selected ? accent.withValues(alpha: 0.35) : Colors.transparent),
          ),
          child: Row(children: [
            Icon(d.icon, size: 19, color: selected ? accent : Palette.text2),
            const SizedBox(width: 12),
            Text(d.label, style: TextStyle(color: selected ? Palette.text : Palette.text2, fontWeight: selected ? FontWeight.w600 : FontWeight.w500)),
          ]),
        ),
      ),
    );
  }
}
