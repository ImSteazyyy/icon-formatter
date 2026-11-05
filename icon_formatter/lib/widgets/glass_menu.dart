import 'package:flutter/material.dart';

import '../app/state.dart';
import '../app/theme.dart';
import 'liquid_glass.dart';

/// One row of a [showGlassMenu] pop-up.
class GlassMenuItem<T> {
  const GlassMenuItem({required this.value, required this.label, this.icon, this.subtitle, this.destructive = false, this.enabled = true, this.selected = false});
  final T value;
  final String label;
  final IconData? icon;
  final String? subtitle;
  final bool destructive;
  final bool enabled;

  /// Shows a check mark (choice menus).
  final bool selected;
}

/// Screen rectangle of the widget owning [context] (menu anchor).
Rect anchorOf(BuildContext context) {
  final box = context.findRenderObject() as RenderBox?;
  if (box == null || !box.hasSize) return Rect.zero;
  return box.localToGlobal(Offset.zero) & box.size;
}

/// iOS 26 style pop-up menu: a liquid-glass panel that grows out of the
/// control that opened it (above it when the control sits low on the
/// screen). Tap outside, or drag the panel down, to close it.
Future<T?> showGlassMenu<T>(BuildContext context, {required Rect anchor, required List<GlassMenuItem<T>> items, String? title}) {
  return Navigator.of(context).push<T>(_GlassMenuRoute<T>(anchor: anchor, items: items, title: title));
}

class _GlassMenuRoute<T> extends PopupRoute<T> {
  _GlassMenuRoute({required this.anchor, required this.items, this.title});
  final Rect anchor;
  final List<GlassMenuItem<T>> items;
  final String? title;

  @override
  Color? get barrierColor => Colors.black.withValues(alpha: 0.22);

  @override
  bool get barrierDismissible => true;

  @override
  String? get barrierLabel => 'menu';

  @override
  Duration get transitionDuration => Duration(milliseconds: AppState.I.appearance.animations ? 240 : 0);

  @override
  Duration get reverseTransitionDuration => Duration(milliseconds: AppState.I.appearance.animations ? 160 : 0);

  @override
  Widget buildPage(BuildContext context, Animation<double> animation, Animation<double> secondaryAnimation) {
    return _GlassMenuView<T>(anchor: anchor, items: items, title: title, animation: animation);
  }
}

class _GlassMenuView<T> extends StatefulWidget {
  const _GlassMenuView({super.key, required this.anchor, required this.items, required this.animation, this.title});
  final Rect anchor;
  final List<GlassMenuItem<T>> items;
  final Animation<double> animation;
  final String? title;

  @override
  State<_GlassMenuView<T>> createState() => _GlassMenuViewState<T>();
}

class _GlassMenuViewState<T> extends State<_GlassMenuView<T>> {
  double drag = 0;

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final size = mq.size;
    const margin = 16.0;
    final width = (size.width - 2 * margin).clamp(0.0, 300.0);
    final a = widget.anchor;
    // low controls open the menu upwards, high ones downwards
    final above = a.center.dy > size.height * 0.55;
    final left = (a.center.dx - width / 2).clamp(margin, size.width - margin - width);
    final accent = Theme.of(context).colorScheme.primary;
    final origin = Alignment(((a.center.dx - left) / width) * 2 - 1, above ? 1 : -1);
    final curve = CurvedAnimation(parent: widget.animation, curve: Curves.easeOutBack, reverseCurve: Curves.easeInCubic);

    final rows = <Widget>[];
    if (widget.title != null) {
      rows.add(Padding(
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 6),
        child: Text(widget.title!, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: Palette.text3)),
      ));
    }
    for (var i = 0; i < widget.items.length; i++) {
      final it = widget.items[i];
      if (i > 0 || widget.title != null) rows.add(Divider(height: 1, thickness: 0.6, indent: 18, endIndent: 18, color: Colors.white.withValues(alpha: 0.08)));
      final color = !it.enabled ? Palette.text3 : (it.destructive ? Palette.danger : Palette.text);
      rows.add(InkWell(
        key: ValueKey('menu-${it.label}'),
        onTap: it.enabled ? () => Navigator.of(context).pop(it.value) : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          child: Row(children: [
            if (it.selected) Padding(padding: const EdgeInsets.only(right: 10), child: Icon(Icons.check_rounded, size: 18, color: accent)),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Text(it.label, style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w500, color: color)),
                if (it.subtitle != null) Text(it.subtitle!, style: const TextStyle(fontSize: 12, color: Palette.text2)),
              ]),
            ),
            // iOS: the symbol sits on the trailing side
            if (it.icon != null) Padding(padding: const EdgeInsets.only(left: 12), child: Icon(it.icon, size: 21, color: color)),
          ]),
        ),
      ));
    }

    final panel = Material(
      type: MaterialType.transparency,
      child: LiquidGlass(
        radius: 26,
        role: GlassRole.panel,
        live: true,
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: size.height * 0.6),
          child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: rows)),
        ),
      ),
    );

    return Stack(children: [
      Positioned(
        left: left,
        width: width,
        top: above ? null : a.bottom + 8 + drag,
        bottom: above ? size.height - a.top + 8 - drag : null,
        child: GestureDetector(
          // drag down to close (like the other panels of the app)
          onVerticalDragUpdate: (d) => setState(() => drag = (drag + d.delta.dy).clamp(0.0, 200.0)),
          onVerticalDragEnd: (d) {
            if (drag > 50 || (d.primaryVelocity ?? 0) > 400) {
              Navigator.of(context).pop();
            } else {
              setState(() => drag = 0);
            }
          },
          child: FadeTransition(
            opacity: CurvedAnimation(parent: widget.animation, curve: Curves.easeOut),
            child: ScaleTransition(scale: Tween(begin: 0.6, end: 1.0).animate(curve), alignment: origin, child: panel),
          ),
        ),
      ),
    ]);
  }
}
