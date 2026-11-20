import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app/models.dart';
import '../app/preset_names.dart';
import '../app/state.dart';
import '../app/storage.dart';
import '../app/theme.dart';
import '../services/bg_removal_service.dart';
import '../src/rust/api/engine.dart';
import '../widgets/ai_mask.dart';
import '../widgets/color_picker.dart';
import '../widgets/common.dart';
import '../widgets/fps_overlay.dart';
import '../widgets/liquid_glass.dart';
import '../widgets/theme_reveal.dart';
import '../widgets/tour2_visibility.dart';
import 'bases_screen.dart';
import 'settings_extras.dart';
import '../l10n/strings.dart';

const appVersion = '1.0.0';

enum SettingsCat { appearance, processing, bases, pack, export, system }

extension on SettingsCat {
  String get label => switch (this) {
        SettingsCat.appearance => S.appearance,
        SettingsCat.processing => S.processing,
        SettingsCat.bases => S.baseIcons,
        SettingsCat.pack => S.packCleanup,
        SettingsCat.export => S.export,
        SettingsCat.system => S.system,
      };

  IconData get icon => switch (this) {
        SettingsCat.appearance => Icons.palette_outlined,
        SettingsCat.processing => Icons.tune_rounded,
        SettingsCat.bases => Icons.crop_square_rounded,
        SettingsCat.pack => Icons.cleaning_services_outlined,
        SettingsCat.export => Icons.ios_share_rounded,
        SettingsCat.system => Icons.memory_outlined,
      };
}

/// Settings: home (title, profile card, two-column grid of categories)
/// and category pages pushed on a nested navigator, so the floating bar /
/// sidebar stay visible and Android back returns to the home.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, this.initial});

  final SettingsCat? initial;

  @override
  State<SettingsScreen> createState() => SettingsScreenState();
}

class SettingsScreenState extends State<SettingsScreen> {
  final _nav = GlobalKey<NavigatorState>();

  void open(SettingsCat c) {
    final nav = _nav.currentState;
    if (nav == null) return;
    nav.popUntil((r) => r.isFirst);
    nav.push(_route(c));
  }

  Route<void> _route(SettingsCat c) => MaterialPageRoute(settings: RouteSettings(name: c.name), builder: (_) => _CatPage(cat: c));

  @override
  void initState() {
    super.initState();
    if (widget.initial != null) WidgetsBinding.instance.addPostFrameCallback((_) => open(widget.initial!));
  }

  @override
  Widget build(BuildContext context) {
    return NavigatorPopHandler(
      onPopWithResult: (_) => _nav.currentState?.maybePop(),
      child: Navigator(
        key: _nav,
        onGenerateRoute: (_) => MaterialPageRoute(builder: (_) => _SettingsHome(onOpen: (c) => _nav.currentState!.push(_route(c)))),
      ),
    );
  }
}

class _SettingsHome extends StatelessWidget {
  const _SettingsHome({required this.onOpen});

  final ValueChanged<SettingsCat> onOpen;

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: ListenableBuilder(
        listenable: AppState.I,
        builder: (context, _) {
          // grouped rows, like a phone's settings: what the app looks like,
          // how the icons are made, then the system
          final groups = <(String, List<SettingsCat>)>[
            (S.interfaccia, [SettingsCat.appearance]),
            (S.icone, [SettingsCat.processing, SettingsCat.bases, SettingsCat.pack, SettingsCat.export]),
            (S.system, [SettingsCat.system]),
          ];
          final st = AppState.I;
          final backupDue = backupReminderDue(
            changes: st.backupChanges,
            lastBackupMs: st.lastBackupMs,
            snoozeUntilMs: st.snoozeUntilMs,
            nowMs: DateTime.now().millisecondsSinceEpoch,
          );
          return ListView(
            padding: EdgeInsets.fromLTRB(20, 12, 20, 24 + GlassInsets.of(context)),
            children: [
              LargeHeader(S.impostazioni),
              const SettingsUpdateCard(),
              if (backupDue) ...[const _BackupCard(), const SizedBox(height: 14)],
              for (final (title, cats) in groups) ...[
                Padding(padding: const EdgeInsets.only(left: 6), child: SectionTitle(title)),
                _CatGroup(cats: cats, onOpen: onOpen),
                const SizedBox(height: 14),
              ],
              Padding(padding: const EdgeInsets.only(left: 6), child: SectionTitle(S.info)),
              const _ProfileCard(),
              const SizedBox(height: 14),
              const SettingsWhatsNewTile(),
              const SizedBox(height: 14),
              const SettingsTourTile(),
              const SizedBox(height: 14),
              const SettingsResetHintsTile(),
              const SizedBox(height: 14),
              const _SupportCard(),
            ],
          );
        },
      ),
    );
  }
}

