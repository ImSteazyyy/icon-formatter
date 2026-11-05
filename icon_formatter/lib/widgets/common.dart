import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/state.dart';
import '../app/theme.dart';
import '../l10n/strings.dart';
import 'toasts.dart';
import 'liquid_glass.dart';

/// Liquid glass panel (Impostazioni › Appearance › Liquid Glass).
class Glass extends StatelessWidget {
  const Glass({super.key, required this.child, this.padding = const EdgeInsets.all(16), this.radius});

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double? radius;

  @override
  Widget build(BuildContext context) =>
      LiquidGlass(radius: radius ?? AppState.I.appearance.radius, padding: padding, chromatic: 0.3, role: GlassRole.panel, child: child);
}

/// Solid anthracite card for cells of long scrolling grids. A glass panel
/// re-samples (and blurs) what is behind it whenever it moves, so dozens of
/// glass cells make every scroll frame expensive; this surface costs nothing.
class Tile extends StatelessWidget {
  const Tile({super.key, required this.child, this.padding = const EdgeInsets.all(8), this.radius});

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double? radius;

  @override
  Widget build(BuildContext context) => RepaintBoundary(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: const Color(0xFF1C1B20),
            borderRadius: BorderRadius.circular(radius ?? AppState.I.appearance.radius),
            border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
          ),
          child: Padding(padding: padding, child: child),
        ),
      );
}

/// Soft ambient background so the glass panels have something to frost.
class Backdrop extends StatelessWidget {
  const Backdrop({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final accent = AppState.I.appearance.accentColor;
    return DecoratedBox(
      decoration: const BoxDecoration(color: Palette.bg),
      child: Stack(children: [
        Positioned(
          left: -160,
          top: -200,
          child: _Blob(color: accent.withValues(alpha: 0.10), size: 520),
        ),
        Positioned(
          right: -220,
          bottom: -260,
          child: _Blob(color: Colors.white.withValues(alpha: 0.045), size: 640),
        ),
        Positioned.fill(child: child),
      ]),
    );
  }
}

class _Blob extends StatelessWidget {
  const _Blob({required this.color, required this.size});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(shape: BoxShape.circle, gradient: RadialGradient(colors: [color, color.withValues(alpha: 0)])),
      );
}

/// Checkerboard to show real alpha.
class Checkerboard extends StatelessWidget {
  const Checkerboard({super.key, required this.child, this.cell = 10, this.enabled = true});

  final Widget child;
  final double cell;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    if (!enabled) return child;
    return CustomPaint(painter: _CheckerPainter(cell), child: child);
  }
}

class _CheckerPainter extends CustomPainter {
  _CheckerPainter(this.cell);

  final double cell;

