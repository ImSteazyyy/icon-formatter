part of '../state.dart';

/// Style presets: create, rename, reset and delete.
extension AppStatePresets on AppState {
  StylePreset get activePreset => presetById(activePresetId);

  StylePreset presetById(String id) => presets.firstWhere((e) => e.id == id, orElse: () => presets.first);

  void setPresetParams(String id, TranslucentSettings t) => update(() => presetById(id).params = t);

  StylePreset savePresetAs(String name, TranslucentSettings t) {
    final pr = StylePreset(id: 'u${DateTime.now().millisecondsSinceEpoch}', name: name, params: t)..savedJson = translucentToJson(t);
    update(() {
      presets.add(pr);
      activePresetId = pr.id;
    });
    return pr;
  }

  /// A user preset holding a Lucent look (copied, so later edits do not touch the source).
  StylePreset savePresetLucent(String name, LucentConfig l) {
    final pr = StylePreset(id: 'u${DateTime.now().millisecondsSinceEpoch}', name: name, params: defaultTranslucent)
      ..lucent = (LucentConfig()..load(l.toJson()))
      ..savedJson = l.toJson();
    update(() {
      presets.add(pr);
      activePresetId = pr.id;
    });
    return pr;
  }

  /// Adds imported presets under new ids and unique names; returns the first new id.
  String? importPresets(List<({String name, TranslucentSettings params})> items) {
    final ids = <String>[];
    update(() {
      for (final (i, it) in items.indexed) {
        final id = 'u${DateTime.now().microsecondsSinceEpoch}$i';
        ids.add(id);
        presets.add(StylePreset(id: id, name: uniqueName(it.name, presets.map((e) => e.name)), params: it.params)..savedJson = translucentToJson(it.params));
      }
    });
    return ids.firstOrNull;
  }

  /// The values a preset returns to: the built-in defaults, or the last save.
  Map<String, dynamic> presetBaseline(StylePreset pr) {
    if (pr.builtIn) {
      final b = builtInPresets(defaultTranslucent).where((e) => e.id == pr.id);
      if (b.isNotEmpty) return b.first.values;
    }
    return pr.savedJson ?? pr.values;
  }

  /// True while the values differ from the saved baseline ("Modified").
  bool presetModified(StylePreset pr) => jsonEncode(pr.values) != jsonEncode(presetBaseline(pr));

  /// Makes the current values the baseline of a user preset ("Update preset").
  void updatePreset(String id) {
    final pr = presetById(id);
    if (pr.builtIn) return;
    update(() => pr.savedJson = pr.values);
  }

  void renamePreset(String id, String name) {
    final pr = presetById(id);
    if (pr.builtIn || name.trim().isEmpty) return;
    update(() => pr.name = name.trim());
  }

  /// "Reset to preset": back to the baseline (built-in defaults or last save).
  void resetPreset(String id) {
    final pr = presetById(id);
    final base = presetBaseline(pr);
    update(() {
      if (pr.lucent != null) {
        pr.lucent = LucentConfig()..load(base);
      } else {
        pr.params = translucentFromJson(base, defaultTranslucent);
      }
    });
  }

  void deletePreset(String id) {
    final pr = presetById(id);
    if (pr.builtIn) return;
    update(() {
      presets.remove(pr);
      if (activePresetId == id) activePresetId = kDefaultPresetId;
      if (packPresetId == id) packPresetId = kDefaultPresetId;
    });
  }
}
