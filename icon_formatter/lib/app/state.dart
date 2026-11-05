import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../services/bg_removal_service.dart';
import '../src/rust/api/engine.dart';
import 'models.dart';
import 'storage.dart';
import '../l10n/strings.dart';

enum StudioMode { original, translucent, preset }

/// Global persisted app state.
class AppState extends ChangeNotifier {
  AppState._();

  static final AppState I = AppState._();

  late TranslucentSettings defaultTranslucent;
  late PlacementSettings defaultPlacement;
  late SegmentSettings defaultSegment;

  final Appearance appearance = Appearance();
  final ExportSettings export = ExportSettings();
  final AiConfig ai = AiConfig();
  final GlassConfig glass = GlassConfig();
  final LucentConfig lucent = LucentConfig();
  final LocalAiConfig localAi = LocalAiConfig();

  List<StylePreset> presets = [];
  String activePresetId = 'nothing';
  List<BaseIcon> bases = [];
  String? selectedBaseId;

  // Processing defaults
  late SegmentSettings segment;
  double scaleMul = 1.0;
  double offsetX = 0;
  double offsetY = 0;
  bool useBaseCalibrationForTranslucent = false;
  int translucentSize = 512;
  int threads = 0;

  /// Background removal provider (local Rust is the default).
  BgProvider bgProvider = BgProvider.local;

  // Pack cleanup
  late SegmentSettings packSegment;
  StudioMode packMode = StudioMode.translucent;
  String packPresetId = 'nothing';

  // Android: packages processed into the current pack
  Set<String> processedPackages = {};

  /// Icon Pack Builder: manual corrections by original key (package or file).
  Map<String, Map<String, dynamic>> packCorrections = {};

  bool _loaded = false;

  Future<void> load() async {
    defaultTranslucent = defaultTranslucentSettings();
    defaultPlacement = defaultPlacementSettings();
    defaultSegment = defaultSegmentSettings();
    segment = defaultSegment;
    packSegment = defaultSegment;
    presets = builtInPresets(defaultTranslucent);
    final f = File(AppPaths.I.stateFile);
    if (await f.exists()) {
      try {
        final j = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
        _fromJson(j);
      } catch (e) {
        debugPrint('state load failed: $e');
      }
    }
    await _ensureReferenceBase();
    _loaded = true;
    notifyListeners();
  }

  void _fromJson(Map<String, dynamic> j) {
    appearance.load((j['appearance'] as Map?)?.cast() ?? {});
    // v1 used the olive/gold accent as default: move untouched defaults to v2
    if ((j['version'] as num? ?? 1) < 2 && appearance.accent == Appearance.legacyAccent) {
      appearance.accent = Appearance.defaultAccent;
    }
    export.load((j['export'] as Map?)?.cast() ?? {});
    ai.load((j['ai'] as Map?)?.cast() ?? {});
    glass.load((j['glass'] as Map?)?.cast() ?? {});
    lucent.load((j['lucent'] as Map?)?.cast() ?? {});
    localAi.load((j['localAi'] as Map?)?.cast() ?? {});
    final ps = (j['presets'] as List?)?.map((e) => StylePreset.fromJson((e as Map).cast(), defaultTranslucent)).toList();
    if (ps != null && ps.isNotEmpty) {
      // keep built-ins present even if a stored list misses them
      final ids = ps.map((e) => e.id).toSet();
      presets = [...ps, ...builtInPresets(defaultTranslucent).where((b) => !ids.contains(b.id))];
    }
    activePresetId = j['activePresetId'] as String? ?? activePresetId;
    bases = ((j['bases'] as List?) ?? [])
        .map((e) => BaseIcon.fromJson((e as Map).cast(), defaultPlacement))
        .where((b) => File(b.path).existsSync())
        .toList();
    selectedBaseId = j['selectedBaseId'] as String?;
    segment = segmentFromJson((j['segment'] as Map?)?.cast() ?? {}, defaultSegment);
    packSegment = segmentFromJson((j['packSegment'] as Map?)?.cast() ?? {}, defaultSegment);
    scaleMul = (j['scaleMul'] as num?)?.toDouble() ?? scaleMul;
    offsetX = (j['offsetX'] as num?)?.toDouble() ?? offsetX;
    offsetY = (j['offsetY'] as num?)?.toDouble() ?? offsetY;
    useBaseCalibrationForTranslucent = j['useBaseCalibrationForTranslucent'] as bool? ?? false;
    translucentSize = (j['translucentSize'] as num?)?.toInt() ?? translucentSize;
    threads = (j['threads'] as num?)?.toInt() ?? threads;
    bgProvider = BgProvider.values.firstWhere((b) => b.name == j['bgProvider'], orElse: () => BgProvider.local);
    packMode = StudioMode.values.firstWhere((m) => m.name == j['packMode'], orElse: () => packMode);
    packPresetId = j['packPresetId'] as String? ?? packPresetId;
    processedPackages = ((j['processedPackages'] as List?) ?? []).cast<String>().toSet();
    packCorrections = ((j['packCorrections'] as Map?) ?? {}).map((k, v) => MapEntry(k as String, (v as Map).cast<String, dynamic>()));
  }