/// Gentle backup reminder after many changes: "Make a backup" or "Later".
class _BackupCard extends StatelessWidget {
  const _BackupCard();

  @override
  Widget build(BuildContext context) {
    final st = AppState.I;
    return Glass(
      key: const ValueKey('settings-backup-reminder'),
      radius: st.appearance.radius + 8,
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.save_alt_rounded, size: 22, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 14),
          Expanded(child: Text(S.comodoBkPromemoria, style: TextStyle(fontSize: 14.5, color: Palette.text))),
        ]),
        const SizedBox(height: 10),
        Row(mainAxisAlignment: MainAxisAlignment.end, children: [
          TextButton(onPressed: st.snoozeBackupReminder, child: Text(S.comodoBkPiuTardi)),
          const SizedBox(width: 8),
          FilledButton(onPressed: () => backupSave(context), child: Text(S.comodoBkFai)),
        ]),
      ]),
    );
  }
}

/// App "profile": identity, version, active base and accent.
class _ProfileCard extends StatelessWidget {
  const _ProfileCard();

  @override
  Widget build(BuildContext context) {
    final st = AppState.I;
    // app icon, name and version: nothing else
    return Glass(
      key: const ValueKey('settings-profile'),
      radius: st.appearance.radius + 8,
      padding: const EdgeInsets.all(16),
      child: Row(children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Image.asset('assets/branding/app_icon.png', width: 60, height: 60, filterQuality: FilterQuality.medium),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(S.iconFormatter, style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700, color: Palette.text)),
            const SizedBox(height: 2),
            Text(S.versioneBreve(appVersion), style: TextStyle(fontSize: 13, color: Palette.text2)),
          ]),
        ),
      ]),
    );
  }
}

/// Page where people can support the project (everything in the app is free).
const kKofiUrl = 'https://ko-fi.com/imsteazyy';

/// "Support the project": opens the Ko-fi page.
class _SupportCard extends StatelessWidget {
  const _SupportCard();

  @override
  Widget build(BuildContext context) {
    final st = AppState.I;
    return Glass(
      key: const ValueKey('settings-support'),
      radius: st.appearance.radius + 8,
      padding: EdgeInsets.zero,
      child: InkWell(
        borderRadius: BorderRadius.circular(st.appearance.radius + 8),
        onTap: () => launchUrl(Uri.parse(kKofiUrl), mode: LaunchMode.externalApplication),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(children: [
            Icon(Icons.favorite_rounded, size: 26, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 16),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(S.sostieniTitolo, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Palette.text)),
                const SizedBox(height: 2),
                Text(S.sostieniSub, style: TextStyle(fontSize: 13, color: Palette.text2)),
              ]),
            ),
            Icon(Icons.open_in_new_rounded, size: 18, color: Palette.text3),
          ]),
        ),
      ),
    );
  }
}

/// One group of categories: a single card, one row per category (icon,
/// name, chevron), thin lines between the rows.
class _CatGroup extends StatelessWidget {
  const _CatGroup({required this.cats, required this.onOpen});

  final List<SettingsCat> cats;
  final ValueChanged<SettingsCat> onOpen;

