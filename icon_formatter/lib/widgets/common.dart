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
/// Height of every button in the app (pills, tool buttons, bars).
const double kButtonHeight = 48;

class Glass extends StatelessWidget {
  const Glass({super.key, required this.child, this.padding = const EdgeInsets.all(16), this.radius, this.live = false});

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double? radius;

  /// Floats over other content: blur it (see [LiquidGlass.live]).
  final bool live;

  @override
  Widget build(BuildContext context) => LiquidGlass(radius: radius ?? AppState.I.appearance.radius, padding: padding, chromatic: 0.3, role: GlassRole.panel, live: live, child: child);
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
      child: Stack(
        children: [
          Positioned(left: -160, top: -200, child: _Blob(color: accent.withValues(alpha: 0.10), size: 520)),
          Positioned(right: -220, bottom: -260, child: _Blob(color: Colors.white.withValues(alpha: 0.045), size: 640)),
          Positioned.fill(child: child),
        ],
      ),
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
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      gradient: RadialGradient(colors: [color, color.withValues(alpha: 0)]),
    ),
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
    // mid greys, far from the black of frosted plates: a plate at low alpha
    // still shows its edge, while the transparency itself is untouched
    final a = Paint()..color = const Color(0xFF55555C);
    final b = Paint()..color = const Color(0xFF3E3E44);
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
    return LayoutBuilder(
      builder: (context, box) {
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
                errorBuilder: (_, _, _) => const Center(child: Icon(Icons.broken_image_outlined, color: Palette.text3)),
              );
        return RepaintBoundary(child: img);
      },
    );
  }
}

class _VersionedFileImage extends FileImage {
  _VersionedFileImage(super.file) : stamp = ImageStamps.of(file);
  final int stamp;

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
    return LayoutBuilder(
      builder: (context, c) {
        final w = c.maxWidth;
        return GestureDetector(
          onHorizontalDragUpdate: (d) => setState(() => split = (split + d.delta.dx / w).clamp(0.0, 1.0)),
          onTapDown: (d) => setState(() => split = (d.localPosition.dx / w).clamp(0.0, 1.0)),
          child: MouseRegion(
            cursor: SystemMouseCursors.resizeLeftRight,
            child: Checkerboard(
              enabled: widget.checker,
              child: Stack(
                fit: StackFit.expand,
                children: [
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
                ],
              ),
            ),
          ),
        );
      },
    );
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
  const SliderRow({super.key, required this.label, required this.value, required this.onChanged, this.min = 0, this.max = 1, this.format, this.onChangeEnd, this.divisions, this.icon});

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
    final style = TextStyle(fontSize: 14, color: _invalid ? Palette.warn : Palette.text2, fontFeatures: const [ui.FontFeature.tabularFigures()]);
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              if (widget.icon != null) ...[IconChip(icon: widget.icon!), const SizedBox(width: 12)],
              Expanded(
                child: Text(widget.label, style: const TextStyle(fontSize: 15, color: Palette.text)),
              ),
              value,
            ],
          ),
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
        ],
      ),
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
    child: Row(
      children: [
        Expanded(child: Text(text.toUpperCase(), style: Theme.of(context).textTheme.titleSmall?.copyWith(fontSize: 11, letterSpacing: 1.1))),
        ?trailing,
      ],
    ),
  );
}

class StatusDot extends StatelessWidget {
  const StatusDot({super.key, required this.color, this.size = 8});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
  );
}