  @override
  void paint(Canvas canvas, Size size) {
    final a = Paint()..color = const Color(0xFF2A2A2D);
    final b = Paint()..color = const Color(0xFF1E1E21);
    canvas.drawRect(Offset.zero & size, b);
    for (var y = 0.0; y < size.height; y += cell) {
      for (var x = 0.0; x < size.width; x += cell) {
        if (((x / cell).floor() + (y / cell).floor()).isEven) {
          canvas.drawRect(Rect.fromLTWH(x, y, cell, cell), a);
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _CheckerPainter old) => old.cell != cell;
}

/// Image from bytes or file with filter quality suited to icons.
class IconImage extends StatelessWidget {
  const IconImage({super.key, this.bytes, this.path, this.fit = BoxFit.contain});

  final Uint8List? bytes;
  final String? path;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    if (bytes == null && path == null) return const SizedBox.shrink();
    // decode at the size shown (grids show 512-1024 px icons at ~80 px):
    // far less memory and decoding work while scrolling on phones
    return LayoutBuilder(builder: (context, box) {
      final dpr = MediaQuery.devicePixelRatioOf(context);
      final side = box.biggest.shortestSide;
      final cache = side.isFinite && side > 0 ? (side * dpr).ceil().clamp(32, 2048) : null;
      final Widget img = bytes != null
          ? Image.memory(bytes!, fit: fit, filterQuality: FilterQuality.medium, gaplessPlayback: true, cacheWidth: cache)
          : Image(
              // keyed by path + modification time: a file rewritten in place
              // (re-processing, Rielabora) never shows the old cached pixels
              image: ResizeImage.resizeIfNeeded(cache, null, _VersionedFileImage(File(path!))),
              fit: fit,
              filterQuality: FilterQuality.medium,
              gaplessPlayback: true,
              errorBuilder: (_, _, _) => const Center(child: Icon(Icons.broken_image_outlined, color: Palette.text3)));
      return RepaintBoundary(child: img);
    });
  }
}

class _VersionedFileImage extends FileImage {
  _VersionedFileImage(super.file) : stamp = _stamp(file);
  final int stamp;

  static int _stamp(File f) {
    try {
      return f.lastModifiedSync().microsecondsSinceEpoch ^ f.lengthSync();
    } catch (_) {
      return 0;
    }
  }

  @override
  bool operator ==(Object other) => other is _VersionedFileImage && other.file.path == file.path && other.stamp == stamp && other.scale == scale;

  @override
  int get hashCode => Object.hash(file.path, stamp, scale);
}

/// Before/After comparison with a draggable divider.
class BeforeAfter extends StatefulWidget {
  const BeforeAfter({super.key, required this.before, required this.after, this.checker = true});

  final Widget before;
  final Widget after;
  final bool checker;

  @override
  State<BeforeAfter> createState() => _BeforeAfterState();
}

class _BeforeAfterState extends State<BeforeAfter> {
  double split = 0.5;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final w = c.maxWidth;
      return GestureDetector(
        onHorizontalDragUpdate: (d) => setState(() => split = (split + d.delta.dx / w).clamp(0.0, 1.0)),
        onTapDown: (d) => setState(() => split = (d.localPosition.dx / w).clamp(0.0, 1.0)),
        child: MouseRegion(
          cursor: SystemMouseCursors.resizeLeftRight,
          child: Checkerboard(
            enabled: widget.checker,
            child: Stack(fit: StackFit.expand, children: [
              widget.after,
              ClipRect(clipper: _LeftClip(split), child: widget.before),
              Positioned(
                left: w * split - 1,
                top: 0,
                bottom: 0,
                child: Container(width: 2, color: Colors.white.withValues(alpha: 0.7)),
              ),
              Positioned(left: 8, top: 8, child: _tag(S.prima)),
              Positioned(right: 8, top: 8, child: _tag(S.dopo)),
            ]),
          ),
        ),
      );
    });
  }

  Widget _tag(String t) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.55), borderRadius: BorderRadius.circular(6)),
        child: Text(t, style: const TextStyle(fontSize: 11, color: Palette.text)),
      );
}

class _LeftClip extends CustomClipper<Rect> {
  _LeftClip(this.split);

  final double split;

  @override
  Rect getClip(Size size) => Rect.fromLTWH(0, 0, size.width * split, size.height);

  @override
  bool shouldReclip(covariant _LeftClip old) => old.split != split;
}

/// Labelled slider with value read-out.
class SliderRow extends StatefulWidget {
  const SliderRow({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.min = 0,
    this.max = 1,
    this.format,
    this.onChangeEnd,
    this.divisions,
    this.icon,
  });

  /// Optional accent icon chip on the left (settings pages).
  final IconData? icon;

  final String label;
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;
  final ValueChanged<double>? onChangeEnd;
  final String Function(double)? format;
  final int? divisions;

  @override
  State<SliderRow> createState() => _SliderRowState();
}

/// Display <-> value mapping derived from [SliderRow.format], which is affine
/// in every control of the app (`v*100`, `v*1000`, `round()`, `°`, …).
class SliderNumber {
  SliderNumber(this.format, this.min, this.max, this.divisions);

  final String Function(double) format;
  final double min;
  final double max;
  final int? divisions;

  static double? parse(String s) {
    final m = RegExp(r'-?\d+(?:[.,]\d+)?').firstMatch(s.trim());
    if (m == null) return null;
    return double.tryParse(m.group(0)!.replaceAll(',', '.'));
  }

  double get displayMin => parse(format(min)) ?? min;
  double get displayMax => parse(format(max)) ?? max;

  /// Decimal places shown for [v].
  int decimals(double v) {
    final m = RegExp(r'[.,](\d+)').firstMatch(format(v));
    return m?.group(1)?.length ?? 0;
  }

  String editText(double v) {
    final d = parse(format(v)) ?? v;
    return d.toStringAsFixed(decimals(v)).replaceAll('.', ',');
  }

