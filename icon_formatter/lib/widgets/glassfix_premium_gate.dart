import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

/// Premium surfaces switch on a few per frame, not all at once. Each one
/// rasterises its geometry synchronously (toImageSync) on its first paint, so
/// a screen of cards switching together stalls the UI thread for seconds.
class GlassPremiumGate {
  /// shortcut: fixed budget, raise it if a phone draws the batches smoothly, lower it if frames still stall
  static const perFrame = 3;

  static final _waiting = <VoidCallback>[];
  static bool _scheduled = false;

  static void request(VoidCallback admit) {
    _waiting.add(admit);
    _schedule();
  }

  static void _schedule() {
    if (_scheduled) return;
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback(_admitBatch);
    WidgetsBinding.instance.scheduleFrame();
  }

  static void _admitBatch(Duration _) {
    _scheduled = false;
    final n = _waiting.length < perFrame ? _waiting.length : perFrame;
    final batch = List<VoidCallback>.of(_waiting.take(n));
    _waiting.removeRange(0, n);
    if (_waiting.isNotEmpty) _schedule();
    for (final admit in batch) {
      admit();
    }
  }
}

/// Hands [builder] the premium quality only once [GlassPremiumGate] admits
/// this surface; until then it draws standard glass.
class GlassStagedQuality extends StatefulWidget {
  const GlassStagedQuality({
    super.key,
    required this.quality,
    required this.builder,
  });

  final GlassQuality quality;
  final Widget Function(GlassQuality quality) builder;

  @override
  State<GlassStagedQuality> createState() => _GlassStagedQualityState();
}

class _GlassStagedQualityState extends State<GlassStagedQuality> {
  bool _ready = false;
  bool _queued = false;

  @override
  void didUpdateWidget(covariant GlassStagedQuality oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.quality != GlassQuality.premium) _ready = false;
  }

  void _admit() {
    _queued = false;
    if (mounted) {
      setState(() => _ready = widget.quality == GlassQuality.premium);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.quality != GlassQuality.premium || _ready) {
      return widget.builder(widget.quality);
    }
    if (!_queued) {
      _queued = true;
      GlassPremiumGate.request(_admit);
    }
    return widget.builder(GlassQuality.standard);
  }
}