/// Batch progress strip: done / remaining / errors + cancel.
class ProgressStrip extends StatelessWidget {
  const ProgressStrip({super.key, required this.done, required this.total, required this.errors, required this.running, this.onCancel, this.label, this.onDismiss});

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
    // the same dark surface as the notices: it floats over moving content,
    // and live glass there costs a full-screen blur on every frame of a batch
    final strip = Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xF2242329),
        borderRadius: BorderRadius.circular(AppState.I.appearance.radius),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        boxShadow: const [BoxShadow(color: Color(0x66000000), blurRadius: 18, offset: Offset(0, 6))],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(S.completateRimanentiErrori(label ?? (running ? 'Elaborazione' : 'Completato'), done, total, total - done, errors), style: const TextStyle(fontSize: 12, color: Palette.text2)),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(value: v, minHeight: 4, backgroundColor: Colors.white.withValues(alpha: 0.06)),
                ),
              ],
            ),
          ),
          if (running && onCancel != null) ...[const SizedBox(width: 12), OutlinedButton.icon(onPressed: onCancel, icon: const Icon(Icons.stop_rounded, size: 18), label: const Text(S.annulla))],
          if (closable) ...[
            const SizedBox(width: 8),
            IconButton(
              key: const ValueKey('progress-close'),
              tooltip: S.scorriGiuPerChiudere,
              icon: const Icon(Icons.close_rounded, size: 18, color: Palette.text2),
              onPressed: onDismiss,
            ),
          ],
        ],
      ),
    );
    if (!closable) return strip;
    // finished: swipe left or right to remove it (like the notices)
    return Dismissible(key: const ValueKey('progress-strip'), direction: DismissDirection.horizontal, onDismissed: (_) => onDismiss!(), child: strip);
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
      content: TextField(
        controller: c,
        autofocus: true,
        decoration: InputDecoration(hintText: hint),
        onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
      ),
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
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(title ?? S.anteprima, style: Theme.of(ctx).textTheme.titleMedium, overflow: TextOverflow.ellipsis),
                ),
                IconButton(onPressed: () => Navigator.pop(ctx), icon: const Icon(Icons.close)),
              ],
            ),
          ),
          Flexible(
            child: AspectRatio(
              aspectRatio: 1,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Checkerboard(
                  cell: 16,
                  child: InteractiveViewer(
                    maxScale: 12,
                    child: IconImage(bytes: bytes, path: path),
                  ),
                ),
              ),
            ),
          ),
          const Padding(
            padding: EdgeInsets.all(10),
            child: Text(S.rotellaPinchZoomTrascinaSpostare, style: TextStyle(fontSize: 11, color: Palette.text3)),
          ),
        ],
      ),
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

  /// Accent pill like Studio's "Importa icone". Inside a card: half its
  /// width, two per row (the card's Wrap spaces them 8 apart); in a
  /// scrolling toolbar (unbounded width): its own width.
  @override
  Widget build(BuildContext context) {
    final button = FilledButton.icon(
      onPressed: onTap,
      style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 14)),
      icon: Icon(icon, size: 20),
      // one size for every label; a long one takes two lines in the 48 dp
      label: Text(label, maxLines: 2, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: const TextStyle(fontSize: 13.5, height: 1.15)),
    );
    return LayoutBuilder(
      builder: (context, box) => box.hasBoundedWidth
          ? SizedBox(width: ((box.maxWidth - 8) / 2).floorToDouble(), height: kButtonHeight, child: button)
          : Padding(
              padding: const EdgeInsets.only(right: 8),
              child: SizedBox(height: kButtonHeight, child: button),
            ),
    );
  }
}

