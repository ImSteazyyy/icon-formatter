part of '../state.dart';

/// Settings per Studio mode, cut-out cache and AI model paths.
extension AppStateStudio on AppState {
  PlacementSettings placementFor(StudioMode mode) {
    var base = defaultPlacement;
    final b = selectedBase;
    if (mode == StudioMode.original || useBaseCalibrationForTranslucent) {
      if (b?.calibration != null) base = b!.calibration!;
    }
    return copyPlacement(base, scaleMul: scaleMul, offsetX: offsetX, offsetY: offsetY, opticalCentre: look.opticalCentre);
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
        final pr = presetById(presetId ?? activePresetId);
        // a Lucent look renders through the plate pipeline, the rest procedurally
        final lk = pr.lucent;
        return lk != null ? BackgroundSettings.lucent(params: lk.toSettings()) : BackgroundSettings.translucent(params: pr.params);
    }
  }

  /// Folder of the saved cutouts, or null while the setting is off.
  String? get cutCacheDir => keepCutouts ? AppPaths.I.cutouts : null;

  /// Keeps the saved cutouts under the size limit. Rust does the work on its
  /// own threads; a failure only leaves the folder larger.
  Future<void> pruneCutouts() async {
    if (!keepCutouts) return;
    try {
      await cutoutCachePrune(dir: AppPaths.I.cutouts, maxBytes: BigInt.from(cutoutLimitMb) * BigInt.from(1024 * 1024));
    } catch (e) {
      debugPrint('cutout prune failed: $e');
    }
  }

  ProcessSettings settingsFor(StudioMode mode, {String? presetId, SegmentSettings? seg}) => ProcessSettings(
        size: sizeFor(mode),
        background: backgroundFor(mode, presetId: presetId),
        placement: placementFor(mode),
        segment: seg ?? segment,
        ai: aiSettings,
        effects: look.effects,
        cutCacheDir: cutCacheDir,
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
