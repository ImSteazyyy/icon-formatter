import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show ScrollController;
import 'package:path/path.dart' as p;

import '../app/models.dart' show copySegment, copyPlacement;
import '../app/state.dart';
import '../app/storage.dart';
import '../services/batch_controller.dart';
import '../services/bg_removal_service.dart';
import '../src/rust/api/engine.dart';
import 'studio_duplicates.dart';
import 'studio_history.dart';
import 'studio_list.dart';

/// One icon in a workspace.
class WorkItem {
  WorkItem({required this.id, required this.name, required this.rel, this.path, this.bytes, this.label, this.package, this.activity});

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

  /// Per-icon plate shape and colour (Lucent only); null = the global ones.
  LucentShape? shapeOverride;
  int? backdropOverride;

  /// 1..31: one day of a dynamic calendar icon taken from an icon pack.
  int? calendarDay;

  /// "Sfondo come il pack": after every processing the plate is brought to the
  /// transparency of the other icons.
  bool matchPlate = false;
  ItemResult? result;

  /// Size and hash of the source file, set by the duplicate scan (null: not checked).
  String? fingerprint;

  /// Id of the first icon with the same file, when this one is a duplicate.
  String? duplicateOf;
  bool get isDuplicate => duplicateOf != null;

  String? get outputPath => result?.ok == true ? result!.output : null;
  bool get hasOverride => segOverride != null || placementOverride != null || strategyOverride != null || shapeOverride != null || backdropOverride != null || matchPlate;
}

