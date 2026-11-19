import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app/models.dart';
import '../app/state.dart';
import '../app/storage.dart';
import '../app/theme.dart';
import '../services/bg_removal_service.dart';
import '../src/rust/api/engine.dart';
import '../widgets/ai_mask.dart';
import '../widgets/color_picker.dart';
import '../widgets/common.dart';
import '../widgets/liquid_glass.dart';
import '../widgets/theme_reveal.dart';
import '../workspace/adjust_panel.dart';
import 'bases_screen.dart';
import 'settings_extras.dart';
import '../l10n/strings.dart';

const appVersion = '1.0.0';

enum SettingsCat { appearance, glass, processing, bases, pack, export, system }

extension on SettingsCat {
  String get label => switch (this) {
        SettingsCat.appearance => S.appearance,
        SettingsCat.glass => S.vetro,
        SettingsCat.processing => S.processing,
        SettingsCat.bases => S.baseIcons,
        SettingsCat.pack => S.packCleanup,
        SettingsCat.export => S.export,
        SettingsCat.system => S.system,
      };

  IconData get icon => switch (this) {
        SettingsCat.appearance => Icons.palette_outlined,
        SettingsCat.glass => Icons.blur_on_rounded,
        SettingsCat.processing => Icons.tune_rounded,
        SettingsCat.bases => Icons.crop_square_rounded,
        SettingsCat.pack => Icons.cleaning_services_outlined,
        SettingsCat.export => Icons.ios_share_rounded,
        SettingsCat.system => Icons.memory_outlined,
      };
}

/// Impostazioni: home (title, profile card, two-column grid of categories)
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
              const _SupportCard(),
            ],
          );
        },
      ),
    );
  }
}

/// Gentle backup reminder after many changes: "Fai il backup" or "Più tardi".
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

/// "Sostieni il progetto": opens the Ko-fi page.
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
            trailing: cat == SettingsCat.glass
                ? TextButton(onPressed: () => AppState.I.update(AppState.I.glass.reset), child: Text(S.ripristina))
                : null,
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
        SettingsCat.glass => SettingsList(header: const GlassPreview(), children: glassControls(context)),
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

  static const accents = [0xFFBA4CD4, 0xFFD46AB8, 0xFFB9A96E, 0xFF9FA36A, 0xFFA8A29A];

  @override
  Widget build(BuildContext context) {
    final st = AppState.I;
    final a = st.appearance;
    final glass = a.style == UiStyle.glass;
    // Glass style: the live preview stays at the top while the glass
    // settings scroll under it
    return SettingsList(header: glass ? const GlassPreview() : null, children: [
      SectionTitle(S.stileApp),
      ChoiceRows<UiStyle>(
        options: [(UiStyle.nothing, S.stileNothing), (UiStyle.glass, S.stileVetro)],
        value: a.style,
        onChanged: (v) => ThemeReveal.run(() => st.update(() => a.style = v)),
      ),
      // follow the phone, or light / dark, in both styles; the new look spreads from the choice
      SectionTitle(S.comodoTema),
      ChoiceRows<ThemeChoice>(
        options: [(ThemeChoice.system, S.comodoTemaSistema), (ThemeChoice.light, S.comodoTemaChiaro), (ThemeChoice.dark, S.comodoTemaScuro)],
        value: a.themeChoice,
        onChanged: (v) => ThemeReveal.run(() => st.update(() {
          a.themeChoice = v;
          a.syncLight();
        })),
      ),
      Text(a.style == UiStyle.nothing ? S.stileNothingSub : S.stileVetroSub, style: TextStyle(fontSize: 12.5, color: Palette.text2)),
      if (a.style == UiStyle.glass) ...[
        SectionTitle(S.accento),
        const _AccentPicker(),
      ],
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
      // only with the Glass style: its material, colour, edges and where it is used
      if (glass) ...[
        ...glassControls(context),
        Center(child: TextButton(onPressed: () => st.update(st.glass.reset), child: Text(S.ripristina))),
      ],
    ]);
  }
}

class _ProcessingPage extends StatelessWidget {
  const _ProcessingPage();

