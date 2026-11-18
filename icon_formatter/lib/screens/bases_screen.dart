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
          Text(S.ogniBaseHaCalibrazioneIndipendente, style: TextStyle(color: Palette.text2, fontSize: 13)),
          const SizedBox(height: 14),
          // two equal actions side by side
          Row(children: [
            Expanded(child: ToolButton(icon: Icons.add_rounded, label: S.importaBase, onTap: () => _import(context))),
            const SizedBox(width: 10),
            Expanded(child: ToolButton(icon: Icons.blur_on_rounded, label: S.creaDaPreset, onTap: () => _fromPreset(context))),
          ]),
          const SizedBox(height: 16),
          for (final b in st.bases) _BaseTile(b: b, selected: st.selectedBase?.id == b.id),
          if (st.bases.isEmpty) Text(S.nessunBaseIcon, style: TextStyle(color: Palette.text3)),
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
    // tap = use it; the menu holds calibration, rename and delete
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Glass(
        padding: EdgeInsets.zero,
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: BorderRadius.circular(AppState.I.appearance.radius),
            onTap: () => st.update(() => st.selectedBaseId = b.id),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 4, 12),
              child: Row(children: [
                SizedBox(width: 56, height: 56, child: IconImage(path: b.path)),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(b.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: Palette.text)),
                    const SizedBox(height: 2),
                    Text(
                      selected ? S.inUso : (cal == null ? S.daCalibrare : S.calibrata),
                      style: TextStyle(fontSize: 12.5, color: cal == null && !selected ? Palette.warn : Palette.text2),
                    ),
                  ]),
                ),
                if (selected) Icon(Icons.check_circle_rounded, size: 22, color: Theme.of(context).colorScheme.primary),
                PopupMenuButton<String>(
                  onSelected: (v) async {
                    if (v == 'cal') {
                      await Navigator.of(context).push(MaterialPageRoute(builder: (_) => CalibrationPage(base: b)));
                    } else if (v == 'rename') {
                      final n = await askText(context, S.rinomina, initial: b.name);
                      if (n != null && n.isNotEmpty) st.renameBase(b, n);
                    } else if (v == 'delete') {
                      if (await confirm(context, S.eliminare(b.label), S.vieneRimossaCopiaInternaSua, ok: S.elimina)) {
                        await st.deleteBase(b);
                      }
                    }
                  },
                  itemBuilder: (_) => [
                    PopupMenuItem(value: 'cal', child: Text(cal == null ? S.calibra : S.ricalibra)),
                    if (!b.builtIn) PopupMenuItem(value: 'rename', child: Text(S.rinomina)),
                    if (!b.builtIn) PopupMenuItem(value: 'delete', child: Text(S.elimina)),
                  ],
                ),
              ]),
            ),
          ),
        ),
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
    showMsg(context, S.calibrazioneSalvata(widget.base.label));
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final o = out;
    final e = edit;
    final wide = MediaQuery.of(context).size.width > 900;
    final left = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SectionTitle(S.esempiCorrettamenteComposti),
      Text(
        S.esempiSelezionatiConsigliatiCirca20(samples.length),
        style: TextStyle(fontSize: 12, color: samples.length < 10 ? Palette.warn : Palette.text2),
      ),
      const SizedBox(height: 10),
      Wrap(spacing: 8, runSpacing: 8, children: [
        OutlinedButton.icon(onPressed: () => _add(ImportService.pickFiles), icon: const Icon(Icons.image_outlined), label: Text(S.file)),
        OutlinedButton.icon(onPressed: () => _add(ImportService.pickFolderImages), icon: const Icon(Icons.folder_open_outlined), label: Text(S.cartella)),
        OutlinedButton.icon(onPressed: () => _add(ImportService.pickZip), icon: const Icon(Icons.folder_zip_outlined), label: Text(S.zipOApk)),
        if (samples.isNotEmpty) TextButton(onPressed: () => setState(() => samples = []), child: Text(S.svuota)),
      ]),
      const SizedBox(height: 12),
      FilledButton.icon(
        onPressed: samples.isEmpty || running ? null : _run,
        icon: running ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.analytics_outlined),
        label: Text(S.analizzaCalibra),
      ),
      if (error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(error!, style: TextStyle(color: Palette.danger))),
      if (o != null) ...[
        const SizedBox(height: 18),
        SectionTitle(S.risultatiMedianaOutlierEsclusi),
        _kv(S.esempiValidi, '${o.inliers} / ${o.samples.length}'),
        _kv(S.latoGlyph, S.mad((o.placement.glyphRatio * 100).toStringAsFixed(2), (o.maxSideMad * 100).toStringAsFixed(2))),
        _kv(S.areaOttica, '${(o.placement.areaRatio * 100).toStringAsFixed(2)}%'),
        _kv(S.centro, '(${o.placement.centerX.toStringAsFixed(3)}, ${o.placement.centerY.toStringAsFixed(3)})'),
        _kv(S.marginiLTRB, o.margins.map((m) => '${(m * 100).toStringAsFixed(1)}%').join(' / ')),
        _kv(S.proporzioneMedia, o.medianAspect.toStringAsFixed(2)),
        const SizedBox(height: 14),
        SectionTitle(S.correzioneManuale),
        SliderRow(label: S.latoGlyph, value: e!.glyphRatio, min: 0.3, max: 0.95, format: (v) => '${(v * 100).toStringAsFixed(1)}%', onChanged: (v) => _setEdit(copyPlacement(e, glyphRatio: v))),
        SliderRow(label: S.centroX, value: e.centerX, min: 0.35, max: 0.65, format: (v) => v.toStringAsFixed(3), onChanged: (v) => _setEdit(copyPlacement(e, centerX: v))),
        SliderRow(label: S.centroY, value: e.centerY, min: 0.35, max: 0.65, format: (v) => v.toStringAsFixed(3), onChanged: (v) => _setEdit(copyPlacement(e, centerY: v))),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: Text(S.dimensioneOtticaArea),
          value: e.areaFit,
          onChanged: (v) => _setEdit(copyPlacement(e, areaFit: v)),
        ),
        Row(children: [
          TextButton(onPressed: () => _setEdit(o.placement), child: Text(S.ripristinaMisurati)),
          const Spacer(),
          FilledButton(onPressed: _save, child: Text(S.salvaCalibrazione)),
        ]),
      ],
    ]);
    final right = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SectionTitle(S.areaUtileSulBase),
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
          Expanded(child: SectionTitle(S.verificaEsempio)),
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
        SectionTitle(S.esempi),
        for (final s in o.samples)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(children: [
              StatusDot(color: s.error != null ? Palette.danger : (s.outlier ? Palette.warn : Palette.ok)),
              const SizedBox(width: 8),
              Expanded(child: Text(s.name, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12))),
              Text(
                s.error ?? '${(s.maxSideRatio * 100).toStringAsFixed(1)}% · ${s.method}${s.outlier ? ' · escluso' : ''}',
                style: TextStyle(fontSize: 11, color: Palette.text2),
              ),
            ]),
          ),
      ],
    ]);
    return Scaffold(
      appBar: AppBar(title: Text(S.calibrazione(widget.base.label)), backgroundColor: Colors.transparent),
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
          SizedBox(width: 150, child: Text(k, style: TextStyle(fontSize: 12, color: Palette.text2))),
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
      ..color = Palette.fg.withValues(alpha: 0.18);
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