  @override
  Widget build(BuildContext context) {
    final r = AppState.I.appearance.radius + 6;
    final accent = Theme.of(context).colorScheme.primary;
    return Glass(
      radius: r,
      padding: EdgeInsets.zero,
      child: Material(
        type: MaterialType.transparency,
        child: Column(children: [
          for (var i = 0; i < cats.length; i++) ...[
            if (i > 0) Divider(height: 1, indent: 60, endIndent: 16, color: Palette.fg.withValues(alpha: 0.07)),
            InkWell(
              key: ValueKey('cat-${cats[i].name}'),
              borderRadius: BorderRadius.vertical(top: Radius.circular(i == 0 ? r : 0), bottom: Radius.circular(i == cats.length - 1 ? r : 0)),
              onTap: () => onOpen(cats[i]),
              child: SizedBox(
                height: 58,
                child: Row(children: [
                  const SizedBox(width: 18),
                  Icon(cats[i].icon, size: 22, color: nothingStyle ? Palette.text : accent),
                  const SizedBox(width: 18),
                  Expanded(child: Text(cats[i].label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 16, color: Palette.text))),
                  Icon(Icons.chevron_right_rounded, color: Palette.text3),
                  const SizedBox(width: 12),
                ]),
              ),
            ),
          ],
        ]),
      ),
    );
  }
}

/// Category page: round back button + large title, then the page body.
class _CatPage extends StatelessWidget {
  const _CatPage({required this.cat});

  final SettingsCat cat;

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
          child: LargeHeader(
            cat.label,
            onBack: () => Navigator.of(context).maybePop(),

          ),
        ),
        Expanded(child: _Page(cat: cat)),
      ]),
    );
  }
}

class _Page extends StatelessWidget {
  const _Page({required this.cat});

  final SettingsCat cat;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppState.I,
      // Pages are created fresh on every change (not const): they read
      // AppState directly in build, so a const instance would never redraw.
      builder: (context, _) => switch (cat) {
        SettingsCat.appearance => _AppearancePage(),
        SettingsCat.processing => _ProcessingPage(),
        SettingsCat.bases => SingleChildScrollView(padding: EdgeInsets.fromLTRB(20, 4, 20, 24 + GlassInsets.of(context)), child: BasesScreen(embedded: true)),
        SettingsCat.pack => _PackPage(),
        SettingsCat.export => _ExportPage(),
        SettingsCat.system => _SystemPage(),
      },
    );
  }
}

class _AppearancePage extends StatelessWidget {
  const _AppearancePage();

  @override
  Widget build(BuildContext context) {
    final st = AppState.I;
    final a = st.appearance;
    return SettingsList(children: [
      // follow the phone, or light / dark; the new look spreads from the choice
      SectionTitle(S.comodoTema),
      ChoiceRows<ThemeChoice>(
        options: [(ThemeChoice.system, S.comodoTemaSistema), (ThemeChoice.light, S.comodoTemaChiaro), (ThemeChoice.dark, S.comodoTemaScuro)],
        value: a.themeChoice,
        onChanged: (v) => ThemeReveal.run(() => st.update(() {
          a.themeChoice = v;
          a.syncLight();
        })),
      ),
      SectionTitle(S.lingua),
      ChoiceRows<String>(
        options: [('', S.linguaSistema), for (final e in appLanguages.entries) (e.key, e.value)],
        value: a.language,
        onChanged: (v) => st.update(() => a.language = v),
      ),
      SectionTitle(S.interfaccia),
      // off while power saving is on: its value is put back when it goes off
      SettingSwitch(icon: Icons.animation_rounded, title: S.animazioni, value: a.animations, onChanged: a.powerSaving ? null : (v) => st.update(() => a.animations = v)),
      SettingSwitch(
        icon: Icons.battery_saver_rounded,
        title: S.comodoRisparmio,
        subtitle: S.comodoRisparmioSub,
        value: a.powerSaving,
        onChanged: (v) => st.setPowerSaving(v),
      ),
    ]);
  }
}

enum _Procs { auto, fewer, all }

/// Processing: workflow switches, the cut-out provider (the segmentation
/// controls live only in the Icon style sheet, linked from here) and the
/// engine details, collapsed by default.
class _ProcessingPage extends StatelessWidget {
  const _ProcessingPage();

