import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../app/state.dart';
import '../app/storage.dart';
import '../services/batch_controller.dart';
import '../services/bg_removal_service.dart';
import '../src/rust/api/engine.dart';

/// One icon in a workspace.
class WorkItem {
  WorkItem({
    required this.id,
    required this.name,
    required this.rel,
    this.path,
    this.bytes,
    this.label,
    this.package,
    this.activity,
  });

  final String id;

  /// Output stem (unique within the workspace).
  final String name;

  /// Relative path inside the source (packs) or file name.
  final String rel;
  final String? path;
  final Uint8List? bytes;

  // Android app metadata
  final String? label;
  final String? package;
  final String? activity;

  bool excluded = false;
  SegmentSettings? segOverride;
  PlacementSettings? placementOverride;

  /// Per-app symbol mode (Rigenera › Modalità); null = Automatica.
  LucentStrategy? strategyOverride;
  ItemResult? result;

  String? get outputPath => result?.ok == true ? result!.output : null;
  bool get hasOverride => segOverride != null || placementOverride != null || strategyOverride != null;
}

/// Shared processing state: items, selection, mode, preview, batch.
class WorkspaceController extends ChangeNotifier {
  WorkspaceController({required this.tag, StudioMode mode = StudioMode.translucent, this.packSettings = false, this.outputRelFor})
      : _mode = mode {
    if (packSettings) {
      _mode = AppState.I.packMode;
      presetId = AppState.I.packPresetId;
    }
    AppState.I.addListener(_onSettings);
    batch.addListener(_onBatch);
  }

  final String tag;

  /// Pack Cleanup: mode, preset and segmentation persisted separately.
  final bool packSettings;

  /// Output path relative to the session folder (default: `<name>.png`).
  final String Function(WorkItem)? outputRelFor;
  final List<WorkItem> items = [];
  final BatchController batch = BatchController();
  String? selectedId;
  String? outputDir;

  StudioMode _mode;
  String? presetId;

  /// When true, adjustments are stored on the selected item only.
  bool editSelectedOnly = false;

  Uint8List? previewPng;
  PreviewResult? previewInfo;
  String? previewError;
  bool previewBusy = false;
  Timer? _debounce;
  int _previewSeq = 0;

  StudioMode get mode => _mode;

  set mode(StudioMode m) {
    _mode = m;
    if (packSettings) AppState.I.update(() => AppState.I.packMode = m);
    notifyListeners();
    schedulePreview();
  }

  WorkItem? get selected {
    for (final i in items) {
      if (i.id == selectedId) return i;
    }
    return null;
  }

  List<WorkItem> get active => items.where((i) => !i.excluded).toList();

  void select(String? id) {
    selectedId = id;
    notifyListeners();
    schedulePreview(immediate: true);
  }

  void _onSettings() => schedulePreview();

  void _onBatch() {
    for (final r in batch.results.values) {
      for (final i in items) {
        if (i.id == r.id) i.result = r;
      }
    }
    notifyListeners();
  }

  // ------------------------------------------------------------------ items

  final Set<String> _names = {};

  String uniqueStem(String stem) {
    var s = stem.isEmpty ? 'icon' : stem;
    var k = 2;
    final base = s;
    while (_names.contains(s.toLowerCase())) {
      s = '${base}_$k';
      k++;
    }
    _names.add(s.toLowerCase());
    return s;
  }

  /// [placeOnly]: ready-made PNGs, not cut out nor recoloured; they are
  /// only cropped to their content, centred and sized on the icon background.
  void addPaths(List<PackImage> imgs, {bool placeOnly = false}) {
    for (final im in imgs) {
      final stem = p.basenameWithoutExtension(im.rel);
      items.add(WorkItem(
        id: 'i${DateTime.now().microsecondsSinceEpoch}_${items.length}',
        name: uniqueStem(stem),
        rel: im.rel,
        path: im.abs,
      )
        ..segOverride = placeOnly ? SegmentSettings(mode: SegMode.keepAlpha, tolerance: 0.10, removeHoles: false, refineEdges: false) : null
        ..strategyOverride = placeOnly ? LucentStrategy.asIs : null);
    }
    selectedId ??= items.isEmpty ? null : items.first.id;
    notifyListeners();
    schedulePreview(immediate: true);
  }

