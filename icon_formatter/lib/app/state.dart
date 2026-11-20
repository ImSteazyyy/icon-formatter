import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' show WidgetsBinding, WidgetsBindingObserver;
import 'package:path/path.dart' as p;

import '../l10n/strings.dart';
import '../services/app_lists.dart';
import '../services/bg_removal_service.dart';
import '../services/extra2_auto_backup.dart';
import '../services/packdb_db.dart';
import '../services/packdb_store.dart';
import '../services/preset_share.dart';
import '../services/update_check.dart';
import '../src/rust/api/engine.dart';
import 'models.dart';
import 'storage.dart';

part 'state/state_backup.dart';
part 'state/state_presets.dart';
part 'state/state_bases.dart';
part 'state/state_studio.dart';

enum StudioMode { original, translucent, preset }

/// Global persisted app state.
class AppState extends ChangeNotifier with WidgetsBindingObserver {
  AppState._();

  static final AppState I = AppState._();

  late TranslucentSettings defaultTranslucent;
  late PlacementSettings defaultPlacement;
  late SegmentSettings defaultSegment;

  final Appearance appearance = Appearance();
  final ExportSettings export = ExportSettings();
  final GlassConfig glass = GlassConfig();
  final LucentConfig lucent = LucentConfig();
  final LocalAiConfig localAi = LocalAiConfig();
  final LookConfig look = LookConfig();

  List<StylePreset> presets = [];
  String activePresetId = kDefaultPresetId;
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

  /// Keep the isolated glyphs, so that a change of plate, opacity or colour
  /// does not cut every icon out again.
  bool keepCutouts = true;

  /// Size limit of the saved cutouts in MB; the oldest are removed above it.
  int cutoutLimitMb = 500;

  /// Online fallback for a single icon (Pack, "Try the online icon"). Off by default: the user turns it on in Settings.
  bool onlineIconsEnabled = false;

  /// Background removal provider (local Rust is the default).
  BgProvider bgProvider = BgProvider.local;

  /// Studio: after "Process all" the results go to the Pack builder.
  bool autoSendToPack = false;

  /// First-launch setup done (Android).
  bool setupDone = false;

  // Pack cleanup
  late SegmentSettings packSegment;
  StudioMode packMode = StudioMode.translucent;
  String packPresetId = kDefaultPresetId;

  // Android: packages processed into the current pack
  Set<String> processedPackages = {};

  /// Icon Pack Builder: manual corrections by original key (package or file).
  Map<String, Map<String, dynamic>> packCorrections = {};

  /// Pack builder: newest first {date, text} lines, at most 30 (release notes).
  List<Map<String, dynamic>> packLog = [];

  /// Saved correction sets: {name, date, corrections}.
  List<Map<String, dynamic>> packProfiles = [];

  /// Saved selections of apps (Apps screen, "Liste").
  List<AppList> appLists = [];

  /// Pack builder: original key -> icon file at the last export (null = never).
  Map<String, String>? packExportSnapshot;

  /// Pack builder: original key -> fingerprint of the system icon at the last generation.
  Map<String, String> packFingerprints = {};

  /// Section guides closed with "Ho capito" (ids), and the first-run tour.
  Set<String> seenGuides = {};
  bool tourDone = false;

  /// Backup reminder: changes since the last backup, last backup and snooze (ms since epoch).
  int backupChanges = 0;
  int lastBackupMs = 0;
  int snoozeUntilMs = 0;
  int _lastChangeMs = 0;

  /// App version whose "What is new" was last shown or recorded ('' = none yet).
  String lastSeenBuild = '';

  /// Automatic backup folder (null = off). Not part of the backup file.
  String? autoBackupDir;
  bool _autoBackupRunning = false;
  int _autoBackupRetryAt = 0;

  /// True while the last automatic backup failed; the Shell shows one message on change.
  final ValueNotifier<bool> autoBackupFailed = ValueNotifier(false);

  /// Looks for a newer release once per start (Settings > System).
  bool checkUpdates = true;
  /// Frame monitor overlay (Settings > System). Not part of the backup file.
  bool showFps = false;
  /// Set by the frame monitor while the app keeps missing the frame budget.
  final ValueNotifier<bool> fpsStruggling = ValueNotifier(false);

  /// Folder whose new images are imported while the Studio is shown (null = off).
  /// Not part of the backup file.
  String? watchDir;

  /// Newer release found at start; not saved, the card hides when dismissed.
  final ValueNotifier<UpdateInfo?> newRelease = ValueNotifier(null);

  bool _loaded = false;