  @override
  Widget build(BuildContext context) {
    final st = AppState.I;
    final s = st.translucentSize;
    final cores = Platform.numberOfProcessors;
    final fewer = cores >= 2 ? cores ~/ 2 : 1;
    final t = st.threads;
    final current = t == 0 ? _Procs.auto : (t >= cores ? _Procs.all : _Procs.fewer);
    final used = t == 0 ? cores : (t > cores ? cores : t);
    return SettingsList(children: [
      SectionTitle(S.ux1a2Flusso),
      SettingSwitch(
        icon: Icons.dashboard_customize_outlined,
        title: S.autoMandaAlPack,
        subtitle: S.autoMandaAlPackSub,
        value: st.autoSendToPack,
        onChanged: (v) => st.update(() => st.autoSendToPack = v),
      ),
      SettingSwitch(
        icon: Icons.save_outlined,
        title: S.ritagliSalva,
        subtitle: S.ux1a2RitagliSub,
        value: st.keepCutouts,
        onChanged: (v) => st.update(() => st.keepCutouts = v),
      ),
      SectionTitle(S.ux1a2Ritaglio),
      const _BgProviderBox(),
      const SizedBox(height: 10),
      _LinkRow(
        key: const ValueKey('processing-fine-tune'),
        icon: Icons.tune_rounded,
        title: S.ux1a2RegolaStile,
        subtitle: S.ux1a2RegolaStileSub,
        // the sheet lives in Studio: switching there is the link
        onTap: () => requestedTab.value = 'studio',
      ),
      const SizedBox(height: 14),
      _Collapsible(
        key: const ValueKey('processing-advanced'),
        title: S.ux1a2Avanzate,
        subtitle: S.ux1a2AvanzateSub,
        children: [
          const LocalAiBox(),
          const SizedBox(height: 14),
          SectionTitle(S.ux1a2Processori),
          SegmentedButton<_Procs>(
            key: const ValueKey('processors-choice'),
            showSelectedIcon: false,
            segments: [
              ButtonSegment(value: _Procs.auto, label: Text(S.ux1a2ProcAuto)),
              ButtonSegment(value: _Procs.fewer, label: Text(S.ux1a2ProcPochi)),
              ButtonSegment(value: _Procs.all, label: Text(S.ux1a2ProcTutti)),
            ],
            selected: {current},
            onSelectionChanged: (choice) => st.update(() => st.threads = switch (choice.first) {
              _Procs.auto => 0,
              _Procs.fewer => fewer,
              _Procs.all => cores,
            }),
          ),
          const SizedBox(height: 6),
          Text(
            switch (current) {
              _Procs.auto => S.ux1a2ProcAutoSub,
              _Procs.fewer => S.ux1a2ProcPochiSub,
              _Procs.all => S.ux1a2ProcTuttiSub,
            },
            style: TextStyle(fontSize: 12.5, color: Palette.text2),
          ),
          Text(S.ux1a2ProcHint(used, cores), style: TextStyle(fontSize: 11.5, color: Palette.text3)),
          const SizedBox(height: 14),
          SectionTitle(S.dimensioni),
          Text(S.originalCompositionUsaDimensioneDel, style: TextStyle(fontSize: 12, color: Palette.text2)),
          Wrap(spacing: 8, children: [
            for (final v in [192, 256, 432, 512, 1024])
              ChoiceChip(label: Text('$v px'), selected: s == v, onSelected: (_) => st.update(() => st.translucentSize = v)),
          ]),
          const SizedBox(height: 14),
          SectionTitle(S.scalaPosizionePredefinite),
          SliderRow(label: S.scala, value: st.scaleMul, min: 0.5, max: 1.6, format: (v) => '${(v * 100).round()}%', onChanged: (v) => st.update(() => st.scaleMul = v)),
          SliderRow(label: S.posizioneX, value: st.offsetX, min: -0.15, max: 0.15, format: (v) => (v * 100).toStringAsFixed(1), onChanged: (v) => st.update(() => st.offsetX = v)),
          SliderRow(label: S.posizioneY, value: st.offsetY, min: -0.15, max: 0.15, format: (v) => (v * 100).toStringAsFixed(1), onChanged: (v) => st.update(() => st.offsetY = v)),
          Text(S.marginiDerivanoDallaCalibrazioneDel, style: TextStyle(fontSize: 11, color: Palette.text3)),
          const SizedBox(height: 8),
        ],
      ),
    ]);
  }
}