  void addItem(WorkItem it) {
    items.add(it);
    selectedId ??= it.id;
  }

  void notify() => notifyListeners();

  void clear() {
    items.clear();
    _names.clear();
    selectedId = null;
    previewPng = null;
    previewInfo = null;
    batch.clear();
    outputDir = null;
    notifyListeners();
  }

  void remove(WorkItem it) {
    items.remove(it);
    _names.remove(it.name.toLowerCase());
    if (selectedId == it.id) selectedId = items.isEmpty ? null : items.first.id;
    notifyListeners();
    schedulePreview(immediate: true);
  }

  void toggleExcluded(WorkItem it) {
    it.excluded = !it.excluded;
    notifyListeners();
  }

  // ------------------------------------------------------------------ settings

  SegmentSettings get globalSegment => packSettings ? AppState.I.packSegment : AppState.I.segment;

  ProcessSettings get settings => AppState.I.settingsFor(_mode, presetId: presetId, seg: globalSegment);

  void setPreset(String? id) {
    presetId = id;
    if (packSettings && id != null) AppState.I.update(() => AppState.I.packPresetId = id);
    notifyListeners();
    schedulePreview();
  }

  ProcessSettings settingsForItem(WorkItem it) {
    final s = settings;
    var bg = s.background;
    final st = it.strategyOverride;
    if (st != null && bg is BackgroundSettings_Lucent) {
      final l = bg.params;
      bg = BackgroundSettings.lucent(
        params: LucentSettings(
          ink: l.ink,
          backdrop: l.backdrop,
          shape: l.shape,
          monochrome: l.monochrome,
          keepComposition: l.keepComposition,
          glyphScale: l.glyphScale,
          rim: l.rim,
          launcherShadow: l.launcherShadow,
          nothingEncode: l.nothingEncode,
          strategy: st,
        ),
      );
    }
    return ProcessSettings(
      size: s.size,
      background: bg,
      placement: it.placementOverride ?? s.placement,
      segment: it.segOverride ?? s.segment,
    );
  }

  /// Current effective placement for the editor (item override or global).
  PlacementSettings get editPlacement {
    final it = selected;
    if (editSelectedOnly && it?.placementOverride != null) return it!.placementOverride!;
    return settings.placement;
  }

  SegmentSettings get editSegment {
    final it = selected;
    if (editSelectedOnly && it?.segOverride != null) return it!.segOverride!;
    return settings.segment;
  }

  void setPlacement(PlacementSettings pl) {
    final it = selected;
    if (editSelectedOnly && it != null) {
      it.placementOverride = pl;
      notifyListeners();
      schedulePreview();
    } else {
      AppState.I.update(() {
        AppState.I.scaleMul = pl.scaleMul;
        AppState.I.offsetX = pl.offsetX;
        AppState.I.offsetY = pl.offsetY;
      });
    }
  }

  void setSegment(SegmentSettings s) {
    final it = selected;
    if (editSelectedOnly && it != null) {
      it.segOverride = s;
      notifyListeners();
      schedulePreview();
    } else {
      AppState.I.update(() {
        if (packSettings) {
          AppState.I.packSegment = s;
        } else {
          AppState.I.segment = s;
        }
      });
    }
  }

  /// Rigenera › Modalità: forces how the symbol is taken for one icon.
  void setStrategy(WorkItem it, LucentStrategy? st) {
    it.strategyOverride = st == LucentStrategy.auto ? null : st;
    notifyListeners();
    process(only: [it]);
    schedulePreview(immediate: true);
  }

  void clearOverrides(WorkItem it) {
    it.segOverride = null;
    it.placementOverride = null;
    it.strategyOverride = null;
    notifyListeners();
    schedulePreview();
  }

  // ------------------------------------------------------------------ preview

  void schedulePreview({bool immediate = false}) {
    _debounce?.cancel();
    _debounce = Timer(Duration(milliseconds: immediate ? 0 : 90), _runPreview);
  }

