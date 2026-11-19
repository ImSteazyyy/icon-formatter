import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:ui' as ui;
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../app/models.dart' show copySegment;
import '../app/state.dart';
import '../workspace/adjust_panel.dart';
import '../workspace/workspace_controller.dart';
import '../app/storage.dart';
import '../app/theme.dart';
import '../l10n/strings.dart';
import '../services/apk_pack_service.dart';
import '../services/export_service.dart';
import '../services/extra_contact_sheet.dart';
import '../services/import_service.dart';
import '../services/pack2_logic.dart';
import '../services/pack3_logic.dart';
import '../services/pack_conflicts.dart';
import '../services/pack_mapping_import.dart';
import '../services/pack_naming.dart';
import '../services/pack_quality.dart';
import '../services/pack_source_filter.dart';
import '../services/pack_suggest.dart';
import '../services/packdb_db.dart';
import '../services/packdb_store.dart';
import '../services/platform_service.dart';
import '../src/rust/api/engine.dart';
import '../widgets/ignored_apps_sheet.dart';
import '../widgets/refresh_time_row.dart';
import '../widgets/common.dart';
import '../widgets/glass_menu.dart';
import '../widgets/home_preview.dart';
import '../widgets/liquid_glass.dart';
import 'pack_screen.dart';
import 'settings_screen.dart' show appVersion;

/// One icon on either side of the association.
class PbIcon {
  PbIcon({required this.id, this.label = '', this.package = '', this.activity = '', this.file = '', this.path, this.bytes, this.isSystem = false, this.calendarDay = 0});

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

  PbIcon withId(String newId) => PbIcon(id: newId, label: label, package: package, activity: activity, file: file, path: path, bytes: bytes, isSystem: isSystem, calendarDay: calendarDay);

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

/// confident = abbinata, review = da verificare (name ok, drawing differs),
/// doubtful = dubbia (weak or visual-only match), missing = icona mancante.
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

  /// Icon replaced by hand ("Modifica icona").
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

/// How a hand-picked image is treated in "Modifica icona".
/// placeOnly: the picture is not cut out nor recoloured, only centred and
/// sized like the other icons on the pack's icon background.
enum EditTreatment { auto, plateColor, fullBleed, asIs, placeOnly, raw }

/// An icon of another pack matched to an app without icon (see matchFromPack).
class PbMatch {
  PbMatch({required this.row, required this.icon, required this.match});
  final PbRow row;
  final PbIcon icon;
  final MappingMatch match;
}

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

  /// Name shown in the pack: the "Rinomina nel pack" label, else the title.
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

  static PbIcon _iconOf(PackRecord r) => PbIcon(id: r.id, label: r.label, package: r.package, activity: r.activity, file: r.file, path: r.path, isSystem: r.isSystem, calendarDay: r.calendarDay);

  static PackRecord _recordOf(String kind, PbIcon i) => PackRecord(kind: kind, id: i.id, path: i.path!, label: i.label, package: i.package, activity: i.activity, file: i.file, calendarDay: i.calendarDay, isSystem: i.isSystem);

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

  /// Android: every app with an icon in the launcher (system apps, Icon
  /// Formatter and its packs included) becomes a row; icons are cached on
  /// disk and only re-rendered when an app is updated.
  Future<void> loadCatalog({bool force = false}) async {
    if (!Platform.isAndroid || busy || (catalogLoaded && !force)) return;
    _set(S.pbLetturaApp, running: true);
    final sw = Stopwatch()..start();
    try {
      final (apps, visible) = await PlatformService.appCatalog(_catalogDir);
      debugPrint('pack: catalogue ${apps.length} apps ${sw.elapsedMilliseconds} ms');
      catalogVisible = visible;
      originals.removeWhere((o) => o.id.startsWith('app:'));
      originals.insertAll(0, [for (final (a, icon) in apps) PbIcon(id: 'app:${a.key}', label: a.label, package: a.package, activity: a.activity, path: icon, isSystem: a.isSystem)]);
      catalogLoaded = true;
      _set(S.pbCatalogo(apps.length, visible), running: false);
      await match();
      debugPrint('pack: catalogue + match ${sw.elapsedMilliseconds} ms');
      unawaited(checkChangedOriginals());
    } catch (e) {
      _set(S.errore(e), running: false);
    }
  }

  Future<void> addInstalledApps() => loadCatalog(force: true);

  /// Apps reported by the automatic change check: the catalogue is re-read
  /// (updated icons are re-rendered, the others come from the cache).
  Future<void> addInstalledComponents(Set<String> components) => loadCatalog(force: true);

  /// Folder, ZIP or APK. Uses appfilter.xml (text or binary) when present to
  /// recover package and activity of each drawable.
  /// The icons of [input]; the flag tells whether it is an icon pack (its
  /// appfilter.xml links the images to apps, see [packIconIndexes]).
  /// The icons of [input], the calendar days of its apps, and whether it is an
  /// icon pack (its appfilter.xml links the images to apps, see [packIconIndexes]).
  Future<(List<PbIcon>, bool, List<PbIcon>)> _readSource(String input, String prefix) async {
    final work = await AppPaths.I.workDir('builder');
    final info = await openPack(input: input, workDir: work);
    final comp = <String, (String, String)>{};
    for (final it in info.appfilterItems) {
      final m = RegExp(r'ComponentInfo\{([^/}]+)/?([^}]*)\}').firstMatch(it.component);
      if (m != null) comp[it.drawable.toLowerCase()] = (m.group(1)!, m.group(2) ?? '');
    }
    final rels = [for (final img in info.images) img.rel];
    final keep = packIconIndexes(rels, comp);
    var k = 0;
    final list = [
      for (final i in keep)
        () {
          final img = info.images[i];
          final stem = p.basenameWithoutExtension(img.rel).toLowerCase();
          final c = comp[stem];
          return PbIcon(id: '$prefix${k++}', file: p.basename(img.rel), package: c?.$1 ?? '', activity: c?.$2 ?? '', path: img.abs);
        }(),
    ];
    final days = [
      for (final d in packCalendarDays(rels, comp))
        PbIcon(id: '${prefix}d${d.day}_${d.index}', file: p.basename(info.images[d.index].rel), package: d.package, activity: d.activity, path: info.images[d.index].abs, calendarDay: d.day),
    ];
    return (list, comp.isNotEmpty, days);
  }

  /// Calendar days of a pack become the days of their app: they replace the
  /// days this app had (the app's one row shows them as variants).
  Future<void> _adoptDays(List<PbIcon> days, int stamp) async {
    if (days.isEmpty) return;
    final dir = Directory(p.join(AppPaths.I.root.path, 'pack_imported', '$stamp'));
    await dir.create(recursive: true);
    final copied = <PbIcon>[];
    for (final d in days) {
      if (d.path == null) continue;
      final dest = p.join(dir.path, 'calendar_${sanitizeDrawableName(name: d.package)}_${d.calendarDay}_${d.id.hashCode.toUnsigned(32).toRadixString(16)}.png');
      await File(d.path!).copy(dest);
      copied.add(PbIcon(id: d.id, label: d.label, package: d.package, activity: d.activity, file: d.file, path: dest, calendarDay: d.calendarDay));
    }
    final apps = {for (final d in copied) d.package};
    calendars.removeWhere((g) => apps.contains(g.package));
    calendars.addAll(copied);
  }

  /// The days of the calendar app of [r] (empty for other apps), by day.
  List<PbIcon> calendarDaysOf(PbRow r) {
    final days = calendars.where((g) => g.path != null);
    return groupCalendarDays(days, packageOf: (g) => g.package, dayOf: (g) => g.calendarDay)[r.original.package] ?? const [];
  }

  /// Rows of the apps named by the change check ("pkg/activity" or "pkg").
  List<PbRow> rowsOfComponents(Set<String> comps) {
    final pkgs = {for (final c in comps) c.split('/').first};
    return [for (final r in rows) if (r.original.package.isNotEmpty && pkgs.contains(r.original.package)) r];
  }

  /// Empties the list of file originals; the installed apps and the icons
  /// already made stay.
  Future<void> clearFileOriginals() async {
    originals.removeWhere((o) => !o.id.startsWith('app:'));
    _reindex();
    if (originals.isEmpty) {
      rows.clear();
      _recount();
      notifyListeners();
    } else {
      await match();
    }
  }