/// A row that opens another section (its chevron says so).
class _LinkRow extends StatelessWidget {
  const _LinkRow({super.key, required this.icon, required this.title, required this.subtitle, required this.onTap});

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(children: [
            Icon(icon, size: 24, color: Palette.text),
            const SizedBox(width: 16),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: TextStyle(fontSize: 15, color: Palette.text)),
                const SizedBox(height: 2),
                Text(subtitle, style: TextStyle(fontSize: 12, color: Palette.text2)),
              ]),
            ),
            Icon(Icons.chevron_right_rounded, color: Palette.text3),
          ]),
        ),
      );
}

/// Collapsed by default: the header row opens the body under it.
class _Collapsible extends StatefulWidget {
  const _Collapsible({super.key, required this.title, required this.subtitle, required this.children});

  final String title;
  final String subtitle;
  final List<Widget> children;

  @override
  State<_Collapsible> createState() => _CollapsibleState();
}

class _CollapsibleState extends State<_Collapsible> {
  bool _open = false;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            key: const ValueKey('collapsible-header'),
            borderRadius: BorderRadius.circular(12),
            onTap: () => setState(() => _open = !_open),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(widget.title, style: TextStyle(fontSize: 15, color: Palette.text)),
                    const SizedBox(height: 2),
                    Text(widget.subtitle, style: TextStyle(fontSize: 12, color: Palette.text2)),
                  ]),
                ),
                AnimatedRotation(
                  turns: _open ? 0.5 : 0,
                  duration: const Duration(milliseconds: 200),
                  child: Icon(Icons.expand_more_rounded, color: Palette.text3),
                ),
              ]),
            ),
          ),
          if (_open) ...widget.children,
        ],
      );
}

class _PackPage extends StatelessWidget {
  const _PackPage();

  @override
  Widget build(BuildContext context) {
    final st = AppState.I;
    final s = st.packSegment;
    return SettingsList(children: [
      SectionTitle(S.segmentazionePackCleanup),
      DropdownButtonFormField<SegMode>(
        key: ValueKey(s.mode),
        initialValue: s.mode,
        items: [for (final m in SegMode.values) DropdownMenuItem(value: m, child: Text(segModeLabel(m)))],
        onChanged: (v) => st.update(() => st.packSegment = copySegment(s, mode: v)),
      ),
      SliderRow(label: S.sensibilita, value: s.tolerance, min: 0.03, max: 0.3, format: (v) => v.toStringAsFixed(2), onChanged: (v) => st.update(() => st.packSegment = copySegment(s, tolerance: v))),
      SwitchListTile(contentPadding: EdgeInsets.zero, title: Text(S.rimuoviSfondoRacchiuso), value: s.removeHoles, onChanged: (v) => st.update(() => st.packSegment = copySegment(s, removeHoles: v))),
      SwitchListTile(contentPadding: EdgeInsets.zero, title: Text(S.rifinisciBordi), value: s.refineEdges, onChanged: (v) => st.update(() => st.packSegment = copySegment(s, refineEdges: v))),
      const SizedBox(height: 14),
      SectionTitle(S.stileDestinazione),
      DropdownButtonFormField<StudioMode>(
        key: ValueKey(st.packMode),
        initialValue: st.packMode,
        items: [
          DropdownMenuItem(value: StudioMode.original, child: Text(S.originalCompositionBaseSelezionato)),
          DropdownMenuItem(value: StudioMode.translucent, child: Text(S.traslucido)),
          DropdownMenuItem(value: StudioMode.preset, child: Text(S.preset)),
        ],
        onChanged: (v) => st.update(() => st.packMode = v!),
      ),
      const SizedBox(height: 10),
      DropdownButtonFormField<String>(
        key: ValueKey('pp${st.packPresetId}${st.presets.length}'),
        initialValue: st.packPresetId,
        decoration: InputDecoration(labelText: S.presetModalitaPreset),
        items: [for (final p in st.presets) DropdownMenuItem(value: p.id, child: Text(presetDisplayName(p)))],
        onChanged: (v) => st.update(() => st.packPresetId = v!),
      ),
      const SizedBox(height: 10),
      Text(
        S.risultatiAmbiguiGlyphSimileAllo,
        style: TextStyle(fontSize: 12, color: Palette.text2),
      ),
    ]);
  }
}