  /// Value for a typed number, or null when not a number. Out-of-range input
  /// is clamped; [clamped] reports it.
  ({double value, bool clamped})? valueOf(String text) {
    final n = parse(text);
    if (n == null) return null;
    final d0 = displayMin, d1 = displayMax;
    final lo = d0 < d1 ? d0 : d1, hi = d0 < d1 ? d1 : d0;
    final c = n.clamp(lo, hi).toDouble();
    var v = d1 == d0 ? min : min + (c - d0) / (d1 - d0) * (max - min);
    final div = divisions;
    if (div != null && div > 0) {
      final step = (max - min) / div;
      v = min + ((v - min) / step).round() * step;
    }
    return (value: v.clamp(min, max).toDouble(), clamped: c != n);
  }
}

class _SliderRowState extends State<SliderRow> {
  final _ctrl = TextEditingController();
  final _focus = FocusNode();
  bool _editing = false;
  bool _invalid = false;

  String Function(double) get _f => widget.format ?? (v) => (v * 100).round().toString();
  SliderNumber get _num => SliderNumber(_f, widget.min, widget.max, widget.divisions);

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (!_focus.hasFocus && _editing) _commit();
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _start() {
    setState(() {
      _editing = true;
      _invalid = false;
      _ctrl.text = _num.editText(widget.value);
      _ctrl.selection = TextSelection(baseOffset: 0, extentOffset: _ctrl.text.length);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
  }

  void _commit() {
    final r = _num.valueOf(_ctrl.text);
    if (r == null) {
      // not a number: keep the previous value
      _cancel();
      return;
    }
    setState(() {
      _editing = false;
      _invalid = r.clamped;
    });
    widget.onChanged(r.value);
    widget.onChangeEnd?.call(r.value);
    if (r.clamped) {
      Future.delayed(const Duration(milliseconds: 900), () {
        if (mounted) setState(() => _invalid = false);
      });
    }
  }

  void _cancel() {
    setState(() => _editing = false);
    _focus.unfocus();
  }

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      fontSize: 14,
      color: _invalid ? Palette.warn : Palette.text2,
      fontFeatures: const [ui.FontFeature.tabularFigures()],
    );
    final value = SizedBox(
      width: 72,
      child: _editing
          ? CallbackShortcuts(
              bindings: {const SingleActivator(LogicalKeyboardKey.escape): _cancel},
              child: TextField(
                key: const ValueKey('slider-edit'),
                controller: _ctrl,
                focusNode: _focus,
                textAlign: TextAlign.right,
                style: style.copyWith(color: Palette.text),
                keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,\-]'))],
                decoration: const InputDecoration(isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 6, vertical: 6)),
                onSubmitted: (_) => _commit(),
                onTapOutside: (_) => _focus.unfocus(),
              ),
            )
          : Tooltip(
              message: S.sliderEditHint,
              child: InkWell(
                key: const ValueKey('slider-value'),
                borderRadius: BorderRadius.circular(8),
                onTap: _start,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                  child: Text(_f(widget.value), textAlign: TextAlign.right, style: style),
                ),
              ),
            ),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          if (widget.icon != null) ...[IconChip(icon: widget.icon!), const SizedBox(width: 12)],
          Expanded(child: Text(widget.label, style: const TextStyle(fontSize: 15, color: Palette.text))),
          value,
        ]),
        SizedBox(
          height: 34,
          child: Slider(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            value: widget.value.clamp(widget.min, widget.max),
            min: widget.min,
            max: widget.max,
            divisions: widget.divisions,
            onChanged: widget.onChanged,
            onChangeEnd: widget.onChangeEnd,
          ),
        ),
      ]),
    );
  }
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key, this.trailing});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10, top: 4),
        child: Row(children: [
          Expanded(child: Text(text.toUpperCase(), style: Theme.of(context).textTheme.titleSmall?.copyWith(fontSize: 11, letterSpacing: 1.1))),
          ?trailing,
        ]),
      );
}

class StatusDot extends StatelessWidget {
  const StatusDot({super.key, required this.color, this.size = 8});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) =>
      Container(width: size, height: size, decoration: BoxDecoration(color: color, shape: BoxShape.circle));
}

/// Batch progress strip: done / remaining / errors + cancel.
class ProgressStrip extends StatelessWidget {
  const ProgressStrip({
    super.key,
    required this.done,
    required this.total,
    required this.errors,
    required this.running,
    this.onCancel,
    this.label,
    this.onDismiss,
  });

  /// When finished, swiping the strip down (or tapping ×) calls this.
  final VoidCallback? onDismiss;

