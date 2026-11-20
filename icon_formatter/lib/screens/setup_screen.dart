import 'dart:io' show Platform;

import 'package:flutter/material.dart';

import '../app/state.dart';
import '../app/theme.dart';
import '../l10n/strings.dart';
import '../widgets/onboarding_pages.dart';
import '../widgets/tour2_visibility.dart';

/// First-run tour, also reopened from Settings. Shown once: [AppState.setupDone]
/// decides. Pages are built lazily by the PageView.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key, this.replay = false});

  /// Opened from Settings: finishing pops back instead of leaving the first-run home.
  final bool replay;

  /// Opens the tour again on top of the app.
  static Future<void> show(BuildContext context) => Navigator.of(context).push(
    MaterialPageRoute(builder: (_) => const OnboardingScreen(replay: true)),
  );

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  // a language change rebuilds the whole app (new key on MaterialApp), so the
  // page is remembered here and the tour comes back on the same page
  static int _lastIndex = 0;
  late final _controller = PageController(initialPage: _lastIndex);
  late int _index = _lastIndex;

  // the permissions page only exists on Android
  List<OnboardingPage> get _pages => [
    if (Platform.isAndroid) OnboardingPage.permissions,
    OnboardingPage.language,
    OnboardingPage.done,
  ];

  @override
  void initState() {
    super.initState();
    // after the frame: the shell must not be notified while it is building
    WidgetsBinding.instance.addPostFrameCallback((_) => tourOpen.value = true);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.addPostFrameCallback((_) => tourOpen.value = false);
    _controller.dispose();
    super.dispose();
  }

  void _go(int i) => _controller.animateToPage(
    i,
    duration: const Duration(milliseconds: 380),
    curve: Curves.easeOutCubic,
  );

  // setupDone also covers "Salta": the tour is never shown again
  void _finish() {
    _lastIndex = 0;
    AppState.I.update(() => AppState.I.setupDone = true);
    if (widget.replay && mounted) Navigator.of(context).pop();
  }

  /// A first step of the last page: finish the tour, then open its section.
  void _finishTo(String tab) {
    _finish();
    requestedTab.value = tab;
  }

  @override
  Widget build(BuildContext context) {
    final pages = _pages;
    final last = _index == pages.length - 1;
    // rebuilt on every change so a new theme shows at once
    return ListenableBuilder(
      listenable: AppState.I,
      builder: (context, _) => Scaffold(
        body: SafeArea(
          child: Column(
            children: [
              SizedBox(
                height: 48,
                child: Align(
                  alignment: Alignment.centerRight,
                  child: last
                      ? const SizedBox.shrink()
                      : Padding(
                          padding: const EdgeInsets.only(right: 12),
                          child: TextButton(
                            onPressed: _finish,
                            child: Text(S.tourSalta),
                          ),
                        ),
                ),
              ),
              Expanded(
                child: PageView.builder(
                  controller: _controller,
                  itemCount: pages.length,
                  onPageChanged: (i) => setState(() => _lastIndex = _index = i),
                  // gentle slide and fade: each page follows the swipe position
                  itemBuilder: (_, i) => AnimatedBuilder(
                    animation: _controller,
                    child: OnboardingPageBody(page: pages[i], onStep: _finishTo),
                    builder: (context, child) {
                      final p = _controller.hasClients
                          ? (_controller.page ?? _index.toDouble())
                          : _index.toDouble();
                      final d = (i - p).clamp(-1.0, 1.0);
                      return Opacity(
                        opacity: 1 - d.abs() * 0.6,
                        child: Transform.translate(
                          offset: Offset(d * 28, 0),
                          child: child,
                        ),
                      );
                    },
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // dots centred; "Indietro" quiet on the left, same height
                    SizedBox(
                      height: 40,
                      child: Row(
                        children: [
                          SizedBox(
                            width: 110,
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: _index == 0
                                  ? const SizedBox.shrink()
                                  : TextButton(
                                      onPressed: () => _go(_index - 1),
                                      child: Text(S.tourIndietro),
                                    ),
                            ),
                          ),
                          Expanded(
                            child: Center(
                              child: _Dots(count: pages.length, index: _index),
                            ),
                          ),
                          const SizedBox(width: 110),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: FilledButton(
                        key: const ValueKey('tour-next'),
                        onPressed: last ? _finish : () => _go(_index + 1),
                        child: Text(
                          last ? S.tourInizia : S.tourAvanti,
                          style: const TextStyle(fontSize: 16),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Page position: the current dot stretches into a pill and animates its width.
class _Dots extends StatelessWidget {
  const _Dots({required this.count, required this.index});

  final int count;
  final int index;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      for (var i = 0; i < count; i++)
        AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOutCubic,
          width: i == index ? 22 : 8,
          height: 8,
          margin: const EdgeInsets.symmetric(horizontal: 3),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(4),
            color: i == index
                ? Palette.text
                : Palette.text3.withValues(alpha: 0.35),
          ),
        ),
    ],
  );
}
