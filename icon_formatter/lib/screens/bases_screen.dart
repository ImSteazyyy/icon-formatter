import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../app/models.dart';
import '../app/state.dart';
import '../app/theme.dart';
import '../services/import_service.dart';
import '../src/rust/api/engine.dart';
import '../widgets/common.dart';
import '../l10n/strings.dart';

/// Base icon management: import, select, rename, delete, calibrate.
class BasesScreen extends StatelessWidget {
  const BasesScreen({super.key, this.embedded = false});

  final bool embedded;

  Future<void> _import(BuildContext context) async {
    final r = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['png', 'webp', 'jpg', 'jpeg'], dialogTitle: S.importaBaseIcon);
    final path = r?.files.single.path;
    if (path == null || !context.mounted) return;
    final name = await askText(context, S.nomeDelBaseIcon, initial: p.basenameWithoutExtension(path));
    if (name == null || name.isEmpty) return;
    try {
      final b = await AppState.I.importBase(path, name);
      if (context.mounted) {
        showMsg(context, S.baseImportatoCalibraloCirca20(b.width, b.height));
      }
    } catch (e) {
      if (context.mounted) showMsg(context, S.importNonRiuscito(e), error: true);
    }
  }

  Future<void> _fromPreset(BuildContext context) async {
    final st = AppState.I;
    final pr = st.activePreset;
    final size = st.export.customSize ? st.export.size : st.translucentSize;
    try {
      final png = await renderBackgroundPng(background: BackgroundSettings.translucent(params: pr.params), size: size);
      await st.addBaseFromPng(png, '${pr.name} $size', size);
      if (context.mounted) showMsg(context, S.baseCreatoDalPreset(pr.name));
    } catch (e) {
      if (context.mounted) showMsg(context, '$e', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppState.I,
      builder: (context, _) {
        final st = AppState.I;
        final content = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (!embedded) Text(S.baseIcons, style: Theme.of(context).textTheme.headlineSmall),
          if (!embedded) const SizedBox(height: 4),
          const Text(
            S.ogniBaseHaCalibrazioneIndipendente,
            style: TextStyle(color: Palette.text2, fontSize: 12),
          ),
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, children: [
            FilledButton.icon(onPressed: () => _import(context), icon: const Icon(Icons.add), label: const Text(S.importaBase)),
            OutlinedButton.icon(onPressed: () => _fromPreset(context), icon: const Icon(Icons.blur_on), label: Text(S.creaPreset(st.activePreset.name))),
          ]),
          const SizedBox(height: 14),
          for (final b in st.bases) _BaseTile(b: b, selected: st.selectedBase?.id == b.id),
          if (st.bases.isEmpty) const Text(S.nessunBaseIcon, style: TextStyle(color: Palette.text3)),
        ]);
        if (embedded) return content;
        return SingleChildScrollView(padding: const EdgeInsets.all(20), child: content);
      },
    );
  }
}

class _BaseTile extends StatelessWidget {
  const _BaseTile({required this.b, required this.selected});

  final BaseIcon b;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final st = AppState.I;
    final cal = b.calibration;
    final info = b.calibrationInfo;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Glass(
        padding: const EdgeInsets.all(12),
        child: Row(children: [
          SizedBox(width: 64, height: 64, child: Checkerboard(cell: 6, child: IconImage(path: b.path))),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Flexible(child: Text(b.name, style: Theme.of(context).textTheme.titleMedium, overflow: TextOverflow.ellipsis)),
                if (selected) ...[
                  const SizedBox(width: 8),
                  Icon(Icons.check_circle, size: 16, color: Theme.of(context).colorScheme.primary),
                ],
              ]),
              Text(S.px(b.width, b.height), style: const TextStyle(fontSize: 12, color: Palette.text2)),
              Text(
                cal == null
                    ? S.nonCalibrato
                    : S.calibratoEsempiValidiGlyph(info?['samples'] ?? '?', info?['inliers'] ?? '?', (cal.glyphRatio * 100).toStringAsFixed(1)),
                style: TextStyle(fontSize: 12, color: cal == null ? Palette.warn : Palette.text2),
              ),
            ]),
          ),
          Wrap(children: [
            if (!selected) TextButton(onPressed: () => st.update(() => st.selectedBaseId = b.id), child: const Text(S.usa)),
            TextButton(
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => CalibrationPage(base: b))),
              child: Text(cal == null ? S.calibra : S.ricalibra),
            ),
            PopupMenuButton<String>(
              onSelected: (v) async {
                if (v == 'rename') {
                  final n = await askText(context, S.rinomina, initial: b.name);
                  if (n != null && n.isNotEmpty) st.renameBase(b, n);
                } else if (v == 'delete') {
                  if (await confirm(context, S.eliminare(b.name), S.vieneRimossaCopiaInternaSua, ok: S.elimina)) {
                    await st.deleteBase(b);
                  }
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'rename', child: Text(S.rinomina)),
                PopupMenuItem(value: 'delete', child: Text(S.elimina)),
              ],
            ),
          ]),
        ]),
      ),
    );
  }
}