  final int done;
  final int total;
  final int errors;
  final bool running;
  final VoidCallback? onCancel;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final v = total == 0 ? 0.0 : done / total;
    final closable = !running && onDismiss != null;
    final strip = Glass(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text(
              S.completateRimanentiErrori(label ?? (running ? 'Elaborazione' : 'Completato'), done, total, total - done, errors),
              style: const TextStyle(fontSize: 12, color: Palette.text2),
            ),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(value: v, minHeight: 4, backgroundColor: Colors.white.withValues(alpha: 0.06)),
            ),
          ]),
        ),
        if (running && onCancel != null) ...[
          const SizedBox(width: 12),
          OutlinedButton.icon(onPressed: onCancel, icon: const Icon(Icons.stop_rounded, size: 18), label: const Text(S.annulla)),
        ],
        if (closable) ...[
          const SizedBox(width: 8),
          IconButton(
            key: const ValueKey('progress-close'),
            tooltip: S.scorriGiuPerChiudere,
            icon: const Icon(Icons.close_rounded, size: 18, color: Palette.text2),
            onPressed: onDismiss,
          ),
        ],
      ]),
    );
    if (!closable) return strip;
    // finished: swipe left or right to remove it (like the notices)
    return Dismissible(
      key: const ValueKey('progress-strip'),
      direction: DismissDirection.horizontal,
      onDismissed: (_) => onDismiss!(),
      child: strip,
    );
  }
}

/// Notice at the top of the app (swipe sideways to remove it).
void showMsg(BuildContext context, String msg, {bool error = false, String? actionLabel, VoidCallback? onAction}) {
  Toasts.show(msg, error: error, actionLabel: actionLabel, onAction: onAction);
}

Future<String?> askText(BuildContext context, String title, {String initial = '', String hint = ''}) async {
  final c = TextEditingController(text: initial);
  return showAppDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: TextField(controller: c, autofocus: true, decoration: InputDecoration(hintText: hint), onSubmitted: (v) => Navigator.pop(ctx, v.trim())),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text(S.annulla)),
        FilledButton(onPressed: () => Navigator.pop(ctx, c.text.trim()), child: const Text('OK')),
      ],
    ),
  );
}

Future<bool> confirm(BuildContext context, String title, String body, {String ok = S.conferma}) async {
  final r = await showAppDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(body),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text(S.annulla)),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(ok)),
      ],
    ),
  );
  return r ?? false;
}

/// Full-screen zoomable viewer for one icon.
Future<void> showZoom(BuildContext context, {Uint8List? bytes, String? path, String? title}) {
  return showAppDialog(
    context: context,
    builder: (ctx) => Dialog(
      insetPadding: const EdgeInsets.all(24),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
          child: Row(children: [
            Expanded(child: Text(title ?? S.anteprima, style: Theme.of(ctx).textTheme.titleMedium, overflow: TextOverflow.ellipsis)),
            IconButton(onPressed: () => Navigator.pop(ctx), icon: const Icon(Icons.close)),
          ]),
        ),
        Flexible(
          child: AspectRatio(
            aspectRatio: 1,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Checkerboard(
                cell: 16,
                child: InteractiveViewer(maxScale: 12, child: IconImage(bytes: bytes, path: path)),
              ),
            ),
          ),
        ),
        const Padding(
          padding: EdgeInsets.all(10),
          child: Text(S.rotellaPinchZoomTrascinaSpostare, style: TextStyle(fontSize: 11, color: Palette.text3)),
        ),
      ]),
    ),
  );
}

/// Toolbar action as a liquid glass pill.
/// Marks a subtree that scrolls (cards of long pages): buttons inside it
/// use solid surfaces instead of glass.
class SolidSurfaces extends InheritedWidget {
  const SolidSurfaces({super.key, required super.child});

  @override
  bool updateShouldNotify(SolidSurfaces oldWidget) => false;
}