  @override
  Widget build(BuildContext context) {
    final st = AppState.I;
    final s = st.segment;
    return SettingsList(children: [
      SectionTitle(S.dimensioni),
      Text(S.originalCompositionUsaDimensioneDel, style: TextStyle(fontSize: 12, color: Palette.text2)),
      Wrap(spacing: 8, children: [
        for (final v in [192, 256, 432, 512, 1024])
          ChoiceChip(label: Text('$v px'), selected: st.translucentSize == v, onSelected: (_) => st.update(() => st.translucentSize = v)),
      ]),
      const SizedBox(height: 14),
      SectionTitle(S.scalaPosizionePredefinite),
      SliderRow(label: S.scala, value: st.scaleMul, min: 0.5, max: 1.6, format: (v) => '${(v * 100).round()}%', onChanged: (v) => st.update(() => st.scaleMul = v)),
      SliderRow(label: S.posizioneX, value: st.offsetX, min: -0.15, max: 0.15, format: (v) => (v * 100).toStringAsFixed(1), onChanged: (v) => st.update(() => st.offsetX = v)),
      SliderRow(label: S.posizioneY, value: st.offsetY, min: -0.15, max: 0.15, format: (v) => (v * 100).toStringAsFixed(1), onChanged: (v) => st.update(() => st.offsetY = v)),
      Text(S.marginiDerivanoDallaCalibrazioneDel, style: TextStyle(fontSize: 11, color: Palette.text3)),
      const SizedBox(height: 14),
      SectionTitle(S.rimozioneSfondoIsolamento),
      const _BgProviderBox(),
      const SizedBox(height: 10),
      DropdownButtonFormField<SegMode>(
        key: ValueKey(s.mode),
        initialValue: s.mode,
        items: [for (final m in SegMode.values) DropdownMenuItem(value: m, child: Text(segModeLabel(m)))],
        onChanged: (v) => st.update(() => st.segment = copySegment(s, mode: v)),
      ),
      SliderRow(label: S.sensibilita, value: s.tolerance, min: 0.03, max: 0.3, format: (v) => v.toStringAsFixed(2), onChanged: (v) => st.update(() => st.segment = copySegment(s, tolerance: v))),
      SwitchListTile(contentPadding: EdgeInsets.zero, title: Text(S.rimuoviSfondoRacchiusoBuchi), value: s.removeHoles, onChanged: (v) => st.update(() => st.segment = copySegment(s, removeHoles: v))),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(S.qualitaRifinituraBordiAntiAlias),
        subtitle: Text(S.separaPixelBordoDalloSfondo),
        value: s.refineEdges,
        onChanged: (v) => st.update(() => st.segment = copySegment(s, refineEdges: v)),
      ),
      const SizedBox(height: 14),
      SectionTitle(S.batch),
      SettingSwitch(
        icon: Icons.dashboard_customize_outlined,
        title: S.autoMandaAlPack,
        subtitle: S.autoMandaAlPackSub,
        value: st.autoSendToPack,
        onChanged: (v) => st.update(() => st.autoSendToPack = v),
      ),
      SliderRow(
        label: S.thread,
        value: st.threads.toDouble(),
        min: 0,
        max: 16,
        divisions: 16,
        format: (v) => v == 0 ? 'auto' : v.round().toString(),
        onChanged: (v) => st.update(() => st.threads = v.round()),
      ),
      const SizedBox(height: 14),
      SectionTitle(S.presetStile),
      for (final pr in st.presets)
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(pr.name),
          subtitle: Text(pr.builtIn ? S.predefinitoModificabile : 'personalizzato'),
          trailing: Wrap(children: [
            IconButton(
              tooltip: S.modifica,
              icon: const Icon(Icons.edit_outlined),
              onPressed: () => showAppSheet(
                context: context,
                isScrollControlled: true,
                builder: (ctx) => SizedBox(
                  height: MediaQuery.of(ctx).size.height * 0.7,
                  child: ListenableBuilder(
                    listenable: st,
                    builder: (ctx, _) => ListView(padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + GlassInsets.of(context)), children: [
                      Text(pr.name, style: Theme.of(ctx).textTheme.titleMedium),
                      const SizedBox(height: 10),
                      ...translucentSliders(st.presetById(pr.id).params, (t) => st.setPresetParams(pr.id, t)),
                    ]),
                  ),
                ),
              ),
            ),
            if (pr.builtIn)
              IconButton(tooltip: S.ripristina, icon: const Icon(Icons.restart_alt), onPressed: () => st.resetPreset(pr.id))
            else
              IconButton(tooltip: S.elimina, icon: const Icon(Icons.delete_outline), onPressed: () => st.deletePreset(pr.id)),
          ]),
        ),
    ]);
  }
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
        items: [for (final p in st.presets) DropdownMenuItem(value: p.id, child: Text(p.name))],
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
  // desktop only returns the chosen path; mobile has already written the bytes
  if (!Platform.isAndroid && !Platform.isIOS) await File(path).writeAsBytes(bytes);
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
    if (mounted) {
      setState(() {
        cache = c;
        outputs = o;
      });
    }
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
        trailing: OutlinedButton(
          onPressed: () async {
            await AppPaths.I.clearCache();
            _refresh();
          },
          child: Text(S.svuota),
        ),
      ),
      ListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(S.risultatiDelleSessioni),
        subtitle: Text(outputs == null ? '…' : formatBytes(outputs!)),
        trailing: OutlinedButton(
          onPressed: () async {
            if (await confirm(context, S.eliminareRisultatiInterni, S.esportazioniGiaSalvateAltroveNon, ok: S.elimina)) {
              await AppPaths.I.clearOutputs();
              _refresh();
            }
          },
          child: Text(S.svuota),
        ),
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
      SettingsDiagnosticsTile(version: appVersion),
      if (!Platform.isAndroid) const SettingsShortcutsTile(),
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
      if (st.bgProvider == BgProvider.localAi) const LocalAiBox(),
      if (st.bgProvider == BgProvider.removeBg) ...[
        const SizedBox(height: 8),
        Text(
          S.ogniImmagineVieneInviataRemove,
          style: TextStyle(fontSize: 11, color: Palette.text3),
        ),
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
              if (context.mounted) showMsg(context, S.apiKeyRemoveBgSalvata);
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


/// Accent colour: presets, hex input (#RRGGBB) and HSL sliders.
class _AccentPicker extends StatefulWidget {
  const _AccentPicker();

  @override
  State<_AccentPicker> createState() => _AccentPickerState();
}

class _AccentPickerState extends State<_AccentPicker> {
  void _set(int argb) => AppState.I.update(() => AppState.I.appearance.accent = argb);

  @override
  Widget build(BuildContext context) {
    final a = AppState.I.appearance;
    final preset = _AppearancePage.accents.contains(a.accent);
    return Wrap(spacing: 10, runSpacing: 10, children: [
      for (final c in _AppearancePage.accents)
        GestureDetector(
          onTap: () => _set(c),
          child: Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: Color(c),
              shape: BoxShape.circle,
              border: Border.all(color: a.accent == c ? Palette.fg : Colors.transparent, width: 2.5),
            ),
          ),
        ),
      // any colour: saturation/brightness square, hue, hex (live preview)
      CustomColorSwatch(
        selected: !preset,
        onTap: () => showColorPicker(context, initial: a.accent, title: S.accentoTitolo, onChanged: _set),
      ),
    ]);
  }
}