/// Shared processing state: items, selection, mode, preview, batch.
class WorkspaceController extends ChangeNotifier {
  WorkspaceController({required this.tag, StudioMode mode = StudioMode.translucent, this.packSettings = false, this.outputRelFor}) : _mode = mode {
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

  /// Undo/redo of the corrections (values only, see StudioHistory).
  final StudioHistory<Map<String, ItemCorrection>> _history = StudioHistory();
  bool get canUndo => _history.canUndo;
  bool get canRedo => _history.canRedo;

  /// Icons picked with a long press (ids); the selection bar acts on them.
  final Set<String> selection = {};
  bool get selecting => selection.isNotEmpty;

  StudioSort sort = StudioSort.added;
  StudioFilter filter = StudioFilter.all;

  /// Preview overlay: plate edge and centre cross (never baked into the output).
  bool safeGuide = false;

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
    // one index per notification: the old nested loop was items x results on
    // every progress tick (166 ms per tick on the host at 5000 icons)
    final byId = {for (final i in items) i.id: i};
    for (final r in batch.results.values) {
      final i = byId[r.id];
      if (i != null) i.result = r;
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
  List<WorkItem> addPaths(List<PackImage> imgs, {bool placeOnly = false}) {
    final added = <WorkItem>[];
    for (final im in imgs) {
      final stem = p.basenameWithoutExtension(im.rel);
      added.add(
        WorkItem(id: 'i${DateTime.now().microsecondsSinceEpoch}_${items.length + added.length}', name: uniqueStem(stem), rel: im.rel, path: im.abs)
          ..segOverride = placeOnly ? SegmentSettings(mode: SegMode.keepAlpha, tolerance: 0.10, removeHoles: false, refineEdges: false) : null
          ..strategyOverride = placeOnly ? LucentStrategy.asIs : null,
      );
      items.add(added.last);
    }
    selectedId ??= items.isEmpty ? null : items.first.id;
    notifyListeners();
    schedulePreview(immediate: true);
    scanDuplicates();
    return added;
  }

  /// Size of one icon (its own placement, else the global one).
  double itemScale(WorkItem it) => (it.placementOverride ?? settings.placement).scaleMul;

  /// "Dimensione": sets the size of [its] only and re-renders them.
  Future<void> setItemsScale(List<WorkItem> its, double v) async {
    _edit('scale', its, () {
      for (final it in its) {
        it.placementOverride = copyPlacement(it.placementOverride ?? settings.placement, scaleMul: v);
      }
    });
    notifyListeners();
    await process(only: its);
    notifyListeners();
  }

  /// Studio › "Calendario da un icon pack": every day of the pack's calendar
  /// icons, tagged with app and day; they are processed like any icon.
  void addCalendar(List<CalendarIconInfo> days) {
    for (final d in days) {
      final stem = '${d.package.replaceAll('.', '_')}_calendario_${d.day}';
      items.add(
        WorkItem(id: 'c${DateTime.now().microsecondsSinceEpoch}_${items.length}', name: uniqueStem(stem), rel: p.basename(d.path), path: d.path, label: 'Calendario ${d.day}', package: d.package, activity: d.activity)
          ..calendarDay = d.day
          // the page of another pack has a tile of its own that would stack
          // on the plate: its background takes the plate's transparency
          ..matchPlate = true
          // pack icons are already cut out: the whole page (number included)
          // is the artwork, it is only trimmed and placed on the plate
          ..segOverride = SegmentSettings(mode: SegMode.keepAlpha, tolerance: 0.10, removeHoles: false, refineEdges: false)
          ..strategyOverride = LucentStrategy.tile,
      );
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
    _history.clear();
    selection.clear();
    _dupScan++;
    notifyListeners();
  }

  void remove(WorkItem it) {
    items.remove(it);
    _names.remove(it.name.toLowerCase());
    selection.remove(it.id);
    if (selectedId == it.id) selectedId = items.isEmpty ? null : items.first.id;
    _markDuplicates();
    notifyListeners();
    schedulePreview(immediate: true);
  }

  void toggleExcluded(WorkItem it) {
    _edit('exclude', [it], () => it.excluded = !it.excluded);
    notifyListeners();
  }

  // ------------------------------------------------------------------ selection

  bool isSelected(WorkItem it) => selection.contains(it.id);

  List<WorkItem> get selectedItems => [for (final i in items) if (selection.contains(i.id)) i];

  void toggleSelect(WorkItem it) {
    if (!selection.remove(it.id)) selection.add(it.id);
    notifyListeners();
  }

  void clearSelection() {
    if (selection.isEmpty) return;
    selection.clear();
    notifyListeners();
  }

  /// Selection bar: excludes or includes the selected icons (undoable).
  Future<void> setSelectedExcluded(bool excluded) async {
    final its = selectedItems;
    if (its.isEmpty) return;
    _edit('exclude', its, () {
      for (final i in its) {
        i.excluded = excluded;
      }
    });
    selection.clear();
    notifyListeners();
    // an icon included again without output is processed now
    final missing = [for (final i in its) if (!excluded && i.outputPath == null) i];
    if (missing.isNotEmpty) await process(only: missing);
    notifyListeners();
  }

  /// Selection bar: takes the icons out of the list (the files stay).
  void removeSelected() {
    final its = selectedItems;
    for (final it in its) {
      items.remove(it);
      _names.remove(it.name.toLowerCase());
    }
    selection.clear();
    if (selectedId != null && items.every((i) => i.id != selectedId)) selectedId = items.isEmpty ? null : items.first.id;
    _markDuplicates();
    notifyListeners();
    schedulePreview(immediate: true);
  }

  // ------------------------------------------------------------------ sort / filter

  void setSort(StudioSort s) {
    if (s == sort) return;
    sort = s;
    notifyListeners();
  }

  void setFilter(StudioFilter f) {
    if (f == filter) return;
    filter = f;
    notifyListeners();
  }

  void toggleSafeGuide() {
    safeGuide = !safeGuide;
    notifyListeners();
  }

  // ------------------------------------------------------------------ duplicates

  /// Icons flagged as duplicates and not excluded yet.
  int get duplicateCount => items.where((i) => i.isDuplicate && !i.excluded).length;

  /// Icons that are the same file as an earlier one are excluded (undoable).
  int excludeDuplicates() {
    final d = [for (final i in items) if (i.isDuplicate && !i.excluded) i];
    if (d.isEmpty) return 0;
    _edit('exclude', d, () {
      for (final i in d) {
        i.excluded = true;
      }
    });
    notifyListeners();
    return d.length;
  }

  /// Bumped by every scan and by clear(): an older scan stops when it sees a newer one.
  int _dupScan = 0;

  /// Files over this size are not hashed (they are not flagged as duplicates).
  static const _dupMaxBytes = 8 * 1024 * 1024;

  /// Only the first icons are checked: a long list must not stall the import.
  static const _dupMaxItems = 400;

  /// Background check: files of equal size are hashed and compared. Each
  /// file is hashed once (the fingerprint is kept on the item).
  Future<void> scanDuplicates() async {
    final gen = ++_dupScan;
    final bySize = <int, List<WorkItem>>{};
    // calendar pages of a pack are never duplicates: each day is its own icon
    for (final it in items.take(_dupMaxItems).toList()) {
      if (it.fingerprint != null || it.calendarDay != null) continue;
      final size = await _sizeOf(it);
      if (gen != _dupScan) return;
      if (size != null && size <= _dupMaxBytes) bySize.putIfAbsent(size, () => []).add(it);
    }
    for (final e in bySize.entries) {
      if (e.value.length < 2) continue;
      for (final it in e.value) {
        if (gen != _dupScan) return;
        try {
          // the hash runs over every byte: off the UI isolate for files
          final path = it.path;
          final h = it.bytes != null ? studioHash(it.bytes!) : await Isolate.run(() => studioHash(File(path!).readAsBytesSync()));
          it.fingerprint = '${e.key}:$h';
        } catch (_) {
          // unreadable file: not a duplicate candidate
        }
        await Future<void>.delayed(Duration.zero);
      }
    }
    if (gen != _dupScan) return;
    _markDuplicates();
    notifyListeners();
  }

  Future<int?> _sizeOf(WorkItem it) async {
    if (it.bytes != null) return it.bytes!.length;
    try {
      return await File(it.path!).length();
    } catch (_) {
      return null;
    }
  }

  void _markDuplicates() {
    final dups = studioDuplicates([for (final i in items) if (i.fingerprint != null && i.calendarDay == null) MapEntry(i.id, i.fingerprint!)]);
    for (final i in items) {
      i.duplicateOf = dups[i.id];
    }
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
    if (bg is BackgroundSettings_Lucent && (st != null || it.shapeOverride != null || it.backdropOverride != null)) {
      final l = bg.params;
      bg = BackgroundSettings.lucent(
        params: LucentSettings(
          ink: l.ink,
          backdrop: it.backdropOverride ?? l.backdrop,
          shape: it.shapeOverride ?? l.shape,
          monochrome: l.monochrome,
          keepComposition: l.keepComposition,
          glyphScale: l.glyphScale,
          rim: l.rim,
          launcherShadow: l.launcherShadow,
          launcherEncode: l.launcherEncode,
          strategy: st ?? l.strategy,
        ),
      );
    }
    return ProcessSettings(size: s.size, background: bg, placement: _placementOf(it, s), segment: it.segOverride ?? s.segment, effects: s.effects, cutCacheDir: s.cutCacheDir);
  }

  /// Placement of [it] with the global optical-centre switch applied.
  PlacementSettings _placementOf(WorkItem it, ProcessSettings s) => copyPlacement(it.placementOverride ?? s.placement, opticalCentre: AppState.I.look.opticalCentre);

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
      _edit('placement', [it], () {
        it.placementOverride = pl;
      });
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
      _edit('segment', [it], () {
        it.segOverride = s;
      });
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
    _edit('strategy', [it], () {
      it.strategyOverride = st == LucentStrategy.auto ? null : st;
    });
    notifyListeners();
    process(only: [it]);
    schedulePreview(immediate: true);
  }

  /// Per-icon plate shape / colour (Lucent): undoable, and the icon is processed again.
  void setItemShape(WorkItem it, LucentShape? v) => _setLook('shape', it, () => it.shapeOverride = v);

  void setItemBackdrop(WorkItem it, int? v) => _setLook('backdrop', it, () => it.backdropOverride = v);

  void _setLook(String kind, WorkItem it, void Function() change) {
    _edit(kind, [it], change);
    notifyListeners();
    process(only: [it]);
    schedulePreview(immediate: true);
  }

  /// White areas closed inside the symbol (Calendar's page, a clock face):
  /// by default they count as background and are removed; per icon they can
  /// be kept (only the "sfondo racchiuso" switch of this icon changes).
  bool keepsInnerWhite(WorkItem it) => !(it.segOverride ?? settings.segment).removeHoles;

  void setKeepInnerWhite(WorkItem it, bool keep) {
    _edit('white', [it], () {
      it.segOverride = copySegment(it.segOverride ?? settings.segment, removeHoles: !keep);
    });
    notifyListeners();
    process(only: [it]);
    schedulePreview(immediate: true);
  }

  void clearOverrides(WorkItem it) {
    _edit('clear', [it], () {
      it.segOverride = null;
      it.placementOverride = null;
      it.strategyOverride = null;
      it.shapeOverride = null;
      it.backdropOverride = null;
      it.matchPlate = false;
    });
    notifyListeners();
    schedulePreview();
  }

  /// Icons that take the corrections of [src]; calendar pages keep their own.
  List<WorkItem> overrideTargets(WorkItem src) => [for (final i in active) if (i != src && i.calendarDay == null) i];

  /// "Applica a tutte le icone": copies the corrections of [src] onto the
  /// [overrideTargets] (replacing theirs) and processes them again.
  /// Returns how many icons were changed.
  Future<int> applyOverridesToAll(WorkItem src) => applyOverridesTo(src, overrideTargets(src));

  /// The corrections of [src] onto [targets] (calendar pages and [src] itself
  /// are skipped), then processed again. Returns how many icons changed.
  Future<int> applyOverridesTo(WorkItem src, List<WorkItem> targets) async {
    final its = [for (final i in targets) if (i != src && i.calendarDay == null && !i.excluded) i];
    if (its.isEmpty || batch.running) return 0;
    _edit('apply', its, () {
      for (final it in its) {
        it.segOverride = src.segOverride;
        it.placementOverride = src.placementOverride;
        it.strategyOverride = src.strategyOverride;
        it.shapeOverride = src.shapeOverride;
        it.backdropOverride = src.backdropOverride;
        it.matchPlate = src.matchPlate;
      }
    });
    notifyListeners();
    await process(only: its);
    schedulePreview();
    return its.length;
  }

  /// Selection bar: the corrections of the previewed icon go to the other
  /// selected icons. Returns how many icons changed (0: nothing to copy).
  Future<int> applySelectionCorrections() async {
    final src = selected;
    if (src == null || !src.hasOverride || batch.running) return 0;
    final n = await applyOverridesTo(src, selectedItems);
    selection.clear();
    notifyListeners();
    return n;
  }

  // ------------------------------------------------------------------ undo / redo

  /// Records one correction: the state of [its] before and after [change].
  /// Steps of the same kind on the same icons within a moment are merged.
  void _edit(String kind, List<WorkItem> its, void Function() change) {
    if (its.isEmpty) {
      change();
      return;
    }
    final before = _snapshot(its);
    change();
    final after = _snapshot(its);
    final changed = [for (final id in before.keys) if (!before[id]!.sameAs(after[id]!)) id];
    if (changed.isEmpty) return;
    _history.push('$kind:${its.length}:${its.first.id}', before, after, DateTime.now());
  }

  Map<String, ItemCorrection> _snapshot(List<WorkItem> its) => {
        for (final i in its)
          i.id: ItemCorrection(
            seg: i.segOverride,
            placement: i.placementOverride,
            strategy: i.strategyOverride,
            shape: i.shapeOverride,
            backdrop: i.backdropOverride,
            matchPlate: i.matchPlate,
            excluded: i.excluded,
          ),
      };

  /// Undoes the last correction. Does nothing while a batch runs.
  Future<void> undo() async {
    if (batch.running || !_history.canUndo) return;
    final s = _history.undo();
    if (s != null) await _restore(s);
  }

  /// Redoes the last undone correction.
  Future<void> redo() async {
    if (batch.running || !_history.canRedo) return;
    final s = _history.redo();
    if (s != null) await _restore(s);
  }

  /// Writes the states back and processes the icons whose look changed.
  Future<void> _restore(Map<String, ItemCorrection> state) async {
    final toRun = <WorkItem>[];
    for (final i in items) {
      final s = state[i.id];
      if (s == null) continue;
      final touches = !s.sameLook(ItemCorrection(seg: i.segOverride, placement: i.placementOverride, strategy: i.strategyOverride, shape: i.shapeOverride, backdrop: i.backdropOverride, matchPlate: i.matchPlate));
      i.segOverride = s.seg;
      i.placementOverride = s.placement;
      i.strategyOverride = s.strategy;
      i.shapeOverride = s.shape;
      i.backdropOverride = s.backdrop;
      i.matchPlate = s.matchPlate;
      i.excluded = s.excluded;
      if (touches || (!s.excluded && i.outputPath == null)) toRun.add(i);
    }
    notifyListeners();
    if (toRun.isNotEmpty) await process(only: toRun);
    schedulePreview(immediate: true);
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
        s = ProcessSettings(size: s.size, background: s.background, placement: s.placement, segment: _keepAlpha(s.segment), effects: s.effects, cutCacheDir: s.cutCacheDir);
        r = await previewFile(path: cut, settings: s);
      } else {
        r = it.path != null ? await previewFile(path: it.path!, settings: s) : await previewBytes(bytes: it.bytes!, settings: s);
      }
      if (seq != _previewSeq) return;
      var png = r.png;
      final plate = _stylePlateAlpha;
      if (it.matchPlate && plate != null) {
        try {
          png = await matchPlateAlphaPng(png: png, reference: plate);
        } catch (_) {}
        if (seq != _previewSeq) return;
      }
      previewPng = png;
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
      batchItems.add(
        BatchItem(
          id: it.id,
          name: it.name,
          path: cloud ? cutouts[it.id] : it.path,
          bytes: !cloud && it.path == null ? it.bytes : null,
          output: out,
          segment: it.segOverride,
          placement: _placementOf(it, s),
          skipIsolation: cloud,
          shape: it.shapeOverride,
          backdrop: it.backdropOverride,
        ),
      );
    }
    if (batchItems.isEmpty) return;
    // the per-icon symbol mode (Rigenera › Modalità, calendar pages) lives
    // in the background settings: one run per mode, the plain ones first
    final byMode = <LucentStrategy?, List<BatchItem>>{};
    final itemById = {for (final it in list) it.id: it};
    for (final b in batchItems) {
      byMode.putIfAbsent(itemById[b.id]?.strategyOverride, () => []).add(b);
    }
    for (final e in byMode.entries) {
      if (batch.cancelRequested) break;
      final first = itemById[e.value.first.id]!;
      await batch.run(e.value, e.key == null ? s : ProcessSettings(size: s.size, background: settingsForItem(first).background, placement: s.placement, segment: s.segment, effects: s.effects, cutCacheDir: s.cutCacheDir));
    }
    // icons marked "Sfondo come il pack" keep it through a new processing
    final marked = list.where((i) => i.matchPlate).toList();
    if (marked.isNotEmpty && !batch.cancelRequested) await _applyPlateMatch(marked);
  }