/// Round liquid glass icon button.
class GlassIconButton extends StatelessWidget {
  const GlassIconButton({super.key, required this.icon, required this.onPressed, this.tooltip, this.size = kButtonHeight, this.label});

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
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(icon, color: Colors.white, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      label!,
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14),
                    ),
                  ],
                ),
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
  const LargeHeader(this.title, {super.key, this.onBack, this.trailing, this.subtitle, this.actions = const []});

  final String title;
  final String? subtitle;
  final VoidCallback? onBack;

  /// One control shown centred under the title (e.g. "Ripristina").
  final Widget? trailing;

  /// Header buttons: one row under the title, equal width, [kButtonHeight].
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final titleBlock = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w700, letterSpacing: -0.8, color: Palette.text, height: 1.15),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 4),
          Text(
            subtitle!,
            key: const ValueKey('header-subtitle'),
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 13, color: Palette.text2, height: 1.3),
          ),
        ],
      ],
    );
    return Padding(
      // buttons under the title: the same 10 dp gap as between the rows below
      padding: EdgeInsets.fromLTRB(0, 8, 0, actions.isNotEmpty ? 10 : 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          // title and subtitle centred; with a back button an equal empty slot
          // on the right keeps them on the screen's centre line
          if (onBack != null)
            Row(
              children: [
                GlassIconButton(key: const ValueKey('header-back'), icon: Icons.arrow_back_rounded, onPressed: onBack, size: kButtonHeight, tooltip: S.indietro),
                const SizedBox(width: 8),
                Expanded(child: titleBlock),
                const SizedBox(width: 8 + kButtonHeight),
              ],
            )
          else
            titleBlock,
          if (actions.isNotEmpty) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                for (var i = 0; i < actions.length; i++) ...[
                  if (i > 0) const SizedBox(width: 10),
                  Expanded(
                    child: SizedBox(height: kButtonHeight, child: actions[i]),
                  ),
                ],
              ],
            ),
          ],
          if (trailing != null) ...[const SizedBox(height: 10), Center(child: trailing!)],
        ],
      ),
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
    // glass card (static glass: no backdrop blur, cheap while scrolling)
    return Glass(
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
    final body = ListView(padding: EdgeInsets.fromLTRB(20, header == null ? 4 : 14, 20, bottom), children: sectioned(children));
    if (header == null) return body;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(padding: const EdgeInsets.fromLTRB(20, 0, 20, 0), child: header!),
        Expanded(
          // content fades under the sticky preview instead of being covered
          child: ShaderMask(
            shaderCallback: (r) => const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.transparent, Colors.black], stops: [0, 0.035]).createShader(r),
            blendMode: BlendMode.dstIn,
            child: body,
          ),
        ),
      ],
    );
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
        child: Row(
          children: [
            if (icon != null) ...[IconChip(icon: icon!), const SizedBox(width: 12)],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontSize: 15, color: Palette.text)),
                  if (subtitle != null) Text(subtitle!, style: const TextStyle(fontSize: 12, color: Palette.text2)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Switch(value: value, onChanged: onChanged),
          ],
        ),
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
    return Column(
      children: [
        for (var i = 0; i < options.length; i++) ...[
          if (i > 0) Divider(height: 1, color: Colors.white.withValues(alpha: 0.06)),
          InkWell(
            onTap: () => onChanged(options[i].$1),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 13),
              child: Row(
                children: [
                  Expanded(
                    child: Text(options[i].$2, style: TextStyle(fontSize: 16, color: options[i].$1 == value ? Palette.text : Palette.text2)),
                  ),
                  if (options[i].$1 == value) Icon(Icons.check_rounded, color: accent),
                ],
              ),
            ),
          ),
        ],
      ],
    );
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
      // glass like the Studio card: static glass skips the backdrop blur, so
      // it scrolls as cheaply as a solid card
      child: Glass(
        radius: AppState.I.appearance.radius + 6,
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: done ? accent : accent.withValues(alpha: 0.16), shape: BoxShape.circle),
                  child: done
                      ? const Icon(Icons.check_rounded, size: 18, color: Colors.white)
                      : step == 0
                      ? Icon(Icons.memory_rounded, size: 18, color: accent)
                      : Text(
                          '$step',
                          style: TextStyle(color: accent, fontWeight: FontWeight.w700),
                        ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Palette.text),
                      ),
                      if (subtitle != null) Text(subtitle!, style: const TextStyle(fontSize: 12, color: Palette.text2)),
                    ],
                  ),
                ),
              ],
            ),
            if (children.isNotEmpty) ...[const SizedBox(height: 10), Wrap(spacing: 8, runSpacing: 8, children: children)],
          ],
        ),
      ),
    );
  }
}

/// Stadium on/off choice, [kButtonHeight] high: filters ("App di sistema")
/// and tabs ("Tema AI online" / "AI locale"). Selected: accent tint and a
/// check, or the [icon] when it has one.
class ChoicePill extends StatelessWidget {
  const ChoicePill({super.key, required this.label, required this.on, required this.onTap, this.icon, this.iconColor, this.iconSize = 18});

  final String label;
  final bool on;
  final VoidCallback onTap;
  final IconData? icon;