  Future<void> addSource({required bool original}) async {
    final kind = await _pickKind();
    if (kind == null) return;
    String? input;
    if (kind == 'folder') {
      input = await ImportService.pickFolder();
    } else {
      final r = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['zip', 'apk'], dialogTitle: S.zipOApk);
      input = r?.files.single.path;
    }
    if (input == null) return;
    _set(S.pbLettura, running: true);
    try {
      final stamp = DateTime.now().millisecondsSinceEpoch;
      final (list, isPack, days) = await _readSource(input, original ? 'o${stamp}_' : 'g${stamp}_');
      // an icon pack, read next to the installed apps (Android), holds finished
      // icons: they are adopted as they are, never rendered again as originals
      // without the catalogue (Windows) the pack's icons are the rows instead:
      // still finished, never rendered again
      if (original && isPack) {
        final catalogue = originals.any((o) => o.id.startsWith('app:'));
        await _adoptPack([for (var i = 0; i < list.length; i++) list[i].withId('pk${stamp}_$i')], stamp, days: days, asOriginals: !catalogue);
        return;
      }
      if (!original && isPack) await _adoptDays(days, stamp);
      (original ? originals : generated).addAll(list);
      _reindex();
      _set(original ? S.pbOriginaliCaricati(originals.length) : S.pbGenerateCaricate(generated.length), running: false);
      if (rows.isNotEmpty || original) await match();
    } catch (e) {
      _set(S.errore(e), running: false);
    }
  }

  /// Studio › "Manda al Pack": generated icons (with app label/package when
  /// known) become step 2; they are matched right away when originals exist.
  Future<int> addFromStudio(List<PbIcon> all) async {
    if (all.isEmpty) return 0;
    // calendar days are kept apart (all of them go into the pack, with a
    // <calendar> entry); the app's row shows today's day, as the launcher
    final cal = all.where((g) => g.calendarDay > 0 && g.package.isNotEmpty).toList();
    if (cal.isNotEmpty) {
      final apps = cal.map((g) => '${g.package}/${g.activity}').toSet();
      calendars.removeWhere((g) => apps.contains('${g.package}/${g.activity}'));
      calendars.addAll(cal);
    }
    final today = DateTime.now().day;
    final icons = [
      ...all.where((g) => g.calendarDay == 0),
      for (final g in cal)
        if (g.calendarDay == today) PbIcon(id: 'studio:calendar:${g.package}', label: g.label, package: g.package, activity: g.activity, file: g.file, path: g.path),
    ];
    if (icons.isEmpty) {
      _set(S.calendarioNelPack(cal.map((g) => g.package).toSet().length), running: false);
      notifyListeners();
      return all.length;
    }
    // icons made from files carry no package: "com_google_android_gm.png"
    // names one, and it is taken only when such an app is in the catalogue
    final byNorm = {
      for (final o in originals)
        if (o.package.isNotEmpty) _norm(o.package): o,
    };
    for (final g in icons) {
      if (g.package.isNotEmpty) continue;
      final o = byNorm[_norm(p.basenameWithoutExtension(g.file))];
      if (o != null) {
        g.package = o.package;
        if (g.activity.isEmpty) g.activity = o.activity;
      }
    }
    final ids = icons.map((g) => g.id).toSet();
    // the newest Studio icon of an app replaces the older Studio ones
    final keys = icons.where((g) => g.package.isNotEmpty).map(_studioKey).toSet();
    generated.removeWhere((g) => ids.contains(g.id) || (g.id.startsWith('studio:') && keys.contains(_studioKey(g))));
    generated.addAll(icons);
    _reindex();
    // Studio wins over what was there: older hand associations and hand-made
    // icons of the same apps step aside (the hand-made files stay on disk)
    final corr = AppState.I.packCorrections;
    for (final o in originals) {
      if (_studioFor(o, among: icons) == null) continue;
      final c = corr[o.key];
      if (c != null && c['generated'] != null) AppState.I.update(() => corr[o.key] = {...c, 'generated': null});
      custom.remove(o.key);
    }
    _set(S.pbGenerateCaricate(generated.length), running: false);
    if (originals.isNotEmpty) await match();
    notifyListeners();
    return all.length;
  }

  /// Opens a pack made by Icon Formatter (the one installed here, or an APK /
  /// ZIP from another phone): its icons become step 2, linked to their apps
  /// through its appfilter, ready to be edited; the next "Installa e applica"
  /// updates that pack and continues its version numbering.
  Future<int> openExistingPack(String path) async {
    _set(S.pbLettura, running: true);
    try {
      if (Platform.isAndroid && path.toLowerCase().endsWith('.apk')) {
        await PlatformService.devicePackArchiveInfo(path);
      }
      final stamp = DateTime.now().millisecondsSinceEpoch;
      final (list, _, days) = await _readSource(path, 'pk${stamp}_');
      return await _adoptPack(list, stamp, days: days);
    } catch (e) {
      _set(S.errore(e), running: false);
      rethrow;
    }
  }

  /// Icons of an opened pack become step 2 (generated, finished): copied next
  /// to the app data, replacing the older copy of the same apps, then matched.
  Future<int> _adoptPack(List<PbIcon> read, int stamp, {List<PbIcon> days = const [], bool asOriginals = false}) async {
    // only icons linked to an app (a phone pack also holds empty slots)
    final list = read.where((g) => g.package.isNotEmpty).toList();
    await _adoptDays(days, stamp);
    if (list.isEmpty) {
      _set(S.pbPackVuoto, running: false);
      return 0;
    }
    // the extracted files live in the cache: keep a copy with the app data
    final dir = Directory(p.join(AppPaths.I.root.path, 'pack_imported', '$stamp'));
    await dir.create(recursive: true);
    for (final g in list) {
      if (g.path == null) continue;
      final dest = p.join(dir.path, '${sanitizeDrawableName(name: g.package)}_${g.id.hashCode.toUnsigned(32).toRadixString(16)}.png');
      await File(g.path!).copy(dest);
      g.path = dest;
    }
    // a newer copy of the same apps replaces the older imported ones
    final pkgs = list.map((g) => g.key).toSet();
    generated.removeWhere((g) => g.id.startsWith('pk') && pkgs.contains(g.key));
    generated.addAll(list);
    if (asOriginals) {
      // no installed-app rows: the pack's own icons are the rows (ids "pko...")
      originals.removeWhere((o) => o.id.startsWith('pko') && pkgs.contains(o.key));
      originals.addAll([for (var i = 0; i < list.length; i++) list[i].withId('pko${stamp}_$i')]);
    }
    _reindex();
    _set(S.pbPackAperto(list.length), running: false);
    await match();
    return list.length;
  }

  Future<String?> Function() _pickKindImpl = () async => null;
  Future<String?> _pickKind() => _pickKindImpl();

  /// Renders the originals with the current Studio settings (pack mode).
  Future<void> generateFromOriginals({List<PbRow>? only}) async {
    final st = AppState.I;
    // icons of a pack or of the Studio are finished: a bulk render leaves them
    // alone (a row is rendered again only when asked for it: "Rielabora")
    final finished = {for (final r in rows) if (r.generatedId?.startsWith('pk') ?? false) r.original.id};
    final targets = only?.map((r) => r.original).toList() ?? [
      for (final o in originals)
        if ((o.path != null || o.bytes != null) && renderOnBulk(originalId: o.id, hasStudioIcon: _studioFor(o) != null, rowFinished: finished.contains(o.id))) o,
    ];
    if (targets.isEmpty) return;
    final byId = {for (final t in targets) t.id: t};
    final rowById = {for (final r in rows) r.original.id: r};
    final out = await AppPaths.I.outputSession('builder');
    final items = [
      for (final o in targets)
        BatchItem(
          id: o.id,
          name: o.title,
          path: o.path,
          bytes: o.path == null ? o.bytes : null,
          output: p.join(out, '${sanitizeDrawableName(name: o.package.isNotEmpty ? o.package : o.title)}_${o.id.hashCode.toUnsigned(32).toRadixString(16)}.png'),
          // per-app choice: keep the white closed inside the symbol
          segment: st.packCorrections[o.key]?['keepWhite'] == true ? copySegment(st.packSegment, removeHoles: false) : null,
          skipIsolation: false,
        ),
    ];
    _set(S.pbGenerazione(0, items.length), prog: 0, running: true);
    _deferAppSaves = true;
    var done = 0;
    var okCount = 0;
    try {
      await for (final ev in runBatch(
        items: items,
        settings: st.settingsFor(st.packMode, presetId: st.packPresetId, seg: st.packSegment),
        threads: st.threads,
        cancel: CancelToken(),
      )) {
        done = ev.done;
        final r = ev.result;
        final o = byId[r.id];
        if (o != null && r.ok && r.output != null) {
          final gid = 'gen:${o.id}';
          okCount++;
          // a scan of the whole list per icon was quadratic over a 5000 batch
          if (_genById.containsKey(gid)) generated.removeWhere((g) => g.id == gid);
          // same name/package as the original: the association is exact
          final g = PbIcon(id: gid, label: o.label, package: o.package, activity: o.activity, file: o.file.isNotEmpty ? o.file : p.basename(r.output!), path: r.output);
          generated.add(g);
          _genById[gid] = g;
          // the new render is the reference for the change check of the system icon
          _changedKeys.remove(o.key);
          if (o.id.startsWith('app:')) unawaited(_rememberFingerprint(o));
          final row = rowById[o.id];
          if (row != null && !row.custom && (only != null || _studioFor(o) == null)) {
            row.generatedId = gid;
            row.baseGeneratedId = gid;
            row.auto = MatchState.confident;
            row.manual = false;
            row.changedOriginal = false;
            row.reason = S.pbRielaborata;
            _forgetChoice(row);
            _save(row);
          }
        }
        _set(S.pbGenerazione(done, ev.total), prog: ev.total == 0 ? null : done / ev.total, throttle: done < ev.total);
      }
      if (okCount > 0) _log(only == null ? S.packLogCreate(okCount) : S.packLogRielabora(okCount));
      if (only == null) await _redoCustom();
    } finally {
      _deferAppSaves = false;
      if (_appSavePending) {
        _appSavePending = false;
        AppState.I.update(() {});
      }
      _recount();
      _set(S.pbGenerateCaricate(generated.length), running: false);
      unawaited(st.pruneCutouts());
    }
    if (only == null) await match();
  }

  // ------------------------------------------------------------ matching

  /// Name/package index first, visual comparison only where needed: the
  /// heavy work runs in Rust (rayon pool, cached signatures), off the UI.
  Future<void> match() async {
    if (originals.isEmpty) return;
    _set(S.pbAbbinamento, running: true);
    try {
      if (!_sigCacheSet) {
        _sigCacheSet = true;
        await setMatchCacheFile(path: p.join(AppPaths.I.root.path, 'match_signatures.bin'));
      }
      final res = generated.isEmpty ? const <MatchOutput>[] : await matchIcons(originals: [for (final o in originals) o.toInput()], generated: [for (final g in generated) g.toInput()]);
      final byId = {for (final r in res) r.original: r};
      rows
        ..clear()
        ..addAll(originals.map(PbRow.new));
      final corr = AppState.I.packCorrections;
      // saved hand associations point at an app key: when several icons
      // share it, a Studio icon is the one meant
      final genByKey = <String, PbIcon>{};
      for (final g in generated) {
        if (g.id.startsWith('studio:')) {
          genByKey[g.key] = g;
        } else {
          genByKey.putIfAbsent(g.key, () => g);
        }
      }
      for (final row in rows) {
        final m = byId[row.original.id];
        if (m != null) {
          row.generatedId = m.generated;
          row.auto = m.state;
          row.reason = m.generated == null ? S.pbNessunaIcona : matchReasonText(m.reason);
        } else {
          row.reason = S.pbNessunaIcona;
        }
        // icons of an opened pack are finished: they count as confident
        final pkIcon = generatedById(row.generatedId);
        if (pkIcon != null && pkIcon.id.startsWith('pk') && pkIcon.package == row.original.package) row.auto = MatchState.confident;
        // saved corrections win over the automatic association
        final c = corr[row.original.key];
        if (c != null) {
          row.excluded = c['excluded'] == true;
          row.verified = c['verified'] == true;
          // saved by icon id now; an older save holds the app key (first icon of it)
          final gk = c['generated'] as String?;
          final pick = gk == null ? null : (_genById[gk] ?? genByKey[gk]);
          if (pick != null) {
            row.generatedId = pick.id;
            row.manual = true;
            row.reason = S.pbCorrezioneSalvata;
          }
        }
        _applyCustom(row);
        _applyStudio(row);
        row.changedOriginal = _changedKeys.contains(row.original.key);
        row.baseGeneratedId = row.generatedId;
        _linkVariant(row);
      }
      _recount();
      final n = rows.where((r) => r.state == PbState.confident || r.state == PbState.verified).length;
      _set(S.pbRisultatoAbbinamento(n, rows.length), running: false);
    } catch (e) {
      _set(S.errore(e), running: false);
    }
  }

  static String _norm(String s) => s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_');

  /// One Studio icon per app component (package + activity when known).
  static String _studioKey(PbIcon g) => g.activity.isNotEmpty ? '${g.package}/${g.activity}' : g.package;

  /// The Studio icon made for [o]: same component, else same package, else
  /// a file name that spells the package. The newest one wins.
  PbIcon? _studioFor(PbIcon o, {Iterable<PbIcon>? among}) {
    if (o.package.isEmpty) return null;
    PbIcon? byComp, byPkg;
    for (final g in among ?? generated) {
      if (!g.id.startsWith('studio:') || g.path == null) continue;
      final pkg = g.package.isNotEmpty ? g.package : null;
      if (pkg == o.package) {
        if (g.activity.isNotEmpty && g.activity == o.activity) byComp = g;
        if (g.activity.isEmpty || g.activity == o.activity) byPkg = g;
      } else if (pkg == null && _norm(p.basenameWithoutExtension(g.file)) == _norm(o.package)) {
        byPkg = g;
      }
    }
    return byComp ?? byPkg;
  }

  /// Studio icons come before anything matched or regenerated here; only a
  /// later hand association or hand-made icon in the Pack goes above them.
  bool _applyStudio(PbRow row) {
    if (row.manual || row.custom) return false;
    final g = _studioFor(row.original);
    if (g == null) return false;
    row.generatedId = g.id;
    row.auto = MatchState.confident;
    row.reason = S.pbDaStudio;
    return true;
  }

  /// Hand-made icons follow the pack style too: each one is rendered again
  /// from its own source image with its own treatment, on the current
  /// background/plate ("Usa così com'è" icons stay untouched).
  Future<void> _redoCustom() async {
    for (final e in custom.entries.toList()) {
      final src = e.value['src'];
      final t = EditTreatment.values.where((v) => v.name == e.value['treatment']).firstOrNull;
      final path = e.value['path'];
      if (src == null || t == null || t == EditTreatment.raw || path == null || !File(src).existsSync()) continue;
      try {
        final png = await renderEdit(src, t);
        await File(path).writeAsBytes(png, flush: true);
        ImageStamps.bump(path);
      } catch (_) {
        // the previous file stays
      }
    }
  }

  /// A hand-made icon replaces whatever the matcher chose.
  void _applyCustom(PbRow row) {
    final c = custom[row.original.key];
    if (c == null) return;
    final id = 'custom:${row.original.key}';
    var g = _genById[id];
    if (g == null) {
      g = PbIcon(id: id, label: row.original.label, package: row.original.package, activity: row.original.activity, file: p.basename(c['path']!), path: c['path']);
      generated.add(g);
      _genById[id] = g;
    }
    row.generatedId = id;
    row.custom = true;
    row.reason = S.pbIconaPersonalizzata;
  }

  void _save(PbRow row) {
    final g = generatedById(row.generatedId);
    // keeps the other saved fields (label, aliases, variants, keepWhite)
    final old = AppState.I.packCorrections[row.original.key] ?? {};
    void apply() => AppState.I.packCorrections[row.original.key] = {
          ...old,
          // ids of an opened pack change at each opening: its app key is saved instead
        'generated': row.manual && g != null ? (g.id.startsWith('pk') ? g.key : g.id) : null,
          'excluded': row.excluded,
          'verified': row.verified,
        };
    // a batch saves per icon: one app-wide rebuild and one disk save at the end
    if (_deferAppSaves) {
      apply();
      _appSavePending = true;
    } else {
      AppState.I.update(apply);
    }
  }

  bool _deferAppSaves = false;
  bool _appSavePending = false;

  void assign(PbRow row, PbIcon g) {
    row.generatedId = g.id;
    row.baseGeneratedId = g.id;
    row.manual = true;
    row.reason = S.pbAssegnataManualmente;
    _forgetChoice(row);
    _save(row);
    _recount();
    notifyListeners();
  }

  /// Per app: keep the white areas closed inside the symbol (Calendar's
  /// page) instead of removing them as background. Regenerates that icon.
  bool keepsInnerWhite(PbRow row) => AppState.I.packCorrections[row.original.key]?['keepWhite'] == true;

  Future<void> setKeepInnerWhite(PbRow row, bool keep) async {
    final c = Map<String, dynamic>.from(AppState.I.packCorrections[row.original.key] ?? {});
    if (keep) {
      c['keepWhite'] = true;
    } else {
      c.remove('keepWhite');
    }
    AppState.I.update(() => AppState.I.packCorrections[row.original.key] = c);
    notifyListeners();
    await generateFromOriginals(only: [row]);
  }

  void setExcluded(PbRow row, bool v) {
    row.excluded = v;
    _linkVariant(row);
    _save(row);
    _recount();
    notifyListeners();
  }

  void setVerified(PbRow row, bool v) {
    row.verified = v;
    // a verified icon is accepted as it is now: its fingerprint is the new reference
    if (v && row.changedOriginal) _acceptOriginal(row);
    _save(row);
    notifyListeners();
  }

  void _acceptOriginal(PbRow row) {
    row.changedOriginal = false;
    _changedKeys.remove(row.original.key);
    unawaited(_rememberFingerprint(row.original));
  }

  // ------------------------------------------------------------ manual edit

  /// Settings of the pack mode with the per-icon treatment applied.
  ProcessSettings editSettings(EditTreatment t) {
    final st = AppState.I;
    final s = st.settingsFor(st.packMode, presetId: st.packPresetId, seg: st.packSegment);
    final strategy = switch (t) {
      EditTreatment.plateColor => LucentStrategy.plateColor,
      EditTreatment.fullBleed => LucentStrategy.fullBleed,
      EditTreatment.asIs => LucentStrategy.asIs,
      // the image as it is: only size and position on the plate, nothing
      // cut out, colours untouched (a full tile covers the plate edge)
      EditTreatment.placeOnly => LucentStrategy.tile,
      _ => LucentStrategy.auto,
    };
    var bg = s.background;
    if (bg is BackgroundSettings_Lucent) {
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
          launcherEncode: l.launcherEncode,
          strategy: strategy,
        ),
      );
    }
    return ProcessSettings(size: s.size, background: bg, placement: s.placement, segment: s.segment, ai: s.ai, effects: AppState.I.look.effects, cutCacheDir: s.cutCacheDir);
  }

  /// Renders a picked image for [row] (nothing is assigned yet). Returns PNG.
  /// Source image and treatment of the last "Modifica icona" render: kept
  /// with the hand-made icon so it follows later changes of the pack style.
  (String, EditTreatment)? _lastEdit;

  Future<Uint8List> renderEdit(String source, EditTreatment t) async {
    _lastEdit = (source, t);
    if (t == EditTreatment.raw) {
      final dest = p.join(await AppPaths.I.workDir('edit'), 'raw.png');
      await importAsPng(src: source, dest: dest);
      return File(dest).readAsBytes();
    }
    if (t == EditTreatment.placeOnly) {
      final dest = p.join(await AppPaths.I.workDir('edit'), 'place.png');
      await importAsPng(src: source, dest: dest);
      return composeGlyphPng(glyphPng: await File(dest).readAsBytes(), settings: editSettings(t));
    }
    final r = await previewFile(path: source, settings: editSettings(t));
    return r.png;
  }

  /// Confirms a hand-made icon for [row]: stored in the app folder, linked
  /// to the app's package/activity and used by every export and by the pack
  /// applied on the phone. The previous choice is kept for "Ripristina".
  Future<void> applyEdit(PbRow row, Uint8List png) async {
    await Directory(_customDir).create(recursive: true);
    final name = '${sanitizeDrawableName(name: row.original.package.isNotEmpty ? row.original.package : row.original.title)}_${DateTime.now().millisecondsSinceEpoch}.png';
    final path = p.join(_customDir, name);
    await File(path).writeAsBytes(png, flush: true);
    final old = custom[row.original.key];
    final prev = old != null ? old['prev'] : (row.custom ? null : generatedById(row.generatedId)?.id);
    // an older hand-made file of the same app is replaced
    if (old?['path'] != null) {
      try {
        await File(old!['path']!).delete();
      } catch (_) {}
    }
    // the source image and treatment, to redo this icon when the pack's
    // background/plate settings change (the user's choice stays)
    String? src;
    final le = _lastEdit;
    if (le != null && File(le.$1).existsSync()) {
      src = p.join(_customDir, '${p.basenameWithoutExtension(name)}_src${p.extension(le.$1)}');
      await File(le.$1).copy(src);
    }
    if (old?['src'] != null) {
      try {
        await File(old!['src']!).delete();
      } catch (_) {}
    }
    custom[row.original.key] = {'path': path, 'prev': prev, if (src != null) 'src': src, if (le != null) 'treatment': le.$2.name};
    final id = 'custom:${row.original.key}';
    generated.removeWhere((g) => g.id == id);
    _genById.remove(id);
    row.variant = false;
    _applyCustom(row);
    row.baseGeneratedId = row.generatedId;
    _recount();
    status = S.pbIconaAggiornata(row.original.title);
    notifyListeners();
  }

  bool hasCustom(PbRow row) => custom.containsKey(row.original.key);

  /// Back to the icon used before "Modifica icona".
  Future<void> restoreEdit(PbRow row) async {
    final c = custom.remove(row.original.key);
    if (c == null) return;
    final id = 'custom:${row.original.key}';
    generated.removeWhere((g) => g.id == id);
    _genById.remove(id);
    try {
      await File(c['path']!).delete();
    } catch (_) {}
    row.custom = false;
    final prev = generatedById(c['prev']);
    row.baseGeneratedId = prev?.id;
    _linkVariant(row);
    _recount();
    row.reason = prev == null ? S.pbNessunaIcona : S.pbRipristinata;
    status = S.pbIconaRipristinata(row.original.title);
    notifyListeners();
  }

  // ------------------------------------------------------------ export

  /// Builds the pack folder (drawables, appfilter.xml, mapping.json).
  Future<String?> _buildPackDir(String name) async {
    final ok = rows.where((r) => !r.excluded && r.generatedId != null).toList();
    if (ok.isEmpty) return null;
    final dir = await AppPaths.I.workDir('iconpack');
    final apps = [...await _packEntries(ok), ..._calendarApps];
    final res = await buildIconPack(apps: apps, outDir: dir, packName: name, zipPath: null);
    return res.outDir;
  }

  /// Pack entries of [ok]: each icon under its own app and under the apps it
  /// is aliased to (an alias replaces that app's own entry). Label = pack name.
  Future<List<IconPackApp>> _packEntries(List<PbRow> ok) async {
    final byKey = {for (final r in rows) r.original.key: r};
    final pngByKey = <String, String>{};
    final keyed = <(String, IconPackApp)>[];
    for (final r in ok) {
      final g = generatedById(r.generatedId)!;
      final png = pngByKey[r.original.key] = g.path ?? await _materialize(g);
      keyed.add((_compKey(r.original), IconPackApp(label: nameOf(r), package: r.original.package, activity: r.original.activity, png: png)));
    }
    for (final r in ok) {
      for (final k in aliasesOf(r)) {
        final t = byKey[k];
        if (t == null || t.excluded || t.original.package.isEmpty) continue;
        keyed.add((_compKey(t.original), IconPackApp(label: nameOf(t), package: t.original.package, activity: t.original.activity, png: pngByKey[r.original.key]!)));
      }
    }
    return pack2LastWins(keyed);
  }

  static String _compKey(PbIcon o) => o.package.isEmpty ? o.key : '${o.package}/${o.activity}';

  /// Entries the pack will hold (each icon's own app and its aliases), as
  /// findConflicts reads them, with the row each entry belongs to.
  ({List<PackEntryInfo> entries, List<PbRow> owners}) conflictInput() {
    final ok = rows.where((r) => !r.excluded && generatedById(r.generatedId) != null).toList();
    final byKey = {for (final r in rows) r.original.key: r};
    final entries = <PackEntryInfo>[];
    final owners = <PbRow>[];
    PackEntryInfo entryOf(PbRow t) => packEntryFor(package: t.original.package, activity: t.original.activity, label: nameOf(t), drawableOf: (k) => sanitizeDrawableName(name: k));
    for (final r in ok) {
      entries.add(entryOf(r));
      owners.add(r);
    }
    for (final r in ok) {
      for (final k in aliasesOf(r)) {
        final t = byKey[k];
        if (t == null || t.excluded || t.original.package.isEmpty) continue;
        entries.add(entryOf(t));
        owners.add(t);
      }
    }
    return (entries: entries, owners: owners);
  }

  /// Icons of another pack (its appfilter links them to apps) matched to the
  /// rows without an icon. Nothing changes until [applyMatches].
  Future<List<PbMatch>> matchFromPack(String path) async {
    _set(S.pbLettura, running: true);
    try {
      final (src, _, _) = await _readSource(path, 'im${DateTime.now().millisecondsSinceEpoch}_');
      final open = [for (final r in rows) if (r.generatedId == null && !r.excluded && r.original.package.isNotEmpty) r];
      final byPkg = <String, PbRow>{};
      for (final r in open) {
        byPkg.putIfAbsent(r.original.package, () => r);
      }
      final installed = [for (final r in byPkg.values) InstalledAppInfo(package: r.original.package, label: nameOf(r), activity: r.original.activity)];
      final entries = mappingSourceEntries([for (final g in src) (package: g.package, activity: g.activity, drawable: p.basenameWithoutExtension(g.file))]);
      final icons = {for (final g in src) if (g.package.isNotEmpty) p.basenameWithoutExtension(g.file).toLowerCase(): g};
      final mapped = importMappingsDetailed(source: entries, installed: installed);
      _set(null, running: false);
      return [
        for (final e in mapped.entries)
          if (byPkg[e.key] != null && icons[e.value.drawable] != null) PbMatch(row: byPkg[e.key]!, icon: icons[e.value.drawable]!, match: e.value.match),
      ];
    } catch (e) {
      _set(S.errore(e), running: false);
      rethrow;
    }
  }

  /// Assigns the matched icons, copied next to the app data first. Rows that
  /// got an icon meanwhile are skipped. Returns how many were assigned.
  Future<int> applyMatches(List<PbMatch> matches) async {
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final dir = Directory(p.join(AppPaths.I.root.path, 'pack_imported', '$stamp'));
    await dir.create(recursive: true);
    var n = 0;
    for (final m in matches) {
      final src = m.icon.path;
      if (m.row.generatedId != null || src == null) continue;
      final dest = p.join(dir.path, 'icon_$n.png');
      await File(src).copy(dest);
      final g = PbIcon(id: 'im${stamp}_$n', label: m.icon.label, package: m.icon.package, activity: m.icon.activity, file: m.icon.file, path: dest);
      generated.add(g);
      _reindex();
      assign(m.row, g);
      n++;
    }
    return n;
  }

  /// Windows: installable icon pack APK with its own icon browser.
  Future<ExportResult?> exportApk(String name) async {
    _set(S.apkCompilazione, running: true);
    try {
      final dir = await _buildPackDir(name);
      if (dir == null) return null;
      final apk = await ApkPackService.build(packDir: dir, name: name, log: (l) => _set(l, running: true));
      _set(S.apkPronto, running: false);
      return await ExportService.saveApk(apk, '${sanitizeDrawableName(name: name)}.apk');
    } catch (e) {
      _set(S.errore(e), running: false);
      rethrow;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  /// Android: builds the pack APK on the phone, installs it and (with
  /// Shizuku) selects it in the system launcher. Returns the user message.
  Future<String?> applyOnDevice({String name = 'Icon Formatter Pack', Future<bool> Function()? confirmReplace}) async {
    name = AppState.I.export.packNameOr(name);
    _set(S.dpCompilazione, running: true);
    try {
      final dir = await _buildPackDir(name);
      if (dir == null) {
        _set(S.pbNienteDaEsportare, running: false);
        return null;
      }
      final accent = '#${(AppState.I.export.packAccentOr(AppState.I.appearance.accentColor.toARGB32()) & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';
      var built = await PlatformService.devicePackBuild(dir, name, accent);
      var apk = built['apk'] as String;
      final n = (built['count'] as num).toInt();
      var v = built['version'] as String? ?? '';
      final shizuku = await PlatformService.shizukuState() == 'granted';
      _set(S.dpInstallazione, running: true);
      try {
        try {
          await PlatformService.devicePackInstall(apk, shizuku: shizuku);
        } catch (e) {
          // Android still remembers a newer number of our pack (removed with
          // "keep data", or installed for another user): the native side
          // noted it, one rebuild with the next number installs in place
          if (!'$e'.contains('VERSION_RETRY')) rethrow;
          built = await PlatformService.devicePackBuild(dir, name, accent);
          apk = built['apk'] as String;
          v = built['version'] as String? ?? '';
          await PlatformService.devicePackInstall(apk, shizuku: shizuku);
        }
      } catch (e) {
        // the installed pack was signed on another phone: it cannot be
        // updated in place; replaced only if the user agrees
        if (!'$e'.contains('SIGNATURE_MISMATCH')) rethrow;
        if (confirmReplace == null || !await confirmReplace()) {
          _set(S.dpFirmaDiversa, running: false);
          return S.dpFirmaDiversa;
        }
        _set(S.dpSostituzione, running: true);
        await PlatformService.devicePackUninstall();
        await PlatformService.devicePackInstall(apk, shizuku: shizuku);
      }
      if (!shizuku) {
        _set(S.dpConfermaSistema, running: false);
        return S.dpConfermaSistema;
      }
      final info = await PlatformService.devicePackInfo();
      if (info['launcher'] == null) {
        _set(S.dpInstallato(n, v), running: false);
        return S.dpNoLauncher;
      }
      _set(S.dpApplicazione, running: true);
      final r = await PlatformService.devicePackApply();
      final msg = r['verified'] == true ? S.dpFatto(n, v) : S.dpNonVerificato;
      if (r['verified'] == true) _log(S.packLogApplicato(n, v));
      _set(msg, running: false);
      return msg;
    } catch (e) {
      _set(S.errore(e), running: false);
      rethrow;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  /// Android: builds the pack APK on the phone (signed, not installed) and
  /// opens the share sheet, e.g. to move it to another phone.
  Future<void> shareApk({String name = 'Icon Formatter Pack'}) async {
    name = AppState.I.export.packNameOr(name);
    _set(S.dpCompilazione, running: true);
    try {
      final dir = await _buildPackDir(name);
      if (dir == null) {
        _set(S.pbNienteDaEsportare, running: false);
        return;
      }
      final accent = '#${(AppState.I.export.packAccentOr(AppState.I.appearance.accentColor.toARGB32()) & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';
      final built = await PlatformService.devicePackBuild(dir, name, accent);
      final v = built['version'] as String? ?? '';
      final out = p.join(await AppPaths.I.workDir('share'), 'IconFormatter-Pack-$v.apk');
      await File(built['apk'] as String).copy(out);
      _set(S.pbApkPronto(v), running: false);
      await ExportService.share([out], text: 'Icon Formatter Pack $v');
    } catch (e) {
      _set(S.errore(e), running: false);
      rethrow;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  /// After a hand edit: the pack on the phone is rebuilt and re-applied when
  /// it is installed and Shizuku is ready. Returns the message, or null.
  Future<String?> refreshDevicePack() async {
    if (!Platform.isAndroid) return null;
    final info = await PlatformService.devicePackInfo();
    if (info['installed'] != true || info['shizuku'] != 'granted') return null;
    return applyOnDevice();
  }

  /// [onlyChanged]: only the icons changed since the last export (calendars
  /// are left out, they have no per-icon state).
  Future<ExportResult?> export({required bool zip, bool onlyChanged = false}) async {
    final all = rows.where((r) => !r.excluded && r.generatedId != null).toList();
    final ok = onlyChanged ? all.where(_changedSince).toList() : all;
    if (ok.isEmpty) return null;
    final dir = await AppPaths.I.workDir('iconpack');
    final apps = [...await _packEntries(ok), if (!onlyChanged) ..._calendarApps];
    final res = await buildIconPack(apps: apps, outDir: dir, packName: 'Icon Formatter', zipPath: null);
    final base = onlyChanged ? 'IconFormatter-pack-modificate' : 'IconFormatter-pack';
    // a ZIP is named with the pack name, version and date; a folder keeps its name
    final name = zip ? exportFileName(packName: AppState.I.export.packNameOr(base), version: appVersion, date: DateTime.now(), ext: '') : base;
    final saved = await ExportService.exportDir(res.outDir, name: name, zip: zip);
    if (saved != null) {
      final snap = AppState.I.packExportSnapshot;
      final now = {for (final r in all) r.original.key: _sig(r)};
      var added = 0, changed = 0;
      if (snap != null) {
        for (final e in now.entries) {
          final old = snap[e.key];
          if (old == null) {
            added++;
          } else if (old != e.value) {
            changed++;
          }
        }
      }
      final removed = snap == null ? 0 : snap.keys.where((k) => !now.containsKey(k)).length;
      _log(onlyChanged
          ? S.packLogEsportataSolo(res.icons)
          : snap == null
              ? S.packLogEsportataPrima(res.icons)
              : S.packLogEsportata(res.icons, added, changed, removed));
      final next = onlyChanged ? {...?snap, for (final r in ok) r.original.key: _sig(r)} : now;
      AppState.I.update(() => AppState.I.packExportSnapshot = next);
    }
    _set(S.pbEsportate(res.icons));
    return saved;
  }

  // ------------------------------------------------------------ quality

  // ------------------------------------------------------------ aliases, labels, variants

  Map<String, dynamic> _corrOf(PbRow r) => Map<String, dynamic>.from(AppState.I.packCorrections[r.original.key] ?? {});

  /// Stores the corrections of [r]; an empty map removes the entry.
  void _putCorr(PbRow r, Map<String, dynamic> m) {
    final key = r.original.key;
    AppState.I.update(() {
      if (m.isEmpty) {
        AppState.I.packCorrections.remove(key);
      } else {
        AppState.I.packCorrections[key] = m;
      }
    });
  }

  /// Keys of the apps that also get this icon ("Usa per altre app").
  List<String> aliasesOf(PbRow r) => ((AppState.I.packCorrections[r.original.key]?['alias'] as List?) ?? const []).cast<String>();

  void setAliases(PbRow r, List<String> keys) {
    final m = _corrOf(r);
    if (keys.isEmpty) {
      m.remove('alias');
    } else {
      m['alias'] = keys;
    }
    _putCorr(r, m);
    notifyListeners();
  }

  /// "Rinomina nel pack": empty or the original title removes the label.
  void setLabel(PbRow r, String label) {
    final m = _corrOf(r);
    final t = label.trim();
    if (t.isEmpty || t == r.original.title) {
      m.remove('label');
    } else {
      m['label'] = t;
    }
    _putCorr(r, m);
    notifyListeners();
  }

  /// Extra icon files of an app, besides its generated one (at most two).
  List<String> variantPaths(PbRow r) => ((AppState.I.packCorrections[r.original.key]?['variants'] as List?) ?? const []).cast<String>();

  /// The variant file in use, or null for the generated icon.
  String? chosenVariant(PbRow r) => AppState.I.packCorrections[r.original.key]?['variant'] as String?;

  /// False when the app already has two extra icons or this one is listed.
  bool addVariant(PbRow r, String path) {
    final list = variantPaths(r);
    if (list.length >= 2 || list.contains(path)) return false;
    final m = _corrOf(r)..['variants'] = [...list, path];
    _putCorr(r, m);
    notifyListeners();
    return true;
  }

  /// Removes an extra icon; if it was the one in use, the generated icon returns.
  void removeVariant(PbRow r, String path) {
    final m = _corrOf(r);
    final list = [...variantPaths(r)]..remove(path);
    if (list.isEmpty) {
      m.remove('variants');
    } else {
      m['variants'] = list;
    }
    if (m['variant'] == path) m.remove('variant');
    _putCorr(r, m);
    _linkVariant(r);
    _recount();
    notifyListeners();
  }

  /// Uses the variant file [path] for [r]; null goes back to the generated icon.
  void chooseVariant(PbRow r, String? path) {
    final m = _corrOf(r);
    if (path == null) {
      m.remove('variant');
    } else {
      m['variant'] = path;
    }
    _putCorr(r, m);
    _linkVariant(r);
    _recount();
    notifyListeners();
  }

  /// A new icon replaced the variant in use: the choice is forgotten.
  void _forgetChoice(PbRow row) {
    row.variant = false;
    final m = _corrOf(row);
    if (m.remove('variant') != null) _putCorr(row, m);
  }

  /// Points [row] at its chosen variant file, else back at its base icon.
  void _linkVariant(PbRow row) {
    final v = chosenVariant(row);
    row.variant = false;
    row.generatedId = row.baseGeneratedId;
    if (v == null || row.custom || row.excluded || !File(v).existsSync()) return;
    final o = row.original;
    final id = 'var:${o.key}|$v';
    var g = _genById[id];
    if (g == null) {
      g = PbIcon(id: id, label: o.label, package: o.package, activity: o.activity, file: p.basename(v), path: v);
      generated.add(g);
      _genById[id] = g;
    }
    row.generatedId = id;
    row.variant = true;
    row.reason = S.pack2VarianteScelta;
  }

  // ------------------------------------------------------------ contact sheet

  /// Contact sheets of the generated icons (96 per sheet, 400 at most), written
  /// to one folder. Each icon is read only when its sheet is drawn.
  Future<List<String>> contactSheetFiles() async {
    final todo = [for (final r in rows) if (!r.excluded && generatedById(r.generatedId)?.path != null) r];
    final n = todo.length < contactSheetMaxIcons ? todo.length : contactSheetMaxIcons;
    if (n == 0 || busy) return const [];
    final out = await AppPaths.I.workDir('sheetout');
    final files = <String>[];
    _set(S.pack2AnteprimaProgresso(0, n), prog: 0, running: true);
    try {
      // the folder only holds the sheets of this run
      await for (final e in Directory(out).list()) {
        if (e is File) await e.delete();
      }
      var start = 0;
      for (final count in contactSheetPages(n)) {
        final icons = <({String name, Uint8List png})>[];
        for (final r in todo.sublist(start, start + count)) {
          try {
            icons.add((name: nameOf(r), png: await File(generatedById(r.generatedId)!.path!).readAsBytes()));
          } catch (_) {
            // a missing icon file is left off the sheet
          }
        }
        start += count;
        // the export draws one sheet into its cache folder; copy it out
        final tmp = await ExportService.exportContactSheet(icons);
        if (tmp != null) {
          final dest = p.join(out, 'IconFormatter-anteprima_${files.length + 1}.png');
          await File(tmp).copy(dest);
          files.add(dest);
        }
        _set(S.pack2AnteprimaProgresso(start, n), prog: start / n, running: true, throttle: true);
      }
    } finally {
      _set(null, running: false);
    }
    return files;
  }

  // ------------------------------------------------------------ changed originals

  /// Keeps the fingerprint of an installed app's icon as the reference.
  Future<void> _rememberFingerprint(PbIcon o) async {
    final path = o.path;
    if (path == null) return;
    try {
      // hashing every byte in Dart: done off the UI isolate
      final fp = await Isolate.run(() => pack2Fingerprint(File(path).readAsBytesSync()));
      if (_deferAppSaves) {
        AppState.I.packFingerprints[o.key] = fp;
        _appSavePending = true;
      } else {
        AppState.I.update(() => AppState.I.packFingerprints[o.key] = fp);
      }
    } catch (_) {
      // an unreadable icon keeps its old reference
    }
  }

  /// Compares each installed app's icon with the reference kept at its last
  /// generation; changed rows become "review". One icon per step, with a yield
  /// in between, so the first frame is never held up.
  Future<void> checkChangedOriginals() async {
    if (_checkingOriginals) return;
    final fps = AppState.I.packFingerprints;
    final todo = [for (final r in rows) if (isInstalled(r) && r.original.path != null && fps.containsKey(r.original.key)) r.original];
    if (todo.isEmpty) return;
    _checkingOriginals = true;
    final before = Set<String>.of(_changedKeys);
    try {
      for (final o in todo) {
        try {
          final now = pack2Fingerprint(await File(o.path!).readAsBytes());
          if (pack2FingerprintChanged(fps[o.key], now)) {
            _changedKeys.add(o.key);
          } else {
            _changedKeys.remove(o.key);
          }
        } catch (_) {
          // unreadable: no verdict for this app
        }
        await Future<void>.delayed(Duration.zero);
      }
    } finally {
      _checkingOriginals = false;
    }
    for (final r in rows) {
      r.changedOriginal = _changedKeys.contains(r.original.key);
    }
    if (before.length != _changedKeys.length || !before.every(_changedKeys.contains)) notifyListeners();
  }

  bool hasSource(PbRow r) => r.original.path != null || r.original.bytes != null;

  /// Missing rows that have an original to render from.
  List<PbRow> get _missingWithSource => [for (final r in rows) if (r.state == PbState.missing && hasSource(r)) r];

  int get missingCount => _missingWithSource.length;

  /// Generates only the rows without an icon, from their originals.
  Future<void> generateMissing() async {
    final todo = _missingWithSource;
    if (todo.isEmpty) return;
    await generateFromOriginals(only: todo);
  }

  /// Pixel checks on every generated icon; only the icons with problems.
  Future<List<(PbRow, List<PbProblem>)>> scanQuality() async {
    final todo = [for (final r in rows) if (!r.excluded && generatedById(r.generatedId)?.path != null) r];
    final out = <(PbRow, List<PbProblem>)>[];
    if (todo.isEmpty) return out;
    _set(S.packQualitaScan(0, todo.length), prog: 0, running: true);
    try {
      for (var i = 0; i < todo.length; i++) {
        try {
          final png = await File(generatedById(todo[i].generatedId)!.path!).readAsBytes();
          final img = await packDecodeRgba(png);
          final probs = packCheckPixels(img.rgba, img.width, img.height);
          if (probs.isNotEmpty) out.add((todo[i], probs));
        } catch (_) {
          // an unreadable icon is skipped
        }
        _set(S.packQualitaScan(i + 1, todo.length), prog: (i + 1) / todo.length, running: true, throttle: true);
      }
    } finally {
      _set(null, running: false);
    }
    return out;
  }

  // ------------------------------------------------------------ log and profiles

  /// Newest first, the last 30 lines (release notes).
  void _log(String text) {
    final st = AppState.I;
    st.update(() {
      st.packLog.insert(0, {'date': DateTime.now().toIso8601String(), 'text': text});
      if (st.packLog.length > 30) st.packLog.removeRange(30, st.packLog.length);
    });
  }

  /// Changes when the icon is rendered again or hand-edited.
  String _sig(PbRow r) => generatedById(r.generatedId)?.path ?? '';

  /// Changed since the last export; with no export yet, the hand-made ones.
  bool _changedSince(PbRow r) {
    final snap = AppState.I.packExportSnapshot;
    if (snap == null) return r.custom || r.manual;
    return snap[r.original.key] != _sig(r);
  }

  /// False until the first export: "Solo le modificate" then means hand edits.
  bool get hasExportBaseline => AppState.I.packExportSnapshot != null;

  static Map<String, Map<String, dynamic>> _copyCorrections(Map m) => (jsonDecode(jsonEncode(m)) as Map).map((k, v) => MapEntry(k as String, (v as Map).cast<String, dynamic>()));

  /// Saves the current corrections under [name] (same name replaces it).
  void saveProfile(String name) {
    final st = AppState.I;
    final copy = _copyCorrections(st.packCorrections);
    st.update(() {
      st.packProfiles.removeWhere((e) => e['name'] == name);
      st.packProfiles.insert(0, {'name': name, 'date': DateTime.now().toIso8601String(), 'corrections': copy});
    });
  }

  /// Replaces the current corrections with a saved set, then matches again.
  Future<void> loadProfile(Map<String, dynamic> profile) async {
    final st = AppState.I;
    final corr = _copyCorrections((profile['corrections'] as Map?) ?? {});
    st.update(() => st.packCorrections = corr);
    _log(S.packLogProfilo(profile['name'] as String));
    await match();
  }

  void deleteProfile(String name) => AppState.I.update(() => AppState.I.packProfiles.removeWhere((e) => e['name'] == name));

  Future<String> _materialize(PbIcon g) async {
    final f = File(p.join(await AppPaths.I.workDir('pbmem'), '${g.id.replaceAll(':', '_')}.png'));
    await f.writeAsBytes(g.bytes!);
    g.path = f.path;
    return f.path;
  }
}

class PackBuilderScreen extends StatefulWidget {
  const PackBuilderScreen({super.key});

  @override
  State<PackBuilderScreen> createState() => _PackBuilderScreenState();
}

class _PackBuilderScreenState extends State<PackBuilderScreen> {
  final c = PackBuilderController.I;
  PbState? filter;

  /// From the coverage line: only the installed apps still without an icon.
  bool installedMissing = false;
  String query = '';
  final _scroll = ScrollController();
  final _search = TextEditingController();

  @override
  void dispose() {
    _scroll.dispose();
    _search.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    c._pickKindImpl = () => showAppSheet<String>(
      context: context,
      builder: (ctx) => SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(contentPadding: const EdgeInsets.symmetric(horizontal: 22), leading: const Icon(Icons.folder_open_outlined), title: Text(S.cartella), onTap: () => Navigator.pop(ctx, 'folder')),
            ListTile(contentPadding: const EdgeInsets.symmetric(horizontal: 22), leading: const Icon(Icons.folder_zip_outlined), title: Text(S.zipOApk), onTap: () => Navigator.pop(ctx, 'zip')),
          ],
        ),
      ),
    );
    // the catalogue of installed apps is always shown (read once per run)
    if (Platform.isAndroid) {
      WidgetsBinding.instance.addPostFrameCallback((_) => c.loadCatalog());
    } else if (c.rows.isEmpty && c.originals.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => c.match());
    }
    // lazy and in the background: changed system icons are marked for review
    WidgetsBinding.instance.addPostFrameCallback((_) => c.checkChangedOriginals());
  }

  // the controller is shared by the whole app (Studio sends icons to it):
  // it is never disposed with the screen

  Color _color(PbState s) => switch (s) {
    PbState.confident => Palette.ok,
    PbState.verified => Theme.of(context).colorScheme.primary,
    PbState.review => const Color(0xFF6FA8FF),
    PbState.doubtful => Palette.warn,
    PbState.missing => Palette.danger,
    PbState.excluded => Palette.text3,
  };

  IconData _icon(PbState s) => switch (s) {
    PbState.confident => Icons.link_rounded,
    PbState.verified => Icons.verified_rounded,
    PbState.review => Icons.visibility_outlined,
    PbState.doubtful => Icons.help_outline_rounded,
    PbState.missing => Icons.hide_image_outlined,
    PbState.excluded => Icons.block_rounded,
  };

  String _label(PbState s) => switch (s) {
    PbState.confident => S.pbSicura,
    PbState.verified => S.pbVerificata,
    PbState.review => S.pbDaVerificare,
    PbState.doubtful => S.pbDubbia,
    PbState.missing => S.pbMancante,
    PbState.excluded => S.pbEsclusa,
  };

  Future<void> _run(Future<void> Function() f) async {
    try {
      await f();
    } catch (e) {
      if (mounted) showMsg(context, S.errore(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) {
        final q = query.toLowerCase();
        final counts = <PbState, int>{for (final s in PbState.values) s: 0};
        final rows = <PbRow>[];
        for (final r in c.rows) {
          final st = r.state;
          counts[st] = counts[st]! + 1;
          if (filter != null && st != filter) continue;
          if (installedMissing && !(c.isInstalled(r) && st == PbState.missing)) continue;
          if (q.isNotEmpty && !r.original.title.toLowerCase().contains(q) && !r.original.package.toLowerCase().contains(q)) continue;
          rows.add(r);
        }
        final pad = EdgeInsets.fromLTRB(20, 0, 20, 0);
        // status / progress floats over the page (nothing moves); a sideways
        // swipe hides it and the work keeps going
        final status = c.status == null
            ? null
            : Padding(
                padding: EdgeInsets.zero,
                child: Dismissible(
                  key: ValueKey('pb-status-${c.status}'),
                  direction: DismissDirection.horizontal,
                  onDismissed: (_) => c.hideStatus(),
                  child: Tile(
                    padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            if (c.busy) const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
                            if (c.busy) const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                c.status!,
                                key: const ValueKey('pb-status'),
                                style: TextStyle(fontSize: 12.5, color: Palette.text2),
                              ),
                            ),
                          ],
                        ),
                        if (c.progress != null && c.busy) ...[
                          const SizedBox(height: 8),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(3),
                            child: LinearProgressIndicator(value: c.progress, minHeight: 4),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              );
        // one scroll view, the grid is lazy (only visible cards are built)
        final page = CustomScrollView(
          controller: _scroll,
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              sliver: SliverList.list(
                children: [
                  // the last summary ("N su M abbinate") is the subtitle once the
                  // work is done; while working the strip floats over card 1
                  LargeHeader(S.pbTitolo),
                  // status floats over the first card, right under the title
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      StepCard(
                        step: 1,
                        icon: Platform.isAndroid ? Icons.apps_rounded : null,
                        title: Platform.isAndroid
                            ? (c.catalogVisible == null ? S.pbPasso1Catalogo : '${S.pbPasso1Catalogo} · ${c.originals.where((o) => o.id.startsWith('app:')).length}')
                            : S.pbPasso1,
                        // desktop: the subtitle says what to load
                        subtitle: Platform.isAndroid ? null : (c.originals.isEmpty ? S.pbPasso1Sub : S.pbOriginaliN(c.originals.length)),
                        done: c.originals.isNotEmpty,
                        children: [
                          if (Platform.isAndroid) ToolButton(icon: Icons.refresh_rounded, label: S.pbAggiornaCatalogo, onTap: c.busy ? null : () => _run(c.addInstalledApps)),
                          ToolButton(icon: Icons.inventory_2_outlined, label: Platform.isAndroid ? S.pbDaFile : S.pbOriginali, onTap: c.busy ? null : () => _run(() => c.addSource(original: true))),
                          if (c.originals.any((o) => !o.id.startsWith('app:')))
                            ToolButton(
                              icon: Icons.clear_all,
                              label: S.svuota,
                              onTap: c.busy
                                  ? null
                                  : () async {
                                      if (await confirm(context, S.svuotareLista, S.fileOriginaliNonVengonoToccati, ok: S.svuota)) _run(c.clearFileOriginals);
                                    },
                            ),
                        ],
                      ),
                      if (status != null && c.busy) Positioned(left: 0, right: 0, top: 0, child: status),
                    ],
                  ),
                  StepCard(
                    step: 2,
                    icon: Icons.auto_awesome_mosaic_outlined,
                    title: S.pbPasso2,
                        done: c.rows.any((r) => r.generatedId != null),
                    children: [
                      ToolButton(icon: Icons.auto_fix_high_outlined, label: S.pbGeneraDaStudio, onTap: c.busy || c.originals.isEmpty ? null : () => _run(() => c.generateFromOriginals())),
                      ToolButton(icon: Icons.collections_outlined, label: S.pbImportaGenerate, onTap: c.busy ? null : () => _run(() => c.addSource(original: false))),
                      Builder(
                        builder: (bctx) => ToolButton(icon: Icons.inventory_outlined, label: S.pbApriPack, onTap: c.busy ? null : () => _run(() => _openPack(anchorOf(bctx)))),
                      ),
                      ToolButton(icon: Icons.join_inner_rounded, label: S.pbAbbina, onTap: c.busy || c.originals.isEmpty ? null : () => _run(c.match)),
                      if (c.missingCount > 0) ToolButton(icon: Icons.add_photo_alternate_outlined, label: S.packMancanti(c.missingCount), onTap: c.busy ? null : () => _run(c.generateMissing)),
                    ],
                  ),
                  if (Platform.isAndroid && c.coverTotal > 0) ...[
                    const SizedBox(height: 14),
                    _coverageTile(),
                  ],
                  if (c.rows.isNotEmpty) ...[
                    // the same space under the coverage line as above it
                    SizedBox(height: Platform.isAndroid && c.coverTotal > 0 ? 14 : 6),
                    // one compact icon per state, in the state's colour; the
                    // name and count of the active filter are spelled out below
                    LayoutBuilder(
                      builder: (context, box) {
                        final states = <PbState?>[null, ...PbState.values.where((s) => counts[s]! > 0 || s == PbState.missing || filter == s)];
                        // wide enough for an icon and three digits, so no count is
                        // shrunk: one row when they fit, else two balanced rows
                        const minW = 76.0;
                        final n = states.length;
                        final perRow = n * minW + (n - 1) * 6 <= box.maxWidth ? n : (n / 2).ceil();
                        final w = ((box.maxWidth - 6 * (perRow - 1)) / perRow).floorToDouble().clamp(minW, 130.0);
                        return Wrap(
                          alignment: WrapAlignment.center,
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            for (final s in states)
                              SizedBox(
                                width: w,
                                child: IconFilterPill(
                                  key: ValueKey('pb-filter-${s?.name ?? 'all'}'),
                                  icon: s == null ? Icons.apps_rounded : _icon(s),
                                  color: s == null ? Theme.of(context).colorScheme.primary : _color(s),
                                  tooltip: s == null ? S.pbTutte(c.rows.length) : '${_label(s)} ${counts[s]}',
                                  on: filter == s,
                                  count: s == null ? c.rows.length : counts[s],
                                  onTap: () => setState(() {
                                    installedMissing = false;
                                    filter = filter == s || s == null ? null : s;
                                  }),
                                ),
                              ),
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 6),
                  ],
                  if (c.rows.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 40),
                      child: Center(
                        child: Text(
                          c.originals.isEmpty ? S.pbVuoto : S.pbPremiAbbina,
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Palette.text2),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            // the search stays at the top while the cards scroll under it
            if (c.rows.isNotEmpty) ...[
              SliverPinnedSearch(
                padding: const EdgeInsets.fromLTRB(20, 6, 20, 6),
                child: TextField(controller: _search, decoration: pillSearchDecoration(context, S.cercaNomeOPackage), onChanged: (v) => setState(() => query = v)),
              ),
            ],
            if (c.rows.isNotEmpty)
              SliverPadding(
                padding: pad,
                sliver: SliverGrid.builder(
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 130, mainAxisExtent: 124, crossAxisSpacing: 8, mainAxisSpacing: 8),
                  itemCount: rows.length,
                  itemBuilder: (context, i) => _card(rows[i]),
                ),
              ),
            SliverPadding(
              padding: EdgeInsets.fromLTRB(20, 12, 20, 16 + GlassInsets.of(context)),
              sliver: SliverList.list(
                children: [
                  if (Platform.isAndroid) LauncherApplyCard(builder: c),
                  if (c.rows.isNotEmpty)
                    StepCard(
                      step: Platform.isAndroid ? 4 : 3,
                      title: S.pbEsporta,
                      subtitle: S.pbEsportaSub,
                      children: [
                        ToolButton(icon: Icons.ios_share_rounded, label: S.pbEsporta, onTap: c.busy ? null : _exportChoose),
                        ToolButton(icon: Icons.phone_android_rounded, label: S.anteprimaHome, onTap: c.busy || !c.rows.any((r) => !r.excluded && c.generatedById(r.generatedId) != null) ? null : _homePreview),
                        ToolButton(icon: Icons.photo_library_outlined, label: S.pack2Anteprima, onTap: c.busy || !c.rows.any((r) => !r.excluded && c.generatedById(r.generatedId) != null) ? null : () => _run(_contactSheet)),
                        if (Platform.isAndroid) ToolButton(icon: Icons.share_outlined, label: S.pbCondividiApk, onTap: c.busy ? null : () => _run(c.shareApk)),
                        if (ApkPackService.available)
                          ToolButton(
                            icon: Icons.android_rounded,
                            label: S.apkCrea,
                            onTap: c.busy
                                ? null
                                : () async {
                                    final name = await askText(context, S.apkNome, initial: 'Icon Formatter Pack');
                                    if (name == null || name.trim().isEmpty) return;
                                    try {
                                      final r = await c.exportApk(name.trim());
                                      if (context.mounted && r != null) showMsg(context, '${r.message} · ${r.location}');
                                    } catch (e) {
                                      if (context.mounted) showMsg(context, S.errore(e), error: true);
                                    }
                                  },
                          ),
                        ToolButton(icon: Icons.fact_check_outlined, label: S.packQualita, onTap: c.busy ? null : () => _run(_quality)),
                        ToolButton(icon: Icons.warning_amber_rounded, label: S.pack3Conflitti, onTap: c.busy ? null : () => _run(_conflicts)),
                        ToolButton(icon: Icons.history_rounded, label: S.btnRegistro, onTap: () => _run(() => _logSheet())),
                        ToolButton(icon: Icons.bookmarks_outlined, label: S.packProfili, onTap: c.busy ? null : () => _run(() => _profilesSheet())),
                      ],
                    ),
                  if (Platform.isAndroid) const SizedBox(height: 12),
                  if (Platform.isAndroid) AutoSyncCard(builder: c),
                  const SizedBox(height: 12),
                  Tile(
                    padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                    child: Row(
                      children: [
                        const IconChip(icon: Icons.cleaning_services_outlined),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                S.packCleanup,
                                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Palette.text),
                              ),
                              Text(S.packCleanupSub, style: TextStyle(fontSize: 12, color: Palette.text2)),
                            ],
                          ),
                        ),
                        TextButton(
                          key: const ValueKey('pb-cleanup'),
                          onPressed: () async {
                            if (!context.mounted) return;
                            Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (ctx) => Scaffold(
                                body: Backdrop(
                                  child: SafeArea(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.stretch,
                                      children: [
                                        Padding(
                                          padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                                          child: LargeHeader(S.packCleanup, onBack: () => Navigator.of(ctx).pop()),
                                        ),
                                        Expanded(child: PackScreen(onOpenBases: () {})),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          );
                          },
                          child: Text(S.apri),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
        // jump to the top / bottom, right side, above the navigation bar
        return Stack(children: [
          page,
          if (MediaQuery.viewInsetsOf(context).bottom == 0) JumpButtonsSlot(controller: _scroll, openBottom: GlassInsets.of(context) + 12, foldedBottom: MediaQuery.viewPaddingOf(context).bottom + 12),
        ]);
      },
    );
  }

  /// "Apri un pack": the one installed on this phone, or an APK/ZIP file.
  Future<void> _openPack(Rect anchor) async {
    final installed = Platform.isAndroid ? await PlatformService.devicePackSource() : null;
    if (!mounted) return;
    final v = await showGlassMenu<String>(
      context,
      anchor: anchor,
      title: S.pbApriPack,
      items: [
        if (installed != null) GlassMenuItem(value: 'installed', label: S.pbPackInstallato, subtitle: S.pbPackInstallatoSub, icon: Icons.phone_android_rounded),
        GlassMenuItem(value: 'file', label: S.pbPackDaFile, subtitle: S.pbPackDaFileSub, icon: Icons.folder_zip_outlined),
        GlassMenuItem(value: 'mappings', label: S.pack3ImportaAbbinamenti, subtitle: S.pack3ImportaSub, icon: Icons.compare_arrows_rounded),
      ],
    );
    if (v == 'mappings') {
      await _importMappings();
      return;
    }
    String? path;
    if (v == 'installed') {
      path = installed;
    } else if (v == 'file') {
      final r = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['apk', 'zip']);
      path = r?.files.single.path;
    }
    if (path == null) return;
    final n = await c.openExistingPack(path);
    if (mounted && n > 0) showMsg(context, S.pbPackAperto(n));
  }

  /// "Anteprima schermata home": the generated icons on a mock launcher.
  Future<void> _homePreview() async {
    await showAppSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => HomePreview(
        apps: [
          for (final r in c.rows)
            if (!r.excluded && c.generatedById(r.generatedId) != null) (c.nameOf(r), c.generatedById(r.generatedId)!.image(size: 56)),
        ],
      ),
    );
  }

  /// "Esporta anteprima": contact sheets of the icons. Shared on Android; on
  /// desktop one sheet is saved as a file, more are saved as a folder.
  Future<void> _contactSheet() async {
    final files = await c.contactSheetFiles();
    if (!mounted) return;
    if (files.isEmpty) {
      showMsg(context, S.pack2AnteprimaVuota);
      return;
    }
    if (Platform.isAndroid) {
      await ExportService.share(files, text: S.pack2AnteprimaTitolo);
      return;
    }
    final r = files.length == 1
        ? await ExportService.saveSingle(await File(files.first).readAsBytes(), 'IconFormatter-anteprima.png')
        : await ExportService.exportDir(p.dirname(files.first), name: 'IconFormatter-anteprima', zip: false);
    if (mounted && r != null) showMsg(context, r.message);
  }

  /// Before/after with a draggable divider, from the details dialog.
  Future<void> _compare(PbRow r, PbIcon g) => showAppDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(S.confrontoTitolo),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // the comparison needs a bounded height: the Stack fills it
          SizedBox(height: 240, child: BeforeAfter(before: r.original.image(size: 240), after: g.image(size: 240))),
          const SizedBox(height: 10),
          Text(S.confrontoSuggerimento, textAlign: TextAlign.center, style: TextStyle(fontSize: 12.5, color: Palette.text3)),
        ],
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: Text(S.chiudi))],
    ),
  );

  /// "Esporta": folder or ZIP, asked when the button is tapped.
  Future<void> _exportChoose() async {
    final choice = await showAppSheet<({bool zip, bool changed})>(
      context: context,
      builder: (ctx) => SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(contentPadding: const EdgeInsets.symmetric(horizontal: 22), leading: const Icon(Icons.drive_folder_upload_outlined), title: Text(S.esportaCartella), onTap: () => Navigator.pop(ctx, (zip: false, changed: false))),
            ListTile(contentPadding: const EdgeInsets.symmetric(horizontal: 22), leading: const Icon(Icons.folder_zip_outlined), title: Text(S.pbEsportaZip), onTap: () => Navigator.pop(ctx, (zip: true, changed: false))),
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 22),
              leading: const Icon(Icons.difference_outlined),
              title: Text(S.packEsportaModificate),
              subtitle: Text(c.hasExportBaseline ? S.packEsportaModificateSub : S.packEsportaPrimaSub, style: TextStyle(fontSize: 12, color: Palette.text3)),
              onTap: () => Navigator.pop(ctx, (zip: false, changed: true)),
            ),
          ],
        ),
      ),
    );
    if (choice != null) await _export(choice.zip, changed: choice.changed);
  }

  Future<void> _export(bool zip, {bool changed = false}) async {
    try {
      final r = await c.export(zip: zip, onlyChanged: changed);
      if (mounted) showMsg(context, r?.message ?? (changed ? S.packNessunaModificata : S.pbNienteDaEsportare));
    } catch (e) {
      if (mounted) showMsg(context, S.errore(e), error: true);
    }
  }

  /// "Controllo qualità": pixel checks, then the icons with problems.
  Future<void> _quality() async {
    final found = await c.scanQuality();
    if (!mounted) return;
    if (found.isEmpty) {
      showMsg(context, S.packQualitaOk);
      return;
    }
    final redo = [for (final f in found) if (c.hasSource(f.$1)) f.$1];
    await showAppSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(padding: const EdgeInsets.fromLTRB(22, 0, 22, 8), child: Text(S.packQualitaN(found.length), style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: Palette.text))),
            for (final (r, probs) in found)
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 22),
                leading: c.generatedById(r.generatedId)?.image(size: 44),
                title: Text(c.nameOf(r), maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Wrap(spacing: 6, runSpacing: 4, children: [for (final prob in probs) _probChip(prob)]),
                onTap: () {
                  Navigator.pop(ctx);
                  _details(r);
                },
              ),
            if (redo.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 10, 22, 0),
                child: FilledButton.icon(
                  icon: const Icon(Icons.refresh_rounded),
                  label: Text(S.packQualitaRielabora(redo.length)),
                  onPressed: c.busy
                      ? null
                      : () {
                          Navigator.pop(ctx);
                          _run(() => c.generateFromOriginals(only: redo));
                        },
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _probChip(PbProblem prob) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
    decoration: BoxDecoration(color: Palette.warn.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(10)),
    child: Text(_probLabel(prob), style: TextStyle(fontSize: 11.5, color: Palette.warn)),
  );

  String _probLabel(PbProblem prob) => switch (prob) {
    PbProblem.nearlyEmpty => S.packProbVuota,
    PbProblem.tooSmall => S.packProbPiccola,
    PbProblem.offCentre => S.packProbDecentrata,
    PbProblem.tooDark => S.packProbScura,
    PbProblem.lowContrast => S.pack2ProbContrasto,
  };

  /// Coverage of the installed apps; a tap shows only those still without an icon.
  Widget _coverageTile() => Tile(
    padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
    child: InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => setState(() {
        installedMissing = !installedMissing;
        filter = installedMissing ? PbState.missing : null;
      }),
      child: Row(
        children: [
          Icon(Icons.pie_chart_outline_rounded, size: 20, color: installedMissing ? Theme.of(context).colorScheme.primary : Palette.text2),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              S.pack2Copertura(c.coverDone, c.coverTotal, c.coverPercent),
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Palette.text),
            ),
          ),
          if (installedMissing) Icon(Icons.close_rounded, size: 18, color: Palette.text3),
        ],
      ),
    ),
  );

  static String _fmtDate(String iso) {
    final d = DateTime.tryParse(iso)?.toLocal();
    if (d == null) return '';
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(d.day)}/${two(d.month)}/${d.year} ${two(d.hour)}:${two(d.minute)}';
  }

  /// "Registro del pack": what happened, copied as release notes.
  Future<void> _logSheet() async {
    await showAppSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        final log = AppState.I.packLog;
        return SingleChildScrollView(
          padding: const EdgeInsets.only(bottom: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(padding: const EdgeInsets.fromLTRB(22, 0, 22, 8), child: Text(S.packRegistro, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: Palette.text))),
              if (log.isEmpty) Padding(padding: const EdgeInsets.fromLTRB(22, 8, 22, 16), child: Text(S.packRegistroVuoto, style: TextStyle(color: Palette.text2))),
              for (final e in log)
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 22),
                  title: Text('${e['text']}', style: TextStyle(fontSize: 14, color: Palette.text)),
                  subtitle: Text(_fmtDate('${e['date']}'), style: TextStyle(fontSize: 12, color: Palette.text3)),
                ),
              if (log.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(22, 10, 22, 0),
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.copy_rounded),
                    label: Text(S.packRegistroCopia),
                    onPressed: () async {
                      final text = [for (final e in log) '${_fmtDate('${e['date']}')}  ${e['text']}'].join('\n');
                      await Clipboard.setData(ClipboardData(text: text));
                      if (mounted) showMsg(context, S.packRegistroCopiato);
                    },
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  /// "Pack salvati": named sets of corrections, loaded or deleted here.
  Future<void> _profilesSheet() async {
    await showAppSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => ListenableBuilder(
        listenable: AppState.I,
        builder: (ctx, _) {
          final list = AppState.I.packProfiles;
          return SingleChildScrollView(
            padding: const EdgeInsets.only(bottom: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 22),
                  leading: const Icon(Icons.bookmark_add_outlined),
                  title: Text(S.packSalvaCome),
                  onTap: () {
                    Navigator.pop(ctx);
                    _saveProfile();
                  },
                ),
                if (list.isEmpty) Padding(padding: const EdgeInsets.fromLTRB(22, 8, 22, 16), child: Text(S.packProfiliVuoto, style: TextStyle(color: Palette.text2))),
                for (final pr in list)
                  ListTile(
                    contentPadding: const EdgeInsets.only(left: 22, right: 8),
                    leading: const Icon(Icons.bookmark_outline),
                    title: Text('${pr['name']}', maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text(S.packProfiloN(((pr['corrections'] as Map?) ?? {}).length, _fmtDate('${pr['date']}')), style: TextStyle(fontSize: 12, color: Palette.text3)),
                    onTap: () {
                      Navigator.pop(ctx);
                      _loadProfile(pr);
                    },
                    trailing: IconButton(tooltip: S.elimina, icon: const Icon(Icons.delete_outline), onPressed: c.busy ? null : () => _deleteProfile(pr)),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _saveProfile() async {
    final name = await askText(context, S.packSalvaCome);
    if (name == null || name.trim().isEmpty) return;
    c.saveProfile(name.trim());
    if (mounted) showMsg(context, S.packSalvato(name.trim()));
  }

  Future<void> _loadProfile(Map<String, dynamic> pr) async {
    final ok = await confirm(context, S.packCaricaConferma('${pr['name']}'), S.packCaricaCorpo, ok: S.packCarica);
    if (!ok || !mounted) return;
    await _run(() => c.loadProfile(pr));
  }

  Future<void> _deleteProfile(Map<String, dynamic> pr) async {
    final name = '${pr['name']}';
    final ok = await confirm(context, S.packEliminaConferma(name), S.packEliminaCorpo, ok: S.elimina);
    if (ok) c.deleteProfile(name);
  }

  Widget _card(PbRow r) {
    final g = c.generatedById(r.generatedId);
    final st = r.state;
    final col = _color(st);
    return Tile(
      key: ValueKey('pb-card-${r.original.id}'),
      padding: const EdgeInsets.all(6),
      child: Builder(
        builder: (cctx) => InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => _details(r),
          onLongPress: () => _menu(r, anchorOf(cctx)),
          onSecondaryTap: () => _menu(r, anchorOf(cctx)),
          // the new icon large on its own tile, the original small in the
          // corner; name and state centred under it (the reason is in the
          // details)
          child: Column(
            children: [
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: nothingStyle ? NothingColors.raised : Palette.fg.withValues(alpha: 0.04),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Stack(children: [
                    Center(
                      child:
                          g?.image(size: 64) ??
                          Icon(Icons.add_photo_alternate_outlined, color: Palette.text3, size: 30),
                    ),
                    Positioned(left: 6, top: 6, child: Opacity(opacity: 0.9, child: r.original.image(size: 26))),
                    if (r.custom) Positioned(right: 8, top: 8, child: Icon(Icons.edit_rounded, size: 14, color: Palette.text2)),
                    // the state as a small symbol, bottom right of the icon window
                    Positioned(right: 7, bottom: 7, child: Tooltip(message: r.original.isSystem ? '${_label(st)} · ${S.pbSistema}' : _label(st), child: Icon(_icon(st), size: 16, color: col))),
                  ]),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                c.nameOf(r),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: Palette.text),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Long press: glass context menu next to the app (tap outside or
  /// drag down to close).
  Future<void> _menu(PbRow r, Rect anchor) async {
    final g = c.generatedById(r.generatedId);
    final choice = await showGlassMenu<String>(
      context,
      anchor: anchor,
      title: r.original.title,
      items: [
        GlassMenuItem(value: 'edit', label: S.pbModificaIcona, icon: Icons.edit_outlined),
        GlassMenuItem(value: 'pick', label: S.pbScegliIcona, icon: Icons.grid_view_rounded),
        if (r.original.path != null || r.original.bytes != null) GlassMenuItem(value: 'redo', label: S.pbRielabora, icon: Icons.refresh_rounded, enabled: !c.busy),
        if (c.hasCustom(r)) GlassMenuItem(value: 'restore', label: S.pbRipristinaPrecedente, icon: Icons.restore_rounded),
        if (g != null) GlassMenuItem(value: 'verify', label: r.verified ? S.pbVerificata : S.pbSegnaVerificata, icon: r.verified ? Icons.verified : Icons.verified_outlined),
        GlassMenuItem(value: 'exclude', label: r.excluded ? S.pbIncludi : S.pbEscludi, icon: r.excluded ? Icons.add_circle_outline : Icons.block, destructive: !r.excluded),
      ],
    );
    if (!mounted || choice == null) return;
    switch (choice) {
      case 'edit':
        await _edit(r);
      case 'pick':
        await _pick(r);
      case 'redo':
        await _run(() => c.generateFromOriginals(only: [r]));
      case 'restore':
        await c.restoreEdit(r);
        if (mounted) showMsg(context, S.pbIconaRipristinata(r.original.title));
        await _refreshPack();
      case 'verify':
        c.setVerified(r, !r.verified);
      case 'exclude':
        c.setExcluded(r, !r.excluded);
    }
  }

  Future<void> _edit(PbRow r) async {
    final png = await Navigator.of(context).push<Uint8List>(
      MaterialPageRoute(
        builder: (_) => IconEditPage(controller: c, row: r),
      ),
    );
    if (png == null || !mounted) return;
    await c.applyEdit(r, png);
    if (mounted) showMsg(context, S.pbIconaAggiornata(r.original.title));
    await _refreshPack();
  }

  /// The pack on the phone follows hand edits (Shizuku + pack installed).
  Future<void> _refreshPack() async {
    try {
      final msg = await c.refreshDevicePack();
      if (mounted && msg != null) showMsg(context, msg);
    } catch (e) {
      if (mounted) showMsg(context, S.errore(e), error: true);
    }
  }

  Future<void> _details(PbRow r) async {
    // the calendar day shown in the Before/After pair (null: the row's icon)
    final dayPick = ValueNotifier<PbIcon?>(null);
    await showAppDialog<void>(
      context: context,
      builder: (ctx) => ListenableBuilder(
        listenable: Listenable.merge([c, dayPick]),
        builder: (ctx, _) {
          final g = c.generatedById(r.generatedId);
          final days = c.calendarDaysOf(r);
          final shown = dayPick.value ?? g;
          final hasSource = r.original.path != null || r.original.bytes != null;
          // secondary actions, two per row, all the same size
          final actions = <(IconData, String, VoidCallback?)>[
            (Icons.grid_view_rounded, S.btnScegliIcona, () => _pick(r)),
            if (hasSource) (Icons.refresh_rounded, S.btnRielabora,c.busy ? null : () => _run(() => c.generateFromOriginals(only: [r]))),
            (r.verified ? Icons.verified : Icons.verified_outlined, r.verified ? S.pbVerificata : S.btnSegnaVerificata, g == null ? null : () => c.setVerified(r, !r.verified)),
            (r.excluded ? Icons.add_circle_outline : Icons.block, r.excluded ? S.pbIncludi : S.btnEscludi, () => c.setExcluded(r, !r.excluded)),
            (Icons.layers_outlined, S.pack2UsaPerAltre, g == null ? null : () => _alias(r)),
            (Icons.drive_file_rename_outline, S.pack2Rinomina, () => _rename(r)),
            if (r.state == PbState.missing || r.state == PbState.doubtful) (Icons.auto_awesome_outlined, S.pack3Suggerisci, c.busy ? null : () => _suggest(r)),
          ];
          // Glass style: every button is a glass pill, no outline
          Widget action((IconData, String, VoidCallback?) a) => SizedBox(
            height: 52,
            child: glassPill(radius: 26, OutlinedButton(
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                shape: const StadiumBorder(),
                side: glassCards ? BorderSide.none : null,
              ),
              onPressed: a.$3,
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(a.$1, size: 18),
                const SizedBox(width: 6),
                Flexible(child: Text(a.$2, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: kToolButtonFontSize))),
              ]),
            )),
          );
          Widget preview(String label, Widget? img, double side) => Column(children: [
            Checkerboard(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: SizedBox(width: side, height: side, child: img == null ? null : FittedBox(child: img)),
              ),
            ),
            const SizedBox(height: 6),
            Text(label, style: TextStyle(fontSize: 12, color: Palette.text2)),
          ]);
          final body = Padding(
            padding: const EdgeInsets.fromLTRB(20, 22, 20, 12),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(c.nameOf(r), textAlign: TextAlign.center, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: Palette.text)),
                  if (r.original.package.isNotEmpty)
                    Text(r.original.package, textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: Palette.text3)),
                  const SizedBox(height: 16),
                  LayoutBuilder(
                    builder: (_, box) {
                      // before and after side by side, as large as the dialog allows
                      final side = ((box.maxWidth - 24) / 2).clamp(72.0, 150.0).floorToDouble();
                      // tap the pair to compare them with the divider
                      return InkWell(
                        borderRadius: BorderRadius.circular(18),
                        onTap: g == null ? null : () => _compare(r, g),
                        child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
                          preview(S.prima, r.original.image(size: 150), side),
                          Icon(Icons.compare_arrows_rounded, size: 18, color: Palette.text3),
                          preview(S.dopo, shown?.image(size: 150), side),
                        ]),
                      );
                    },
                  ),
                  const SizedBox(height: 4),
                  if (days.isNotEmpty) ...[_dayStrip(days, dayPick), const SizedBox(height: 14)],
                  if (g != null) ...[_variantStrip(r), const SizedBox(height: 14)],
                  // the state as a quiet status row (state icon, name, reason under it), no dot
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(color: Palette.fg.withValues(alpha: 0.05), borderRadius: BorderRadius.circular(14)),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(_icon(r.state), size: 20, color: _color(r.state)),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(_label(r.state), style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: Palette.text)),
                              const SizedBox(height: 2),
                              Text(r.changedOriginal ? S.pack2OriginaleCambiata : r.reason, style: TextStyle(fontSize: 12.5, color: Palette.text2)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(children: [
                    Expanded(
                      child: SizedBox(
                        height: 52,
                        child: FilledButton.icon(
                          // Glass style: the accent colour instead of a white slab
                          style: glassCards ? FilledButton.styleFrom(backgroundColor: Theme.of(ctx).colorScheme.primary.withValues(alpha: 0.85), foregroundColor: Colors.white) : null,
                          icon: const Icon(Icons.edit_outlined),
                          label: Text(S.pbModificaIcona),
                          onPressed: () {
                            Navigator.pop(ctx);
                            _edit(r);
                          },
                        ),
                      ),
                    ),
                    // only after a manual edit: back to the previous icon
                    if (c.hasCustom(r)) ...[
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 52,
                        height: 52,
                        child: IconButton.outlined(
                          tooltip: S.pbRipristinaPrecedente,
                          icon: const Icon(Icons.restore_rounded),
                          onPressed: () async {
                            await c.restoreEdit(r);
                            await _refreshPack();
                          },
                        ),
                      ),
                    ],
                  ]),
                  const SizedBox(height: 10),
                  for (var i = 0; i < actions.length; i += 2) ...[
                    if (i > 0) const SizedBox(height: 8),
                    Row(children: [
                      Expanded(child: action(actions[i])),
                      const SizedBox(width: 8),
                      Expanded(child: i + 1 < actions.length ? action(actions[i + 1]) : const SizedBox()),
                    ]),
                  ],
                  // an option of the processing, not an action
                  if (hasSource) ...[
                    const SizedBox(height: 8),
                    glassPill(radius: 26, Container(
                      height: 52,
                      padding: const EdgeInsets.only(left: 18, right: 8),
                      decoration: ShapeDecoration(shape: StadiumBorder(side: glassCards ? BorderSide.none : BorderSide(color: Palette.fg.withValues(alpha: 0.14)))),
                      child: Row(children: [
                        Expanded(child: Text(S.mantieniBiancoInterno, maxLines: 2, style: TextStyle(fontSize: 13.5, color: Palette.text))),
                        Switch(
                          key: const ValueKey('pb-keep-white'),
                          value: c.keepsInnerWhite(r),
                          onChanged: c.busy ? null : (v) => _run(() => c.setKeepInnerWhite(r, v)),
                        ),
                      ]),
                    )),
                  ],
                  const SizedBox(height: 2),
                  TextButton(onPressed: () => Navigator.pop(ctx), child: Text(S.chiudi)),
                ],
              ),
            ),
          );
          return Dialog(
            backgroundColor: glassCards ? Colors.transparent : null,
            insetPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              // glass rim and light, on a dark frosted body so the list
              // behind never shows through the text
              child: glassCards
                  ? LiquidGlass(
                      radius: 28,
                      live: true,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(28),
                        child: BackdropFilter(
                          filter: ui.ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                          child: ColoredBox(color: Colors.black.withValues(alpha: 0.35), child: body),
                        ),
                      ),
                    )
                  : body,
            ),
          );
        },
      ),
    ).whenComplete(dayPick.dispose);
  }


  /// "Conflitti": clashes between the entries of the pack, one tile per entry.
  /// Computed when the sheet opens, not at build time.
  Future<void> _conflicts() async {
    final input = c.conflictInput();
    final found = findConflicts(input.entries);
    if (!mounted) return;
    if (found.isEmpty) {
      showMsg(context, S.pack3ConflittiOk);
      return;
    }
    final tiles = <(PackConflict, int)>[for (final f in found) for (final i in f.entries) (f, i)];
    await showAppSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(padding: const EdgeInsets.fromLTRB(22, 0, 22, 8), child: Text(S.pack3ConflittiN(found.length), style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: Palette.text))),
            for (final (f, i) in tiles)
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 22),
                leading: Icon(
                  f.severity == ConflictSeverity.warning ? Icons.warning_amber_rounded : Icons.info_outline_rounded,
                  color: f.severity == ConflictSeverity.warning ? Palette.warn : Palette.text2,
                ),
                title: Text(c.nameOf(input.owners[i]), maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text(_conflictLabel(f.kind), style: TextStyle(fontSize: 12, color: Palette.text3)),
                onTap: () {
                  Navigator.pop(ctx);
                  _details(input.owners[i]);
                },
              ),
          ],
        ),
      ),
    );
  }

  String _conflictLabel(ConflictKind k) => switch (k) {
    ConflictKind.sharedDrawable => S.pack3ConflittoCondiviso,
    ConflictKind.duplicateComponent => S.pack3ConflittoComponente,
    ConflictKind.emptyDrawable => S.pack3ConflittoVuoto,
    ConflictKind.emptyPackage => S.pack3ConflittoPacchetto,
  };

  /// "Suggerisci": the three best icons that no other app uses.
  Future<void> _suggest(PbRow r) async {
    final used = {for (final o in c.rows) if (o != r && o.generatedId != null) o.generatedId!};
    final free = freeCandidates(
      icons: [for (final g in c.generated) CandidateIcon(id: g.id, label: g.title, package: g.package, file: g.file)],
      usedIds: used,
      ownId: r.generatedId,
    );
    final picks = suggestIcons(label: c.nameOf(r), package: r.original.package, candidates: free);
    if (picks.isEmpty) {
      showMsg(context, S.pack3NessunSuggerimento);
      return;
    }
    final byId = {for (final g in c.generated) g.id: g};
    final picked = await showAppDialog<PbIcon>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(S.pack3SuggerimentiTitolo),
        content: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            for (final s in picks)
              InkWell(
                onTap: () => Navigator.pop(ctx, byId[s.candidate.id]),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Checkerboard(cell: 5, child: byId[s.candidate.id]!.image(size: 72)),
                    SizedBox(
                      width: 96,
                      child: Text(byId[s.candidate.id]!.title, maxLines: 2, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: const TextStyle(fontSize: 11)),
                    ),
                  ],
                ),
              ),
          ],
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: Text(S.annulla))],
      ),
    );
    // same call as the manual pick
    if (picked != null) c.assign(r, picked);
  }

  /// "Importa abbinamenti da un pack": the icons of another pack matched to
  /// the apps without an icon. The matches are listed; "Applica" assigns them.
  Future<void> _importMappings() async {
    final r = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['apk', 'zip'], dialogTitle: S.zipOApk);
    final path = r?.files.single.path;
    if (path == null) return;
    final List<PbMatch> found;
    try {
      found = await c.matchFromPack(path);
    } catch (e) {
      if (mounted) showMsg(context, S.errore(e), error: true);
      return;
    }
    if (!mounted) return;
    if (found.isEmpty) {
      showMsg(context, S.pack3ImportaNessuno);
      return;
    }
    await showAppSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(padding: const EdgeInsets.fromLTRB(22, 0, 22, 8), child: Text(S.pack3AbbinamentiTitolo, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: Palette.text))),
            for (final m in found)
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 22),
                leading: m.icon.image(size: 44),
                title: Text(c.nameOf(m.row), maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text(_matchLabel(m.match), style: TextStyle(fontSize: 12, color: Palette.text3)),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 10, 22, 0),
              child: FilledButton.icon(
                icon: const Icon(Icons.done_all_rounded),
                label: Text(S.pack3Applica),
                onPressed: c.busy
                    ? null
                    : () {
                        Navigator.pop(ctx);
                        _run(() async {
                          final n = await c.applyMatches(found);
                          if (mounted) showMsg(context, S.pack3AbbinamentiApplicati(n));
                        });
                      },
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _matchLabel(MappingMatch m) => switch (m) {
    MappingMatch.component => S.pack3MatchComponente,
    MappingMatch.package => S.pack3MatchPacchetto,
    MappingMatch.label => S.pack3MatchEtichetta,
  };

  /// Picks one of the generated icons: assigned to the app, or, with
  /// [variant], kept as one of its extra icons.
  Future<void> _pick(PbRow r, {bool variant = false}) async {
    final picked = await showAppDialog<PbIcon>(
      context: context,
      builder: (ctx) {
        var q = '';
        return StatefulBuilder(
          builder: (ctx, setS) {
            final list = c.generated.where((g) {
              if (q.isEmpty) return true;
              final s = '${g.title} ${g.file} ${g.package}'.toLowerCase();
              return s.contains(q.toLowerCase());
            }).toList();
            // fits the screen: shorter on small phones and with the keyboard up
            final mq = MediaQuery.of(ctx);
            final avail = mq.size.height - mq.viewInsets.bottom - mq.padding.vertical - 220;
            return AlertDialog(
              title: Text(S.pbScegliIcona),
              insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
              content: SizedBox(
                width: 520,
                height: avail.clamp(180.0, 420.0),
                child: Column(
                  children: [
                    // no autofocus: the keyboard would cover half of the icons
                    TextField(decoration: pillSearchDecoration(ctx, S.pbCercaGenerate), onChanged: (v) => setS(() => q = v)),
                    const SizedBox(height: 8),
                    Expanded(
                      child: GridView.builder(
                        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 96, mainAxisExtent: 104, crossAxisSpacing: 4, mainAxisSpacing: 4),
                        itemCount: list.length,
                        itemBuilder: (_, i) => InkWell(
                          onTap: () => Navigator.pop(ctx, list[i]),
                          child: Column(
                            children: [
                              Checkerboard(cell: 5, child: list[i].image(size: 64)),
                              Text(list[i].title, maxLines: 2, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: const TextStyle(fontSize: 10)),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: Text(S.annulla))],
            );
          },
        );
      },
    );
    if (picked == null) return;
    if (!variant) {
      c.assign(r, picked);
    } else if (picked.path == null || !c.addVariant(r, picked.path!)) {
      if (mounted) showMsg(context, S.pack2VariantiMax);
    }
  }

  /// "Usa per altre app": the icon also goes to the apps picked here.
  Future<void> _alias(PbRow r) async {
    await showAppSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        var q = '';
        return StatefulBuilder(
          builder: (ctx, setS) {
            final others = [for (final o in c.rows) if (o != r && o.original.package.isNotEmpty && !o.excluded) o];
            final list = others.where((o) => q.isEmpty || c.nameOf(o).toLowerCase().contains(q) || o.original.package.toLowerCase().contains(q)).toList();
            final chosen = c.aliasesOf(r).toSet();
            return SingleChildScrollView(
              padding: const EdgeInsets.only(bottom: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(padding: const EdgeInsets.fromLTRB(22, 0, 22, 8), child: Text(S.pack2AliasTitolo, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: Palette.text))),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(22, 0, 22, 8),
                    child: TextField(decoration: pillSearchDecoration(ctx, S.pack2AliasCerca), onChanged: (v) => setS(() => q = v.toLowerCase())),
                  ),
                  if (list.isEmpty) Padding(padding: const EdgeInsets.fromLTRB(22, 8, 22, 16), child: Text(S.pack2AliasVuoto, style: TextStyle(color: Palette.text2))),
                  for (final o in list)
                    CheckboxListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 22),
                      secondary: o.original.image(size: 36),
                      title: Text(c.nameOf(o), maxLines: 1, overflow: TextOverflow.ellipsis),
                      value: chosen.contains(o.original.key),
                      onChanged: (v) {
                        final next = {...chosen};
                        if (v == true) {
                          next.add(o.original.key);
                        } else {
                          next.remove(o.original.key);
                        }
                        c.setAliases(r, next.toList());
                        setS(() {});
                      },
                    ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  /// "Rinomina nel pack": the name shown in the pack for this app.
  Future<void> _rename(PbRow r) async {
    final name = await askText(context, S.pack2RinominaTitolo, initial: c.nameOf(r));
    if (name == null) return;
    c.setLabel(r, name);
  }

  /// The days of a calendar app as one horizontal strip; a tap shows the day in
  /// the Before/After pair (the export keeps all the days as before).
  Widget _dayStrip(List<PbIcon> days, ValueNotifier<PbIcon?> pick) {
    return Column(
      children: [
        Text(S.pack2Varianti, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, letterSpacing: 0.2, color: Palette.text2)),
        const SizedBox(height: 8),
        SizedBox(
          height: 66,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: days.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (_, i) {
              final d = days[i];
              final on = identical(pick.value, d);
              return InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => pick.value = d,
                child: Container(
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: on ? Theme.of(context).colorScheme.primary : Colors.transparent, width: 2),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(width: 40, height: 40, child: IconImage(path: d.path)),
                      Text('${d.calendarDay}', style: TextStyle(fontSize: 11, color: Palette.text2)),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  /// Variant thumbnails: the generated icon first, then up to two extra icons.
  /// A tap switches the icon used; a long press on an extra one removes it.
  Widget _variantStrip(PbRow r) {
    final base = c.generatedById(r.baseGeneratedId);
    final chosen = c.chosenVariant(r);
    final extras = c.variantPaths(r);
    Widget thumb(Widget img, bool on, VoidCallback onTap, {VoidCallback? onLong}) => InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      onLongPress: onLong,
      child: Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: on ? Theme.of(context).colorScheme.primary : Colors.transparent, width: 2),
        ),
        child: img,
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(S.pack2Varianti, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, letterSpacing: 0.2, color: Palette.text2)),
        const SizedBox(height: 8),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 8,
          runSpacing: 8,
          children: [
            if (base != null) thumb(base.image(size: 44), chosen == null, () => c.chooseVariant(r, null)),
            for (final e in extras)
              Tooltip(
                message: S.pack2VarianteTogli,
                child: thumb(
                  SizedBox(width: 44, height: 44, child: IconImage(path: e)),
                  chosen == e,
                  () => c.chooseVariant(r, e),
                  onLong: () => c.removeVariant(r, e),
                ),
              ),
            if (extras.length < 2)
              Tooltip(
                message: S.pack2VarianteAggiungi,
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: c.busy ? null : () => _pick(r, variant: true),
                  child: SizedBox(
                    width: 50,
                    height: 50,
                    child: Icon(Icons.add_rounded, color: Palette.text2),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

/// "Modifica icona": pick an image, process it with the pack pipeline,
/// compare Before/After, then confirm (returns the PNG) or cancel (null).
class IconEditPage extends StatefulWidget {
  const IconEditPage({super.key, required this.controller, required this.row});
  final PackBuilderController controller;
  final PbRow row;

  @override
  State<IconEditPage> createState() => _IconEditPageState();
}

class _IconEditPageState extends State<IconEditPage> {
  /// The pack's generation settings (same panel as Studio › Personalizza).
  late final WorkspaceController _style = WorkspaceController(tag: 'edit', mode: AppState.I.packMode, packSettings: true);

  @override
  void dispose() {
    _style.dispose();
    super.dispose();
  }

  Future<void> _openStyle() async {
    await showAppSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => SizedBox(
        height: MediaQuery.of(ctx).size.height * 0.80,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(padding: EdgeInsets.fromLTRB(20, 0, 20, 4), child: Text(S.stileTitolo, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: Palette.text))),
          Padding(padding: EdgeInsets.fromLTRB(20, 0, 20, 8), child: Text(S.stileSpiegazioneModifica, style: TextStyle(fontSize: 13, color: Palette.text2))),
          Expanded(child: AdjustPanel(c: _style)),
        ]),
      ),
    );
    // the new settings apply to the icon right away
    await _render();
  }

  String? source;
  EditTreatment treatment = EditTreatment.auto;
  Uint8List? result;
  bool working = false;
  String? error;
  int _seq = 0;

  Future<void> _pickImage() async {
    final r = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['png', 'jpg', 'jpeg', 'webp']);
    final path = r?.files.single.path;
    if (path == null) return;
    // the picked file may be a temporary copy: keep our own one
    final dest = p.join(await AppPaths.I.workDir('edit'), 'source${p.extension(path).toLowerCase()}');
    await File(path).copy(dest);
    setState(() => source = dest);
    await _render();
  }

  Future<void> _render() async {
    if (source == null) return;
    final seq = ++_seq;
    setState(() {
      working = true;
      error = null;
    });
    try {
      final png = await widget.controller.renderEdit(source!, treatment);
      if (!mounted || seq != _seq) return;
      setState(() => result = png);
    } catch (e) {
      if (mounted && seq == _seq) setState(() => error = S.errore(e));
    } finally {
      if (mounted && seq == _seq) setState(() => working = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final row = widget.row;
    final current = widget.controller.generatedById(row.generatedId);
    final before = current ?? row.original;
    return Scaffold(
      body: Backdrop(
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            children: [
              LargeHeader(S.pbModificaIcona, subtitle: '${row.original.title}${row.original.package.isEmpty ? '' : ' · ${row.original.package}'}', onBack: () => Navigator.pop(context)),
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 360),
                  child: AspectRatio(
                    aspectRatio: 1,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(24),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          BeforeAfter(
                            key: const ValueKey('edit-before-after'),
                            before: Padding(
                              padding: const EdgeInsets.all(28),
                              child: IconImage(bytes: before.bytes, path: before.path),
                            ),
                            after: Padding(
                              padding: const EdgeInsets.all(28),
                              child: result == null
                                  ? Center(
                                      child: Text(
                                        S.pbScegliImmagineHint,
                                        textAlign: TextAlign.center,
                                        style: TextStyle(color: Palette.text3),
                                      ),
                                    )
                                  : IconImage(bytes: result),
                            ),
                          ),
                          if (working) const Center(child: CircularProgressIndicator()),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              if (error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(error!, style: TextStyle(color: Palette.danger, fontSize: 12)),
                ),
              const SizedBox(height: 14),
              StepCard(
                step: 1,
                title: S.pbImmagine,
                subtitle: source == null ? S.pbFormatiImmagine : p.basename(source!),
                done: source != null,
                children: [
                  ToolButton(key: const ValueKey('edit-pick'), icon: Icons.image_outlined, label: source == null ? S.pbScegliImmagine : S.pbCambiaImmagine, onTap: working ? null : _pickImage),
                ],
              ),
              StepCard(
                step: 2,
                title: S.pbTrattamento,
                subtitle: S.pbTrattamentoSub,
                done: result != null,
                children: [
                  // one full-width column: the style button, then the options under it
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      ButtonRows(children: [ToolButton(key: const ValueKey('edit-style'), icon: Icons.tune, label: S.stile, onTap: working ? null : _openStyle)]),
                      const SizedBox(height: 10),
                      ChoiceRows<EditTreatment>(
                        options: [
                          (EditTreatment.auto, S.modoAuto),
                          (EditTreatment.plateColor, S.modoColorePiatto),
                          (EditTreatment.fullBleed, S.modoBordoPieno),
                          (EditTreatment.asIs, S.modoNormale),
                          (EditTreatment.placeOnly, S.pbSoloPosizione),
                          (EditTreatment.raw, S.pbUsaComeE),
                        ],
                        value: treatment,
                        onChanged: (v) {
                          setState(() => treatment = v);
                          _render();
                        },
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(key: const ValueKey('edit-cancel'), onPressed: () => Navigator.pop(context), child: Text(S.annulla)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      key: const ValueKey('edit-confirm'),
                      icon: const Icon(Icons.check_rounded),
                      label: Text(S.pbConfermaSostituzione),
                      onPressed: result == null || working ? null : () => Navigator.pop(context, result),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Android: automatic change detection and launcher refresh helpers.
class AutoSyncCard extends StatefulWidget {
  const AutoSyncCard({super.key, required this.builder});
  final PackBuilderController builder;

  @override
  State<AutoSyncCard> createState() => _AutoSyncCardState();
}

class _AutoSyncCardState extends State<AutoSyncCard> {
  Map<String, dynamic> st = {};
  bool busy = false;

  @override
  void initState() {
    super.initState();
    _load(PlatformService.autoSyncStatus);
  }

  Future<void> _load(Future<Map<String, dynamic>> Function() f) async {
    setState(() => busy = true);
    try {
      final r = await f();
      if (mounted) setState(() => st = r);
    } catch (e) {
      if (mounted) showMsg(context, S.errore(e), error: true);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  /// Apps the automatic check leaves out; saved on the native side.
  Future<void> _editIgnored() async {
    setState(() => busy = true);
    try {
      final apps = await PlatformService.listApps();
      if (!mounted) return;
      final picked = await showIgnoredAppsSheet(context, current: ((st['ignored'] as List?) ?? const []).cast<String>(), apps: apps);
      if (picked == null || !mounted) return;
      await PlatformService.autoSyncIgnoredSet(picked);
      await _load(PlatformService.autoSyncStatus);
    } catch (e) {
      if (mounted) showMsg(context, S.errore(e), error: true);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  /// "Aggiorna giorno": today's day into the installed pack now.
  Future<void> _refreshCalendar() async {
    setState(() => busy = true);
    try {
      final r = await PlatformService.calendarRefreshNow();
      if (!mounted) return;
      final msg = switch (r['state']) {
        'updated' => S.calAggiornato(r['changed'] ?? 0),
        'current' => S.calGiaOggi,
        'no_shizuku' => S.calServeShizuku,
        'error' => S.errore(r['message'] ?? ''),
        _ => S.calNessuno,
      };
      showMsg(context, msg, error: r['state'] == 'error' || r['state'] == 'no_shizuku');
      await _load(PlatformService.autoSyncStatus);
    } catch (e) {
      if (mounted) showMsg(context, S.errore(e), error: true);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pending = ((st['pending'] as List?) ?? []).cast<Map>();
    final last = (st['lastCheck'] as num?)?.toInt() ?? 0;
    final hasCal = (st['calendar'] as Map?)?['has'] == true;
    final ignored = ((st['ignored'] as List?) ?? const []).cast<String>();
    return Tile(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SwitchListTile(
            key: const ValueKey('autosync-switch'),
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: Text(S.asTitolo, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            subtitle: Text(last == 0 ? S.asMai : S.asUltimo(DateTime.fromMillisecondsSinceEpoch(last).toLocal().toString().substring(0, 16)), style: const TextStyle(fontSize: 11)),
            value: st['enabled'] == true,
            onChanged: busy ? null : (v) => _load(() => PlatformService.autoSyncSetEnabled(v)),
          ),
          // the pack has calendar apps: today's day, every morning (same layout as the row above)
          if (hasCal)
            SwitchListTile(
              key: const ValueKey('calendar-daily-switch'),
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: Text(S.calGiornaliero, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              subtitle: Text(S.calGiornalieroInfo, style: const TextStyle(fontSize: 11)),
              value: st['calendarDaily'] != false,
              onChanged: busy ? null : (v) => _load(() => PlatformService.calendarDailySet(v)),
            ),
          if (hasCal) RefreshTimeRow(status: st, busy: busy, load: _load),
          ListTile(
            key: const ValueKey('autosync-interval'),
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: Text(S.asOgni, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            trailing: DropdownButton<int>(
              value: ((st['intervalHours'] as num?)?.toInt() ?? 6),
              underline: const SizedBox.shrink(),
              items: [for (final h in const [6, 12, 24]) DropdownMenuItem(value: h, child: Text(S.asOre(h)))],
              onChanged: busy ? null : (h) => _load(() => PlatformService.autoSyncScheduleSet(h ?? 6, st['onlyCharging'] == true)),
            ),
          ),
          SwitchListTile(
            key: const ValueKey('autosync-charging'),
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: Text(S.asSoloInCarica, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            value: st['onlyCharging'] == true,
            onChanged: busy ? null : (v) => _load(() => PlatformService.autoSyncScheduleSet(((st['intervalHours'] as num?)?.toInt() ?? 6), v)),
          ),
          const SizedBox(height: 8),
          // the same buttons as the cards above: two to a row, equal
          ButtonRows(
            children: [
              if (hasCal) ToolButton(key: const ValueKey('calendar-refresh-now'), icon: Icons.today_rounded, label: S.calAggiornaOra, onTap: busy ? null : _refreshCalendar),
              ToolButton(key: const ValueKey('autosync-check'), icon: Icons.refresh_rounded, label: S.asControllaOra, onTap: busy ? null : () => _load(PlatformService.autoSyncCheckNow)),
              ToolButton(
                key: const ValueKey('autosync-ignored'),
                icon: Icons.visibility_off_outlined,
                label: ignored.isEmpty ? S.wireAppIgnorate : S.wireAppIgnorateN(ignored.length),
                onTap: busy ? null : _editIgnored,
              ),
              if (pending.isNotEmpty && pending.every((m) => m['change'] == 'disinstallata'))
                ToolButton(
                  icon: Icons.done_all_rounded,
                  label: S.asSegnaViste,
                  onTap: busy
                      ? null
                      : () async {
                          await PlatformService.autoSyncClear();
                          await _load(PlatformService.autoSyncStatus);
                        },
                ),
              if (pending.any((m) => m['change'] != 'disinstallata'))
                ToolButton(
                  icon: Icons.auto_fix_high_outlined,
                  label: S.asRielabora(pending.where((m) => m['change'] != 'disinstallata').length),
                  onTap: busy || widget.builder.busy
                      ? null
                      : () async {
                          final comps = pending.where((m) => m['change'] != 'disinstallata').map((m) => m['component'] as String).toSet();
                          await widget.builder.addInstalledComponents(comps);
                          // only the apps the change check named are rendered again
                          await widget.builder.generateFromOriginals(only: widget.builder.rowsOfComponents(comps));
                          await PlatformService.autoSyncClear(pending.map((m) => m['component'] as String).toList());
                          await _load(PlatformService.autoSyncStatus);
                          // with Shizuku the refreshed pack is re-applied right away
                          final info = await PlatformService.devicePackInfo();
                          if (info['shizuku'] == 'granted' && info['installed'] == true) {
                            final msg = await widget.builder.applyOnDevice();
                            if (context.mounted && msg != null) showMsg(context, msg);
                          }
                        },
                ),
            ],
          ),
          if (pending.isNotEmpty) ...[
            const SizedBox(height: 6),
            for (final m in pending.take(6)) Text('· ${m['label']} — ${m['change']}', style: TextStyle(fontSize: 12, color: Palette.text2)),
            if (pending.length > 6) Text(S.asAltre(pending.length - 6), style: TextStyle(fontSize: 11, color: Palette.text3)),
          ],
        ],
      ),
    );
  }
}

/// Android: install the pack and select it in the system launcher through
/// Shizuku (DevicePack.kt). Without Shizuku: system installer + manual pick.
class LauncherApplyCard extends StatefulWidget {
  const LauncherApplyCard({super.key, required this.builder});
  final PackBuilderController builder;

  @override
  State<LauncherApplyCard> createState() => _LauncherApplyCardState();
}

class _LauncherApplyCardState extends State<LauncherApplyCard> with WidgetsBindingObserver {
  Map<String, dynamic> info = {};
  bool busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // changes made in the Shizuku app (start, permission) show up on return
  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    try {
      final r = await PlatformService.devicePackInfo();
      if (!mounted) return;
      setState(() => info = r);
      // the pack was uninstalled since the last look: say so once
      if (r['removed'] == true) showMsg(context, r['selectorReset'] == true ? S.dpRimossoRipristinato : S.dpRimosso);
    } catch (_) {}
  }

  Future<void> _do(Future<String?> Function() f) async {
    setState(() => busy = true);
    try {
      final msg = await f();
      if (mounted && msg != null) showMsg(context, msg);
    } catch (e) {
      if (mounted) showMsg(context, S.errore(e), error: true);
    } finally {
      if (mounted) setState(() => busy = false);
      await _refresh();
    }
  }

  /// One fact per line: label on the left, value on the right.
  Widget _infoRow(String k, String v) => Row(
    children: [
      Text(k, style: TextStyle(fontSize: 13, color: Palette.text3)),
      const SizedBox(width: 12),
      Expanded(child: Text(v, textAlign: TextAlign.right, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, color: Palette.text2))),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final sh = info['shizuku'] as String? ?? 'missing';
    final launcher = info['launcher'];
    final (stateText, stateColor) = switch (sh) {
      'granted' => (S.dpShizukuOk, Palette.ok),
      'denied' => (S.dpShizukuNegato, Palette.warn),
      'stopped' => (S.dpShizukuFermo, Palette.warn),
      'old' => (S.dpShizukuVecchio, Palette.danger),
      _ => (S.dpShizukuMancante, Palette.text2),
    };
    final hasRows = widget.builder.rows.any((r) => !r.excluded && r.generatedId != null);
    final working = busy || widget.builder.busy;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Tile(
        key: const ValueKey('launcher-apply-card'),
        radius: AppState.I.appearance.radius + 6,
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // header like the other step cards: centred, number badge and title
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 32,
                  height: 32,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.16), shape: BoxShape.circle),
                  child: Text('3', style: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.w700)),
                ),
                const SizedBox(width: 12),
                Flexible(child: Text(S.dpTitolo, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Palette.text))),
              ],
            ),
            const SizedBox(height: 14),
            // the state as a quiet status row: an icon in the state's colour, no dot
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(color: Palette.fg.withValues(alpha: 0.05), borderRadius: BorderRadius.circular(14)),
              child: Row(
                children: [
                  Icon(stateColor == Palette.ok ? Icons.check_circle_outline_rounded : Icons.info_outline_rounded, size: 20, color: stateColor),
                  const SizedBox(width: 10),
                  Expanded(child: Text(stateText, key: const ValueKey('shizuku-state'), style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w500, color: Palette.text))),
                ],
              ),
            ),
            const SizedBox(height: 12),
            // what is installed, one fact per line: label left, value right
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Column(
                children: [
                  _infoRow(S.dpInfoPack, info['version'] != null ? S.dpInfoVersione(info['version']) : S.dpInfoNonInstallato),
                  const SizedBox(height: 8),
                  _infoRow(S.dpInfoLauncher, launcher ?? S.dpInfoNonTrovato),
                ],
              ),
            ),
            if (info['state'] == 'residual') ...[
              const SizedBox(height: 6),
              Text(
                S.dpResiduo(info['residualVersion']),
                key: const ValueKey('dp-residual'),
                style: TextStyle(fontSize: 12, color: Palette.warn),
              ),
            ],
            const SizedBox(height: 10),
            WideColumn(
              children: [
                if (sh == 'granted')
                  FilledButton.icon(
                    key: const ValueKey('dp-apply'),
                    icon: const Icon(Icons.auto_awesome_outlined, size: 18),
                    label: Text(S.dpApplica),
                    onPressed: working || !hasRows
                        ? null
                        : () => _do(() => widget.builder.applyOnDevice(confirmReplace: () => confirm(context, S.dpSostituireTitolo, S.dpSostituireTesto, ok: S.dpSostituisci))),
                  )
                else
                  FilledButton.tonalIcon(
                    key: const ValueKey('dp-install'),
                    icon: const Icon(Icons.download_rounded, size: 18),
                    label: Text(S.dpSoloInstalla),
                    onPressed: working || !hasRows
                        ? null
                        : () => _do(() => widget.builder.applyOnDevice(confirmReplace: () => confirm(context, S.dpSostituireTitolo, S.dpSostituireTesto, ok: S.dpSostituisci))),
                  ),
                if (sh == 'denied') OutlinedButton(onPressed: PlatformService.shizukuRequest, child: Text(S.dpConcedi)),
                if (sh == 'stopped' || sh == 'old') OutlinedButton(onPressed: PlatformService.openShizuku, child: Text(S.dpApriShizuku)),
                if (sh == 'granted' && info['state'] == 'residual')
                  OutlinedButton.icon(
                    key: const ValueKey('dp-cleanup'),
                    icon: const Icon(Icons.cleaning_services_outlined, size: 18),
                    label: Text(S.dpPulisciResidui),
                    onPressed: working ? null : () => _do(() async => await PlatformService.devicePackCleanup() ? S.dpResiduiPuliti : S.dpResiduiRimasti),
                  ),
                if (sh == 'granted' && info['installed'] == true)
                  OutlinedButton(onPressed: working ? null : () => _do(() async => S.dpRipristinato(await PlatformService.devicePackRestore())), child: Text(S.dpRipristina)),
                TextButton(
                  onPressed: () async {
                    if (!await PlatformService.openLauncherPicker()) await PlatformService.openHomeSettings();
                  },
                  child: Text(S.dpScegliManuale),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
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