  Map<String, dynamic> toJson() => {
        'version': 2,
        'appearance': appearance.toJson(),
        'export': export.toJson(),
        'ai': ai.toJson(),
        'glass': glass.toJson(),
        'lucent': lucent.toJson(),
        'localAi': localAi.toJson(),
        'presets': presets.map((e) => e.toJson()).toList(),
        'activePresetId': activePresetId,
        'bases': bases.map((e) => e.toJson()).toList(),
        'selectedBaseId': selectedBaseId,
        'segment': segmentToJson(segment),
        'packSegment': segmentToJson(packSegment),
        'scaleMul': scaleMul,
        'offsetX': offsetX,
        'offsetY': offsetY,
        'useBaseCalibrationForTranslucent': useBaseCalibrationForTranslucent,
        'translucentSize': translucentSize,
        'threads': threads,
        'bgProvider': bgProvider.name,
        'packMode': packMode.name,
        'packPresetId': packPresetId,
        'processedPackages': processedPackages.toList(),
        'packCorrections': packCorrections,
      };

  Future<void>? _pending;

  /// Persists (debounced) and notifies listeners.
  void update([VoidCallback? fn]) {
    fn?.call();
    notifyListeners();
    if (!_loaded) return;
    _pending ??= Future.delayed(const Duration(milliseconds: 400), () async {
      _pending = null;
      await save();
    });
  }

  Future<void> save() async {
    final f = File(AppPaths.I.stateFile);
    final tmp = File('${f.path}.tmp');
    await tmp.writeAsString(const JsonEncoder.withIndent(' ').convert(toJson()));
    await tmp.rename(f.path);
  }

  Future<void> resetAll() async {
    final f = File(AppPaths.I.stateFile);
    if (await f.exists()) await f.delete();
    appearance.load(Appearance().toJson());
    export.load(ExportSettings().toJson());
    ai.load(AiConfig().toJson());
    glass.reset();
    lucent.reset();
    localAi.load(LocalAiConfig().toJson());
    presets = builtInPresets(defaultTranslucent);
    activePresetId = 'nothing';
    segment = defaultSegment;
    packSegment = defaultSegment;
    scaleMul = 1;
    offsetX = 0;
    offsetY = 0;
    useBaseCalibrationForTranslucent = false;
    translucentSize = 512;
    threads = 0;
    bgProvider = BgProvider.local;
    packMode = StudioMode.translucent;
    packPresetId = 'nothing';
    processedPackages = {};
    update();
  }

  // ------------------------------------------------------------ presets

  StylePreset get activePreset => presets.firstWhere((e) => e.id == activePresetId, orElse: () => presets.first);

  StylePreset presetById(String id) => presets.firstWhere((e) => e.id == id, orElse: () => presets.first);

  void setPresetParams(String id, TranslucentSettings t) => update(() => presetById(id).params = t);

  StylePreset savePresetAs(String name, TranslucentSettings t) {
    final pr = StylePreset(id: 'u${DateTime.now().millisecondsSinceEpoch}', name: name, params: t);
    update(() {
      presets.add(pr);
      activePresetId = pr.id;
    });
    return pr;
  }

  void resetPreset(String id) {
    final b = builtInPresets(defaultTranslucent).where((e) => e.id == id);
    if (b.isNotEmpty) update(() => presetById(id).params = b.first.params);
  }

  void deletePreset(String id) {
    final pr = presetById(id);
    if (pr.builtIn) return;
    update(() {
      presets.remove(pr);
      if (activePresetId == id) activePresetId = 'nothing';
      if (packPresetId == id) packPresetId = 'nothing';
    });
  }

  // ------------------------------------------------------------ bases

  BaseIcon? get selectedBase {
    for (final b in bases) {
      if (b.id == selectedBaseId) return b;
    }
    return bases.isEmpty ? null : bases.first;
  }