class _ExportPage extends StatelessWidget {
  const _ExportPage();

  @override
  Widget build(BuildContext context) {
    final st = AppState.I;
    final ex = st.export;
    return SettingsList(children: [
      SectionTitle(S.packPersonalizzato),
      ListTile(
        key: const ValueKey('pack-name'),
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.badge_outlined),
        title: Text(S.packNome),
        subtitle: Text(ex.packName.trim().isEmpty ? 'Icon Formatter Pack' : ex.packName.trim()),
        onTap: () async {
          if (!context.mounted) return;
          final n = await askText(context, S.packNome, initial: ex.packName);
          if (n != null) st.update(() => ex.packName = n.trim());
        },
      ),
      ListTile(
        key: const ValueKey('pack-accent'),
        contentPadding: EdgeInsets.zero,
        leading: Icon(Icons.circle, color: Color(ex.packAccent ?? st.appearance.accent)),
        title: Text(S.packColore),
        trailing: ex.packAccent == null ? null : TextButton(onPressed: () => st.update(() => ex.packAccent = null), child: Text(S.ripristina)),
        onTap: () async {
          if (!context.mounted) return;
          showColorPicker(context, initial: ex.packAccent ?? st.appearance.accent, title: S.packColore, onChanged: (c) => st.update(() => ex.packAccent = c));
        },
      ),
      SectionTitle(S.formato),
      Text(S.pngRgbaTrasparenzaReale8, style: TextStyle(fontSize: 12, color: Palette.text2)),
      const SizedBox(height: 14),
      SectionTitle(S.risoluzione),
      SwitchListTile(contentPadding: EdgeInsets.zero, title: Text(S.risoluzionePersonalizzata), value: ex.customSize, onChanged: (v) => st.update(() => ex.customSize = v)),
      if (ex.customSize)
        Wrap(spacing: 8, children: [
          for (final v in [128, 192, 256, 432, 512, 1024])
            ChoiceChip(label: Text('$v px'), selected: ex.size == v, onSelected: (_) => st.update(() => ex.size = v)),
        ]),
      const SizedBox(height: 14),
      SectionTitle(S.nomiFile),
      DropdownButtonFormField<ExportNaming>(
        key: ValueKey(ex.naming),
        initialValue: ex.naming,
        items: [
          DropdownMenuItem(value: ExportNaming.original, child: Text(S.nomeOriginale)),
          DropdownMenuItem(value: ExportNaming.withSize, child: Text(S.nomeDimensione)),
          DropdownMenuItem(value: ExportNaming.prefixed, child: Text(S.prefissoNome)),
        ],
        onChanged: (v) => st.update(() => ex.naming = v!),
      ),
      if (ex.naming == ExportNaming.prefixed)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: TextFormField(initialValue: ex.prefix, decoration: InputDecoration(labelText: S.prefisso), onChanged: (v) => st.update(() => ex.prefix = v)),
        ),
      Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Text(S.esempio(ex.fileName('calendar', ex.size)), style: TextStyle(fontSize: 12, color: Palette.text3)),
      ),
      const SizedBox(height: 14),
      SectionTitle(S.destinazione),
      Text(ex.destination ?? S.sceltaOgniEsportazione, style: TextStyle(fontSize: 12, color: Palette.text2)),
      Text(S.windowsDialogNativoAndroidStorage,
          style: TextStyle(fontSize: 11, color: Palette.text3)),
      SwitchListTile(contentPadding: EdgeInsets.zero, title: Text(S.preferisciZip), value: ex.zip, onChanged: (v) => st.update(() => ex.zip = v)),
    ]);
  }
}

/// Saves the backup file (shared by System and the reminder card); a saved file resets the reminder.
Future<void> backupSave(BuildContext context) async {
  final bytes = Uint8List.fromList(utf8.encode(AppState.I.backupJson()));
  final path = await FilePicker.platform.saveFile(fileName: 'icon-formatter-backup.json', bytes: bytes, type: FileType.custom, allowedExtensions: ['json']);
  if (path == null) return;
  AppState.I.markBackupMade();
  if (context.mounted) showMsg(context, S.bkSalvato);
}

