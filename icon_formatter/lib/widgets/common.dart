import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../app/state.dart';
import '../app/theme.dart';
import 'liquid_glass.dart';

/// Frosted glass panel driven by the Appearance settings.
class Glass extends StatelessWidget {
  const Glass({super.key, required this.child, this.padding = const EdgeInsets.all(16), this.radius, this.blur = true});

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double? radius;
  final bool blur;

  @override
  Widget build(BuildContext context) {
    final a = AppState.I.appearance;
    if (a.liquid) {
      return LiquidGlass(radius: radius ?? a.radius, padding: padding, chromatic: 0.3, child: child);
    }
    final r = BorderRadius.circular(radius ?? a.radius);
    final fill = 0.025 + a.brightness * 0.05 + (1 - a.transparency) * 0.06;
    final panel = Container(
      padding: padding,
      decoration: BoxDecoration(
        borderRadius: r,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white.withValues(alpha: fill + a.reflections * 0.05),
            Colors.white.withValues(alpha: fill * 0.6 + a.frosting * 0.02),
          ],
        ),
        border: Border.all(color: Colors.white.withValues(alpha: 0.03 + a.borders * 0.09)),
      ),
      child: withGlassShadows(child),
    );
    if (!blur || a.blur <= 0.5) return ClipRRect(borderRadius: r, child: panel);
    return ClipRRect(
      borderRadius: r,
      child: BackdropFilter(filter: ui.ImageFilter.blur(sigmaX: a.blur, sigmaY: a.blur), child: panel),
    );
  }
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
              Positioned(left: 8, top: 8, child: _tag('Prima')),
              Positioned(right: 8, top: 8, child: _tag('Dopo')),
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
class SliderRow extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final f = format ?? (v) => (v * 100).round().toString();
    return Row(children: [
      SizedBox(width: 118, child: Text(label, style: Theme.of(context).textTheme.bodySmall)),
      Expanded(
        child: Slider(
          value: value.clamp(min, max),
          min: min,
          max: max,
          divisions: divisions,
          onChanged: onChanged,
          onChangeEnd: onChangeEnd,
        ),
      ),
      SizedBox(width: 44, child: Text(f(value), textAlign: TextAlign.right, style: const TextStyle(fontSize: 12, color: Palette.text2, fontFeatures: [ui.FontFeature.tabularFigures()]))),
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
              '${label ?? (running ? 'Elaborazione' : 'Completato')} · $done/$total completate · ${total - done} rimanenti · $errors errori',
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
          OutlinedButton.icon(onPressed: onCancel, icon: const Icon(Icons.stop_rounded, size: 18), label: const Text('Annulla')),
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
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annulla')),
        FilledButton(onPressed: () => Navigator.pop(ctx, c.text.trim()), child: const Text('OK')),
      ],
    ),
  );
}

Future<bool> confirm(BuildContext context, String title, String body, {String ok = 'Conferma'}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(body),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annulla')),
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
            Expanded(child: Text(title ?? 'Anteprima', style: Theme.of(ctx).textTheme.titleMedium, overflow: TextOverflow.ellipsis)),
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
          child: Text('Rotella / pinch per lo zoom · trascina per spostare', style: TextStyle(fontSize: 11, color: Palette.text3)),
        ),
      ]),
    ),
  );
}

class ToolButton extends StatelessWidget {
  const ToolButton({super.key, required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(left: 6),
        child: TextButton.icon(onPressed: onTap, icon: Icon(icon, size: 18), label: Text(label)),
      );
}
