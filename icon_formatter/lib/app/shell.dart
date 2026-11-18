import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;

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
  _Dest('studio', S.studio, Icons.auto_awesome_mosaic_outlined),
  _Dest('builder', S.pbTitolo, Icons.dashboard_customize_outlined, S.pack),
  if (!Platform.isAndroid)
    _Dest('pack', S.packCleanup, Icons.cleaning_services_outlined),
  if (Platform.isAndroid) _Dest('apps', S.app, Icons.apps_rounded),
  if (!Platform.isAndroid)
    _Dest('bases', S.baseIcons, Icons.crop_square_rounded),
  _Dest('settings', S.impostazioni, Icons.settings_outlined, S.opzioni),
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

  /// Scrolling down folds the bar into two round buttons (the current
  /// section and Opzioni); scrolling up or tapping the section unfolds it.
  bool _navFolded = false;

  /// The floating action bars sit low, next to the folded button. They move
  /// together with the tab bar (see FloatingBarSlot for the timing that
  /// keeps the two apart).
  bool _barsDown = false;
  bool _wantFold = false;

  void _setFold(bool fold) {
    if (fold == _wantFold) return;
    _wantFold = fold;
    setState(() => _navFolded = _barsDown = fold);
  }

  bool _onScroll(UserScrollNotification n) {
    if (n.metrics.axis != Axis.vertical) return false;
    final fold = switch (n.direction) {
      ScrollDirection.reverse => n.metrics.extentAfter > 0,
      ScrollDirection.forward => false,
      ScrollDirection.idle => _wantFold,
    };
    _setFold(fold);
    return false;
  }

  /// Glass style bar: the glass package's tab bar with its own material and
  /// indicator; scrolling down it shrinks to the open tab, liquid-like.
  Widget _glassNav() => appGlassTabBar(
    key: _navKey,
    icons: [for (final d in dests) d.icon],
    labels: [for (final d in dests) d.label],
    index: index,
    onSelect: _select,
    minimized: _navFolded,
    onExpand: () => _setFold(false),
  );

  /// Nothing style bar: a dark blurred pill in the middle, icons only; the
  /// open section sits in a darker circle.
  Widget _nothingNav() {
    const d = 60.0;
    // scrolling down folds the pill into a 50 dp button with the open
    // section (like the Glass bar); tapping it opens the pill again
    final folded = _navFolded;
    return Padding(
      key: _navKey,
      padding: const EdgeInsets.all(12),
      child: LayoutBuilder(
        builder: (context, box) => Align(
          alignment: Alignment.bottomLeft,
          child: AnimatedContainer(
            duration: Duration(milliseconds: AppState.I.appearance.animations ? 340 : 0),
            curve: Curves.easeInOutCubic,
            width: folded ? 50 : box.maxWidth,
            height: folded ? 50 : d + 10,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(d),
              child: BackdropFilter(
                filter: ui.ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                child: ColoredBox(
                  color: NothingColors.navPill,
                  // the tabs only once there is room for them
                  child: LayoutBuilder(
                    builder: (context, inner) => inner.maxWidth < 200
                        ? Material(
                            type: MaterialType.transparency,
                            child: InkWell(
                              onTap: () => _setFold(false),
                              child: Center(child: Icon(dests[index].icon, color: Palette.fg, semanticLabel: dests[index].label)),
                            ),
                          )
                        : Padding(
                            padding: const EdgeInsets.all(5),
                            child: _BlobTabs(
                              index: index,
                              size: d,
                              animate: AppState.I.appearance.animations,
                              icons: [for (final x in dests) x.icon],
                              labels: [for (final x in dests) x.label],
                              onTap: _select,
                            ),
                          ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  final _settingsKey = GlobalKey<SettingsScreenState>();
  late final List<_Dest> dests = _dests;
  late final List<Widget> pages;

  /// Android: sections side by side, reachable with a horizontal swipe.
  final _pager = PageController();

  @override
  void initState() {
    super.initState();
    if (Platform.isAndroid) {
      // opened from the "icon pack da aggiornare" notification
      PlatformService.takeLaunchAction().then((a) {
        final i = dests.indexWhere((d) => d.id == a);
        if (a != null && i >= 0 && mounted) _select(i);
      });
    }
    pages = [
      for (final d in dests)
        switch (d.id) {
          'studio' => StudioScreen(
            onOpenBases: _openBases,
            onOpenPack: () => _go('builder'),
            onOpenApps: Platform.isAndroid ? () => _go('apps') : null,
          ),
          'pack' => PackScreen(onOpenBases: _openBases),
          'builder' => const PackBuilderScreen(),
          'apps' => InstalledAppsScreen(onOpenBases: _openBases),
          'bases' => const BasesScreen(),
          _ => SettingsScreen(key: _settingsKey),
        },
    ];
  }

  @override
  void dispose() {
    _pager.dispose();
    super.dispose();
  }

  void _go(String id) => _select(dests.indexWhere((d) => d.id == id));

  /// Selects a section from the bar (or code); the pager follows. Adjacent
  /// sections slide, farther ones jump (no intermediate page is built).
  void _select(int i) {
    if (i < 0) return;
    final from = index;
    setState(() {
      index = i;
      _navFolded = _barsDown = _wantFold = false;
    });
    if (!_pager.hasClients) return;
    if ((i - from).abs() == 1 && AppState.I.appearance.animations) {
      _pager.animateToPage(
        i,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
      );
    } else {
      _pager.jumpToPage(i);
    }
  }

  /// Swipeable sections; each one is kept alive (no reload when coming back).
  Widget _pagerView() => PageView(
    controller: _pager,
    // pages may draw under the status bar ("Le tue app" scrolls up under
    // it instead of being cut at the safe area); sideways the neighbours
    // are off screen anyway
    clipBehavior: Clip.none,
    physics: const PageScrollPhysics(parent: ClampingScrollPhysics()),
    onPageChanged: (i) {
      if (i != index) {
        setState(() {
          index = i;
          _navFolded = _barsDown = _wantFold = false;
        });
      }
    },
    children: [for (final p in pages) _KeepAlive(child: p)],
  );

  void _openBases() {
    if (dests.any((d) => d.id == 'bases')) {
      _go('bases');
    } else {
      _openSettings(SettingsCat.bases);
    }
  }

  void _openSettings(SettingsCat c) {
    _go('settings');
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _settingsKey.currentState?.open(c),
    );
  }

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    final stack = IndexedStack(index: index, children: pages);
    if (Platform.isAndroid && w < 840) {
      final stack = _pagerView();
      // Floating liquid-glass navigation: content scrolls underneath it.
      // real height of the floating bar (measured after layout)
      WidgetsBinding.instance.addPostFrameCallback((_) {
        var h = _navKey.currentContext?.size?.height;
        // measured only while the bar is open: the folded bar is lower, and
        // following it made the bars above sink and overlap the bar when it
        // opened again
        // Nothing pill: its open height is fixed (12 + 70 + 12)
        if (nothingStyle) h = 94;
        if (!_navFolded && h != null && (h - _navCovered).abs() > 0.5 && mounted)
          setState(() => _navCovered = h!);
      });
      final inset = MediaQuery.of(context).viewPadding.bottom;
      final covered = _navCovered + inset;
      return Scaffold(
        // the keyboard slides over the page instead of squeezing it: the
        // floating bars stay at the bottom, under the keyboard, and never
        // jump up over the search field and filters
        resizeToAvoidBottomInset: false,
        body: Backdrop(
          child: Stack(
            children: [
              Positioned.fill(
                child: GlassInsets(
                  bottom: covered,
                  folded: _barsDown,
                  child: NotificationListener<UserScrollNotification>(
                    onNotification: _onScroll,
                    child: SafeArea(bottom: false, child: stack),
                  ),
                ),
              ),
              // typing (search): the keyboard owns the bottom, the bar steps aside
              if (MediaQuery.viewInsetsOf(context).bottom == 0)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: inset,
                  // nav redraws on every settings change (glass, accent, shadows)
                  child: ListenableBuilder(
                    listenable: AppState.I,
                    builder: (context, _) =>
                        nothingStyle ? _nothingNav() : _glassNav(),
                  ),
                ),
            ],
          ),
        ),
      );
    }
    if (Platform.isAndroid) {
      final stack = _pagerView();
      return Scaffold(
        body: Backdrop(
          child: SafeArea(
            child: Row(
              children: [
                NavigationRail(
                  backgroundColor: Colors.transparent,
                  selectedIndex: index,
                  labelType: NavigationRailLabelType.all,
                  onDestinationSelected: _select,
                  destinations: [
                    for (final d in dests)
                      NavigationRailDestination(
                        icon: Icon(d.icon),
                        label: Text(d.label),
                      ),
                  ],
                ),
                Expanded(child: stack),
              ],
            ),
          ),
        ),
      );
    }
    // Windows / desktop: sidebar
    return Scaffold(
      body: Backdrop(
        child: Column(
          children: [
            const AppTitleBar(),
            Expanded(
              child: Row(
                children: [
                  Container(
                    width: 220,
                    padding: const EdgeInsets.fromLTRB(14, 8, 14, 16),
                    decoration: BoxDecoration(
                      color: Palette.fg.withValues(alpha: 0.02),
                      border: Border(
                        right: BorderSide(
                          color: Palette.fg.withValues(alpha: 0.06),
                        ),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
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
                              child: Row(
                                children: [
                                  SizedBox(
                                    width: 30,
                                    height: 30,
                                    child: b == null
                                        ? const SizedBox()
                                        : IconImage(path: b.path),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          S.baseAttivo,
                                          style: TextStyle(
                                            fontSize: 10,
                                            color: Palette.text3,
                                          ),
                                        ),
                                        Text(
                                          b?.label ?? '—',
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(fontSize: 12),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                  Expanded(child: stack),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SideItem extends StatelessWidget {
  const _SideItem({
    required this.d,
    required this.selected,
    required this.onTap,
  });

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
          duration: Duration(
            milliseconds: AppState.I.appearance.animations ? 160 : 0,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            color: selected
                ? accent.withValues(alpha: 0.12)
                : Colors.transparent,
            border: Border.all(
              color: selected
                  ? accent.withValues(alpha: 0.35)
                  : Colors.transparent,
            ),
          ),
          child: Row(
            children: [
              Icon(d.icon, size: 19, color: selected ? accent : Palette.text2),
              const SizedBox(width: 12),
              Text(
                d.label,
                style: TextStyle(
                  color: selected ? Palette.text : Palette.text2,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _KeepAlive extends StatefulWidget {
  const _KeepAlive({required this.child});
  final Widget child;

  @override
  State<_KeepAlive> createState() => _KeepAliveState();
}

class _KeepAliveState extends State<_KeepAlive>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}

/// Nothing style tabs: the dark circle of the open section travels to the
/// next one as a drop, its front edge leaving first and the back catching up,
/// so it stretches into a pill and settles back into a circle.
class _BlobTabs extends StatefulWidget {
  const _BlobTabs({
    required this.index,
    required this.size,
    required this.animate,
    required this.icons,
    required this.labels,
    required this.onTap,
  });

  final int index;
  final double size;
  final bool animate;
  final List<IconData> icons;
  final List<String> labels;
  final ValueChanged<int> onTap;

  @override
  State<_BlobTabs> createState() => _BlobTabsState();
}

class _BlobTabsState extends State<_BlobTabs>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 460),
    value: 1,
  );
  late double _from = widget.index.toDouble();
  late double _to = widget.index.toDouble();

  /// Edges of the blob in tab units at animation time [t].
  (double, double) _edges(double t) {
    final lead = Curves.easeOutCubic.transform(t);
    final trail = Curves.easeInOutCubic.transform(
      ((t - 0.18) / 0.82).clamp(0.0, 1.0),
    );
    final a = _from + (_to - _from) * lead;
    final b = _from + (_to - _from) * trail;
    return (a < b ? a : b, a < b ? b : a);
  }

  @override
  void didUpdateWidget(_BlobTabs old) {
    super.didUpdateWidget(old);
    if (old.index == widget.index) return;
    // starts from where the blob is now, even mid-way
    final (l, r) = _edges(_c.value);
    _from = (l + r) / 2;
    _to = widget.index.toDouble();
    if (widget.animate) {
      _c.forward(from: 0);
    } else {
      _c.value = 1;
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.size;
    return LayoutBuilder(
      builder: (context, box) {
        // tabs share the bar's width; the blob is a circle in the middle of one
        final w = box.maxWidth.isFinite
            ? box.maxWidth / widget.icons.length
            : d;
        return SizedBox(
          width: w * widget.icons.length,
          height: d,
          child: AnimatedBuilder(
            animation: _c,
            builder: (context, _) {
              final (l, r) = _edges(_c.value);
              final stretch = r - l;
              // a stretched drop gets a little thinner
              final h = d * (1 - 0.12 * stretch.clamp(0.0, 1.0));
              return Stack(
                children: [
                  Positioned(
                    left: l * w + 2,
                    width: w - 4 + stretch * w,
                    top: (d - h) / 2,
                    height: h,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        // light: a grey blob, a white one vanished on the white pill
                        color: AppState.I.appearance.light ? NothingColors.control : NothingColors.card,
                        borderRadius: BorderRadius.circular(d),
                      ),
                    ),
                  ),
                  Row(
                    children: [
                      for (var i = 0; i < widget.icons.length; i++)
                        Tooltip(
                          message: widget.labels[i],
                          child: Semantics(
                            selected: i == widget.index,
                            button: true,
                            label: widget.labels[i],
                            child: InkResponse(
                              onTap: () => widget.onTap(i),
                              radius: d / 2,
                              child: SizedBox(
                                width: w,
                                height: d,
                                child: Icon(
                                  widget.icons[i],
                                  size: 27,
                                  color: i == widget.index
                                      ? Palette.fg
                                      : Palette.text2,
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }
}