class _SystemPage extends StatefulWidget {
  const _SystemPage();

  @override
  State<_SystemPage> createState() => _SystemPageState();
}

class _SystemPageState extends State<_SystemPage> {
  int? cache;
  int? outputs;
  int? cutouts;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _backupRestore() async {
    final r = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['json'], withData: true);
    final f = r?.files.firstOrNull;
    if (f == null) return;
    try {
      final data = f.bytes ?? await File(f.path!).readAsBytes();
      await AppState.I.restoreBackup(utf8.decode(data));
      if (mounted) showMsg(context, S.bkRipristinato);
    } on FormatException {
      if (mounted) showMsg(context, S.bkNonValido, error: true);
    } catch (e) {
      if (mounted) showMsg(context, S.errore(e), error: true);
    }
  }

  Future<void> _refresh() async {
    final c = await AppPaths.I.cacheSize();
    final o = await AppPaths.I.outputsSize();
    final k = (await cutoutCacheSize(dir: AppPaths.I.cutouts)).toInt();
    if (mounted) {
      setState(() {
        cache = c;
        outputs = o;
        cutouts = k;
      });
    }
  }

  /// Id of the cache being emptied: its button shows a spinner inline, the page stays usable.
  String? _busy;

  /// Empties one cache. Disabled when there is nothing to clear; the outputs
  /// (results of past sessions) ask for confirmation first.
  Widget _clearButton(String id, int? size, Future<void> Function() clear, {bool confirmFirst = false}) {
    if (_busy == id) {
      return const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2));
    }
    return OutlinedButton(
      onPressed: size == null || size == 0
          ? null
          : () async {
              if (confirmFirst && !await confirm(context, S.eliminareRisultatiInterni, S.esportazioniGiaSalvateAltroveNon, ok: S.elimina)) return;
              setState(() => _busy = id);
              try {
                await clear();
              } finally {
                if (mounted) setState(() => _busy = null);
              }
              await _refresh();
            },
      child: Text(S.svuota),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SettingsList(children: [
      SectionTitle(S.bkTitolo),
      ListTile(
        key: const ValueKey('backup-save'),
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.save_alt_rounded),
        title: Text(S.bkSalva),
        subtitle: Text(S.bkSalvaSub),
        onTap: () => backupSave(context),
      ),
      ListTile(
        key: const ValueKey('backup-restore'),
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.settings_backup_restore_rounded),
        title: Text(S.bkRipristina),
        subtitle: Text(S.bkRipristinaSub),
        onTap: _backupRestore,
      ),
      const SettingsAutoBackupTile(),
      const SettingsWatchFolderTile(),
      SectionTitle(S.cache),
      ListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(S.fileTemporaneiImportZipEstratti),
        subtitle: Text(cache == null ? '…' : formatBytes(cache!)),
        trailing: _clearButton('cache', cache, () => AppPaths.I.clearCache()),
      ),
      ListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(S.ritagliSalvati),
        subtitle: Text(cutouts == null ? '…' : cutouts == 0 ? S.ux1a2RitagliVuoto : formatBytes(cutouts!)),
        trailing: _clearButton('cutouts', cutouts, () => cutoutCacheClear(dir: AppPaths.I.cutouts)),
      ),
      ListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(S.risultatiDelleSessioni),
        subtitle: Text(outputs == null ? '…' : formatBytes(outputs!)),
        trailing: _clearButton('outputs', outputs, () => AppPaths.I.clearOutputs(), confirmFirst: true),
      ),
      const SizedBox(height: 14),
      SectionTitle(S.performance),
      Text(AppState.I.threads == 0 ? S.elaborazioneParallelaAuto : S.coreRustElaborazioneParallelaRayon(AppState.I.threads),
          style: TextStyle(fontSize: 12, color: Palette.text2)),
      const SizedBox(height: 14),
      SectionTitle(S.ripristino),
      OutlinedButton(
        onPressed: () async {
          if (await confirm(context, S.ripristinareImpostazioni, S.presetAspettoEdExportTornano, ok: S.ripristina)) {
            await AppState.I.resetAll();
          }
        },
        child: Text(S.ripristinaImpostazioniPredefinite),
      ),
      const SizedBox(height: 14),
      SectionTitle(S.versione),
      Text(S.iconFormatterCore(appVersion, coreVersion()), style: TextStyle(fontSize: 12, color: Palette.text2)),
      Text(S.datiApp(AppPaths.I.root.path), style: TextStyle(fontSize: 11, color: Palette.text3)),
      const SizedBox(height: 14),
      const SettingsUpdateSwitch(),
      const SettingsFpsSwitch(),
      SettingsDiagnosticsTile(version: appVersion),
    ]);
  }
}