  /// "Sfondo come il pack": the plate of [its] takes the transparency of the
  /// other processed icons (their median); with none, the plate of the current
  /// style. Remembered per icon, so a new processing keeps it. Null when
  /// there is nothing processed to work on.
  Future<PlateMatch?> matchPlateOf(List<WorkItem> its) async {
    _edit('plate', its, () {
      for (final it in its) {
        it.matchPlate = true;
      }
    });
    return _applyPlateMatch(its);
  }

  /// The same for every calendar page of the list.
  Future<PlateMatch?> matchPlateAll() => matchPlateOf([for (final i in items) if (!i.excluded && i.calendarDay != null) i]);

  /// Alpha (0..1) of the plate the current style draws, 0 included; null when
  /// the style has no such plate.
  double? get _stylePlateAlpha {
    final bg = settings.background;
    return bg is BackgroundSettings_Lucent ? ((bg.params.backdrop >> 24) & 0xFF) / 255.0 : null;
  }

  Future<PlateMatch?> _applyPlateMatch(List<WorkItem> its) async {
    bool onDisk(WorkItem i) => i.outputPath != null && File(i.outputPath!).existsSync();
    final targets = [for (final i in its) if (onDisk(i)) i.outputPath!];
    if (targets.isEmpty) return null;
    final ids = {for (final i in its) i.id};
    // the pack: every other processed icon that is not itself being matched
    final refs = [
      for (final i in items)
        if (!i.excluded && !ids.contains(i.id) && !i.matchPlate && i.calendarDay == null && onDisk(i)) i.outputPath!,
    ];
    try {
      final r = await matchPlateAlpha(targets: targets, references: refs.take(40).toList(), style: _stylePlateAlpha ?? -1);
      notifyListeners();
      return r;
    } catch (_) {
      return null;
    }
  }

