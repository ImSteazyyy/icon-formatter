import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../app/theme.dart';
import '../../l10n/strings.dart';
import '../../services/pack_mapping_import.dart';
import '../../src/rust/api/engine.dart';
import '../../widgets/common.dart';
import 'pb_controller.dart';

/// One icon on either side of the association.
class PbIcon {
  PbIcon({required this.id, this.label = '', this.package = '', this.activity = '', this.file = '', this.path, this.bytes, this.isSystem = false, this.calendarDay = 0, this.isFresh = false});

  /// 1..31: one day of a dynamic calendar icon (0 = normal icon).
  final int calendarDay;

  final String id;
  final String label;
  String package;
  String activity;
  final String file;
  String? path;
  Uint8List? bytes;

  /// System app (catalogue only).
  final bool isSystem;

  /// Added from the installed apps in this session and rendered from its own launcher icon; cleared once the user opens, edits or confirms it.
  bool isFresh;

  /// Stable key used to persist corrections between sessions.
  String get key => package.isNotEmpty ? 'pkg:$package' : 'file:${file.toLowerCase()}';

  String get title => label.isNotEmpty ? label : (file.isNotEmpty ? p.basenameWithoutExtension(file) : package);

  /// Decoded at the size shown (grids show 432-1024 px icons at ~52 px).
  Widget image({double size = 56}) {
    if (bytes == null && path == null) {
      return SizedBox(
        width: size,
        height: size,
        child: Icon(Icons.image_not_supported_outlined, color: Palette.text3),
      );
    }
    return SizedBox(
      width: size,
      height: size,
      child: IconImage(bytes: bytes, path: path),
    );
  }

  PbIcon withId(String newId) => PbIcon(id: newId, label: label, package: package, activity: activity, file: file, path: path, bytes: bytes, isSystem: isSystem, calendarDay: calendarDay, isFresh: isFresh);

  MatchInput toInput() => MatchInput(id: id, label: label, package: package, file: file, path: path, png: path == null ? bytes : null);

  Map<String, Object?> toJson() => {'id': id, 'label': label, 'package': package, 'activity': activity, 'file': file, 'path': path, if (calendarDay > 0) 'calendarDay': calendarDay};

  static PbIcon? fromJson(Map m) {
    final path = m['path'] as String?;
    if (path == null || !File(path).existsSync()) return null;
    return PbIcon(
      id: m['id'] as String,
      label: m['label'] as String? ?? '',
      package: m['package'] as String? ?? '',
      activity: m['activity'] as String? ?? '',
      file: m['file'] as String? ?? '',
      path: path,
      calendarDay: (m['calendarDay'] as num?)?.toInt() ?? 0,
    );
  }
}

/// confident = matched, review = to check (name ok, drawing differs),
/// doubtful = weak or visual-only match, missing = icon missing.
enum PbState { confident, review, doubtful, missing, excluded, verified }

class PbRow {
  PbRow(this.original);
  final PbIcon original;
  String? generatedId;
  MatchState auto = MatchState.missing;
  String reason = '';
  bool excluded = false;
  bool verified = false;
  bool manual = false;

  /// Icon replaced by hand ("Edit icon").
  bool custom = false;

  /// One of the app's variant icons is the one used (see [PackBuilderController]).
  bool variant = false;

  /// Icon the row would use without its variant choice.
  String? baseGeneratedId;

  /// The system icon changed since the last generation.
  bool changedOriginal = false;

  PbState get state {
    if (excluded) return PbState.excluded;
    if (generatedId == null) return PbState.missing;
    if (changedOriginal) return PbState.review;
    if (verified || manual || custom || variant) return PbState.verified;
    return switch (auto) {
      MatchState.confident => PbState.confident,
      MatchState.review => PbState.review,
      _ => PbState.doubtful,
    };
  }
}

/// How a hand-picked image is treated in "Edit icon".
/// placeOnly: the picture is not cut out nor recoloured, only centred and
/// sized like the other icons on the pack's icon background.
/// "Change background" of the whole pack: plate opacity (0..1) and colour
/// mode ('auto' keeps the preset colour, 'dark' or 'light' replace it).
class PlateOverride {
  const PlateOverride({required this.opacity, required this.mode});

  final double opacity;
  final String mode;
}

enum EditTreatment { auto, plateColor, fullBleed, asIs, placeOnly, raw }

/// An icon of another pack matched to an app without icon (see matchFromPack).
class PbMatch {
  PbMatch({required this.row, required this.icon, required this.match});
  final PbRow row;
  final PbIcon icon;
  final MappingMatch match;
}

/// The match reason from the core ("package · somiglianza 87%",
/// "solo somiglianza visiva 64%") in the app language.
String matchReasonText(String raw) {
  final only = RegExp(r'^solo somiglianza visiva (\d+)%$').firstMatch(raw);
  if (only != null) return S.pbSoloSomiglianza(only.group(1));
  final m = RegExp(r'^(.*) · somiglianza (\d+)%$').firstMatch(raw);
  final why = m?.group(1) ?? raw;
  final text = switch (why) {
    'package' => S.pbPerPackage,
    'nome app' => S.pbPerNomeApp,
    'nome file' => S.pbPerNomeFile,
    _ => why,
  };
  return m == null ? text : '$text · ${S.pbSomiglianza(m.group(2))}';
}

ProcessSettings plateSettings(ProcessSettings s, PlateOverride? o) {
  final bg = s.background;
  if (o == null || bg is! BackgroundSettings_Lucent) return s;
  final l = bg.params;
  final rgb = switch (o.mode) {
    'dark' => 0x1C1C1E,
    'light' => 0xF2F2F7,
    _ => l.backdrop & 0xFFFFFF,
  };
  final alpha = (o.opacity.clamp(0.0, 1.0) * 255).round();
  final lucent = LucentSettings(
    ink: l.ink,
    backdrop: (alpha << 24) | rgb,
    shape: l.shape,
    monochrome: l.monochrome,
    keepComposition: l.keepComposition,
    glyphScale: l.glyphScale,
    rim: l.rim,
    launcherShadow: l.launcherShadow,
    launcherEncode: l.launcherEncode,
    strategy: l.strategy,
  );
  return ProcessSettings(
    size: s.size,
    background: BackgroundSettings.lucent(params: lucent),
    placement: s.placement,
    segment: s.segment,
    ai: s.ai,
    effects: s.effects,
    cutCacheDir: s.cutCacheDir,
  );
}