/// Background removal provider: local (default) or remove.bg (optional).
class _BgProviderBox extends StatefulWidget {
  const _BgProviderBox();

  @override
  State<_BgProviderBox> createState() => _BgProviderBoxState();
}

class _BgProviderBoxState extends State<_BgProviderBox> {
  final key = TextEditingController();
  bool hasKey = false;
  String? status;
  bool testing = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final k = await BgRemovalService.readKey();
    if (mounted) setState(() => hasKey = k != null && k.isNotEmpty);
  }

  @override
  Widget build(BuildContext context) {
    final st = AppState.I;
    return ListenableBuilder(listenable: st, builder: (context, _) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(S.providerRimozioneSfondo, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Palette.text)),
      const SizedBox(height: 4),
      // every option visible with what it means (no hidden dropdown)
      ChoiceRows<BgProvider>(
        options: [
          (BgProvider.local, S.scontornoClassico),
          (BgProvider.localAi, S.scontornoAiLocale),
          (BgProvider.removeBg, S.scontornoRemoveBg),
        ],
        value: st.bgProvider,
        onChanged: (v) => st.update(() => st.bgProvider = v),
      ),
      if (st.bgProvider == BgProvider.localAi)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(
            st.modelReady(st.localAi.model) ? S.ux1a2AvanzateSub : S.ux2bNoticeAiNoModel,
            style: TextStyle(fontSize: 11.5, color: st.modelReady(st.localAi.model) ? Palette.text3 : Palette.warn),
          ),
        ),
      if (st.bgProvider == BgProvider.removeBg) ...[
        const SizedBox(height: 8),
        Text(
          S.ogniImmagineVieneInviataRemove,
          style: TextStyle(fontSize: 11, color: Palette.text3),
        ),
        // the feature that needs the key says why it is unavailable
        if (!hasKey) ...[
          const SizedBox(height: 6),
          Text(S.ux1a2ChiaveServe, style: TextStyle(fontSize: 12, color: Palette.text2)),
        ],
        const SizedBox(height: 8),
        TextField(
          controller: key,
          obscureText: true,
          decoration: InputDecoration(hintText: hasKey ? S.chiaveSalvataInserisciSostituire : S.apiKeyRemoveBg),
        ),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [
          FilledButton(
            onPressed: () async {
              await BgRemovalService.writeKey(key.text.trim());
              key.clear();
              await _load();
            },
            child: Text(S.salvaChiave),
          ),
          if (hasKey)
            OutlinedButton(
              onPressed: () async {
                await BgRemovalService.writeKey(null);
                await _load();
              },
              child: Text(S.rimuovi),
            ),
          OutlinedButton(
            onPressed: testing
                ? null
                : () async {
                    setState(() {
                      testing = true;
                      status = null;
                    });
                    try {
                      final s = await BgRemovalService.testConnection();
                      setState(() => status = s);
                    } catch (e) {
                      setState(() => status = S.errore(e));
                    } finally {
                      setState(() => testing = false);
                    }
                  },
            child: Text(S.testCrediti),
          ),
          TextButton(
            onPressed: () => launchUrl(Uri.parse(BgRemovalService.pricingUrl), mode: LaunchMode.externalApplication),
            child: Text(S.listino),
          ),
        ]),
        if (status != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(status!, style: TextStyle(fontSize: 12, color: status!.startsWith(S.errore4) ? Palette.danger : Palette.ok)),
          ),
        const SizedBox(height: 4),
        Text(BgRemovalService.costNote, style: TextStyle(fontSize: 11, color: Palette.text3)),
      ],
    ]));
  }
}