  /// Leading icon colour (status dots); accent / grey by default.
  final Color? iconColor;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    final Widget lead = icon != null
        ? Icon(icon, key: ValueKey(on), size: iconSize, color: iconColor ?? (on ? accent : Palette.text2))
        : (on ? Icon(Icons.check_rounded, key: const ValueKey(1), size: 18, color: accent) : const SizedBox(key: ValueKey(0), width: 0));
    return Material(
      color: on ? accent.withValues(alpha: 0.18) : Colors.transparent,
      shape: StadiumBorder(side: BorderSide(color: on ? accent.withValues(alpha: 0.55) : Colors.white.withValues(alpha: 0.14))),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: SizedBox(
          height: kButtonHeight,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            // centred when stretched, own width inside a Wrap
            child: Center(
              widthFactor: 1,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AnimatedSwitcher(duration: const Duration(milliseconds: 150), child: lead),
                  if (icon != null || on) const SizedBox(width: 6),
                  // shrinks a little instead of cutting the word
                  Flexible(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        label,
                        maxLines: 1,
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: on ? Palette.text : Palette.text2),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Compact filter: a single coloured icon in a [kButtonHeight] pill, with a
/// tooltip and an accessible label (the visible name sits elsewhere).
class IconFilterPill extends StatelessWidget {
  const IconFilterPill({super.key, required this.icon, required this.color, required this.tooltip, required this.on, required this.onTap});

  final IconData icon;
  final Color color;
  final String tooltip;
  final bool on;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        selected: on,
        label: tooltip,
        excludeSemantics: true,
        child: Material(
          color: on ? color.withValues(alpha: 0.20) : Colors.transparent,
          shape: StadiumBorder(
            side: BorderSide(color: on ? color.withValues(alpha: 0.75) : Colors.white.withValues(alpha: 0.14), width: on ? 1.5 : 1),
          ),
          child: InkWell(
            customBorder: const StadiumBorder(),
            onTap: onTap,
            child: SizedBox(
              height: kButtonHeight,
              child: Center(child: Icon(icon, size: 22, color: color)),
            ),
          ),
        ),
      ),
    );
  }
}

/// A search field that stays at the top of a [CustomScrollView] while the
/// content scrolls under it. A dark backing keeps it readable over the icons.
class SliverPinnedSearch extends StatelessWidget {
  const SliverPinnedSearch({super.key, required this.child, this.padding = const EdgeInsets.fromLTRB(0, 6, 0, 6)});

  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) => SliverPersistentHeader(pinned: true, delegate: _PinnedSearchDelegate(child, padding));
}

class _PinnedSearchDelegate extends SliverPersistentHeaderDelegate {
  _PinnedSearchDelegate(this.child, this.padding);
  final Widget child;
  final EdgeInsets padding;

  /// below the field: the fade of the backing
  static const double _tail = 14;

  @override
  double get minExtent => kButtonHeight + padding.vertical + _tail;
  @override
  double get maxExtent => kButtonHeight + padding.vertical + _tail;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    final solid = (padding.vertical + kButtonHeight) / maxExtent;
    return DecoratedBox(
      // always there (a fixed-height pinned header gets no scroll signal);
      // a plain gradient, no blur: cheap at 120 Hz. Solid behind the field,
      // then a short fade below it
      decoration: BoxDecoration(
        gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: const [Color(0xFF0F0D12), Color(0xFF0F0D12), Color(0x000F0D12)], stops: [0.0, solid, 1.0]),
      ),
      child: Padding(padding: padding.copyWith(bottom: padding.bottom + _tail), child: Material(type: MaterialType.transparency, child: child)),
    );
  }

  @override
  bool shouldRebuild(covariant _PinnedSearchDelegate old) => old.child != child || old.padding != padding;
}

/// Two small round glass buttons: jump to the top / to the bottom of a list.
class ScrollJumpButtons extends StatefulWidget {
  const ScrollJumpButtons({super.key, required this.controller});
  final ScrollController controller;

  @override
  State<ScrollJumpButtons> createState() => _ScrollJumpButtonsState();
}