class ToolButton extends StatelessWidget {
  const ToolButton({super.key, required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    final enabled = onTap != null;
    // inside scrolling cards the pill is solid: moving glass re-captures and
    // blurs its background on every scroll frame
    final solid = context.dependOnInheritedWidgetOfExactType<SolidSurfaces>() != null;
    return Padding(
      padding: const EdgeInsets.only(right: 8, top: 4, bottom: 4),
      child: solid
          ? Material(
              color: Colors.white.withValues(alpha: 0.06),
              shape: StadiumBorder(side: BorderSide(color: Colors.white.withValues(alpha: 0.12))),
              child: InkWell(
                customBorder: const StadiumBorder(),
                onTap: onTap,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(icon, size: 18, color: enabled ? accent : Palette.text3),
                    const SizedBox(width: 8),
                    Text(label, style: TextStyle(fontWeight: FontWeight.w600, color: enabled ? Palette.text : Palette.text3)),
                  ]),
                ),
              ),
            )
          : LiquidGlass(
        radius: 22,
        chromatic: 0.3,
        role: GlassRole.button,
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            customBorder: const StadiumBorder(),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(icon, size: 18, color: enabled ? accent : Palette.text3),
                const SizedBox(width: 8),
                Text(label, style: TextStyle(fontWeight: FontWeight.w600, color: enabled ? Palette.text : Palette.text3)),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

/// Round liquid glass icon button.
class GlassIconButton extends StatelessWidget {
  const GlassIconButton({super.key, required this.icon, required this.onPressed, this.tooltip, this.size = 48, this.label});

  final IconData icon;

  /// With a label the button is a pill "icon + text" (self-explaining).
  final String? label;
  final VoidCallback? onPressed;
  final String? tooltip;
  final double size;

  @override
  Widget build(BuildContext context) {
    if (label != null) {
      return SizedBox(
        height: size,
        child: LiquidGlass(
          radius: size / 2,
          chromatic: 0.5,
          role: GlassRole.button,
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              customBorder: const StadiumBorder(),
              onTap: onPressed,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(icon, color: Colors.white, size: 20),
                  const SizedBox(width: 8),
                  Text(label!, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14)),
                ]),
              ),
            ),
          ),
        ),
      );
    }
    final b = SizedBox(
      width: size,
      height: size,
      child: LiquidGlass(
        radius: size / 2,
        chromatic: 0.5,
        role: GlassRole.button,
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onPressed,
            child: Center(child: Icon(icon, color: Colors.white)),
          ),
        ),
      ),
    );
    return tooltip == null ? b : Tooltip(message: tooltip!, child: b);
  }
}


// ---------------------------------------------------------------- design kit
// Shared building blocks of the dark minimal UI: every screen, menu and
// settings page uses these instead of ad-hoc containers.

/// Accent icon in a soft rounded tile (settings rows, cards, headers).
class IconChip extends StatelessWidget {
  const IconChip({super.key, required this.icon, this.size = 36});

  final IconData icon;
  final double size;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: accent.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(size * 0.3)),
      child: Icon(icon, size: size * 0.56, color: accent),
    );
  }
}

/// Large page title with an optional round glass back button.
class LargeHeader extends StatelessWidget {
  const LargeHeader(this.title, {super.key, this.onBack, this.trailing, this.subtitle});

  final String title;
  final String? subtitle;
  final VoidCallback? onBack;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      // no side inset: titles line up with the cards below
      padding: const EdgeInsets.fromLTRB(0, 8, 0, 14),
      // title and subtitle share one column; the buttons stay on the right,
      // centred on the title block (the subtitle never runs under them)
      child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
        if (onBack != null) ...[
          GlassIconButton(key: const ValueKey('header-back'), icon: Icons.arrow_back_rounded, onPressed: onBack, size: 50, tooltip: S.indietro),
          const SizedBox(width: 16),
        ],
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text(title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w700, letterSpacing: -0.8, color: Palette.text, height: 1.15)),
            if (subtitle != null) ...[
              const SizedBox(height: 4),
              Text(subtitle!, key: const ValueKey('header-subtitle'), style: const TextStyle(fontSize: 13, color: Palette.text2, height: 1.3)),
            ],
          ]),
        ),
        if (trailing != null) ...[const SizedBox(width: 12), trailing!],
      ]),
    );
  }
}

/// Dark card holding a group of settings rows, separated by thin dividers.
class SettingsCard extends StatelessWidget {
  const SettingsCard({super.key, required this.children, this.padding = const EdgeInsets.symmetric(horizontal: 16, vertical: 6)});

  final List<Widget> children;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      if (i > 0) rows.add(Divider(height: 1, thickness: 1, color: Colors.white.withValues(alpha: 0.06)));
      rows.add(Padding(padding: const EdgeInsets.symmetric(vertical: 6), child: children[i]));
    }
    // solid card: settings pages scroll, moving glass would re-blur per frame
    return Tile(
      padding: padding,
      radius: AppState.I.appearance.radius + 6,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: rows),
    );
  }
}