  Future<void> _runPreview() async {
    final it = selected;
    if (it == null) {
      previewPng = null;
      previewInfo = null;
      notifyListeners();
      return;
    }
    final seq = ++_previewSeq;
    previewBusy = true;
    notifyListeners();
    try {
      var s = settingsForItem(it);
      PreviewResult r;
      if (AppState.I.bgProvider == BgProvider.removeBg) {
        final cut = await BgRemovalService.cutout(cacheKey: it.id + (it.path ?? ''), path: it.path, bytes: it.bytes);
        if (seq != _previewSeq) return;
        s = ProcessSettings(size: s.size, background: s.background, placement: s.placement, segment: _keepAlpha(s.segment));
        r = await previewFile(path: cut, settings: s);
      } else {
        r = it.path != null ? await previewFile(path: it.path!, settings: s) : await previewBytes(bytes: it.bytes!, settings: s);
      }
      if (seq != _previewSeq) return;
      previewPng = r.png;
      previewInfo = r;
      previewError = null;
    } catch (e) {
      if (seq != _previewSeq) return;
      previewError = e.toString();
      previewPng = null;
      previewInfo = null;
    } finally {
      if (seq == _previewSeq) {
        previewBusy = false;
        notifyListeners();
      }
    }
  }

  // ------------------------------------------------------------------ batch

  Future<void> process({Iterable<WorkItem>? only}) async {
    final list = (only ?? active).where((i) => !i.excluded).toList();
    if (list.isEmpty || batch.running) return;
    outputDir ??= await AppPaths.I.outputSession(tag);
    final s = settings;
    final cloud = AppState.I.bgProvider == BgProvider.removeBg;
    final cutouts = <String, String>{};
    if (cloud) {
      // Cloud pre-pass: one remove.bg call per image (cached), 3 in flight.
      var done = 0, errors = 0;
      batch.external(phase: 'remove.bg', done: 0, total: list.length, errors: 0, running: true);
      final queue = [...list];
      Future<void> worker() async {
        while (queue.isNotEmpty && !batch.cancelRequested) {
          final it = queue.removeAt(0);
          try {
            cutouts[it.id] = await BgRemovalService.cutout(cacheKey: it.id + (it.path ?? ''), path: it.path, bytes: it.bytes);
          } catch (e) {
            errors++;
            it.result = ItemResult(id: it.id, name: it.name, ok: false, error: e.toString(), ambiguous: true, confidence: 0, method: 'remove.bg', notes: const []);
          }
          done++;
          batch.external(phase: 'remove.bg', done: done, total: list.length, errors: errors, running: true);
          notifyListeners();
        }
      }
      await Future.wait([worker(), worker(), worker()]);
      batch.external(phase: 'remove.bg', done: done, total: list.length, errors: errors, running: false);
      if (batch.cancelRequested) return;
    }
    final batchItems = <BatchItem>[];
    for (final it in list) {
      if (cloud && !cutouts.containsKey(it.id)) continue;
      final out = p.joinAll([outputDir!, ...(outputRelFor?.call(it) ?? '${it.name}.png').split('/')]);
      batchItems.add(BatchItem(
        id: it.id,
        name: it.name,
        path: cloud ? cutouts[it.id] : it.path,
        bytes: !cloud && it.path == null ? it.bytes : null,
        output: out,
        segment: it.segOverride,
        placement: it.placementOverride,
        skipIsolation: cloud,
      ));
    }
    if (batchItems.isNotEmpty) await batch.run(batchItems, s);
  }

  SegmentSettings _keepAlpha(SegmentSettings s) =>
      SegmentSettings(mode: SegMode.keepAlpha, tolerance: s.tolerance, removeHoles: s.removeHoles, refineEdges: s.refineEdges);

  List<WorkItem> get processed => items.where((i) => !i.excluded && i.outputPath != null && File(i.outputPath!).existsSync()).toList();

  List<WorkItem> get ambiguous => items.where((i) => i.result?.ambiguous == true && i.result?.ok == true).toList();

  @override
  void dispose() {
    AppState.I.removeListener(_onSettings);
    batch.removeListener(_onBatch);
    batch.dispose();
    _debounce?.cancel();
    super.dispose();
  }
}