  SegmentSettings _keepAlpha(SegmentSettings s) => SegmentSettings(mode: SegMode.keepAlpha, tolerance: s.tolerance, removeHoles: s.removeHoles, refineEdges: s.refineEdges);

  /// Processed items whose output is still on disk (sync I/O per item: for
  /// actions such as export, not for build methods).
  List<WorkItem> get processed => items.where((i) => !i.excluded && i.outputPath != null && File(i.outputPath!).existsSync()).toList();

  /// How many items have an output, without touching the disk: safe to call
  /// on every rebuild (a batch rebuilds the screen several times a second).
  /// Scroll position of the icon grid (jump to top / bottom buttons).
  final ScrollController gridScroll = ScrollController();

  /// Studio search: file name, app name or path contains [query].
  String query = '';

  void setQuery(String q) {
    if (q == query) return;
    query = q;
    notifyListeners();
  }

  /// What the grid shows: search, filter and sort (display only; processing
  /// always works on [active]).
  List<WorkItem> get visibleItems => studioArrange(items, query: query, sort: sort, filter: filter);

  int get processedCount => items.where((i) => !i.excluded && i.outputPath != null).length;

  List<WorkItem> get ambiguous => items.where((i) => i.result?.ambiguous == true && i.result?.ok == true).toList();

  @override
  void dispose() {
    _dupScan++;
    gridScroll.dispose();
    AppState.I.removeListener(_onSettings);
    batch.removeListener(_onBatch);
    batch.dispose();
    _debounce?.cancel();
    super.dispose();
  }
}
