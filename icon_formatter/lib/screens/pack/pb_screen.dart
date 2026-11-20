import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';

import '../../app/state.dart';
import '../../app/theme.dart';
import '../../l10n/strings.dart';
import '../../services/export_service.dart';
import '../../services/pack3_logic.dart';
import '../../services/pack_conflicts.dart';
import '../../services/pack_mapping_import.dart';
import '../../services/pack_quality.dart';
import '../../services/pack_suggest.dart';
import '../../services/platform_service.dart';
import '../../widgets/app_search.dart';
import '../../widgets/common.dart';
import '../../widgets/glass_menu.dart';
import '../../widgets/home_preview.dart';
import '../../widgets/liquid_glass.dart';
import '../../widgets/pack_rows.dart';
import '../pack_screen.dart';
import 'pb_model.dart';
import 'pb_plate_sheet.dart';
import 'pb_controller.dart';
import 'pb_edit_page.dart';
import 'pb_cards.dart';

part 'pb_screen_sheets.dart';
part 'pb_screen_rows.dart';
part 'pb_screen_details.dart';

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
    c.pickKindImpl = () => showAppSheet<String>(
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

  /// Rebuilds through the State, for the extension parts (setState is protected).
  void rebuildScreen(VoidCallback fn) => setState(fn);

  Color _color(PbState s) => switch (s) {
    PbState.confident => Palette.ok,
    PbState.verified => Palette.selection,
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

  /// Adds the installed apps; says once how many icons were generated and
  /// opens the first one to check.
  Future<void> _addApps() async {
    await _run(c.addInstalledApps);
    final n = c.takeFreshNotice();
    if (n == 0 || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(S.ux1bGenBanner(n)),
      action: SnackBarAction(
        label: S.ux1bReviewStart,
        onPressed: () {
          final first = c.rows.where((r) => r.original.isFresh).firstOrNull;
          if (first != null) _details(first);
        },
      ),
    ));
  }

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
                              // announced as it changes, so the progress is heard without looking
                              child: Semantics(
                                liveRegion: true,
                                child: Text(
                                  c.status!,
                                  key: const ValueKey('pb-status'),
                                  style: TextStyle(fontSize: 12.5, color: Palette.text2),
                                ),
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
                          if (Platform.isAndroid) ToolButton(icon: Icons.refresh_rounded, label: S.pbAggiornaCatalogo, onTap: c.busy ? null : _addApps),
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
                                  color: s == null ? Palette.text2 : _color(s),
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
            // shown whenever there is a catalogue or a query, so a query with no match can be cleared
            if (c.originals.isNotEmpty || c.rows.isNotEmpty || query.isNotEmpty) ...[
              // the one shared search field (same pill as Studio and Your apps)
              SliverPinnedSearch(
                framed: false,
                padding: const EdgeInsets.fromLTRB(20, 6, 20, 6),
                child: AppSearchField(controller: _search, hint: S.cercaNomeOPackage, onChanged: (v) => setState(() => query = v), onClear: () => setState(() => query = '')),
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
                        // the plate alone, one visible step: no cut-out is redone
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            OutlinedButton.icon(
                              key: const ValueKey('pb-change-bg'),
                              onPressed: c.busy ? null : () => showPlateSheet(context, c),
                              icon: const Icon(Icons.format_paint_outlined),
                              label: Text(S.ux1bChangeBg),
                            ),
                            Padding(
                              padding: const EdgeInsets.only(top: 4, bottom: 6),
                              child: Text(S.ux2bChangeBgSub, style: TextStyle(fontSize: 11.5, color: Palette.text2)),
                            ),
                          ],
                        ),
                        ToolButton(icon: Icons.ios_share_rounded, label: S.pbEsporta, onTap: c.busy ? null : _exportChoose),
                        ToolButton(icon: Icons.phone_android_rounded, label: S.anteprimaHome, onTap: c.busy || !c.rows.any((r) => !r.excluded && c.generatedById(r.generatedId) != null) ? null : _homePreview),
                      ],
                    ),
                  // the less used tools sit behind one button: a tidy sheet
                  const SizedBox(height: 12),
                  ButtonRows(
                    children: [
                      Builder(
                        builder: (bctx) => ToolButton(key: const ValueKey('pb-altro'), icon: Icons.more_horiz_rounded, label: S.altro, onTap: () => _moreSheet(anchorOf(bctx))),
                      ),
                    ],
                  ),
                  if (Platform.isAndroid) const SizedBox(height: 20),
                  if (Platform.isAndroid) AutoSyncCard(builder: c),
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

  static String _fmtDate(String iso) {
    final d = DateTime.tryParse(iso)?.toLocal();
    if (d == null) return '';
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(d.day)}/${two(d.month)}/${d.year} ${two(d.hour)}:${two(d.minute)}';
  }

}