  Future<void> load() async {
    WidgetsBinding.instance.addObserver(this);
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
    // Pack builder maps: from pack.db when it is in use, else as read above
    final pk = await packStoreBoot(
      PackContent.maps(corrections: packCorrections, log: packLog, profiles: packProfiles, exportSnapshot: packExportSnapshot, fingerprints: packFingerprints),
      root: AppPaths.I.root.path,
      stateFile: AppPaths.I.stateFile,
      exists: (f) => File(f).existsSync(),
    );
    packCorrections = pk.corrections;
    packLog = pk.log;
    packProfiles = pk.profiles;
    packExportSnapshot = pk.exportSnapshot;
    packFingerprints = pk.fingerprints;
    PackStore.onFallback.add(update);
    if (PackStore.fallbackReason != null) {
      packLog.insert(0, {'date': DateTime.now().toIso8601String(), 'text': S.dbPackFallback(PackStore.fallbackReason!)});
    }
    await _ensureReferenceBase();
    _loaded = true;
    notifyListeners();
    // the cache check runs later, after the first frames
    Future<void>.delayed(const Duration(seconds: 4)).then((_) => pruneCutouts());
  }

  Future<void>? _pending;

  /// Phone light / dark switched: only the "Follow the phone" choice changes.
  @override
  void didChangePlatformBrightness() {
    if (appearance.themeChoice == ThemeChoice.system && appearance.syncLight()) notifyListeners();
  }

  /// Power saving: no animations; the user's value is put back when it goes off.
  void setPowerSaving(bool on) => update(() {
        final a = appearance;
        if (on == a.powerSaving) return;
        if (on) {
          a.savedAnimations = a.animations;
          a.animations = false;
        } else {
          if (!a.animations) a.animations = a.savedAnimations;
        }
        a.powerSaving = on;
      });

  /// Counts a change for the backup reminder; a burst (slider drag) counts once.
  void _countChange() {
    if (!_loaded) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastChangeMs > 1000) backupChanges++;
    _lastChangeMs = now;
  }

  /// Persists (debounced) and notifies listeners.
  void update([VoidCallback? fn]) {
    _countChange();
    fn?.call();
    notifyListeners();
    if (!_loaded) return;
    _pending ??= Future.delayed(const Duration(milliseconds: 400), () async {
      _pending = null;
      await save();
      _maybeAutoBackup();
    });
  }

  /// Restores a backup made by [backupJson]; throws FormatException if it is not one.
  Future<void> restoreBackup(String text) async {
    final j = jsonDecode(text);
    if (j is! Map<String, dynamic> || j['appearance'] is! Map) throw const FormatException('backup');
    final ai = localAi.toJson();
    _fromJson(j);
    localAi.load(ai);
    notifyListeners();
    await save();
  }

  Future<void> save() async {
    final f = File(AppPaths.I.stateFile);
    final tmp = File('${f.path}.tmp');
    // the pack maps go to pack.db (one row per change) when it is in use
    if (PackStore.I.ownsMaps) {
      await PackStore.I.writeMaps(PackContent.maps(corrections: packCorrections, log: packLog, profiles: packProfiles, exportSnapshot: packExportSnapshot, fingerprints: packFingerprints));
    }
    final j = toJson();
    if (PackStore.I.ownsMaps) {
      for (final k in const ['packCorrections', 'packLog', 'packProfiles', 'packExportSnapshot', 'packFingerprints']) {
        j.remove(k);
      }
    }
    await tmp.writeAsString(const JsonEncoder.withIndent(' ').convert(j));
    await tmp.rename(f.path);
  }

  Future<void> resetAll() async {
    final f = File(AppPaths.I.stateFile);
    if (await f.exists()) await f.delete();
    appearance.load(Appearance().toJson());
    export.load(ExportSettings().toJson());
    glass.reset();
    lucent.reset();
    look.load(LookConfig().toJson());
    localAi.load(LocalAiConfig().toJson());
    presets = builtInPresets(defaultTranslucent);
    activePresetId = kDefaultPresetId;
    segment = defaultSegment;
    packSegment = defaultSegment;
    scaleMul = 1;
    offsetX = 0;
    offsetY = 0;
    useBaseCalibrationForTranslucent = false;
    translucentSize = 512;
    threads = 0;
    keepCutouts = true;
    cutoutLimitMb = 500;
    bgProvider = BgProvider.local;
    autoSendToPack = false;
    packMode = StudioMode.translucent;
    packPresetId = kDefaultPresetId;
    processedPackages = {};
    update();
  }

  // ------------------------------------------------------------ presets

  // ------------------------------------------------------------ bases

  // ------------------------------------------------------------ settings builders

}