class _ScrollJumpButtonsState extends State<ScrollJumpButtons> {
  bool canUp = false, canDown = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_sync);
    WidgetsBinding.instance.addPostFrameCallback((_) => _sync());
  }

  @override
  void dispose() {
    widget.controller.removeListener(_sync);
    super.dispose();
  }

  void _sync() {
    if (!mounted || !widget.controller.hasClients) return;
    final pos = widget.controller.position;
    final up = pos.pixels > 200;
    final down = pos.maxScrollExtent - pos.pixels > 200;
    if (up != canUp || down != canDown) {
      setState(() {
        canUp = up;
        canDown = down;
      });
    }
  }

  void _go(bool top) {
    final c = widget.controller;
    if (!c.hasClients) return;
    final target = top ? c.position.minScrollExtent : c.position.maxScrollExtent;
    // long lists: jump most of the way, animate the last screen
    final far = (target - c.position.pixels).abs() > 3000;
    if (far) c.jumpTo(top ? target + 1200 : target - 1200);
    c.animateTo(target, duration: const Duration(milliseconds: 320), curve: Curves.easeOutCubic);
  }

  Widget _btn(IconData icon, String tip, bool on, VoidCallback f) => AnimatedOpacity(
        duration: const Duration(milliseconds: 160),
        opacity: on ? 1 : 0.0,
        child: IgnorePointer(
          ignoring: !on,
          child: Tooltip(
            message: tip,
            child: Material(
              color: const Color(0xE6242329),
              shape: CircleBorder(side: BorderSide(color: Colors.white.withValues(alpha: 0.16))),
              elevation: 4,
              child: InkWell(customBorder: const CircleBorder(), onTap: f, child: SizedBox(width: 40, height: 40, child: Icon(icon, size: 22, color: Palette.text))),
            ),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Column(mainAxisSize: MainAxisSize.min, children: [
      _btn(Icons.keyboard_double_arrow_up_rounded, 'Vai in cima', canUp, () => _go(true)),
      const SizedBox(height: 8),
      _btn(Icons.keyboard_double_arrow_down_rounded, 'Vai in fondo', canDown, () => _go(false)),
    ]);
  }
}

/// Search field shaped like the buttons: a [kButtonHeight] pill.
InputDecoration pillSearchDecoration(BuildContext context, String hint) {
  OutlineInputBorder b(Color c) => OutlineInputBorder(
    borderRadius: BorderRadius.circular(kButtonHeight / 2),
    borderSide: BorderSide(color: c),
  );
  return InputDecoration(
    prefixIcon: const Icon(Icons.search),
    hintText: hint,
    isDense: false,
    constraints: const BoxConstraints(minHeight: kButtonHeight, maxHeight: kButtonHeight),
    contentPadding: const EdgeInsets.symmetric(horizontal: 16),
    fillColor: Colors.white.withValues(alpha: 0.05),
    border: b(Colors.white.withValues(alpha: 0.14)),
    enabledBorder: b(Colors.white.withValues(alpha: 0.14)),
    focusedBorder: b(Theme.of(context).colorScheme.primary.withValues(alpha: 0.7)),
  );
}

/// Version of each image file shown by [IconImage], so a file rewritten in
/// place never shows stale cached pixels.
///
/// Normally read from the file (modification time and length). While a batch
/// is writing ([busy] > 0) the disk is not touched from build methods: a
/// file stat on the UI thread competing with four workers writing PNGs
/// stalled frames for 200 ms on the Phone (2a) Plus. The batch reports every
/// file it rewrites through [bump] instead.
class ImageStamps {
  static final Map<String, int> _memo = {};
  static int busy = 0;

  static int of(File f) {
    final p = f.path;
    if (busy > 0) {
      final m = _memo[p];
      if (m != null) return m;
    }
    int s;
    try {
      s = f.lastModifiedSync().microsecondsSinceEpoch ^ f.lengthSync();
    } catch (_) {
      s = 0;
    }
    return _memo[p] = s;
  }

  /// [path] was just (re)written.
  static void bump(String path) => _memo[path] = DateTime.now().microsecondsSinceEpoch;
}
