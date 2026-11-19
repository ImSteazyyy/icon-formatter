import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../app/theme.dart';
import '../l10n/strings.dart';
import 'common.dart';
import 'liquid_glass.dart';

/// Wallpaper chosen in this app session. Not persisted.
ImageProvider? _sessionWallpaper;

/// Mock launcher home screen filled with the pack's icons, on a dark or
/// light wallpaper. The apps are (name, icon) pairs, in pack order.
class HomePreview extends StatefulWidget {
  const HomePreview({super.key, required this.apps});

  final List<(String, Widget)> apps;

  @override
  State<HomePreview> createState() => _HomePreviewState();
}

class _HomePreviewState extends State<HomePreview> {
  bool _dark = true;
  ImageProvider? _wallpaper = _sessionWallpaper;

  /// Picked image, decoded at phone width so the full file never stays in memory.
  Future<void> _pickWallpaper() async {
    final path = (await FilePicker.platform.pickFiles(type: FileType.image))?.files.firstOrNull?.path;
    if (path == null || !mounted) return;
    _setWallpaper(ResizeImage(FileImage(File(path)), width: 720));
  }

  void _setWallpaper(ImageProvider? img) {
    _wallpaper?.evict(); // frees the decoded copy from the image cache
    _sessionWallpaper = img;
    setState(() => _wallpaper = img);
  }

  @override
  Widget build(BuildContext context) {
    final fg = _dark ? Colors.white : const Color(0xFF1C1C1C);
    final shadow = _dark ? Colors.black54 : Colors.white70;
    final wallpaper = _dark ? const [Color(0xFF243B5C), Color(0xFF0B0B0D)] : const [Color(0xFFDCE8F7), Color(0xFFF4F1EC)];
    final height = (MediaQuery.sizeOf(context).height * 0.62).clamp(340.0, 600.0);
    final image = _wallpaper;

    Widget screen = ClipRRect(
      borderRadius: BorderRadius.circular(28),
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: wallpaper),
          image: image == null ? null : DecorationImage(image: image, fit: BoxFit.cover),
        ),
        child: widget.apps.isEmpty
            ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(S.anteprimaVuota, textAlign: TextAlign.center, style: TextStyle(color: fg))))
            : GridView.builder(
                padding: const EdgeInsets.fromLTRB(12, 40, 12, 16),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 4, mainAxisExtent: 96, crossAxisSpacing: 4, mainAxisSpacing: 6),
                itemCount: widget.apps.length,
                itemBuilder: (_, i) {
                  final (name, icon) = widget.apps[i];
                  Widget label = Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 11, color: fg, shadows: [Shadow(color: shadow, blurRadius: 4)]),
                  );
                  // subtle scrim under the names so they read on a photo
                  if (image != null) {
                    label = DecoratedBox(
                      decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.28), borderRadius: BorderRadius.circular(6)),
                      child: Padding(padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1), child: label),
                    );
                  }
                  return Column(
                    children: [
                      icon,
                      const SizedBox(height: 4),
                      label,
                    ],
                  );
                },
              ),
      ),
    );
    // glass rim around the phone screen, as on the other glass panels
    if (glassCards) screen = LiquidGlass(radius: 28, child: screen);

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(S.anteprimaTitolo, textAlign: TextAlign.center, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Palette.text)),
          const SizedBox(height: 12),
          Wrap(
            alignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              SegmentedButton<bool>(
                showSelectedIcon: false,
                segments: [
                  ButtonSegment(value: true, icon: const Icon(Icons.dark_mode_outlined), label: Text(S.anteprimaScuro)),
                  ButtonSegment(value: false, icon: const Icon(Icons.light_mode_outlined), label: Text(S.anteprimaChiaro)),
                ],
                selected: {_dark},
                onSelectionChanged: (s) => setState(() => _dark = s.first),
              ),
              OutlinedButton.icon(onPressed: _pickWallpaper, icon: const Icon(Icons.wallpaper_outlined, size: 18), label: Text(S.extraSfondo)),
              if (image != null) TextButton(onPressed: () => _setWallpaper(null), child: Text(S.rimuovi)),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(height: height.toDouble(), child: screen),
        ],
      ),
    );
  }
}
