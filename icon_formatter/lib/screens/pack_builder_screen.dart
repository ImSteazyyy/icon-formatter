import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

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
import '../widgets/liquid_glass.dart';
import 'pack_screen.dart';

/// One icon on either side of the association.
class PbIcon {
  PbIcon({required this.id, this.label = '', this.package = '', this.activity = '', this.file = '', this.path, this.bytes});

  final String id;
  final String label;
  final String package;
  final String activity;
  final String file;
  String? path;
  Uint8List? bytes;

  /// Stable key used to persist corrections between sessions.
  String get key => package.isNotEmpty ? 'pkg:$package' : 'file:${file.toLowerCase()}';

  String get title => label.isNotEmpty ? label : (file.isNotEmpty ? p.basenameWithoutExtension(file) : package);

  Widget image({double size = 56}) {
    if (bytes != null) return Image.memory(bytes!, width: size, height: size, fit: BoxFit.contain, gaplessPlayback: true);
    if (path != null) return Image.file(File(path!), width: size, height: size, fit: BoxFit.contain, gaplessPlayback: true);
    return SizedBox(width: size, height: size, child: const Icon(Icons.image_not_supported_outlined, color: Palette.text3));
  }

  MatchInput toInput() => MatchInput(id: id, label: label, package: package, file: file, path: path, png: path == null ? bytes : null);
}

enum PbState { confident, doubtful, missing, excluded, verified }

class PbRow {
  PbRow(this.original);
  final PbIcon original;
  String? generatedId;
  MatchState auto = MatchState.missing;
  String reason = '';
  bool excluded = false;
  bool verified = false;
  bool manual = false;

  PbState get state {
    if (excluded) return PbState.excluded;
    if (generatedId == null) return PbState.missing;
    if (verified || manual) return PbState.verified;
    return auto == MatchState.confident ? PbState.confident : PbState.doubtful;
  }
}

/// Icon Pack Builder: originals ↔ generated association, corrections, export.
class PackBuilderController extends ChangeNotifier {
  final List<PbIcon> originals = [];
  final List<PbIcon> generated = [];
  final List<PbRow> rows = [];
  bool busy = false;
  String? status;
  double? progress;

  PbIcon? generatedById(String? id) {
    for (final g in generated) {
      if (g.id == id) return g;
    }
    return null;
  }

  void _set(String? s, {double? prog, bool? running}) {
    status = s;
    progress = prog;
    if (running != null) busy = running;
    notifyListeners();
  }

  // ------------------------------------------------------------ sources

  Future<void> addInstalledApps() async {
    _set(S.pbLetturaApp, running: true);
    try {
      final apps = await PlatformService.listApps(includeSystem: false);
      final icons = await PlatformService.getIcons(apps, size: 432, glyphOnly: false);
      for (var i = 0; i < apps.length; i++) {
        final a = apps[i];
        if (icons[i] == null) continue;
        originals.add(PbIcon(id: 'o${originals.length}', label: a.label, package: a.package, activity: a.activity, bytes: icons[i]));
      }
    } finally {
      _set(S.pbOriginaliCaricati(originals.length), running: false);
    }
  }

