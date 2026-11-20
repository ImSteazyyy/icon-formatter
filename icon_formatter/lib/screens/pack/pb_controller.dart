import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../app/models.dart' show copySegment;
import '../../app/state.dart';
import '../../app/storage.dart';
import '../../l10n/strings.dart';
import '../../services/export_service.dart';
import '../../services/extra_contact_sheet.dart';
import '../../services/import_service.dart';
import '../../services/pack2_logic.dart';
import '../../services/pack3_logic.dart';
import '../../services/pack_conflicts.dart';
import '../../services/pack_mapping_import.dart';
import '../../services/pack_naming.dart';
import '../../services/pack_quality.dart';
import '../../services/pack_source_filter.dart';
import '../../services/packdb_db.dart';
import '../../services/packdb_store.dart';
import '../../services/platform_service.dart';
import '../../src/rust/api/engine.dart';
import '../../widgets/common.dart';
import '../settings_screen.dart' show appVersion;
import 'pb_model.dart';

part 'pb_controller_sources.dart';
part 'pb_controller_generate.dart';
part 'pb_controller_export.dart';
part 'pb_controller_corrections.dart';

/// Icon Pack Builder: originals ↔ generated association, corrections, export.
class PackBuilderController extends ChangeNotifier {
  PackBuilderController() {
    _restore();
    PackStore.onFallback.add(notifyListeners);
  }

  /// One builder for the app: the Studio sends its results here.
  static final I = PackBuilderController();

  final List<PbIcon> originals = [];
  final List<PbIcon> generated = [];

  /// Dynamic calendar icons from the Studio: every day of each app.
  final List<PbIcon> calendars = [];

  /// Pack entries for the calendar days (the launcher picks today's).
  List<IconPackApp> get _calendarApps => [
        for (final g in calendars)
          if (g.path != null && !(rows.any((r) => r.excluded && r.original.package == g.package)))
            IconPackApp(label: g.label, package: g.package, activity: g.activity, png: g.path!, calendarDay: g.calendarDay),
      ];
  final List<PbRow> rows = [];
  final Map<String, PbIcon> _genById = {};
  bool busy = false;
  String? status;
  double? progress;

  /// Android catalogue: number of launcher activities Android lets the app
  /// see, and whether the catalogue has been read in this session.
  int? catalogVisible;
  bool catalogLoaded = false;

  /// Apps added by the last catalogue action and generated from their launcher icon (one-time notice).
  int freshNotice = 0;

  /// Plate change of the whole pack, applied on the next generation (null: the preset).
  PlateOverride? plate;

  /// Token of the generation in progress; [cancelGeneration] stops it between icons.
  CancelToken? _runCancel;

  /// Stops the running generation: icons already done are kept.
  void cancelGeneration() => _runCancel?.cancel();

  /// Hand-made icons: original key -> {path, prev (generated key before)}.
  final Map<String, Map<String, String?>> custom = {};

  /// Original keys whose system icon changed since the last generation.
  final Set<String> _changedKeys = {};
  bool _checkingOriginals = false;

  /// Coverage of the installed apps (Android catalogue), counted once per
  /// change of the rows: icons made, apps counted, percentage.
  int coverDone = 0, coverTotal = 0, coverPercent = 0;

  PbIcon? generatedById(String? id) => id == null ? null : _genById[id];

  /// Installed app (catalogue row) rather than a file original.
  bool isInstalled(PbRow r) => r.original.id.startsWith('app:');

  /// Name shown in the pack: the "Name in the pack" label, else the title.
  String nameOf(PbRow r) {
    final l = AppState.I.packCorrections[r.original.key]?['label'];
    return l is String && l.isNotEmpty ? l : r.original.title;
  }

  void _recount() {
    final cov = pack2Coverage([for (final r in rows) if (isInstalled(r) && !r.excluded) r.generatedId != null]);
    coverDone = cov.done;
    coverTotal = cov.total;
    coverPercent = cov.percent;
  }

  /// Hides the status card (swipe); the next status shows it again.
  void hideStatus() {
    status = null;
    super.notifyListeners();
  }

  void _reindex() {
    _genById
      ..clear()
      ..addEntries(generated.map((g) => MapEntry(g.id, g)));
  }

  DateTime _lastNotify = DateTime(0);

