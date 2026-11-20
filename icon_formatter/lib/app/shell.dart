import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;

import '../screens/settings_whats_new.dart';
import '../screens/installed_apps_screen.dart';
import '../screens/pack_builder_screen.dart';
import '../services/platform_service.dart';
import '../services/update_check.dart';
import '../screens/settings_screen.dart';
import '../screens/studio_screen.dart';
import '../widgets/common.dart';
import '../widgets/barfold_geometry.dart';
import '../widgets/liquid_glass.dart';
import '../widgets/tour2_visibility.dart';
import '../widgets/toasts.dart';
import '../widgets/coach_hint.dart';
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

/// Destinations (Android only).
List<_Dest> get _dests => [
  _Dest('studio', S.studio, Icons.auto_awesome_mosaic_outlined),
  _Dest('builder', S.pbTitolo, Icons.dashboard_customize_outlined, S.pack),
  _Dest('apps', S.app, Icons.apps_rounded),
  _Dest('settings', S.impostazioni, Icons.settings_outlined, S.opzioni),
];

class Shell extends StatefulWidget {
  const Shell({super.key});

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> with SingleTickerProviderStateMixin {
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

  /// The one fold timeline (0 open, 1 folded) read by the tab bar, the action
  /// bar and the jump buttons; see barfold_geometry.dart.
  late final AnimationController _fold = AnimationController(vsync: this, duration: const Duration(milliseconds: 380));
  Timer? _foldDebounce;

  /// Moves from the current progress, so a reversal mid-way carries on from there.
  void _runFold(bool fold) {
    final target = fold ? 1.0 : 0.0;
    if (AppState.I.appearance.animations) {
      _fold.animateTo(target, curve: Curves.easeInOutCubic);
    } else {
      _fold.value = target;
    }
  }

  void _setFold(bool fold) {
    _foldDebounce?.cancel();
    if (fold == _wantFold) return;
    _wantFold = fold;
    setState(() => _navFolded = _barsDown = fold);
    _runFold(fold);
  }

  /// A scroll that flips direction for a moment must not reverse the fold: the
  /// new state applies only once it has held for 120 ms.
  void _requestFold(bool fold) {
    if (fold == _wantFold) {
      _foldDebounce?.cancel();
      return;
    }
    if (_foldDebounce?.isActive ?? false) return;
    _foldDebounce = Timer(const Duration(milliseconds: 120), () => _setFold(fold));
  }

  bool _onScroll(UserScrollNotification n) {
    if (n.metrics.axis != Axis.vertical) return false;
    final fold = switch (n.direction) {
      ScrollDirection.reverse => n.metrics.extentAfter > 0,
      ScrollDirection.forward => false,
      ScrollDirection.idle => _wantFold,
    };
    _requestFold(fold);
    return false;
  }

  /// Nothing style bar: a dark blurred pill in the middle, icons only; the
  /// open section sits in a darker circle.
  Widget _nothingNav() {
    const d = 60.0;
    // scrolling down folds the pill into a 50 dp button with the open
    // section (like the Glass bar); tapping it opens the pill again
    return Padding(
      key: _navKey,
      padding: const EdgeInsets.all(12),
      child: LayoutBuilder(
        builder: (context, box) => Align(
          alignment: Alignment.bottomLeft,
          child: AnimatedBuilder(
            animation: _fold,
            builder: (context, clip) => SizedBox(
              width: BarFold.navWidth(_fold.value, box.maxWidth),
              height: BarFold.navHeight(_fold.value),
              child: clip,
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(d),
              child: BackdropFilter(
                filter: ui.ImageFilter.blur(sigmaX: 32, sigmaY: 32),
                child: ColoredBox(
                  color: NothingColors.navPill,
                  // the tabs only once there is room for them
                  child: LayoutBuilder(
                    builder: (context, inner) => inner.maxWidth < 200
                        ? Material(
                            type: MaterialType.transparency,
                            child: InkWell(
                              onTap: () => _setFold(false),
                              // the open section in its own round blob, as in the open
                              // pill (60 in 70 there, 43 in 50 here: same proportion)
                              child: Center(
                                child: Container(
                                  width: 43,
                                  height: 43,
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: AppState.I.appearance.light ? NothingColors.control : NothingColors.card,
                                  ),
                                  child: Icon(dests[index].icon, size: 24, color: Palette.fg, semanticLabel: dests[index].label),
                                ),
                              ),
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

  /// True while the Studio tab is shown (its folder watch runs only then).
  final studioShown = ValueNotifier<bool>(true);
  Timer? _updateTimer;
  static bool _updateScheduled = false;

  /// Android: sections side by side, reachable with a horizontal swipe.
  final _pager = PageController();

  @override
  void initState() {
    super.initState();
    // after the first frame: "What is new" after an update, one message if the automatic backup fails
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) checkWhatsNew(context, appVersion);
    });
    AppState.I.autoBackupFailed.addListener(_onAutoBackupFailed);
    // the tour may request a section before this shell exists (first run)
    requestedTab.addListener(_onRequestedTab);
    WidgetsBinding.instance.addPostFrameCallback((_) => _onRequestedTab());
    // one check per start, a few seconds after the first frame; off = no timer
    if (!_updateScheduled && AppState.I.checkUpdates) {
      _updateScheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _updateTimer = Timer(const Duration(seconds: 3), _checkUpdate);
      });
    }
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
            onOpenApps: () => _go('apps'),
            onShow: () => _go('studio'),
            tabShown: studioShown,
          ),
          'builder' => const PackBuilderScreen(),
          'apps' => InstalledAppsScreen(onOpenBases: _openBases),
          _ => SettingsScreen(key: _settingsKey),
        },
    ];
  }

  void _onRequestedTab() {
    final id = requestedTab.value;
    if (id == null || !mounted) return;
    requestedTab.value = null;
    _go(id);
  }

  @override
  void dispose() {
    requestedTab.removeListener(_onRequestedTab);
    AppState.I.autoBackupFailed.removeListener(_onAutoBackupFailed);
    _updateTimer?.cancel();
    studioShown.dispose();
    _pager.dispose();
    _foldDebounce?.cancel();
    _fold.dispose();
    super.dispose();
  }

  /// Looks for a newer release; the Settings card shows it. Never throws.
  Future<void> _checkUpdate() async {
    if (!AppState.I.checkUpdates) return;
    final info = await checkForUpdate(currentVersion: appVersion);
    if (info != null) AppState.I.newRelease.value = info;
  }

  void _onAutoBackupFailed() {
    if (AppState.I.autoBackupFailed.value && mounted) showMsg(context, S.extra2BkAutoFallito, error: true);
  }

  void _go(String id) => _select(dests.indexWhere((d) => d.id == id));

  /// Selects a section from the bar (or code); the pager follows. Adjacent
  /// sections slide, farther ones jump (no intermediate page is built).
  /// A section change closes the keyboard and the notice on screen.
  void _leaveSection() {
    Toasts.dismiss();
    FocusManager.instance.primaryFocus?.unfocus();
  }

  void _select(int i) {
    if (i < 0) return;
    final from = index;
    _leaveSection();
    setState(() {
      index = i;
      _navFolded = _barsDown = _wantFold = false;
    });
    _foldDebounce?.cancel();
    _runFold(false);
    studioShown.value = dests[i].id == 'studio';
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
    // pages may draw under the status bar ("Your apps" scrolls up under
    // it instead of being cut at the safe area); sideways the neighbours
    // are off screen anyway
    clipBehavior: Clip.none,
    physics: const PageScrollPhysics(parent: ClampingScrollPhysics()),
    onPageChanged: (i) {
      if (i != index) {
        _leaveSection();
        setState(() {
          index = i;
          _navFolded = _barsDown = _wantFold = false;
        });
        _foldDebounce?.cancel();
        _runFold(false);
        studioShown.value = dests[i].id == 'studio';
      }
    },
    children: [for (final p in pages) _KeepAlive(child: p)],
  );

  void _openBases() => _openSettings(SettingsCat.bases);

  void _openSettings(SettingsCat c) {
    _go('settings');
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _settingsKey.currentState?.open(c),
    );
  }

  @override
  Widget build(BuildContext context) {
    // first-run hints float above the bottom bar of the phone layout
    final narrowPhone = Platform.isAndroid && MediaQuery.sizeOf(context).width < 840;
    return CoachHintLayer(
      tabId: dests[index].id,
      bottom: narrowPhone ? _navCovered + MediaQuery.viewPaddingOf(context).bottom : 0,
      child: _shellBody(context),
    );
  }

  Widget _shellBody(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    if (Platform.isAndroid && w < 840) {
      final stack = _pagerView();
      // Floating navigation pill: content scrolls underneath it. Its open
      // height is fixed (12 + 70 + 12); it is set only while the bar is open,
      // since the folded bar is lower and following it made the bars above
      // sink and overlap the bar when it opened again.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        const h = 94.0;
        if (!_navFolded && (h - _navCovered).abs() > 0.5 && mounted) setState(() => _navCovered = h);
        // the notice floats above the bar
        if (mounted) Toasts.bottomInset.value = _navCovered + MediaQuery.viewPaddingOf(context).bottom;
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
                  fold: _fold,
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
                  // nav redraws on every settings change (accent, theme)
                  // the tour owns the screen: the bar fades out while it is open
                  child: ValueListenableBuilder<bool>(
                    valueListenable: tourOpen,
                    builder: (context, open, bar) => IgnorePointer(
                      ignoring: open,
                      child: AnimatedOpacity(
                        opacity: open ? 0 : 1,
                        duration: const Duration(milliseconds: 180),
                        child: bar,
                      ),
                    ),
                    child: ListenableBuilder(
                      listenable: AppState.I,
                      builder: (context, _) => _nothingNav(),
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
    }
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
