import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/state.dart';
import '../app/theme.dart';
import '../l10n/strings.dart';
import 'liquid_glass.dart';

/// Liquid glass panel (Impostazioni › Appearance › Liquid Glass).
class Glass extends StatelessWidget {
  const Glass({super.key, required this.child, this.padding = const EdgeInsets.all(16), this.radius});

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double? radius;

  @override
  Widget build(BuildContext context) =>
      LiquidGlass(radius: radius ?? AppState.I.appearance.radius, padding: padding, chromatic: 0.3, child: child);
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
    if (bytes != null) {
      return Image.memory(bytes!, fit: fit, filterQuality: FilterQuality.medium, gaplessPlayback: true);
    }
    if (path != null) {
      return Image.file(File(path!), fit: fit, filterQuality: FilterQuality.medium, gaplessPlayback: true,
          errorBuilder: (_, _, _) => const Center(child: Icon(Icons.broken_image_outlined, color: Palette.text3)));
    }
    return const SizedBox.shrink();
  }
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
  });

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
      fontSize: 12,
      color: _invalid ? Palette.warn : Palette.text2,
      fontFeatures: const [ui.FontFeature.tabularFigures()],
    );
    return Row(children: [
      SizedBox(width: 118, child: Text(widget.label, style: Theme.of(context).textTheme.bodySmall)),
      Expanded(
        child: Slider(
          value: widget.value.clamp(widget.min, widget.max),
          min: widget.min,
          max: widget.max,
          divisions: widget.divisions,
          onChanged: widget.onChanged,
          onChangeEnd: widget.onChangeEnd,
        ),
      ),
      SizedBox(
        width: 56,
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
                  decoration: const InputDecoration(isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 4, vertical: 6)),
                  onSubmitted: (_) => _commit(),
                  onTapOutside: (_) => _focus.unfocus(),
                ),
              )
            : Tooltip(
                message: S.sliderEditHint,
                child: InkWell(
                  key: const ValueKey('slider-value'),
                  borderRadius: BorderRadius.circular(6),
                  onTap: _start,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
                    child: Text(_f(widget.value), textAlign: TextAlign.right, style: style.copyWith(decoration: TextDecoration.underline, decorationStyle: TextDecorationStyle.dotted)),
                  ),
                ),
              ),
      ),
    ]);
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
  });

  final int done;
  final int total;
  final int errors;
  final bool running;
  final VoidCallback? onCancel;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final v = total == 0 ? 0.0 : done / total;
    return Glass(
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
      ]),
    );
  }
}

void showMsg(BuildContext context, String msg, {bool error = false}) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content: Text(msg),
    backgroundColor: error ? const Color(0xFF3A2422) : null,
    duration: Duration(seconds: error ? 6 : 3),
  ));
}

Future<String?> askText(BuildContext context, String title, {String initial = '', String hint = ''}) async {
  final c = TextEditingController(text: initial);
  return showDialog<String>(
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
  final r = await showDialog<bool>(
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
  return showDialog(
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
class ToolButton extends StatelessWidget {
  const ToolButton({super.key, required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    final enabled = onTap != null;
    return Padding(
      padding: const EdgeInsets.only(right: 8, top: 4, bottom: 4),
      child: LiquidGlass(
        radius: 22,
        chromatic: 0.3,
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
  const GlassIconButton({super.key, required this.icon, required this.onPressed, this.tooltip, this.size = 48});

  final IconData icon;
  final VoidCallback? onPressed;
  final String? tooltip;
  final double size;

  @override
  Widget build(BuildContext context) {
    final b = SizedBox(
      width: size,
      height: size,
      child: LiquidGlass(
        radius: size / 2,
        chromatic: 0.5,
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