  void _set(String? s, {double? prog, bool? running, bool throttle = false}) {
    status = s;
    progress = prog;
    if (running != null) busy = running;
    // progress events arrive per icon: at most ~8 rebuilds per second
    final now = DateTime.now();
    if (throttle && now.difference(_lastNotify).inMilliseconds < (Platform.isAndroid ? 250 : 120)) return;
    _lastNotify = now;
    notifyListeners();
  }

  // ------------------------------------------------------------ persistence
  // The lists live in PackStore (pack.db, or pack_builder.json as fallback):
  // see services/packdb_store.dart.

  String get _customDir => p.join(AppPaths.I.root.path, 'pack_custom');
  String get _catalogDir => p.join(AppPaths.I.root.path, 'catalog');

  bool _sigCacheSet = false;

  bool _restored = false;

  /// The saved sources were cleaned by the one-time pass (see [parsePackJson]).
  bool _cleaned = false;

  void _restore() {
    try {
      final c = PackStore.I.readAll();
      generated.addAll(c.generated.map(_iconOf));
      calendars.addAll(c.calendars.map(_iconOf));
      // file-based originals (Windows / imported packs); the Android
      // catalogue is read again from the system
      originals.addAll(c.originals.map(_iconOf));
      _cleaned = c.cleaned;
      custom.addAll(c.custom);
      _reindex();
    } catch (_) {
      // a damaged state only loses the builder lists
    } finally {
      _restored = true;
      if (_cleaned) _persist();
    }
  }

  static PbIcon _iconOf(PackRecord r) => PbIcon(id: r.id, label: r.label, package: r.package, activity: r.activity, file: r.file, path: r.path, isSystem: r.isSystem, calendarDay: r.calendarDay, isFresh: r.isFresh);

  static PackRecord _recordOf(String kind, PbIcon i) => PackRecord(kind: kind, id: i.id, path: i.path!, label: i.label, package: i.package, activity: i.activity, file: i.file, calendarDay: i.calendarDay, isSystem: i.isSystem, isFresh: i.isFresh);

  Timer? _saveTimer;

  /// Debounced: one write per burst of changes, and only the changed rows
  /// reach pack.db (the JSON store rewrites its file).
  void _persist() {
    if (!_restored) return;
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 400), () {
      unawaited(PackStore.I.writeIcons(_iconsSnapshot()).catchError((Object e) => debugPrint('pack save: $e')));
    });
  }

  PackContent _iconsSnapshot() => PackContent(
        generated: [for (final g in generated) if (g.path != null) _recordOf('generated', g)],
        originals: [for (final o in originals) if (!o.id.startsWith('app:') && o.path != null) _recordOf('original', o)],
        calendars: [for (final g in calendars) if (g.path != null) _recordOf('calendar', g)],
        custom: custom,
      );

  @override
  void notifyListeners() {
    _persist();
    super.notifyListeners();
  }

  // ------------------------------------------------------------ sources

  Future<String?> Function() pickKindImpl = () async => null;
  Future<String?> _pickKind() => pickKindImpl();

  // ------------------------------------------------------------ matching

  static String _norm(String s) => s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_');

  /// One Studio icon per app component (package + activity when known).
  static String _studioKey(PbIcon g) => g.activity.isNotEmpty ? '${g.package}/${g.activity}' : g.package;

  bool _deferAppSaves = false;
  bool _appSavePending = false;

  // ------------------------------------------------------------ manual edit

  /// Renders a picked image for [row] (nothing is assigned yet). Returns PNG.
  /// Source image and treatment of the last "Edit icon" render: kept
  /// with the hand-made icon so it follows later changes of the pack style.
  (String, EditTreatment)? _lastEdit;

  // ------------------------------------------------------------ export

  static String _compKey(PbIcon o) => o.package.isEmpty ? o.key : '${o.package}/${o.activity}';

  // ------------------------------------------------------------ quality

  // ------------------------------------------------------------ aliases, labels, variants

  // ------------------------------------------------------------ contact sheet

  // ------------------------------------------------------------ changed originals

  // ------------------------------------------------------------ log and profiles

  static Map<String, Map<String, dynamic>> _copyCorrections(Map m) => (jsonDecode(jsonEncode(m)) as Map).map((k, v) => MapEntry(k as String, (v as Map).cast<String, dynamic>()));

}
