import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../app/models.dart' show copySegment;
import '../app/state.dart';
import '../app/storage.dart';
import '../app/theme.dart';
import '../l10n/strings.dart';
import '../services/apk_pack_service.dart';
import '../services/export_service.dart';
import '../services/import_service.dart';
import '../services/platform_service.dart';
import '../src/rust/api/engine.dart';
import '../widgets/common.dart';
import '../widgets/glass_menu.dart';
import '../widgets/liquid_glass.dart';
import 'pack_screen.dart';

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
        child: const Icon(Icons.image_not_supported_outlined, color: Palette.text3),
      );
    }
    return SizedBox(
      width: size,
      height: size,
      child: IconImage(bytes: bytes, path: path),
    );
  }

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

  PbState get state {
    if (excluded) return PbState.excluded;
    if (generatedId == null) return PbState.missing;
    if (verified || manual || custom) return PbState.verified;
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

/// Icon Pack Builder: originals ↔ generated association, corrections, export.
class PackBuilderController extends ChangeNotifier {
  PackBuilderController() {
    _restore();
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

  PbIcon? generatedById(String? id) => id == null ? null : _genById[id];

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

  String get _stateFile => p.join(AppPaths.I.root.path, 'pack_builder.json');
  String get _customDir => p.join(AppPaths.I.root.path, 'pack_custom');
  String get _catalogDir => p.join(AppPaths.I.root.path, 'catalog');

  bool _restored = false;

  void _restore() {
    try {
      final f = File(_stateFile);
      if (!f.existsSync()) return;
      final j = jsonDecode(f.readAsStringSync()) as Map;
      generated.addAll(((j['generated'] as List?) ?? []).cast<Map>().map(PbIcon.fromJson).whereType<PbIcon>());
      calendars.addAll(((j['calendars'] as List?) ?? []).cast<Map>().map(PbIcon.fromJson).whereType<PbIcon>());
      // file-based originals (Windows / imported packs); the Android
      // catalogue is read again from the system
      originals.addAll(((j['originals'] as List?) ?? []).cast<Map>().map(PbIcon.fromJson).whereType<PbIcon>());
      ((j['custom'] as Map?) ?? {}).forEach((k, v) {
        final m = (v as Map).cast<String, String?>();
        if (m['path'] != null && File(m['path']!).existsSync()) custom[k as String] = m;
      });
      _reindex();
    } catch (_) {
      // a damaged state file only loses the builder lists
    } finally {
      _restored = true;
    }
  }

  Timer? _saveTimer;

  void _persist() {
    if (!_restored) return;
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 400), () async {
      final j = {
        'generated': [
          for (final g in generated)
            if (g.path != null) g.toJson(),
        ],
        'originals': [
          for (final o in originals)
            if (!o.id.startsWith('app:') && o.path != null) o.toJson(),
        ],
        'custom': custom,
        'calendars': [
          for (final g in calendars)
            if (g.path != null) g.toJson(),
        ],
      };
      final f = File(_stateFile);
      final tmp = File('${f.path}.tmp');
      await tmp.writeAsString(jsonEncode(j));
      await tmp.rename(f.path);
    });
  }

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
    try {
      final (apps, visible) = await PlatformService.appCatalog(_catalogDir);
      catalogVisible = visible;
      originals.removeWhere((o) => o.id.startsWith('app:'));
      originals.insertAll(0, [for (final (a, icon) in apps) PbIcon(id: 'app:${a.key}', label: a.label, package: a.package, activity: a.activity, path: icon, isSystem: a.isSystem)]);
      catalogLoaded = true;
      _set(S.pbCatalogo(apps.length, visible), running: false);
      await match();
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
  Future<List<PbIcon>> _readSource(String input, String prefix) async {
    final work = await AppPaths.I.workDir('builder');
    final info = await openPack(input: input, workDir: work);
    final comp = <String, (String, String)>{};
    for (final it in info.appfilterItems) {
      final m = RegExp(r'ComponentInfo\{([^/}]+)/?([^}]*)\}').firstMatch(it.component);
      if (m != null) comp[it.drawable.toLowerCase()] = (m.group(1)!, m.group(2) ?? '');
    }
    var k = 0;
    return [
      for (final img in info.images)
        () {
          final stem = p.basenameWithoutExtension(img.rel).toLowerCase();
          final c = comp[stem];
          return PbIcon(id: '$prefix${k++}', file: p.basename(img.rel), package: c?.$1 ?? '', activity: c?.$2 ?? '', path: img.abs);
        }(),
    ];
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
      final list = await _readSource(input, original ? 'o${stamp}_' : 'g${stamp}_');
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
      // only icons linked to an app (a phone pack also holds empty slots)
      final list = (await _readSource(path, 'pk${stamp}_')).where((g) => g.package.isNotEmpty).toList();
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
      _reindex();
      _set(S.pbPackAperto(list.length), running: false);
      await match();
      return list.length;
    } catch (e) {
      _set(S.errore(e), running: false);
      rethrow;
    }
  }

  Future<String?> Function() _pickKindImpl = () async => null;
  Future<String?> _pickKind() => _pickKindImpl();

  /// Renders the originals with the current Studio settings (pack mode).
  Future<void> generateFromOriginals({List<PbRow>? only}) async {
    final st = AppState.I;
    final targets = only?.map((r) => r.original).toList() ?? originals.where((o) => o.path != null || o.bytes != null).toList();
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
    var done = 0;
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
          generated.removeWhere((g) => g.id == gid);
          // same name/package as the original: the association is exact
          final g = PbIcon(id: gid, label: o.label, package: o.package, activity: o.activity, file: o.file.isNotEmpty ? o.file : p.basename(r.output!), path: r.output);
          generated.add(g);
          _genById[gid] = g;
          final row = rowById[o.id];
          if (row != null && !row.custom && (only != null || _studioFor(o) == null)) {
            row.generatedId = gid;
            row.auto = MatchState.confident;
            row.manual = false;
            row.reason = S.pbRielaborata;
            _save(row);
          }
        }
        _set(S.pbGenerazione(done, ev.total), prog: ev.total == 0 ? null : done / ev.total, throttle: done < ev.total);
      }
    } finally {
      _set(S.pbGenerateCaricate(generated.length), running: false);
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
          row.reason = m.generated == null ? S.pbNessunaIcona : m.reason;
        } else {
          row.reason = S.pbNessunaIcona;
        }
        // saved corrections win over the automatic association
        final c = corr[row.original.key];
        if (c != null) {
          row.excluded = c['excluded'] == true;
          row.verified = c['verified'] == true;
          final gk = c['generated'] as String?;
          if (gk != null && genByKey[gk] != null) {
            row.generatedId = genByKey[gk]!.id;
            row.manual = true;
            row.reason = S.pbCorrezioneSalvata;
          }
        }
        _applyCustom(row);
        _applyStudio(row);
      }
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
    AppState.I.update(() => AppState.I.packCorrections[row.original.key] = {
          'generated': row.manual ? g?.key : null,
          'excluded': row.excluded,
          'verified': row.verified,
          if (keepsInnerWhite(row)) 'keepWhite': true,
        });
  }

  void assign(PbRow row, PbIcon g) {
    row.generatedId = g.id;
    row.manual = true;
    row.reason = S.pbAssegnataManualmente;
    _save(row);
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
    _save(row);
    notifyListeners();
  }

  void setVerified(PbRow row, bool v) {
    row.verified = v;
    _save(row);
    notifyListeners();
  }

  // ------------------------------------------------------------ manual edit

  /// Settings of the pack mode with the per-icon treatment applied.
  ProcessSettings editSettings(EditTreatment t) {
    final st = AppState.I;
    final s = st.settingsFor(st.packMode, presetId: st.packPresetId, seg: st.packSegment);
    final strategy = switch (t) {
      EditTreatment.plateColor => LucentStrategy.plateColor,
      EditTreatment.fullBleed => LucentStrategy.fullBleed,
      EditTreatment.asIs || EditTreatment.placeOnly => LucentStrategy.asIs,
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
          nothingEncode: l.nothingEncode,
          strategy: strategy,
        ),
      );
    }
    return ProcessSettings(size: s.size, background: bg, placement: s.placement, segment: s.segment, ai: s.ai);
  }

  /// Renders a picked image for [row] (nothing is assigned yet). Returns PNG.
  Future<Uint8List> renderEdit(String source, EditTreatment t) async {
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
    custom[row.original.key] = {'path': path, 'prev': prev};
    final id = 'custom:${row.original.key}';
    generated.removeWhere((g) => g.id == id);
    _genById.remove(id);
    _applyCustom(row);
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
    row.generatedId = prev?.id;
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
    final apps = [
      for (final r in ok)
        IconPackApp(label: r.original.title, package: r.original.package, activity: r.original.activity, png: generatedById(r.generatedId)!.path ?? await _materialize(generatedById(r.generatedId)!)),
      ..._calendarApps,
    ];
    final res = await buildIconPack(apps: apps, outDir: dir, packName: name, zipPath: null);
    return res.outDir;
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
  /// Shizuku) selects it in Nothing Launcher. Returns the user message.
  Future<String?> applyOnDevice({String name = 'Icon Formatter Pack', Future<bool> Function()? confirmReplace}) async {
    _set(S.dpCompilazione, running: true);
    try {
      final dir = await _buildPackDir(name);
      if (dir == null) {
        _set(S.pbNienteDaEsportare, running: false);
        return null;
      }
      final accent = '#${(AppState.I.appearance.accent & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';
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
        return S.dpNoNothing;
      }
      _set(S.dpApplicazione, running: true);
      final r = await PlatformService.devicePackApply();
      final msg = r['verified'] == true ? S.dpFatto(n, v) : S.dpNonVerificato;
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
    _set(S.dpCompilazione, running: true);
    try {
      final dir = await _buildPackDir(name);
      if (dir == null) {
        _set(S.pbNienteDaEsportare, running: false);
        return;
      }
      final accent = '#${(AppState.I.appearance.accent & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';
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

  Future<ExportResult?> export({required bool zip}) async {
    final ok = rows.where((r) => !r.excluded && r.generatedId != null).toList();
    if (ok.isEmpty) return null;
    final dir = await AppPaths.I.workDir('iconpack');
    final apps = [
      for (final r in ok)
        IconPackApp(label: r.original.title, package: r.original.package, activity: r.original.activity, png: generatedById(r.generatedId)!.path ?? await _materialize(generatedById(r.generatedId)!)),
      ..._calendarApps,
    ];
    final res = await buildIconPack(apps: apps, outDir: dir, packName: 'Icon Formatter', zipPath: null);
    final saved = await ExportService.exportDir(res.outDir, name: 'IconFormatter-pack', zip: zip);
    _set(S.pbEsportate(res.icons));
    return saved;
  }

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
  String query = '';

  @override
  void initState() {
    super.initState();
    c._pickKindImpl = () => showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(leading: const Icon(Icons.folder_open_outlined), title: const Text(S.cartella), onTap: () => Navigator.pop(ctx, 'folder')),
            ListTile(leading: const Icon(Icons.folder_zip_outlined), title: const Text(S.zipOApk), onTap: () => Navigator.pop(ctx, 'zip')),
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
                                style: const TextStyle(fontSize: 12.5, color: Palette.text2),
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
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              sliver: SliverList.list(
                children: [
                  // the last summary ("N su M abbinate") is the subtitle once the
                  // work is done; while working the strip floats over card 1
                  LargeHeader(S.pbTitolo, subtitle: !c.busy && c.status != null ? c.status : S.pbSottotitoloBreve),
                  // status floats over the first card, right under the title
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      StepCard(
                        step: 1,
                        title: Platform.isAndroid ? S.pbPasso1Catalogo : S.pbPasso1,
                        subtitle: Platform.isAndroid
                            ? (c.catalogVisible == null ? S.pbCatalogoLettura : S.pbCatalogoInfo(c.originals.where((o) => o.id.startsWith('app:')).length, c.catalogVisible!))
                            : (c.originals.isEmpty ? S.pbPasso1Sub : S.pbOriginaliN(c.originals.length)),
                        done: c.originals.isNotEmpty,
                        children: [
                          if (Platform.isAndroid) ToolButton(icon: Icons.refresh_rounded, label: S.pbAggiornaCatalogo, onTap: c.busy ? null : () => _run(c.addInstalledApps)),
                          ToolButton(icon: Icons.inventory_2_outlined, label: Platform.isAndroid ? S.pbDaFile : S.pbOriginali, onTap: c.busy ? null : () => _run(() => c.addSource(original: true))),
                        ],
                      ),
                      if (status != null && c.busy) Positioned(left: 0, right: 0, top: 0, child: status),
                    ],
                  ),
                  StepCard(
                    step: 2,
                    title: S.pbPasso2,
                    subtitle: S.pbPasso2Sub,
                    done: c.rows.any((r) => r.generatedId != null),
                    children: [
                      ToolButton(icon: Icons.auto_fix_high_outlined, label: S.pbGeneraDaStudio, onTap: c.busy || c.originals.isEmpty ? null : () => _run(() => c.generateFromOriginals())),
                      ToolButton(icon: Icons.collections_outlined, label: S.pbImportaGenerate, onTap: c.busy ? null : () => _run(() => c.addSource(original: false))),
                      Builder(
                        builder: (bctx) => ToolButton(icon: Icons.inventory_outlined, label: S.pbApriPack, onTap: c.busy ? null : () => _run(() => _openPack(anchorOf(bctx)))),
                      ),
                      ToolButton(icon: Icons.join_inner_rounded, label: S.pbAbbina, onTap: c.busy || c.originals.isEmpty ? null : () => _run(c.match)),
                    ],
                  ),
                  if (c.rows.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    // one compact icon per state, in the state's colour; the
                    // name and count of the active filter are spelled out below
                    LayoutBuilder(
                      builder: (context, box) {
                        final states = <PbState?>[null, ...PbState.values.where((s) => counts[s]! > 0 || s == PbState.missing || filter == s)];
                        // compact pills, narrower only when they would not fit
                        final w = ((box.maxWidth - 6 * (states.length - 1)) / states.length).clamp(40.0, 64.0).floorToDouble();
                        return Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            for (final (k, s) in states.indexed) ...[
                              if (k > 0) const SizedBox(width: 6),
                              SizedBox(
                                width: w,
                                child: IconFilterPill(
                                  key: ValueKey('pb-filter-${s?.name ?? 'all'}'),
                                  icon: s == null ? Icons.apps_rounded : _icon(s),
                                  color: s == null ? Theme.of(context).colorScheme.primary : _color(s),
                                  tooltip: s == null ? S.pbTutte(c.rows.length) : '${_label(s)} ${counts[s]}',
                                  on: filter == s,
                                  onTap: () => setState(() => filter = filter == s || s == null ? null : s),
                                ),
                              ),
                            ],
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 6),
                    Text(
                      filter == null ? S.pbTutte(c.rows.length) : '${_label(filter!)} · ${counts[filter]}',
                      key: const ValueKey('pb-filter-label'),
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: filter == null ? Palette.text : _color(filter!)),
                    ),
                    const SizedBox(height: 10),
                    TextField(decoration: pillSearchDecoration(context, S.cercaNomeOPackage), onChanged: (v) => setState(() => query = v)),
                    const SizedBox(height: 8),
                    const Text(
                      S.pbTieniPremuto,
                      key: ValueKey('pb-hint'),
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 12.5, color: Palette.text2),
                    ),
                  ],
                  const SizedBox(height: 8),
                  if (c.rows.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 40),
                      child: Center(
                        child: Text(
                          c.originals.isEmpty ? S.pbVuoto : S.pbPremiAbbina,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Palette.text2),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            if (c.rows.isNotEmpty)
              SliverPadding(
                padding: pad,
                sliver: SliverGrid.builder(
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 220, mainAxisExtent: 150, crossAxisSpacing: 8, mainAxisSpacing: 8),
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
                        ToolButton(icon: Icons.drive_folder_upload_outlined, label: S.esportaCartella, onTap: c.busy ? null : () => _export(false)),
                        ToolButton(icon: Icons.folder_zip_outlined, label: S.pbEsportaZip, onTap: c.busy ? null : () => _export(true)),
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
                        const Expanded(
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
                          onPressed: () => Navigator.of(context).push(
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
                          ),
                          child: const Text(S.apri),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
        return page;
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
        if (installed != null) const GlassMenuItem(value: 'installed', label: S.pbPackInstallato, subtitle: S.pbPackInstallatoSub, icon: Icons.phone_android_rounded),
        const GlassMenuItem(value: 'file', label: S.pbPackDaFile, subtitle: S.pbPackDaFileSub, icon: Icons.folder_zip_outlined),
      ],
    );
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

  Future<void> _export(bool zip) async {
    try {
      final r = await c.export(zip: zip);
      if (mounted) showMsg(context, r?.message ?? S.pbNienteDaEsportare);
    } catch (e) {
      if (mounted) showMsg(context, S.errore(e), error: true);
    }
  }

  Widget _card(PbRow r) {
    final g = c.generatedById(r.generatedId);
    final st = r.state;
    final col = _color(st);
    return Tile(
      key: ValueKey('pb-card-${r.original.id}'),
      padding: const EdgeInsets.all(8),
      child: Builder(
        builder: (cctx) => InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => _details(r),
          onLongPress: () => _menu(r, anchorOf(cctx)),
          onSecondaryTap: () => _menu(r, anchorOf(cctx)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  r.original.image(size: 52),
                  const Icon(Icons.arrow_forward_rounded, size: 16, color: Palette.text3),
                  SizedBox(
                    child:
                        g?.image(size: 52) ??
                        Container(
                          width: 52,
                          height: 52,
                          decoration: BoxDecoration(
                            border: Border.all(color: Palette.danger.withValues(alpha: 0.5)),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(Icons.add_photo_alternate_outlined, color: Palette.danger, size: 22),
                        ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                r.original.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              ),
              Text(
                r.original.isSystem ? '${S.pbSistema} · ${r.reason}' : r.reason,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 10, color: Palette.text3),
              ),
              const Spacer(),
              Row(
                children: [
                  Icon(Icons.circle, size: 8, color: col),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      _label(st),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11, color: col),
                    ),
                  ),
                  if (r.custom) const Icon(Icons.edit_rounded, size: 12, color: Palette.text3),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Long press: iOS 26 style context menu next to the app (tap outside or
  /// drag down to close).
  Future<void> _menu(PbRow r, Rect anchor) async {
    final g = c.generatedById(r.generatedId);
    final choice = await showGlassMenu<String>(
      context,
      anchor: anchor,
      title: r.original.title,
      items: [
        const GlassMenuItem(value: 'edit', label: S.pbModificaIcona, icon: Icons.edit_outlined),
        const GlassMenuItem(value: 'pick', label: S.pbScegliIcona, icon: Icons.grid_view_rounded),
        if (r.original.path != null || r.original.bytes != null) GlassMenuItem(value: 'redo', label: S.pbRielabora, icon: Icons.refresh_rounded, enabled: !c.busy),
        if (c.hasCustom(r)) const GlassMenuItem(value: 'restore', label: S.pbRipristinaPrecedente, icon: Icons.restore_rounded),
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
    await showAppDialog<void>(
      context: context,
      builder: (ctx) => ListenableBuilder(
        listenable: c,
        builder: (ctx, _) {
          final g = c.generatedById(r.generatedId);
          return AlertDialog(
            title: Text(r.original.title),
            content: SizedBox(
              width: 520,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (r.original.package.isNotEmpty) Text(r.original.package, style: const TextStyle(fontSize: 12, color: Palette.text2)),
                    const SizedBox(height: 10),
                    LayoutBuilder(
                      builder: (_, box) {
                        // two previews side by side, never wider than the dialog
                        final side = ((box.maxWidth - 12) / 2).clamp(64.0, 140.0).floorToDouble();
                        Widget prev(String label, Widget? img) => Column(
                          children: [
                            Text(label, style: const TextStyle(fontSize: 11)),
                            const SizedBox(height: 4),
                            Checkerboard(
                              child: SizedBox(
                                width: side,
                                height: side,
                                child: img == null ? null : FittedBox(child: img),
                              ),
                            ),
                          ],
                        );
                        return Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [prev(S.prima, r.original.image(size: 140)), prev(S.dopo, g?.image(size: 140))]);
                      },
                    ),
                    const SizedBox(height: 8),
                    Text('${_label(r.state)} · ${r.reason}', style: TextStyle(fontSize: 12, color: _color(r.state))),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        FilledButton.tonalIcon(
                          icon: const Icon(Icons.edit_outlined),
                          label: const Text(S.pbModificaIcona),
                          onPressed: () {
                            Navigator.pop(ctx);
                            _edit(r);
                          },
                        ),
                        OutlinedButton.icon(icon: const Icon(Icons.grid_view_rounded), label: const Text(S.pbScegliIcona), onPressed: () => _pick(r)),
                        if (r.original.path != null || r.original.bytes != null)
                          OutlinedButton.icon(
                            icon: const Icon(Icons.refresh_rounded),
                            label: const Text(S.pbRielabora),
                            onPressed: c.busy ? null : () => _run(() => c.generateFromOriginals(only: [r])),
                          ),
                        if (r.original.path != null || r.original.bytes != null)
                      OutlinedButton.icon(
                        key: const ValueKey('pb-keep-white'),
                        icon: Icon(c.keepsInnerWhite(r) ? Icons.check_box_outlined : Icons.check_box_outline_blank_rounded),
                        label: const Text(S.mantieniBiancoInterno),
                        onPressed: c.busy ? null : () => _run(() => c.setKeepInnerWhite(r, !c.keepsInnerWhite(r))),
                      ),
                    if (c.hasCustom(r))
                          OutlinedButton.icon(
                            icon: const Icon(Icons.restore_rounded),
                            label: const Text(S.pbRipristinaPrecedente),
                            onPressed: () async {
                              await c.restoreEdit(r);
                              await _refreshPack();
                            },
                          ),
                        OutlinedButton.icon(
                          icon: Icon(r.verified ? Icons.verified : Icons.verified_outlined),
                          label: Text(r.verified ? S.pbVerificata : S.pbSegnaVerificata),
                          onPressed: g == null ? null : () => c.setVerified(r, !r.verified),
                        ),
                        OutlinedButton.icon(
                          icon: Icon(r.excluded ? Icons.add_circle_outline : Icons.block),
                          label: Text(r.excluded ? S.pbIncludi : S.pbEscludi),
                          onPressed: () => c.setExcluded(r, !r.excluded),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text(S.chiudi))],
          );
        },
      ),
    );
  }

  Future<void> _pick(PbRow r) async {
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
              title: const Text(S.pbScegliIcona),
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
              actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text(S.annulla))],
            );
          },
        );
      },
    );
    if (picked != null) c.assign(r, picked);
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
                                  ? const Center(
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
                  child: Text(error!, style: const TextStyle(color: Palette.danger, fontSize: 12)),
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
                  SizedBox(
                    width: double.infinity,
                    child: ChoiceRows<EditTreatment>(
                      options: const [
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
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(key: const ValueKey('edit-cancel'), onPressed: () => Navigator.pop(context), child: const Text(S.annulla)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      key: const ValueKey('edit-confirm'),
                      icon: const Icon(Icons.check_rounded),
                      label: const Text(S.pbConfermaSostituzione),
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

  @override
  Widget build(BuildContext context) {
    final pending = ((st['pending'] as List?) ?? []).cast<Map>();
    final last = (st['lastCheck'] as num?)?.toInt() ?? 0;
    return Tile(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SwitchListTile(
            key: const ValueKey('autosync-switch'),
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: const Text(S.asTitolo, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            subtitle: Text(last == 0 ? S.asMai : S.asUltimo(DateTime.fromMillisecondsSinceEpoch(last).toLocal().toString().substring(0, 16)), style: const TextStyle(fontSize: 11)),
            value: st['enabled'] == true,
            onChanged: busy ? null : (v) => _load(() => PlatformService.autoSyncSetEnabled(v)),
          ),
          const Text(S.asInfo, style: TextStyle(fontSize: 11, color: Palette.text3)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              OutlinedButton.icon(
                key: const ValueKey('autosync-check'),
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text(S.asControllaOra),
                onPressed: busy ? null : () => _load(PlatformService.autoSyncCheckNow),
              ),
              if (pending.isNotEmpty && pending.every((m) => m['change'] == 'disinstallata'))
                OutlinedButton.icon(
                  icon: const Icon(Icons.done_all_rounded, size: 18),
                  label: const Text(S.asSegnaViste),
                  onPressed: busy
                      ? null
                      : () async {
                          await PlatformService.autoSyncClear();
                          await _load(PlatformService.autoSyncStatus);
                        },
                ),
              if (pending.any((m) => m['change'] != 'disinstallata'))
                FilledButton.tonalIcon(
                  icon: const Icon(Icons.auto_fix_high_outlined, size: 18),
                  label: Text(S.asRielabora(pending.where((m) => m['change'] != 'disinstallata').length)),
                  onPressed: busy || widget.builder.busy
                      ? null
                      : () async {
                          final comps = pending.where((m) => m['change'] != 'disinstallata').map((m) => m['component'] as String).toSet();
                          await widget.builder.addInstalledComponents(comps);
                          await widget.builder.generateFromOriginals();
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
            for (final m in pending.take(6)) Text('· ${m['label']} — ${m['change']}', style: const TextStyle(fontSize: 12, color: Palette.text2)),
            if (pending.length > 6) Text(S.asAltre(pending.length - 6), style: const TextStyle(fontSize: 11, color: Palette.text3)),
          ],
        ],
      ),
    );
  }
}

/// Android: install the pack and select it in Nothing Launcher through
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
            Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.16), shape: BoxShape.circle),
                  child: Text(
                    '3',
                    style: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.w700),
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    S.dpTitolo,
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Palette.text),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Icon(Icons.circle, size: 9, color: stateColor),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    stateText,
                    key: const ValueKey('shizuku-state'),
                    style: const TextStyle(fontSize: 12.5, color: Palette.text),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              [
                if (info['version'] != null) S.dpVersioneInstallata(info['version']),
                launcher == null ? S.dpNoNothing : S.dpLauncher(launcher),
                if (sh == 'granted') S.dpSelettore(info['selector']),
              ].join(' · '),
              style: const TextStyle(fontSize: 11, color: Palette.text3),
            ),
            if (info['state'] == 'residual') ...[
              const SizedBox(height: 6),
              Text(
                S.dpResiduo(info['residualVersion']),
                key: const ValueKey('dp-residual'),
                style: const TextStyle(fontSize: 12, color: Palette.warn),
              ),
            ],
            const SizedBox(height: 4),
            const Text(S.dpInfo, style: TextStyle(fontSize: 11, color: Palette.text3)),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (sh == 'granted')
                  FilledButton.icon(
                    key: const ValueKey('dp-apply'),
                    icon: const Icon(Icons.auto_awesome_outlined, size: 18),
                    label: const Text(S.dpApplica),
                    onPressed: working || !hasRows
                        ? null
                        : () => _do(() => widget.builder.applyOnDevice(confirmReplace: () => confirm(context, S.dpSostituireTitolo, S.dpSostituireTesto, ok: S.dpSostituisci))),
                  )
                else
                  FilledButton.tonalIcon(
                    key: const ValueKey('dp-install'),
                    icon: const Icon(Icons.download_rounded, size: 18),
                    label: const Text(S.dpSoloInstalla),
                    onPressed: working || !hasRows
                        ? null
                        : () => _do(() => widget.builder.applyOnDevice(confirmReplace: () => confirm(context, S.dpSostituireTitolo, S.dpSostituireTesto, ok: S.dpSostituisci))),
                  ),
                if (sh == 'denied') OutlinedButton(onPressed: PlatformService.shizukuRequest, child: const Text(S.dpConcedi)),
                if (sh == 'stopped' || sh == 'old') OutlinedButton(onPressed: PlatformService.openShizuku, child: const Text(S.dpApriShizuku)),
                if (sh == 'granted' && info['state'] == 'residual')
                  OutlinedButton.icon(
                    key: const ValueKey('dp-cleanup'),
                    icon: const Icon(Icons.cleaning_services_outlined, size: 18),
                    label: const Text(S.dpPulisciResidui),
                    onPressed: working ? null : () => _do(() async => await PlatformService.devicePackCleanup() ? S.dpResiduiPuliti : S.dpResiduiRimasti),
                  ),
                if (sh == 'granted' && info['installed'] == true)
                  OutlinedButton(onPressed: working ? null : () => _do(() async => S.dpRipristinato(await PlatformService.devicePackRestore())), child: const Text(S.dpRipristina)),
                TextButton(
                  onPressed: () async {
                    if (!await PlatformService.openNothingPicker()) await PlatformService.openHomeSettings();
                  },
                  child: const Text(S.dpScegliManuale),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
