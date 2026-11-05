import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/theme.dart';
import '../l10n/strings.dart';
import 'common.dart';
import 'liquid_glass.dart' show LiquidGlass, showAppDialog;

/// Full colour picker in a centred window: saturation/brightness square, hue
/// bar, preview and hex code. [onChanged] runs live while dragging (the app
/// recolours behind the window); "Annulla" or tapping outside calls it once
/// more with [initial]. Returns the chosen colour, or null when cancelled.
Future<int?> showColorPicker(BuildContext context, {required int initial, required String title, required ValueChanged<int> onChanged}) async {
  final picked = await showAppDialog<int>(
    context: context,
    // a liquid-glass panel, like the pop-up menus
    builder: (ctx) => Dialog(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: LiquidGlass(
          radius: 30,
          live: true,
          child: Material(
            type: MaterialType.transparency,
            child: SingleChildScrollView(child: _ColorPickerSheet(initial: initial, title: title, onChanged: onChanged)),
          ),
        ),
      ),
    ),
  );
  if (picked == null) onChanged(initial);
  return picked;
}

/// Round rainbow swatch that opens [showColorPicker] ("Personalizzato"),
/// ringed when [selected].
class CustomColorSwatch extends StatelessWidget {
  const CustomColorSwatch({super.key, required this.selected, required this.onTap, this.size = 34});

  final bool selected;
  final VoidCallback onTap;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: S.coloreSceglitu,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: selected ? Colors.white : Colors.transparent, width: 2.5),
            gradient: SweepGradient(colors: [for (var h = 0; h <= 360; h += 45) HSVColor.fromAHSV(1, h % 360.0, 0.9, 1).toColor()]),
          ),
          child: Icon(Icons.colorize_rounded, size: size * 0.5, color: Colors.white, shadows: const [Shadow(color: Colors.black54, blurRadius: 3)]),
        ),
      ),
    );
  }
}

class _ColorPickerSheet extends StatefulWidget {
  const _ColorPickerSheet({required this.initial, required this.title, required this.onChanged});

  final int initial;
  final String title;
  final ValueChanged<int> onChanged;

  @override
  State<_ColorPickerSheet> createState() => _ColorPickerSheetState();
}

class _ColorPickerSheetState extends State<_ColorPickerSheet> {
  late HSVColor hsv = HSVColor.fromColor(Color(widget.initial | 0xFF000000));
  late final TextEditingController hex = TextEditingController(text: _hex(hsv));
  bool hexError = false;

  static String _hex(HSVColor c) => (c.toColor().toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase();

  int get argb => hsv.toColor().toARGB32();

  void _set(HSVColor c, {bool fromHex = false}) {
    setState(() {
      hsv = c;
      hexError = false;
      if (!fromHex) hex.text = _hex(c);
    });
    widget.onChanged(argb);
  }

  @override
  void dispose() {
    hex.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pure = HSVColor.fromAHSV(1, hsv.hue, 1, 1).toColor();
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(widget.title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: Palette.text)),
          const SizedBox(height: 16),
          // saturation (left to right) and brightness (bottom to top)
          AspectRatio(
            aspectRatio: 1.5,
            child: LayoutBuilder(builder: (context, box) {
              void pick(Offset p) => _set(hsv
                  .withSaturation((p.dx / box.maxWidth).clamp(0.0, 1.0))
                  .withValue(1 - (p.dy / box.maxHeight).clamp(0.0, 1.0)));
              return GestureDetector(
                onPanDown: (d) => pick(d.localPosition),
                onPanUpdate: (d) => pick(d.localPosition),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(18),
                  child: Stack(children: [
                    Positioned.fill(child: DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(colors: [Colors.white, pure])))),
                    const Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.transparent, Colors.black])),
                      ),
                    ),
                    Positioned(
                      left: hsv.saturation * box.maxWidth - 12,
                      top: (1 - hsv.value) * box.maxHeight - 12,
                      child: IgnorePointer(
                        child: Container(
                          width: 24,
                          height: 24,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: hsv.toColor(),
                            border: Border.all(color: Colors.white, width: 3),
                            boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 4)],
                          ),
                        ),
                      ),
                    ),
                  ]),
                ),
              );
            }),
          ),
          const SizedBox(height: 16),
          // hue
          LayoutBuilder(builder: (context, box) {
            void pick(double x) => _set(hsv.withHue((x / box.maxWidth * 360).clamp(0.0, 359.9)));
            return GestureDetector(
              onPanDown: (d) => pick(d.localPosition.dx),
              onPanUpdate: (d) => pick(d.localPosition.dx),
              child: SizedBox(
                height: 32,
                child: Stack(clipBehavior: Clip.none, children: [
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        gradient: LinearGradient(colors: [for (var h = 0; h <= 360; h += 30) HSVColor.fromAHSV(1, h % 360.0, 1, 1).toColor()]),
                      ),
                    ),
                  ),
                  Positioned(
                    left: hsv.hue / 360 * box.maxWidth - 14,
                    top: 2,
                    child: IgnorePointer(
                      child: Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(shape: BoxShape.circle, color: pure, border: Border.all(color: Colors.white, width: 3), boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 4)]),
                      ),
                    ),
                  ),
                ]),
              ),
            );
          }),
          const SizedBox(height: 16),
          // preview and hex code
          Row(children: [
            Container(
              width: kButtonHeight,
              height: kButtonHeight,
              decoration: BoxDecoration(color: hsv.toColor(), borderRadius: BorderRadius.circular(14), border: Border.all(color: Colors.white.withValues(alpha: 0.25))),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: hex,
                maxLength: 6,
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp('[0-9a-fA-F]'))],
                style: const TextStyle(fontFamily: 'monospace', letterSpacing: 1.5),
                decoration: InputDecoration(prefixText: '#', counterText: '', labelText: S.hex, errorText: hexError ? S.formatoRrggbb : null),
                onChanged: (v) {
                  if (v.length == 6) {
                    _set(HSVColor.fromColor(Color(0xFF000000 | int.parse(v, radix: 16))), fromHex: true);
                  } else {
                    setState(() => hexError = v.isNotEmpty);
                  }
                },
              ),
            ),
          ]),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(child: OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text(S.annulla))),
            const SizedBox(width: 10),
            Expanded(child: FilledButton(onPressed: () => Navigator.pop(context, argb), child: const Text(S.applica))),
          ]),
        ]),
      ),
    );
  }
}