class GlassPreview extends StatefulWidget {
  const GlassPreview({super.key});

  @override
  State<GlassPreview> createState() => _GlassPreviewState();
}

class _GlassPreviewState extends State<GlassPreview> {
  int index = 0;

  @override
  Widget build(BuildContext context) {
    final accent = AppState.I.appearance.accentColor;
    return ClipRRect(
      key: const ValueKey('glass-preview'),
      borderRadius: BorderRadius.circular(AppState.I.appearance.radius + 10),
      child: SizedBox(
        height: 160,
        child: Stack(children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [accent, const Color(0xFFF2784B), const Color(0xFF2EC4B6), const Color(0xFF1B3A4B)],
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                ),
              ),
            ),
          ),
          // stripes behind the glass make refraction and aberration visible
          Positioned.fill(
            child: Column(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
              for (var i = 0; i < 6; i++)
                Container(height: 5, margin: EdgeInsets.only(right: i.isEven ? 40 : 0), color: Colors.white.withValues(alpha: i.isEven ? 0.85 : 0.35)),
            ]),
          ),
          Positioned(
            left: 12,
            right: 12,
            top: 10,
            height: 56,
            // Studio action bar, same layout as the real one
            child: LiquidGlass(
              radius: 28,
              role: GlassRole.panel,
              live: true,
              padding: const EdgeInsets.all(6),
              child: Row(children: [
                Expanded(
                  child: Container(
                    height: 44,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(22)),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 18),
                      const SizedBox(width: 6),
                      Text(S.elaboraTutte, style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13, shadows: glassTextShadows())),
                    ]),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Container(
                    height: 44,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(border: Border.all(color: Colors.white.withValues(alpha: 0.30)), borderRadius: BorderRadius.circular(22)),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.drive_folder_upload_outlined, color: Colors.white, size: 18),
                      const SizedBox(width: 6),
                      Flexible(child: Text(S.esportaCartella, overflow: TextOverflow.ellipsis, style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13, shadows: glassTextShadows()))),
                    ]),
                  ),
                ),
              ]),
            ),
          ),
          // the real bottom bar, so the preview behaves like it
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: 88,
            child: appGlassTabBar(
              icons: const [Icons.auto_awesome_mosaic_outlined, Icons.dashboard_customize_outlined, Icons.apps_rounded, Icons.settings_outlined],
              labels: [S.studio, S.pbTitolo, S.app, S.impostazioni],
              index: index,
              onSelect: (i) => setState(() => index = i),
            ),
          ),
        ]),
      ),
    );
  }
}

