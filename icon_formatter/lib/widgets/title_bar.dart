import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../app/theme.dart';
import '../l10n/strings.dart';

/// Custom Windows title bar (the native caption is hidden): drag area,
/// double-click to maximise, and minimise / maximise / close buttons.
class AppTitleBar extends StatefulWidget {
  const AppTitleBar({super.key});

  static const height = 38.0;

  @override
  State<AppTitleBar> createState() => _AppTitleBarState();
}

class _AppTitleBarState extends State<AppTitleBar> with WindowListener {
  bool maximized = false;
  bool focused = true;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    windowManager.isMaximized().then((v) => mounted ? setState(() => maximized = v) : null);
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  @override
  void onWindowMaximize() => setState(() => maximized = true);

  @override
  void onWindowUnmaximize() => setState(() => maximized = false);

  @override
  void onWindowFocus() => setState(() => focused = true);

  @override
  void onWindowBlur() => setState(() => focused = false);

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: AppTitleBar.height,
      child: Row(children: [
        Expanded(
          child: DragToMoveArea(
            child: Container(
              color: Colors.transparent,
              padding: const EdgeInsets.only(left: 14),
              child: Row(children: [
                Image.asset('assets/branding/app_icon.png', width: 18, height: 18, filterQuality: FilterQuality.medium),
                const SizedBox(width: 10),
                Text(
                  S.iconFormatter,
                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: focused ? Palette.text : Palette.text3, letterSpacing: 0.2),
                ),
              ]),
            ),
          ),
        ),
        _CaptionButton(icon: Icons.remove_rounded, tooltip: S.riduciIcona, onTap: windowManager.minimize),
        _CaptionButton(
          icon: maximized ? Icons.filter_none_rounded : Icons.crop_square_rounded,
          iconSize: maximized ? 13 : 15,
          tooltip: maximized ? S.ripristina : S.ingrandisci,
          onTap: () async => maximized ? windowManager.unmaximize() : windowManager.maximize(),
        ),
        _CaptionButton(icon: Icons.close_rounded, tooltip: S.chiudi, danger: true, onTap: windowManager.close),
      ]),
    );
  }
}

class _CaptionButton extends StatefulWidget {
  const _CaptionButton({required this.icon, required this.tooltip, required this.onTap, this.danger = false, this.iconSize = 16});

  final IconData icon;
  final String tooltip;
  final Future<void> Function() onTap;
  final bool danger;
  final double iconSize;

  @override
  State<_CaptionButton> createState() => _CaptionButtonState();
}

class _CaptionButtonState extends State<_CaptionButton> {
  bool hover = false;
  bool down = false;

  @override
  Widget build(BuildContext context) {
    final bg = widget.danger
        ? (hover ? const Color(0xFFC42B1C).withValues(alpha: down ? 0.8 : 1) : Colors.transparent)
        : Colors.white.withValues(alpha: hover ? (down ? 0.05 : 0.09) : 0);
    return Tooltip(
      message: widget.tooltip,
      waitDuration: const Duration(milliseconds: 800),
      child: MouseRegion(
        onEnter: (_) => setState(() => hover = true),
        onExit: (_) => setState(() {
          hover = false;
          down = false;
        }),
        child: GestureDetector(
          onTapDown: (_) => setState(() => down = true),
          onTapCancel: () => setState(() => down = false),
          onTap: () {
            setState(() => down = false);
            widget.onTap();
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            width: 46,
            height: AppTitleBar.height,
            color: bg,
            child: Icon(widget.icon, size: widget.iconSize, color: hover && widget.danger ? Colors.white : Palette.text2),
          ),
        ),
      ),
    );
  }
}