/// Splits a flat list of settings widgets into cards: every [SectionTitle]
/// starts a new card, plain vertical spacers are dropped.
List<Widget> sectioned(List<Widget> items) {
  final out = <Widget>[];
  var group = <Widget>[];
  void flush() {
    if (group.isNotEmpty) {
      out.add(SettingsCard(children: group));
      out.add(const SizedBox(height: 22));
    }
    group = <Widget>[];
  }

  for (final w in items) {
    if (w is SectionTitle) {
      flush();
      out.add(Padding(padding: const EdgeInsets.only(left: 6), child: w));
    } else if (w is SizedBox && w.child == null && w.width == null) {
      continue;
    } else if (w is SettingsCard || w is LargeHeader) {
      flush();
      out.add(w);
      out.add(const SizedBox(height: 22));
    } else {
      group.add(w);
    }
  }
  flush();
  return out;
}

/// Scrollable settings page body: cards from [sectioned], padding for the
/// floating glass bar.
class SettingsList extends StatelessWidget {
  const SettingsList({super.key, required this.children, this.header});

  final List<Widget> children;

  /// Pinned widget kept visible while scrolling (e.g. Liquid Glass preview).
  final Widget? header;

  @override
  Widget build(BuildContext context) {
    final bottom = 24 + GlassInsets.of(context);
    final body = ListView(
      padding: EdgeInsets.fromLTRB(20, header == null ? 4 : 14, 20, bottom),
      children: sectioned(children),
    );
    if (header == null) return body;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(padding: const EdgeInsets.fromLTRB(20, 0, 20, 0), child: header!),
      Expanded(
        // content fades under the sticky preview instead of being covered
        child: ShaderMask(
          shaderCallback: (r) => const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.transparent, Colors.black],
            stops: [0, 0.035],
          ).createShader(r),
          blendMode: BlendMode.dstIn,
          child: body,
        ),
      ),
    ]);
  }
}

/// Toggle row: icon chip, title, optional subtitle, switch.
class SettingSwitch extends StatelessWidget {
  const SettingSwitch({super.key, required this.title, required this.value, required this.onChanged, this.icon, this.subtitle});

  final String title;
  final String? subtitle;
  final IconData? icon;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onChanged == null ? null : () => onChanged!(!value),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(children: [
          if (icon != null) ...[IconChip(icon: icon!), const SizedBox(width: 12)],
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: const TextStyle(fontSize: 15, color: Palette.text)),
              if (subtitle != null) Text(subtitle!, style: const TextStyle(fontSize: 12, color: Palette.text2)),
            ]),
          ),
          const SizedBox(width: 8),
          Switch(value: value, onChanged: onChanged),
        ]),
      ),
    );
  }
}

/// Single-choice list (rows with a check mark on the selected one).
class ChoiceRows<T> extends StatelessWidget {
  const ChoiceRows({super.key, required this.options, required this.value, required this.onChanged});

  final List<(T, String)> options;
  final T value;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return Column(children: [
      for (var i = 0; i < options.length; i++) ...[
        if (i > 0) Divider(height: 1, color: Colors.white.withValues(alpha: 0.06)),
        InkWell(
          onTap: () => onChanged(options[i].$1),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 13),
            child: Row(children: [
              Expanded(
                child: Text(options[i].$2,
                    style: TextStyle(fontSize: 16, color: options[i].$1 == value ? Palette.text : Palette.text2)),
              ),
              if (options[i].$1 == value) Icon(Icons.check_rounded, color: accent),
            ]),
          ),
        ),
      ],
    ]);
  }
}


/// Numbered step of a guided flow (Pack: sorgenti -> icone nuove -> applica).
class StepCard extends StatelessWidget {
  const StepCard({super.key, required this.step, required this.title, this.subtitle, this.children = const [], this.done = false});

  final int step;
  final String title;
  final String? subtitle;
  final List<Widget> children;
  final bool done;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Tile(
        radius: AppState.I.appearance.radius + 6,
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
          Row(children: [
            Container(
              width: 32,
              height: 32,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: done ? accent : accent.withValues(alpha: 0.16), shape: BoxShape.circle),
              child: done
                  ? const Icon(Icons.check_rounded, size: 18, color: Colors.white)
                  : step == 0
                      ? Icon(Icons.memory_rounded, size: 18, color: accent)
                      : Text('$step', style: TextStyle(color: accent, fontWeight: FontWeight.w700)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Palette.text)),
                if (subtitle != null) Text(subtitle!, style: const TextStyle(fontSize: 12, color: Palette.text2)),
              ]),
            ),
          ]),
          if (children.isNotEmpty) ...[
            const SizedBox(height: 10),
            SolidSurfaces(child: Wrap(children: children)),
          ],
        ]),
      ),
    );
  }
}
