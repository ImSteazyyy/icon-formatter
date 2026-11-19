import 'dart:async';

import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import '../app/models.dart';
import '../app/state.dart';
import 'liquid_glass.dart';

/// Paints one premium glass surface, invisibly and for a single frame, shortly
/// after start, so the premium pipeline is compiled before Qualità is picked.
/// Runs only while another quality is selected: otherwise the real surfaces
/// already draw premium and warm it up themselves.
class GlassWarmUp extends StatefulWidget {
  const GlassWarmUp({super.key});

  @override
  State<GlassWarmUp> createState() => _GlassWarmUpState();
}

class _GlassWarmUpState extends State<GlassWarmUp> {
  // 0 waiting, 1 painting, 2 removed
  int _stage = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer(const Duration(milliseconds: 1500), _start);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _start() {
    if (!mounted) return;
    final g = AppState.I.glass;
    if (!premiumGlassSupported ||
        nothingStyle ||
        g.quality == GlassQualityLevel.quality) {
      setState(() => _stage = 2);
      return;
    }
    setState(() => _stage = 1);
    // the premium paint happens in the frame that shows this widget; remove it right after
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _stage = 2);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_stage != 1) return const SizedBox.shrink();
    return Align(
      alignment: Alignment.topLeft,
      child: SizedBox(
        width: 24,
        height: 24,
        child: IgnorePointer(
          child: Opacity(
            opacity: 0.01,
            child: GlassContainer(
              shape: LiquidRoundedSuperellipse(borderRadius: 6),
              settings: appGlassSettings(),
              useOwnLayer: true,
              quality: GlassQuality.premium,
              child: const SizedBox.expand(),
            ),
          ),
        ),
      ),
    );
  }
}