  Future<BaseIcon> importBase(String src, String name) async {
    final id = 'b${DateTime.now().microsecondsSinceEpoch}';
    final dest = p.join(AppPaths.I.bases, '$id.png');
    final dims = await importAsPng(src: src, dest: dest);
    final b = BaseIcon(id: id, name: name, path: dest, width: dims[0], height: dims[1]);
    update(() {
      bases.add(b);
      selectedBaseId = id;
    });
    return b;
  }

  /// Saves a rendered background (e.g. the current translucent preset) as base.
  Future<BaseIcon> addBaseFromPng(Uint8List png, String name, int size) async {
    final id = 'b${DateTime.now().microsecondsSinceEpoch}';
    final dest = p.join(AppPaths.I.bases, '$id.png');
    await File(dest).writeAsBytes(png);
    final b = BaseIcon(id: id, name: name, path: dest, width: size, height: size);
    update(() {
      bases.add(b);
      selectedBaseId = id;
    });
    return b;
  }

  void renameBase(BaseIcon b, String name) => update(() => b.name = name);

  Future<void> deleteBase(BaseIcon b) async {
    update(() {
      bases.remove(b);
      if (selectedBaseId == b.id) selectedBaseId = bases.isEmpty ? null : bases.first.id;
    });
    final f = File(b.path);
    if (await f.exists()) await f.delete();
  }

  void saveCalibration(BaseIcon b, PlacementSettings pl, Map<String, dynamic> info) => update(() {
        b.calibration = pl;
        b.calibrationInfo = info;
      });

  /// First run: install the base extracted from the reference pack, with the
  /// calibration measured on it (base-difference method, 26 samples).
  Future<void> _ensureReferenceBase() async {
    if (bases.any((b) => b.id == 'reference')) return;
    final dest = p.join(AppPaths.I.bases, 'reference.png');
    final data = await rootBundle.load('assets/bases/reference_translucent.png');
    await File(dest).writeAsBytes(data.buffer.asUint8List());
    final cal = jsonDecode(await rootBundle.loadString('assets/bases/reference_calibration.json')) as Map<String, dynamic>;
    bases.insert(
      0,
      BaseIcon(
        id: 'reference',
        name: S.referenceTranslucent,
        path: dest,
        width: 192,
        height: 192,
        calibration: placementFromJson((cal['placement'] as Map).cast(), defaultPlacement),
        calibrationInfo: (cal['info'] as Map).cast(),
      ),
    );
    selectedBaseId ??= 'reference';
    await save();
  }

  // ------------------------------------------------------------ settings builders

  PlacementSettings placementFor(StudioMode mode) {
    var base = defaultPlacement;
    final b = selectedBase;
    if (mode == StudioMode.original || useBaseCalibrationForTranslucent) {
      if (b?.calibration != null) base = b!.calibration!;
    }
    return copyPlacement(base, scaleMul: scaleMul, offsetX: offsetX, offsetY: offsetY);
  }

  int sizeFor(StudioMode mode) {
    if (export.customSize) return export.size;
    if (mode == StudioMode.original && selectedBase != null) return selectedBase!.size;
    return translucentSize;
  }

  BackgroundSettings backgroundFor(StudioMode mode, {String? presetId}) {
    switch (mode) {
      case StudioMode.original:
        final b = selectedBase;
        return b == null ? const BackgroundSettings.transparent() : BackgroundSettings.baseImage(path: b.path);
      case StudioMode.translucent:
        return BackgroundSettings.lucent(params: lucent.toSettings());
      case StudioMode.preset:
        return BackgroundSettings.translucent(params: presetById(presetId ?? activePresetId).params);
    }
  }

  ProcessSettings settingsFor(StudioMode mode, {String? presetId, SegmentSettings? seg}) => ProcessSettings(
        size: sizeFor(mode),
        background: backgroundFor(mode, presetId: presetId),
        placement: placementFor(mode),
        segment: seg ?? segment,
        ai: aiSettings,
      );

  /// Path of a downloaded local model.
  String modelPath(AiModelInfo m) => '${AppPaths.I.models}${Platform.pathSeparator}${m.id}.onnx';

  bool modelReady(AiModelInfo m) => File(modelPath(m)).existsSync();

  /// Local AI settings when that engine is selected and its model is on disk.
  AiSettings? get aiSettings {
    if (bgProvider != BgProvider.localAi) return null;
    final m = localAi.model;
    if (!modelReady(m)) return null;
    return AiSettings(modelPath: modelPath(m), model: m.kind, low: localAi.low, high: localAi.high);
  }
}
