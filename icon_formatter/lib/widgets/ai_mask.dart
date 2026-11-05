import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../app/models.dart';
import '../app/state.dart';
import '../app/storage.dart';
import '../app/theme.dart';
import '../l10n/strings.dart';
import '../services/ai_model_service.dart';
import '../src/rust/api/engine.dart';
import 'common.dart';
import 'liquid_glass.dart';

/// Settings › Elaborazione: local AI model manager (download, size, RAM,
/// delete, mask thresholds, test on an image).
class LocalAiBox extends StatefulWidget {
  const LocalAiBox({super.key});

  @override
  State<LocalAiBox> createState() => _LocalAiBoxState();
}

class _LocalAiBoxState extends State<LocalAiBox> {
  double? progress;
  String? downloading;
  String? error;
  bool cancel = false;

  String _mb(int b) => '${(b / 1048576).toStringAsFixed(1).replaceAll('.', ',')} MB';

  Future<void> _download(AiModelInfo m) async {
    setState(() {
      progress = 0;
      downloading = m.id;
      error = null;
      cancel = false;
    });
    try {
      await AiModelService.download(m, (p) {
        if (mounted) setState(() => progress = p);
      }, cancelled: () => cancel);
    } catch (e) {
      if (mounted) setState(() => error = S.aiDownloadFallito(e));
    } finally {
      if (mounted) {
        setState(() {
          progress = null;
          downloading = null;
        });
      }
      AppState.I.update();
    }
  }

  @override
  Widget build(BuildContext context) {
    final st = AppState.I;
    final cfg = st.localAi;
    return ListenableBuilder(
      listenable: st,
      builder: (context, _) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const SizedBox(height: 8),
        const Text(S.aiLocaleInfo, style: TextStyle(fontSize: 11, color: Palette.text3)),
        const SizedBox(height: 8),
        for (final m in aiModelsHere)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Radio<String>(
                  value: m.id,
                  groupValue: cfg.modelId,
                  onChanged: (v) => st.update(() => cfg.modelId = v!),
                ),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(m.label, style: const TextStyle(fontWeight: FontWeight.w600)),
                    Text(S.aiModelloDettagli(_mb(m.bytes), m.ramMb), style: const TextStyle(fontSize: 12, color: Palette.text2)),
                    Text(m.note, style: const TextStyle(fontSize: 11, color: Palette.text3)),
                    const SizedBox(height: 4),
                    Wrap(spacing: 6, children: [
                      if (m.phone) _Tag(S.aiTagTelefono),
                      if (m.desktop) _Tag(m.phone ? S.aiTagWindows : S.aiTagSoloWindows),
                    ]),
                  ]),
                ),
                if (st.modelReady(m)) ...[
                  const Icon(Icons.check_circle_outline, color: Palette.ok, size: 18),
                  IconButton(
                    tooltip: S.aiEliminaModello,
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () async {
                      await AiModelService.delete(m);
                      st.update();
                    },
                  ),
                ] else if (downloading == null)
                  FilledButton.tonal(key: ValueKey('ai-download-${m.id}'), onPressed: () => _download(m), child: const Text(S.aiScarica))
                else if (downloading == m.id)
                  TextButton(onPressed: () => setState(() => cancel = true), child: const Text(S.annulla)),
              ]),
              if (downloading == m.id && progress != null) LinearProgressIndicator(value: progress),
            ]),
          ),
        if (error != null) Text(error!, style: const TextStyle(color: Palette.danger, fontSize: 12)),
        const SizedBox(height: 8),
        SliderRow(label: S.aiSogliaBassa, value: cfg.low, max: 0.9, onChanged: (v) => st.update(() => cfg.low = v.clamp(0, cfg.high - 0.02))),
        SliderRow(label: S.aiSogliaAlta, value: cfg.high, min: 0.1, onChanged: (v) => st.update(() => cfg.high = v.clamp(cfg.low + 0.02, 1))),
        const SizedBox(height: 4),
        OutlinedButton.icon(
          key: const ValueKey('ai-test'),
          icon: const Icon(Icons.layers_outlined),
          label: const Text(S.aiProvaMaschera),
          onPressed: st.modelReady(cfg.model)
              ? () async {
                  final r = await FilePicker.platform.pickFiles(type: FileType.image);
                  final path = r?.files.single.path;
                  if (path != null && context.mounted) await showAiMaskDialog(context, path: path);
                }
              : null,
        ),
        if (!st.modelReady(cfg.model))
          const Padding(
            padding: EdgeInsets.only(top: 6),
            child: Text(S.aiModelloMancante, style: TextStyle(fontSize: 12, color: Palette.warn)),
          ),
      ]),
    );
  }
}