/// Glass controls (Impostazioni › Vetro). Every value is read by
/// [appGlassSettings], [LiquidGlass], the bottom bar, dialogs and the theme.
List<Widget> glassControls(BuildContext context) {
  final st = AppState.I;
  final g = st.glass;
  final a = st.appearance;
  void set(VoidCallback f) => st.update(f);
  return [
    SectionTitle(S.materiale),
    ChoiceRows<GlassQualityLevel>(
      options: [
        (GlassQualityLevel.fast, S.vetroVeloce),
        (GlassQualityLevel.balanced, S.vetroBilanciato),
        (GlassQualityLevel.quality, S.qualita),
      ],
      value: g.quality,
      onChanged: (v) {
        if (v == GlassQualityLevel.quality && premiumGlassSupported) {
          // tell the user first, then switch after the message has been painted
          showMsg(context, S.vetroApplico);
          WidgetsBinding.instance.addPostFrameCallback((_) => Future.delayed(const Duration(milliseconds: 150), () => set(() => g.quality = v)));
        } else {
          set(() => g.quality = v);
        }
      },
    ),
    if (g.quality == GlassQualityLevel.quality && !premiumGlassSupported) Text(S.vetroQualitaNonDisponibile, style: TextStyle(fontSize: 11.5, color: Palette.warn)),
    SettingSwitch(icon: Icons.auto_awesome_outlined, title: S.vetroNativo, subtitle: S.vetroNativoSub, value: g.native, onChanged: (v) => set(() => g.native = v)),
    if (nativeGlass) ...[
      SettingSwitch(icon: Icons.ac_unit_rounded, title: S.smerigliatura, value: g.nFrostOn, onChanged: (v) => set(() => g.nFrostOn = v)),
      SliderRow(icon: Icons.water_drop_outlined, label: S.colore, value: g.nColour, format: (v) => '${(v * 100).round()}%', onChanged: (v) => set(() => g.nColour = v)),
      SliderRow(icon: Icons.camera_rounded, label: S.smerigliatura, value: g.nFrost, min: 0, max: 12, format: (v) => '${v.round()} dp', onChanged: (v) => set(() => g.nFrost = v)),
      SectionTitle(S.colore),
      _TintPicker(value: g.tintColor, onChanged: (c) => set(() => g.tintColor = c)),
      SliderRow(icon: Icons.layers_outlined, label: S.pellicola, value: g.nFilm, format: (v) => '${(v * 100).round()}%', onChanged: (v) => set(() => g.nFilm = v)),
      SliderRow(icon: Icons.tab_rounded, label: S.schedaAttiva, value: g.nActiveTab, format: (v) => '${(v * 100).round()}%', onChanged: (v) => set(() => g.nActiveTab = v)),
      SectionTitle(S.bordi),
      SliderRow(icon: Icons.highlight_rounded, label: S.luceBordo, value: g.nEdgeLight, format: (v) => '${(v * 100).round()}%', onChanged: (v) => set(() => g.nEdgeLight = v)),
      SliderRow(icon: Icons.line_weight_rounded, label: S.spessoreBordo, value: g.nEdgeDepth, min: 0, max: 40, format: (v) => '${v.round()} dp', onChanged: (v) => set(() => g.nEdgeDepth = v)),
      SliderRow(icon: Icons.lens_blur_rounded, label: S.rifrazione, value: g.nBend, min: 0, max: 60, format: (v) => '${v.round()} dp', onChanged: (v) => set(() => g.nBend = v)),
      SettingSwitch(icon: Icons.gradient_rounded, title: S.separazioneColori, value: g.nSplit, onChanged: (v) => set(() => g.nSplit = v)),
      // native: Depth deepens the edge, no drop shadow
      SettingSwitch(icon: Icons.layers_rounded, title: S.profondita, value: g.depth, onChanged: (v) => set(() => g.depth = v)),
    ] else ...[
      SliderRow(icon: Icons.blur_on_rounded, label: S.blur, value: g.blur, min: 0, max: 30, format: (v) => v.toStringAsFixed(1), onChanged: (v) => set(() => g.blur = v)),
      SliderRow(icon: Icons.ac_unit_rounded, label: S.frost, value: g.frost, onChanged: (v) => set(() => g.frost = v)),
      SliderRow(icon: Icons.invert_colors_rounded, label: S.saturazione, value: g.saturation, min: 0.5, max: 2.5, format: (v) => v.toStringAsFixed(2), onChanged: (v) => set(() => g.saturation = v)),
      SectionTitle(S.colore),
      _TintPicker(value: g.tintColor, onChanged: (c) => set(() => g.tintColor = c)),
      SliderRow(icon: Icons.water_drop_outlined, label: S.tintaVetro, value: g.tint, max: 0.5, onChanged: (v) => set(() => g.tint = v)),
      SectionTitle(S.bordoProfondita),
      SliderRow(icon: Icons.layers_outlined, label: S.spessore, value: g.thickness, min: 0, max: 60, format: (v) => '${v.round()} dp', onChanged: (v) => set(() => g.thickness = v)),
      SliderRow(icon: Icons.rounded_corner_rounded, label: S.curvatura, value: a.radius, min: 4, max: 32, format: (v) => '${v.round()} dp', onChanged: (v) => set(() => a.radius = v)),
      SliderRow(icon: Icons.lens_blur_rounded, label: S.rifrazione, value: g.refractiveIndex, min: 1.0, max: 2.0, format: (v) => v.toStringAsFixed(2), onChanged: (v) => set(() => g.refractiveIndex = v)),
      SliderRow(icon: Icons.gradient_rounded, label: S.aberrCromatica, value: g.chromatic, min: 0, max: 0.05, format: (v) => (v * 1000).round().toString(), onChanged: (v) => set(() => g.chromatic = v)),
      SettingSwitch(icon: Icons.layers_rounded, title: S.profondita, subtitle: S.profonditaSub, value: g.depth, onChanged: (v) => set(() => g.depth = v)),
      if (g.quality != GlassQualityLevel.quality) Text(S.vetroNotaQualita, style: TextStyle(fontSize: 11.5, color: Palette.text3)),
      SectionTitle(S.luce),
      SliderRow(icon: Icons.light_mode_outlined, label: S.intensita, value: g.lightIntensity, max: 1.5, onChanged: (v) => set(() => g.lightIntensity = v)),
      SliderRow(icon: Icons.explore_outlined, label: S.angoloLuce, value: g.lightAngle, min: 0, max: 360, format: (v) => '${v.round()}°', onChanged: (v) => set(() => g.lightAngle = v)),
      SliderRow(icon: Icons.highlight_rounded, label: S.rimLight, value: g.rimLight, onChanged: (v) => set(() => g.rimLight = v)),
      SettingSwitch(icon: Icons.auto_awesome_outlined, title: S.bordoLucido, subtitle: S.riflessoSpeculareSulBordoPiu, value: g.gloss, onChanged: (v) => set(() => g.gloss = v)),
      if (g.gloss) SliderRow(icon: Icons.flare_rounded, label: S.lucentezza, value: g.glossIntensity, onChanged: (v) => set(() => g.glossIntensity = v)),
      SectionTitle(S.leggibilita),
      SliderRow(icon: Icons.text_fields_rounded, label: S.ombraTesto, value: g.textShadow, onChanged: (v) => set(() => g.textShadow = v)),
      SliderRow(icon: Icons.blur_linear_rounded, label: S.sfocaturaOmbra, value: g.textShadowBlur, min: 0, max: 16, format: (v) => v.toStringAsFixed(1), onChanged: (v) => set(() => g.textShadowBlur = v)),
      SliderRow(icon: Icons.contrast_rounded, label: S.scurezzaLente, value: g.lensDarkness, max: 0.8, onChanged: (v) => set(() => g.lensDarkness = v)),
    ],
    SectionTitle(S.doveUsarlo),
    SettingSwitch(icon: Icons.view_agenda_outlined, title: S.vetroBarra, value: g.useNav, onChanged: (v) => set(() => g.useNav = v)),
    if (nativeGlass)
      SettingSwitch(icon: Icons.dashboard_outlined, title: S.vetroNeiPannelliNativo, value: g.nPanels, onChanged: (v) => set(() => g.nPanels = v))
    else
      SettingSwitch(icon: Icons.dashboard_outlined, title: S.vetroPannelli, value: g.usePanels, onChanged: (v) => set(() => g.usePanels = v)),
    SettingSwitch(icon: Icons.smart_button_outlined, title: S.vetroPulsanti, value: g.useButtons, onChanged: (v) => set(() => g.useButtons = v)),
    SettingSwitch(icon: Icons.web_asset_rounded, title: S.vetroDialoghi, value: g.useDialogs, onChanged: (v) => set(() => g.useDialogs = v)),
  ];
}