  /// Installed apps limited to [components] ("package/activity"), e.g. the
  /// ones reported by the automatic change check.
  Future<void> addInstalledComponents(Set<String> components) async {
    _set(S.pbLetturaApp, running: true);
    try {
      final apps = (await PlatformService.listApps(includeSystem: true)).where((a) => components.contains(a.key)).toList();
      final icons = await PlatformService.getIcons(apps, size: 432, glyphOnly: false);
      for (var i = 0; i < apps.length; i++) {
        final a = apps[i];
        if (icons[i] == null || originals.any((o) => o.package == a.package && o.activity == a.activity)) continue;
        originals.add(PbIcon(id: 'o${originals.length}', label: a.label, package: a.package, activity: a.activity, bytes: icons[i]));
      }
    } finally {
      _set(S.pbOriginaliCaricati(originals.length), running: false);
    }
  }

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
      final list = await _readSource(input, original ? 'o${originals.length}_' : 'g${generated.length}_');
      (original ? originals : generated).addAll(list);
      _set(original ? S.pbOriginaliCaricati(originals.length) : S.pbGenerateCaricate(generated.length), running: false);
    } catch (e) {
      _set(S.errore(e), running: false);
    }
  }

  Future<String?> Function() _pickKindImpl = () async => null;
  Future<String?> _pickKind() => _pickKindImpl();

  /// Renders the originals with the current Studio settings (pack mode).
  Future<void> generateFromOriginals({List<PbRow>? only}) async {
    final st = AppState.I;
    final targets = only?.map((r) => r.original).toList() ?? originals;
    if (targets.isEmpty) return;
    final out = await AppPaths.I.outputSession('builder');
    final items = [
      for (final o in targets)
        BatchItem(id: o.id, name: o.title, path: o.path, bytes: o.path == null ? o.bytes : null, output: p.join(out, '${sanitizeDrawableName(name: o.package.isNotEmpty ? o.package : o.title)}_${o.id}.png'), skipIsolation: false),
    ];
    _set(S.pbGenerazione(0, items.length), prog: 0, running: true);
    var done = 0;
    try {
      await for (final ev in runBatch(items: items, settings: st.settingsFor(st.packMode, presetId: st.packPresetId, seg: st.packSegment), threads: st.threads, cancel: CancelToken())) {
        done = ev.done;
        final r = ev.result;
        final o = targets.firstWhere((t) => t.id == r.id);
        if (r.ok && r.output != null) {
          final gid = 'gen:${o.id}';
          generated.removeWhere((g) => g.id == gid);
          // same name/package as the original: the association is exact
          generated.add(PbIcon(id: gid, label: o.label, package: o.package, activity: o.activity, file: o.file.isNotEmpty ? o.file : p.basename(r.output!), path: r.output));
          final row = rows.where((x) => x.original.id == o.id).firstOrNull;
          if (row != null) {
            row.generatedId = gid;
            row.auto = MatchState.confident;
            row.manual = false;
            row.reason = S.pbRielaborata;
            _save(row);
          }
        }
        _set(S.pbGenerazione(done, ev.total), prog: ev.total == 0 ? null : done / ev.total);
      }
    } finally {
      _set(S.pbGenerateCaricate(generated.length), running: false);
    }
    if (only == null) await match();
  }

  // ------------------------------------------------------------ matching

  Future<void> match() async {
    if (originals.isEmpty) return;
    _set(S.pbAbbinamento, running: true);
    try {
      final res = await matchIcons(originals: [for (final o in originals) o.toInput()], generated: [for (final g in generated) g.toInput()]);
      final byId = {for (final r in res) r.original: r};
      rows
        ..clear()
        ..addAll(originals.map(PbRow.new));
      final corr = AppState.I.packCorrections;
      final genByKey = {for (final g in generated) g.key: g};
      for (final row in rows) {
        final m = byId[row.original.id];
        if (m != null) {
          row.generatedId = m.generated;
          row.auto = m.state;
          row.reason = m.reason;
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
      }
      final n = rows.where((r) => r.state == PbState.confident || r.state == PbState.verified).length;
      _set(S.pbRisultatoAbbinamento(n, rows.length), running: false);
    } catch (e) {
      _set(S.errore(e), running: false);
    }
  }

  void _save(PbRow row) {
    final g = generatedById(row.generatedId);
    AppState.I.update(() => AppState.I.packCorrections[row.original.key] = {
          'generated': row.manual ? g?.key : null,
          'excluded': row.excluded,
          'verified': row.verified,
        });
  }

  void assign(PbRow row, PbIcon g) {
    row.generatedId = g.id;
    row.manual = true;
    row.reason = S.pbAssegnataManualmente;
    _save(row);
    notifyListeners();
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

  Future<void> replaceWithFile(PbRow row) async {
    final r = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['png', 'webp', 'jpg', 'jpeg']);
    final path = r?.files.single.path;
    if (path == null) return;
    final g = PbIcon(id: 'file:${generated.length}', file: p.basename(path), path: path);
    generated.add(g);
    assign(row, g);
  }

  // ------------------------------------------------------------ export

  /// Builds the pack folder (drawables, appfilter.xml, mapping.json).
  Future<String?> _buildPackDir(String name) async {
    final ok = rows.where((r) => !r.excluded && r.generatedId != null).toList();
    if (ok.isEmpty) return null;
    final dir = await AppPaths.I.workDir('iconpack');
    final apps = [
      for (final r in ok)
        IconPackApp(
          label: r.original.title,
          package: r.original.package,
          activity: r.original.activity,
          png: generatedById(r.generatedId)!.path ?? await _materialize(generatedById(r.generatedId)!),
        ),
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

  Future<ExportResult?> export({required bool zip}) async {
    final ok = rows.where((r) => !r.excluded && r.generatedId != null).toList();
    if (ok.isEmpty) return null;
    final dir = await AppPaths.I.workDir('iconpack');
    final apps = [
      for (final r in ok)
        IconPackApp(
          label: r.original.title,
          package: r.original.package,
          activity: r.original.activity,
          png: generatedById(r.generatedId)!.path ?? await _materialize(generatedById(r.generatedId)!),
        ),
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
  final c = PackBuilderController();
  PbState? filter;
  String query = '';

  @override
  void initState() {
    super.initState();
    c._pickKindImpl = () => showModalBottomSheet<String>(
          context: context,
          builder: (ctx) => SafeArea(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              ListTile(leading: const Icon(Icons.folder_open_outlined), title: const Text(S.cartella), onTap: () => Navigator.pop(ctx, 'folder')),
              ListTile(leading: const Icon(Icons.folder_zip_outlined), title: const Text(S.zipOApk), onTap: () => Navigator.pop(ctx, 'zip')),
            ]),
          ),
        );
  }

  @override
  void dispose() {
    c.dispose();
    super.dispose();
  }

  Color _color(PbState s) => switch (s) {
        PbState.confident => Palette.ok,
        PbState.verified => Theme.of(context).colorScheme.primary,
        PbState.doubtful => Palette.warn,
        PbState.missing => Palette.danger,
        PbState.excluded => Palette.text3,
      };

  String _label(PbState s) => switch (s) {
        PbState.confident => S.pbSicura,
        PbState.verified => S.pbVerificata,
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
        final rows = c.rows.where((r) {
          if (filter != null && r.state != filter) return false;
          if (query.isEmpty) return true;
          final q = query.toLowerCase();
          return r.original.title.toLowerCase().contains(q) || r.original.package.toLowerCase().contains(q);
        }).toList();
        return Padding(
          padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + GlassInsets.of(context)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(S.pbTitolo, style: Theme.of(context).textTheme.titleLarge)),
                TextButton.icon(
                  icon: const Icon(Icons.cleaning_services_outlined, size: 18),
                  label: const Text(S.packCleanup),
                  onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => Scaffold(appBar: AppBar(title: const Text(S.packCleanup)), body: PackScreen(onOpenBases: () {})))),
                ),
            ]),
            const SizedBox(height: 4),
            Text(S.pbSottotitolo, style: const TextStyle(fontSize: 12, color: Palette.text2)),
            if (Platform.isAndroid) AutoSyncCard(builder: c),
            const SizedBox(height: 10),
            Wrap(children: [
              if (Platform.isAndroid) ToolButton(icon: Icons.apps_rounded, label: S.pbAppInstallate, onTap: c.busy ? null : () => _run(c.addInstalledApps)),
              ToolButton(icon: Icons.inventory_2_outlined, label: S.pbOriginali, onTap: c.busy ? null : () => _run(() => c.addSource(original: true))),
              ToolButton(icon: Icons.auto_fix_high_outlined, label: S.pbGeneraDaStudio, onTap: c.busy || c.originals.isEmpty ? null : () => _run(() => c.generateFromOriginals())),
              ToolButton(icon: Icons.collections_outlined, label: S.pbImportaGenerate, onTap: c.busy ? null : () => _run(() => c.addSource(original: false))),
              ToolButton(icon: Icons.join_inner_rounded, label: S.pbAbbina, onTap: c.busy || c.originals.isEmpty ? null : () => _run(c.match)),
            ]),
            if (c.status != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(children: [
                  if (c.busy) const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
                  if (c.busy) const SizedBox(width: 8),
                  Expanded(child: Text(c.status!, key: const ValueKey('pb-status'), style: const TextStyle(fontSize: 12, color: Palette.text2))),
                ]),
              ),
            if (c.progress != null && c.busy) LinearProgressIndicator(value: c.progress),
            if (c.rows.isNotEmpty) ...[
              const SizedBox(height: 6),
              Wrap(spacing: 6, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
                ChoiceChip(label: Text(S.pbTutte(c.rows.length)), selected: filter == null, onSelected: (_) => setState(() => filter = null)),
                for (final s in PbState.values)
                  ChoiceChip(
                    label: Text('${_label(s)} ${c.rows.where((r) => r.state == s).length}'),
                    selected: filter == s,
                    onSelected: (_) => setState(() => filter = filter == s ? null : s),
                  ),
                SizedBox(
                  width: 220,
                  child: TextField(
                    decoration: const InputDecoration(isDense: true, prefixIcon: Icon(Icons.search, size: 18), hintText: S.cercaNomeOPackage),
                    onChanged: (v) => setState(() => query = v),
                  ),
                ),
              ]),
            ],
            const SizedBox(height: 8),
            Expanded(
              child: c.rows.isEmpty
                  ? Center(child: Text(c.originals.isEmpty ? S.pbVuoto : S.pbPremiAbbina, textAlign: TextAlign.center, style: const TextStyle(color: Palette.text2)))
                  : GridView.builder(
                      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 220, mainAxisExtent: 150, crossAxisSpacing: 8, mainAxisSpacing: 8),
                      itemCount: rows.length,
                      itemBuilder: (context, i) => _card(rows[i]),
                    ),
            ),
            if (c.rows.isNotEmpty)
              Wrap(alignment: WrapAlignment.end, children: [
                ToolButton(icon: Icons.drive_folder_upload_outlined, label: S.esportaCartella, onTap: c.busy ? null : () => _export(false)),
                ToolButton(icon: Icons.folder_zip_outlined, label: S.pbEsportaZip, onTap: c.busy ? null : () => _export(true)),
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
                              if (mounted && r != null) showMsg(context, '${r.message} · ${r.location}');
                            } catch (e) {
                              if (mounted) showMsg(context, S.errore(e), error: true);
                            }
                          },
                  ),
              ]),
          ]),
        );
      },
    );
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
    final col = _color(r.state);
    return Glass(
      padding: const EdgeInsets.all(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _details(r),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
            Checkerboard(cell: 6, child: r.original.image(size: 52)),
            const Icon(Icons.arrow_forward_rounded, size: 16, color: Palette.text3),
            Checkerboard(cell: 6, child: g?.image(size: 52) ?? const SizedBox(width: 52, height: 52, child: Icon(Icons.help_outline, color: Palette.danger))),
          ]),
          const SizedBox(height: 6),
          Text(r.original.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
          Text(r.reason, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10, color: Palette.text3)),
          const Spacer(),
          Row(children: [
            Icon(Icons.circle, size: 8, color: col),
            const SizedBox(width: 4),
            Text(_label(r.state), style: TextStyle(fontSize: 11, color: col)),
          ]),
        ]),
      ),
    );
  }

  Future<void> _details(PbRow r) async {
    await showDialog<void>(
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
                child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                  if (r.original.package.isNotEmpty) Text(r.original.package, style: const TextStyle(fontSize: 12, color: Palette.text2)),
                  const SizedBox(height: 10),
                  Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
                    Column(children: [const Text(S.prima, style: TextStyle(fontSize: 11)), Checkerboard(child: r.original.image(size: 140))]),
                    Column(children: [const Text(S.dopo, style: TextStyle(fontSize: 11)), Checkerboard(child: g?.image(size: 140) ?? const SizedBox(width: 140, height: 140))]),
                  ]),
                  const SizedBox(height: 8),
                  Text('${_label(r.state)} · ${r.reason}', style: TextStyle(fontSize: 12, color: _color(r.state))),
                  const SizedBox(height: 12),
                  Wrap(spacing: 8, runSpacing: 8, children: [
                    FilledButton.tonalIcon(icon: const Icon(Icons.grid_view_rounded), label: const Text(S.pbScegliIcona), onPressed: () => _pick(r)),
                    OutlinedButton.icon(icon: const Icon(Icons.upload_file_outlined), label: const Text(S.pbSostituisci), onPressed: () => _run(() => c.replaceWithFile(r))),
                    OutlinedButton.icon(icon: const Icon(Icons.refresh_rounded), label: const Text(S.pbRielabora), onPressed: c.busy ? null : () => _run(() => c.generateFromOriginals(only: [r]))),
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
                  ]),
                ]),
              ),
            ),
            actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text(S.chiudi))],
          );
        },
      ),
    );
  }

  Future<void> _pick(PbRow r) async {
    final picked = await showDialog<PbIcon>(
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
            return AlertDialog(
              title: const Text(S.pbScegliIcona),
              content: SizedBox(
                width: 520,
                height: 420,
                child: Column(children: [
                  TextField(
                    autofocus: true,
                    decoration: const InputDecoration(isDense: true, prefixIcon: Icon(Icons.search, size: 18), hintText: S.pbCercaGenerate),
                    onChanged: (v) => setS(() => q = v),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: GridView.builder(
                      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 96, mainAxisExtent: 110),
                      itemCount: list.length,
                      itemBuilder: (_, i) => InkWell(
                        onTap: () => Navigator.pop(ctx, list[i]),
                        child: Column(children: [
                          Checkerboard(cell: 5, child: list[i].image(size: 64)),
                          Text(list[i].title, maxLines: 2, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: const TextStyle(fontSize: 10)),
                        ]),
                      ),
                    ),
                  ),
                ]),
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
    return Glass(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SwitchListTile(
          key: const ValueKey('autosync-switch'),
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: const Text(S.asTitolo, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          subtitle: Text(
            last == 0 ? S.asMai : S.asUltimo(DateTime.fromMillisecondsSinceEpoch(last).toLocal().toString().substring(0, 16)),
            style: const TextStyle(fontSize: 11),
          ),
          value: st['enabled'] == true,
          onChanged: busy ? null : (v) => _load(() => PlatformService.autoSyncSetEnabled(v)),
        ),
        const Text(S.asInfo, style: TextStyle(fontSize: 11, color: Palette.text3)),
        const SizedBox(height: 6),
        Wrap(spacing: 8, runSpacing: 6, children: [
          OutlinedButton.icon(
            key: const ValueKey('autosync-check'),
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: const Text(S.asControllaOra),
            onPressed: busy ? null : () => _load(PlatformService.autoSyncCheckNow),
          ),
          if (pending.isNotEmpty)
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
                    },
            ),
          TextButton.icon(
            icon: const Icon(Icons.home_outlined, size: 18),
            label: const Text(S.asApplicaLauncher),
            onPressed: () async {
              await showDialog<void>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text(S.asApplicaLauncher),
                  content: const Text(S.asLimiteLauncher),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(ctx), child: const Text(S.chiudi)),
                    FilledButton(
                      onPressed: () {
                        Navigator.pop(ctx);
                        PlatformService.openHomeSettings();
                      },
                      child: const Text(S.asApriImpostazioniLauncher),
                    ),
                  ],
                ),
              );
            },
          ),
        ]),
        if (pending.isNotEmpty) ...[
          const SizedBox(height: 6),
          for (final m in pending.take(6)) Text('· ${m['label']} — ${m['change']}', style: const TextStyle(fontSize: 12, color: Palette.text2)),
          if (pending.length > 6) Text(S.asAltre(pending.length - 6), style: const TextStyle(fontSize: 11, color: Palette.text3)),
        ],
      ]),
    );
  }
}