/// Calibration: ~20 correctly composed examples -> robust statistics,
/// visual check, manual correction and save.
class CalibrationPage extends StatefulWidget {
  const CalibrationPage({super.key, required this.base});

  final BaseIcon base;

  @override
  State<CalibrationPage> createState() => _CalibrationPageState();
}

class _CalibrationPageState extends State<CalibrationPage> {
  List<String> samples = [];
  CalibrationOutput? out;
  PlacementSettings? edit;
  bool running = false;
  String? error;
  int testIndex = 0;
  Uint8List? testPng;

  Future<void> _add(Future<List<PackImage>> Function() f) async {
    try {
      final imgs = await f();
      setState(() => samples = {...samples, ...imgs.map((e) => e.abs)}.toList());
    } catch (e) {
      if (mounted) showMsg(context, '$e', error: true);
    }
  }

  Future<void> _run() async {
    setState(() {
      running = true;
      error = null;
    });
    try {
      final r = await calibrateBase(basePath: widget.base.path, samplePaths: samples);
      setState(() {
        out = r;
        edit = r.placement;
      });
      await _test();
    } catch (e) {
      setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => running = false);
    }
  }

  Future<void> _test() async {
    if (edit == null || samples.isEmpty) return;
    final s = ProcessSettings(
      size: widget.base.size,
      background: BackgroundSettings.baseImage(path: widget.base.path),
      placement: edit!,
      segment: AppState.I.segment,
    );
    try {
      final r = await previewFile(path: samples[testIndex % samples.length], settings: s);
      if (mounted) setState(() => testPng = r.png);
    } catch (e) {
      if (mounted) setState(() => testPng = null);
    }
  }

  void _setEdit(PlacementSettings p) {
    setState(() => edit = p);
    _test();
  }

  void _save() {
    final o = out!;
    AppState.I.saveCalibration(widget.base, edit!, {
      'samples': o.samples.length,
      'inliers': o.inliers,
      'maxSideMad': o.maxSideMad,
      'centerMad': o.centerMad,
      'margins': o.margins.toList(),
      'usefulArea': o.usefulArea.toList(),
      'medianAspect': o.medianAspect,
      'date': DateTime.now().toIso8601String(),
      'manual': edit!.glyphRatio != o.placement.glyphRatio || edit!.centerX != o.placement.centerX || edit!.centerY != o.placement.centerY,
    });
    showMsg(context, S.calibrazioneSalvata(widget.base.name));
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final o = out;
    final e = edit;
    final wide = MediaQuery.of(context).size.width > 900;
    final left = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const SectionTitle(S.esempiCorrettamenteComposti),
      Text(
        S.esempiSelezionatiConsigliatiCirca20(samples.length),
        style: TextStyle(fontSize: 12, color: samples.length < 10 ? Palette.warn : Palette.text2),
      ),
      const SizedBox(height: 10),
      Wrap(spacing: 8, runSpacing: 8, children: [
        OutlinedButton.icon(onPressed: () => _add(ImportService.pickFiles), icon: const Icon(Icons.image_outlined), label: const Text(S.file)),
        OutlinedButton.icon(onPressed: () => _add(ImportService.pickFolderImages), icon: const Icon(Icons.folder_open_outlined), label: const Text(S.cartella)),
        OutlinedButton.icon(onPressed: () => _add(ImportService.pickZip), icon: const Icon(Icons.folder_zip_outlined), label: const Text(S.zipOApk)),
        if (samples.isNotEmpty) TextButton(onPressed: () => setState(() => samples = []), child: const Text(S.svuota)),
      ]),
      const SizedBox(height: 12),
      FilledButton.icon(
        onPressed: samples.isEmpty || running ? null : _run,
        icon: running ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.analytics_outlined),
        label: const Text(S.analizzaCalibra),
      ),
      if (error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(error!, style: const TextStyle(color: Palette.danger))),
      if (o != null) ...[
        const SizedBox(height: 18),
        const SectionTitle(S.risultatiMedianaOutlierEsclusi),
        _kv(S.esempiValidi, '${o.inliers} / ${o.samples.length}'),
        _kv(S.latoGlyph, S.mad((o.placement.glyphRatio * 100).toStringAsFixed(2), (o.maxSideMad * 100).toStringAsFixed(2))),
        _kv(S.areaOttica, '${(o.placement.areaRatio * 100).toStringAsFixed(2)}%'),
        _kv(S.centro, '(${o.placement.centerX.toStringAsFixed(3)}, ${o.placement.centerY.toStringAsFixed(3)})'),
        _kv(S.marginiLTRB, o.margins.map((m) => '${(m * 100).toStringAsFixed(1)}%').join(' / ')),
        _kv(S.proporzioneMedia, o.medianAspect.toStringAsFixed(2)),
        const SizedBox(height: 14),
        const SectionTitle(S.correzioneManuale),
        SliderRow(label: S.latoGlyph, value: e!.glyphRatio, min: 0.3, max: 0.95, format: (v) => '${(v * 100).toStringAsFixed(1)}%', onChanged: (v) => _setEdit(copyPlacement(e, glyphRatio: v))),
        SliderRow(label: S.centroX, value: e.centerX, min: 0.35, max: 0.65, format: (v) => v.toStringAsFixed(3), onChanged: (v) => _setEdit(copyPlacement(e, centerX: v))),
        SliderRow(label: S.centroY, value: e.centerY, min: 0.35, max: 0.65, format: (v) => v.toStringAsFixed(3), onChanged: (v) => _setEdit(copyPlacement(e, centerY: v))),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: const Text(S.dimensioneOtticaArea),
          value: e.areaFit,
          onChanged: (v) => _setEdit(copyPlacement(e, areaFit: v)),
        ),
        Row(children: [
          TextButton(onPressed: () => _setEdit(o.placement), child: const Text(S.ripristinaMisurati)),
          const Spacer(),
          FilledButton(onPressed: _save, child: const Text(S.salvaCalibrazione)),
        ]),
      ],
    ]);
    final right = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const SectionTitle(S.areaUtileSulBase),
      AspectRatio(
        aspectRatio: 1,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Checkerboard(
            child: Stack(fit: StackFit.expand, children: [
              IconImage(path: widget.base.path),
              if (o != null) CustomPaint(painter: _CalPainter(o, e!)),
            ]),
          ),
        ),
      ),
      if (o != null) ...[
        const SizedBox(height: 12),
        Row(children: [
          const Expanded(child: SectionTitle(S.verificaEsempio)),
          IconButton(
            onPressed: () {
              testIndex++;
              _test();
            },
            icon: const Icon(Icons.skip_next),
          ),
        ]),
        if (testPng != null)
          AspectRatio(aspectRatio: 1, child: ClipRRect(borderRadius: BorderRadius.circular(12), child: Checkerboard(child: IconImage(bytes: testPng)))),
        const SizedBox(height: 12),
        const SectionTitle(S.esempi),
        for (final s in o.samples)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(children: [
              StatusDot(color: s.error != null ? Palette.danger : (s.outlier ? Palette.warn : Palette.ok)),
              const SizedBox(width: 8),
              Expanded(child: Text(s.name, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12))),
              Text(
                s.error ?? '${(s.maxSideRatio * 100).toStringAsFixed(1)}% · ${s.method}${s.outlier ? ' · escluso' : ''}',
                style: const TextStyle(fontSize: 11, color: Palette.text2),
              ),
            ]),
          ),
      ],
    ]);
    return Scaffold(
      appBar: AppBar(title: Text(S.calibrazione(widget.base.name)), backgroundColor: Colors.transparent),
      body: SafeArea(
        child: wide
            ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(child: SingleChildScrollView(padding: const EdgeInsets.all(20), child: left)),
                SizedBox(width: 420, child: SingleChildScrollView(padding: const EdgeInsets.all(20), child: right)),
              ])
            : ListView(padding: const EdgeInsets.all(16), children: [left, const SizedBox(height: 20), right]),
      ),
    );
  }

  Widget _kv(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(children: [
          SizedBox(width: 150, child: Text(k, style: const TextStyle(fontSize: 12, color: Palette.text2))),
          Expanded(child: Text(v, style: const TextStyle(fontSize: 13))),
        ]),
      );
}