/// "Tinta": neutral or one of the colour dots, plus a hue strip.
class _TintPicker extends StatelessWidget {
  const _TintPicker({required this.value, required this.onChanged});

  final int value;
  final ValueChanged<int> onChanged;

  static const colors = [0xFF8E8E93, 0xFFFF3B30, 0xFFFF9500, 0xFFFFCC00, 0xFF34C759, 0xFF32D2E6, 0xFF3478F6, 0xFF8E44F2, 0xFFFF2D9A];

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        const IconChip(icon: Icons.palette_outlined),
        const SizedBox(width: 12),
        Expanded(child: Text(S.tinta, style: TextStyle(fontSize: 15, color: Palette.text))),
        TextButton(onPressed: value == 0 ? null : () => onChanged(0), child: Text(value == 0 ? S.nessuna : S.rimuovi)),
      ]),
      const SizedBox(height: 8),
      const SizedBox(height: 8),
      Wrap(spacing: 10, runSpacing: 10, children: [
        // any colour (full picker, live on the glass)
        CustomColorSwatch(
          selected: value != 0 && !colors.contains(value | 0xFF000000),
          onTap: () => showColorPicker(context, initial: value == 0 ? 0xFF8E44F2 : value, title: S.tintaTitolo, onChanged: onChanged),
        ),
        for (final c in colors)
          GestureDetector(
            onTap: () => onChanged(c),
            child: Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: Color(c),
                shape: BoxShape.circle,
                border: Border.all(color: (value | 0xFF000000) == c ? Palette.fg : Colors.transparent, width: 2.5),
              ),
            ),
          ),
      ]),
      const SizedBox(height: 4),
    ]);
  }
}