/// Alpha-mask preview of the local AI on one image, with live thresholds.
Future<void> showAiMaskDialog(BuildContext context, {String? path, Uint8List? bytes}) async {
  var p = path;
  if (p == null && bytes != null) {
    final d = await AppPaths.I.workDir('aimask');
    p = '$d${Platform.pathSeparator}src.png';
    await File(p).writeAsBytes(bytes);
  }
  if (p == null || !context.mounted) return;
  await showAppDialog<void>(context: context, builder: (_) => _AiMaskDialog(path: p!));
}

class _AiMaskDialog extends StatefulWidget {
  const _AiMaskDialog({required this.path});
  final String path;

  @override
  State<_AiMaskDialog> createState() => _AiMaskDialogState();
}

class _AiMaskDialogState extends State<_AiMaskDialog> {
  AiPreview? res;
  String? error;
  bool busy = false;

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    final st = AppState.I;
    final m = st.localAi.model;
    if (!st.modelReady(m)) {
      setState(() => error = S.aiModelloMancante);
      return;
    }
    setState(() => busy = true);
    try {
      final r = await aiPreview(
        path: widget.path,
        settings: AiSettings(modelPath: st.modelPath(m), model: m.kind, low: st.localAi.low, high: st.localAi.high),
      );
      if (mounted) setState(() => res = r);
    } catch (e) {
      if (mounted) setState(() => error = S.errore(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Widget _tile(String title, Widget child) => Expanded(
        child: Column(children: [
          Text(title, style: const TextStyle(fontSize: 12, color: Palette.text2)),
          const SizedBox(height: 6),
          AspectRatio(aspectRatio: 1, child: ClipRRect(borderRadius: BorderRadius.circular(10), child: child)),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final st = AppState.I;
    final r = res;
    return AlertDialog(
      title: const Text(S.aiMascheraTitolo),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              _tile(S.aiOriginale, Checkerboard(child: Image.file(File(widget.path), fit: BoxFit.contain))),
              const SizedBox(width: 8),
              _tile(S.aiMaschera, r == null ? const Center(child: CircularProgressIndicator()) : Image.memory(r.maskPng, fit: BoxFit.contain)),
              const SizedBox(width: 8),
              _tile(S.aiRisultato, r == null ? const SizedBox() : Checkerboard(child: Image.memory(r.glyphPng, fit: BoxFit.contain))),
            ]),
            const SizedBox(height: 10),
            if (busy) const LinearProgressIndicator(),
            if (error != null) Text(error!, style: const TextStyle(color: Palette.danger)),
            if (r != null) ...[
              Row(children: [
                Icon(
                  !r.needed ? Icons.info_outline : (r.uncertain ? Icons.warning_amber_rounded : Icons.check_circle_outline),
                  color: !r.needed ? Palette.text2 : (r.uncertain ? Palette.warn : Palette.ok),
                  size: 18,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    !r.needed ? S.aiNonNecessaria : (r.uncertain ? S.aiIncerto : S.aiAffidabile((r.confidence * 100).round())),
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
                Text('${r.millis} ms', style: const TextStyle(fontSize: 12, color: Palette.text3)),
              ]),
              for (final n in r.notes) Text('· $n', style: const TextStyle(fontSize: 11, color: Palette.text3)),
            ],
            const SizedBox(height: 8),
            SliderRow(
              label: S.aiSogliaBassa,
              value: st.localAi.low,
              max: 0.9,
              onChanged: (v) => setState(() => st.update(() => st.localAi.low = v.clamp(0, st.localAi.high - 0.02))),
              onChangeEnd: (_) => _run(),
            ),
            SliderRow(
              label: S.aiSogliaAlta,
              value: st.localAi.high,
              min: 0.1,
              onChanged: (v) => setState(() => st.update(() => st.localAi.high = v.clamp(st.localAi.low + 0.02, 1))),
              onChangeEnd: (_) => _run(),
            ),
            const Text(S.aiCorrezioneInfo, style: TextStyle(fontSize: 11, color: Palette.text3)),
          ]),
        ),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text(S.chiudi))],
    );
  }
}


class _Tag extends StatelessWidget {
  const _Tag(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(color: accent.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(8)),
      child: Text(text, style: TextStyle(fontSize: 11, color: accent, fontWeight: FontWeight.w600)),
    );
  }
}
