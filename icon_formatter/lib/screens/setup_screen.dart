import 'dart:io' show Platform;

import 'package:flutter/material.dart';

import '../app/state.dart';
import '../app/theme.dart';
import '../l10n/strings.dart';
import '../widgets/onboarding_pages.dart';

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
  final _controller = PageController();
  int _index = 0;

  // the permissions page only exists on Android
  List<OnboardingPage> get _pages => [
    OnboardingPage.welcome,
    OnboardingPage.theme,
    if (Platform.isAndroid) OnboardingPage.permissions,
    OnboardingPage.language,
    OnboardingPage.done,
  ];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _go(int i) => _controller.animateToPage(
    i,
    duration: const Duration(milliseconds: 280),
    curve: Curves.easeOut,
  );

  // setupDone also covers "Salta": the tour is never shown again
  void _finish() {
    AppState.I.update(() => AppState.I.setupDone = true);
    if (widget.replay && mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final pages = _pages;
    final last = _index == pages.length - 1;
    // rebuilt on every change so a new style or theme shows at once
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
                          padding: const EdgeInsets.only(right: 8),
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
                  onPageChanged: (i) => setState(() => _index = i),
                  itemBuilder: (_, i) => OnboardingPageBody(page: pages[i]),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                child: Row(
                  children: [
                    Expanded(
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
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (var i = 0; i < pages.length; i++)
                          Container(
                            width: 8,
                            height: 8,
                            margin: const EdgeInsets.symmetric(horizontal: 4),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: i == _index
                                  ? Palette.text
                                  : Palette.text3.withValues(alpha: 0.35),
                            ),
                          ),
                      ],
                    ),
                    Expanded(
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: FilledButton(
                          key: const ValueKey('tour-next'),
                          style: FilledButton.styleFrom(
                            minimumSize: const Size(128, 50),
                          ),
                          onPressed: last ? _finish : () => _go(_index + 1),
                          child: Text(
                            last ? S.tourInizia : S.tourAvanti,
                            style: const TextStyle(fontSize: 16),
                          ),
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
