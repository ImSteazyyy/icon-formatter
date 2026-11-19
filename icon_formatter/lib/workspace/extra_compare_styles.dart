import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/models.dart';
import '../app/state.dart';
import '../app/theme.dart';
import '../l10n/strings.dart';
import '../src/rust/api/engine.dart';
import '../widgets/liquid_glass.dart';
import 'workspace_controller.dart';

/// Opens two style presets side by side on one sample icon.
Future<void> showCompareStyles(BuildContext context, WorkspaceController c, String currentPresetId) {
  return showAppSheet<void>(
    context: context,
    builder: (_) => _CompareStyles(c: c, presetA: currentPresetId),
  );
}

class _CompareStyles extends StatefulWidget {
  const _CompareStyles({required this.c, required this.presetA});

  final WorkspaceController c;
  final String presetA;

  @override
  State<_CompareStyles> createState() => _CompareStylesState();
}

class _CompareStylesState extends State<_CompareStyles> {
  late String _a = widget.presetA;
  late String _b = _previousBuiltIn(widget.presetA);
  Uint8List? _pngA, _pngB;
  Uint8List? _reference;
  bool _noSample = false;
  String? _error;
  int _seq = 0;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _render();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  /// The built-in preset before [id] (the last one when [id] is first).
  String _previousBuiltIn(String id) {
    final ids = [for (final p in AppState.I.presets) if (p.builtIn) p.id];
    if (ids.isEmpty) return id;
    final i = ids.indexOf(id);
    return ids[i <= 0 ? ids.length - 1 : i - 1];
  }

  /// Sample: the first active item, else the bundled reference base.
  Future<void> _render() async {
    final seq = ++_seq;
    try {
      final it = widget.c.active.firstOrNull;
      if (it == null) {
        _reference ??= (await rootBundle.load('assets/bases/reference_translucent.png')).buffer.asUint8List();
      }
      final a = await _renderOne(it, _a);
      final b = await _renderOne(it, _b);
      if (!mounted || seq != _seq) return;
      setState(() {
        _pngA = a;
        _pngB = b;
        _noSample = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted || seq != _seq) return;
      setState(() {
        _noSample = _reference == null && widget.c.active.isEmpty;
        _error = _noSample ? null : S.errore(e);
      });
    }
  }

  Future<Uint8List> _renderOne(WorkItem? it, String presetId) async {
    final s = AppState.I.settingsFor(StudioMode.preset, presetId: presetId, seg: widget.c.globalSegment);
    final PreviewResult r;
    if (it == null) {
      r = await previewBytes(bytes: _reference!, settings: s);
    } else if (it.path != null) {
      r = await previewFile(path: it.path!, settings: s);
    } else {
      r = await previewBytes(bytes: it.bytes!, settings: s);
    }
    return r.png;
  }

  /// Dropdown change: update now, render again after a short pause.
  void _pick(bool isA, String id) {
    setState(() => isA ? _a = id : _b = id);
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 150), _render);
  }

  @override
  Widget build(BuildContext context) {
    final presets = AppState.I.presets;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(S.extraConfrontaStili, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: Palette.text)),
          const SizedBox(height: 16),
          if (_noSample) Text(S.extraNessunCampione, style: TextStyle(color: Palette.text2)),
          if (_error != null) Text(_error!, style: TextStyle(color: Palette.text2)),
          if (!_noSample)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: _column(S.extraStileA, _a, _pngA, presets, (v) => _pick(true, v))),
                const SizedBox(width: 12),
                Expanded(child: _column(S.extraStileB, _b, _pngB, presets, (v) => _pick(false, v))),
              ],
            ),
        ],
      ),
    );
  }

  Widget _column(String label, String value, Uint8List? png, List<StylePreset> presets, ValueChanged<String> onChanged) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(label, style: TextStyle(fontSize: 13, color: Palette.text2)),
        const SizedBox(height: 6),
        DropdownButtonFormField<String>(
          key: ValueKey('$label$value'),
          initialValue: value,
          isExpanded: true,
          items: [for (final x in presets) DropdownMenuItem(value: x.id, child: Text(x.name, overflow: TextOverflow.ellipsis))],
          onChanged: (v) {
            if (v != null) onChanged(v);
          },
        ),
        const SizedBox(height: 12),
        AspectRatio(
          aspectRatio: 1,
          child: DecoratedBox(
            decoration: BoxDecoration(color: const Color(0xFF1A1A1E), borderRadius: BorderRadius.circular(20)),
            child: png == null
                ? const SizedBox.shrink()
                // decoded at 256 px: the preview PNG is larger than the card
                : ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: Image.memory(png, fit: BoxFit.contain, cacheWidth: 256, gaplessPlayback: true),
                  ),
          ),
        ),
      ],
    );
  }
}