/// Draws sample boxes (thin), useful area (dashed-like) and target box.
class _CalPainter extends CustomPainter {
  _CalPainter(this.o, this.e);

  final CalibrationOutput o;
  final PlacementSettings e;

  @override
  void paint(Canvas canvas, Size size) {
    final thin = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = Colors.white.withValues(alpha: 0.18);
    for (final s in o.samples) {
      if (s.outlier || s.error != null) continue;
      final b = s.bbox;
      canvas.drawRect(Rect.fromLTRB(b[0] * size.width, b[1] * size.height, b[2] * size.width, b[3] * size.height), thin);
    }
    final ua = o.usefulArea;
    canvas.drawRect(
      Rect.fromLTRB(ua[0] * size.width, ua[1] * size.height, ua[2] * size.width, ua[3] * size.height),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = const Color(0xFF8FB07A),
    );
    final side = e.glyphRatio * size.width;
    final c = Offset(e.centerX * size.width, e.centerY * size.height);
    canvas.drawRect(
      Rect.fromCenter(center: c, width: side, height: side),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = const Color(0xFFD6B25E),
    );
    canvas.drawCircle(c, 3, Paint()..color = const Color(0xFFD6B25E));
  }

  @override
  bool shouldRepaint(covariant _CalPainter old) => true;
}

bool fileExists(String p) => File(p).existsSync();
