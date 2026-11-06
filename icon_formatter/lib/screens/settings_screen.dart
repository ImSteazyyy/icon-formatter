import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app/models.dart';
import '../app/state.dart';
import '../app/storage.dart';
import '../app/theme.dart';
import '../services/ai_service.dart';
import '../services/bg_removal_service.dart';
import '../src/rust/api/engine.dart';
import '../widgets/ai_mask.dart';
import '../widgets/color_picker.dart';
import '../widgets/common.dart';
import '../widgets/liquid_glass.dart';
import '../workspace/adjust_panel.dart';
import 'bases_screen.dart';
import '../l10n/strings.dart';

const appVersion = '1.3.2';

enum SettingsCat { appearance, glass, processing, bases, ai, pack, export, system }

extension on SettingsCat {
  String get label => switch (this) {
        SettingsCat.appearance => S.appearance,
        SettingsCat.glass => S.vetro,
        SettingsCat.processing => S.processing,
        SettingsCat.bases => S.baseIcons,
        SettingsCat.ai => S.aiProvider,
        SettingsCat.pack => S.packCleanup,
        SettingsCat.export => S.export,
        SettingsCat.system => S.system,
      };

  String get description => switch (this) {
        SettingsCat.appearance => S.catAspettoDesc,
        SettingsCat.glass => S.catVetroDesc,
        SettingsCat.processing => S.catElaborazioneDesc,
        SettingsCat.bases => S.catBaseDesc,
        SettingsCat.ai => S.catAiDesc,
        SettingsCat.pack => S.catPackDesc,
        SettingsCat.export => S.catExportDesc,
        SettingsCat.system => S.catSistemaDesc,
      };

  IconData get icon => switch (this) {
        SettingsCat.appearance => Icons.palette_outlined,
        SettingsCat.glass => Icons.blur_on_rounded,
        SettingsCat.processing => Icons.tune_rounded,
        SettingsCat.bases => Icons.crop_square_rounded,
        SettingsCat.ai => Icons.auto_awesome_outlined,
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
        builder: (context, _) => LayoutBuilder(builder: (context, box) {
          final cols = box.maxWidth >= 1100 ? 4 : (box.maxWidth >= 720 ? 3 : 2);
          return CustomScrollView(slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              sliver: SliverList.list(children: [
                const LargeHeader(S.impostazioni),
                const _ProfileCard(),
                const SizedBox(height: 18),
              ]),
            ),
            SliverPadding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 24 + GlassInsets.of(context)),
              sliver: SliverGrid.builder(
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: cols,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  mainAxisExtent: 150,
                ),
                itemCount: SettingsCat.values.length,
                itemBuilder: (context, i) => _CatTile(cat: SettingsCat.values[i], onTap: () => onOpen(SettingsCat.values[i])),
              ),
            ),
          ]);
        }),
      ),
    );
  }
}

/// App "profile": identity, version, active base and accent.
class _ProfileCard extends StatelessWidget {
  const _ProfileCard();

  @override
  Widget build(BuildContext context) {
    final st = AppState.I;
    final base = st.selectedBase;
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
            const Text(S.iconFormatter, style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700, color: Palette.text)),
            const SizedBox(height: 2),
            Text(S.versioneBreve(appVersion), style: const TextStyle(fontSize: 12.5, color: Palette.text2)),
            const SizedBox(height: 6),
            Row(children: [
              Container(width: 10, height: 10, decoration: BoxDecoration(color: st.appearance.accentColor, shape: BoxShape.circle)),
              const SizedBox(width: 6),
              Expanded(
                child: Text('${S.baseAttivo}: ${base?.name ?? '—'}',
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: Palette.text2)),
              ),
            ]),
          ]),
        ),
        if (base != null) SizedBox(width: 44, height: 44, child: IconImage(path: base.path)),
      ]),
    );
  }
}

class _CatTile extends StatelessWidget {
  const _CatTile({required this.cat, required this.onTap});

  final SettingsCat cat;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final r = AppState.I.appearance.radius + 6;
    return Glass(
      radius: r,
      padding: EdgeInsets.zero,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          key: ValueKey('cat-${cat.name}'),
          borderRadius: BorderRadius.circular(r),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              IconChip(icon: cat.icon, size: 40),
              const Spacer(),
              Text(cat.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Palette.text)),
              const SizedBox(height: 3),
              Text(cat.description, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, height: 1.3, color: Palette.text2)),
            ]),
          ),
        ),
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
                ? TextButton(onPressed: () => AppState.I.update(AppState.I.glass.reset), child: const Text(S.ripristina))
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
        SettingsCat.ai => _AiPage(),
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
    return SettingsList(children: [
      const SectionTitle(S.accento),
      const _AccentPicker(),
      const SectionTitle(S.interfaccia),
      SettingSwitch(icon: Icons.animation_rounded, title: S.animazioni, value: a.animations, onChanged: (v) => st.update(() => a.animations = v)),
      SettingSwitch(icon: Icons.density_medium_rounded, title: S.densitaCompatta, value: a.compact, onChanged: (v) => st.update(() => a.compact = v)),
      SettingsCard(children: [
        Row(children: [
          const IconChip(icon: Icons.blur_on_rounded),
          const SizedBox(width: 12),
          const Expanded(child: Text(S.catVetroDesc, style: TextStyle(fontSize: 13, color: Palette.text2))),
          TextButton(
            onPressed: () => Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const _CatPage(cat: SettingsCat.glass))),
            child: const Text(S.apri),
          ),
        ]),
      ]),
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
      const SectionTitle(S.dimensioni),
      Text(S.originalCompositionUsaDimensioneDel, style: const TextStyle(fontSize: 12, color: Palette.text2)),
      Wrap(spacing: 8, children: [
        for (final v in [192, 256, 432, 512, 1024])
          ChoiceChip(label: Text('$v px'), selected: st.translucentSize == v, onSelected: (_) => st.update(() => st.translucentSize = v)),
      ]),
      const SizedBox(height: 14),
      const SectionTitle(S.scalaPosizionePredefinite),
      SliderRow(label: S.scala, value: st.scaleMul, min: 0.5, max: 1.6, format: (v) => '${(v * 100).round()}%', onChanged: (v) => st.update(() => st.scaleMul = v)),
      SliderRow(label: S.posizioneX, value: st.offsetX, min: -0.15, max: 0.15, format: (v) => (v * 100).toStringAsFixed(1), onChanged: (v) => st.update(() => st.offsetX = v)),
      SliderRow(label: S.posizioneY, value: st.offsetY, min: -0.15, max: 0.15, format: (v) => (v * 100).toStringAsFixed(1), onChanged: (v) => st.update(() => st.offsetY = v)),
      const Text(S.marginiDerivanoDallaCalibrazioneDel, style: TextStyle(fontSize: 11, color: Palette.text3)),
      const SizedBox(height: 14),
      const SectionTitle(S.rimozioneSfondoIsolamento),
      const _BgProviderBox(),
      const SizedBox(height: 10),
      DropdownButtonFormField<SegMode>(
        key: ValueKey(s.mode),
        initialValue: s.mode,
        items: [for (final m in SegMode.values) DropdownMenuItem(value: m, child: Text(segModeLabel(m)))],
        onChanged: (v) => st.update(() => st.segment = copySegment(s, mode: v)),
      ),
      SliderRow(label: S.sensibilita, value: s.tolerance, min: 0.03, max: 0.3, format: (v) => v.toStringAsFixed(2), onChanged: (v) => st.update(() => st.segment = copySegment(s, tolerance: v))),
      SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text(S.rimuoviSfondoRacchiusoBuchi), value: s.removeHoles, onChanged: (v) => st.update(() => st.segment = copySegment(s, removeHoles: v))),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text(S.qualitaRifinituraBordiAntiAlias),
        subtitle: const Text(S.separaPixelBordoDalloSfondo),
        value: s.refineEdges,
        onChanged: (v) => st.update(() => st.segment = copySegment(s, refineEdges: v)),
      ),
      const SizedBox(height: 14),
      const SectionTitle(S.batch),
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
      const SectionTitle(S.presetStile),
      for (final pr in st.presets)
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(pr.name),
          subtitle: Text(pr.builtIn ? S.predefinitoModificabile : 'personalizzato'),
          trailing: Wrap(children: [
            IconButton(
              tooltip: S.modifica,
              icon: const Icon(Icons.edit_outlined),
              onPressed: () => showModalBottomSheet(
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

class _AiPage extends StatefulWidget {
  const _AiPage();

  @override
  State<_AiPage> createState() => _AiPageState();
}

class _AiPageState extends State<_AiPage> {
  final key = TextEditingController();
  bool hasKey = false;
  bool obscure = true;
  String? status;
  bool testing = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final k = await AiService.readKey(AppState.I.ai.provider);
    setState(() {
      hasKey = k != null && k.isNotEmpty;
      key.text = '';
      status = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final st = AppState.I;
    final ai = st.ai;
    final info = aiProviders[ai.provider]!;
    return SettingsList(children: [
      // the online AI needs an API key; the local AI does not
      Text(S.aiOnlineSpiega, style: const TextStyle(fontSize: 12.5, color: Palette.text2)),
      const SizedBox(height: 6),
      const SectionTitle(S.aiModelliLocali),
      const Text(S.aiLocaleSpiega, style: TextStyle(fontSize: 12, color: Palette.text2)),
      ListenableBuilder(
        listenable: st,
        builder: (context, _) => SettingSwitch(
          title: S.aiUsaLocale,
          subtitle: st.modelReady(st.localAi.model) ? S.aiUsaLocaleSub : S.aiModelloMancante,
          value: st.bgProvider == BgProvider.localAi,
          onChanged: st.modelReady(st.localAi.model) || st.bgProvider == BgProvider.localAi
              ? (v) => st.update(() => st.bgProvider = v ? BgProvider.localAi : BgProvider.local)
              : null,
        ),
      ),
      const LocalAiBox(),
      const SizedBox(height: 10),
      const SectionTitle(S.aiOnlineTitolo),
      const SectionTitle(S.provider),
      DropdownButtonFormField<AiProviderKind>(
        key: ValueKey(ai.provider),
        initialValue: ai.provider,
        items: [for (final e in aiProviders.entries) DropdownMenuItem(value: e.key, child: Text(e.value.name))],
        onChanged: (v) {
          st.update(() {
            ai.provider = v!;
            ai.model = aiProviders[v]!.defaultModel;
            ai.baseUrl = aiProviders[v]!.defaultBaseUrl;
          });
          _load();
        },
      ),
      const SizedBox(height: 10),
      TextFormField(
        key: ValueKey('model${ai.provider}'),
        initialValue: ai.model,
        decoration: const InputDecoration(labelText: S.modello2),
        onChanged: (v) => st.update(() => ai.model = v.trim()),
      ),
      const SizedBox(height: 10),
      if (ai.provider == AiProviderKind.openaiCompatible)
        TextFormField(
          initialValue: ai.baseUrl,
          decoration: const InputDecoration(labelText: S.baseUrlEsHttpsApi),
          onChanged: (v) => st.update(() => ai.baseUrl = v.trim()),
        ),
      if (ai.provider != AiProviderKind.gemini) ...[
        const SizedBox(height: 10),
        DropdownButtonFormField<String>(
          initialValue: ai.quality,
          decoration: const InputDecoration(labelText: S.qualitaGptImage),
          items: const [
            DropdownMenuItem(value: 'low', child: Text('low')),
            DropdownMenuItem(value: 'medium', child: Text('medium')),
            DropdownMenuItem(value: 'high', child: Text('high')),
          ],
          onChanged: (v) => st.update(() => ai.quality = v!),
        ),
      ],
      const SizedBox(height: 18),
      const SectionTitle(S.apiKey),
      Text(hasKey ? S.chiaveESalvataNellArchivio : S.nessunaChiaveSalvata, style: const TextStyle(fontSize: 12, color: Palette.text2)),
      const SizedBox(height: 8),
      TextField(
        controller: key,
        obscureText: obscure,
        decoration: InputDecoration(
          hintText: hasKey ? S.inserisciSostituire : S.incollaApiKey,
          suffixIcon: IconButton(icon: Icon(obscure ? Icons.visibility : Icons.visibility_off), onPressed: () => setState(() => obscure = !obscure)),
        ),
      ),
      const SizedBox(height: 8),
      Wrap(spacing: 8, runSpacing: 8, children: [
        FilledButton(
          onPressed: () async {
            await AiService.writeKey(ai.provider, key.text.trim());
            await _load();
            st.update();
            if (context.mounted) showMsg(context, S.apiKeySalvata);
          },
          child: const Text(S.salvaChiave),
        ),
        if (hasKey)
          OutlinedButton(
            onPressed: () async {
              await AiService.writeKey(ai.provider, null);
              await _load();
              st.update();
            },
            child: const Text(S.rimuovi),
          ),
        OutlinedButton.icon(
          onPressed: testing
              ? null
              : () async {
                  setState(() {
                    testing = true;
                    status = null;
                  });
                  try {
                    final s = await AiService.testConnection();
                    setState(() => status = s);
                  } catch (e) {
                    setState(() => status = S.errore(e));
                  } finally {
                    setState(() => testing = false);
                  }
                },
          icon: testing ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.wifi_tethering),
          label: const Text(S.testConnessione),
        ),
      ]),
      if (status != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(status!, style: TextStyle(color: status!.startsWith('Errore') ? Palette.danger : Palette.ok))),
      const SizedBox(height: 18),
      const SectionTitle(S.costiLimiti),
      Text(info.costNote, style: const TextStyle(fontSize: 12, color: Palette.text2)),
      if (info.pricingUrl.isNotEmpty)
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => launchUrl(Uri.parse(info.pricingUrl), mode: LaunchMode.externalApplication),
            icon: const Icon(Icons.open_in_new, size: 16),
            label: const Text(S.listinoUfficiale),
          ),
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
      const SectionTitle(S.segmentazionePackCleanup),
      DropdownButtonFormField<SegMode>(
        key: ValueKey(s.mode),
        initialValue: s.mode,
        items: [for (final m in SegMode.values) DropdownMenuItem(value: m, child: Text(segModeLabel(m)))],
        onChanged: (v) => st.update(() => st.packSegment = copySegment(s, mode: v)),
      ),
      SliderRow(label: S.sensibilita, value: s.tolerance, min: 0.03, max: 0.3, format: (v) => v.toStringAsFixed(2), onChanged: (v) => st.update(() => st.packSegment = copySegment(s, tolerance: v))),
      SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text(S.rimuoviSfondoRacchiuso), value: s.removeHoles, onChanged: (v) => st.update(() => st.packSegment = copySegment(s, removeHoles: v))),
      SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text(S.rifinisciBordi), value: s.refineEdges, onChanged: (v) => st.update(() => st.packSegment = copySegment(s, refineEdges: v))),
      const SizedBox(height: 14),
      const SectionTitle(S.stileDestinazione),
      DropdownButtonFormField<StudioMode>(
        key: ValueKey(st.packMode),
        initialValue: st.packMode,
        items: const [
          DropdownMenuItem(value: StudioMode.original, child: Text(S.originalCompositionBaseSelezionato)),
          DropdownMenuItem(value: StudioMode.translucent, child: Text(S.nothingTranslucent)),
          DropdownMenuItem(value: StudioMode.preset, child: Text(S.preset)),
        ],
        onChanged: (v) => st.update(() => st.packMode = v!),
      ),
      const SizedBox(height: 10),
      DropdownButtonFormField<String>(
        key: ValueKey('pp${st.packPresetId}${st.presets.length}'),
        initialValue: st.packPresetId,
        decoration: const InputDecoration(labelText: S.presetModalitaPreset),
        items: [for (final p in st.presets) DropdownMenuItem(value: p.id, child: Text(p.name))],
        onChanged: (v) => st.update(() => st.packPresetId = v!),
      ),
      const SizedBox(height: 10),
      const Text(
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
      const SectionTitle(S.formato),
      const Text(S.pngRgbaTrasparenzaReale8, style: TextStyle(fontSize: 12, color: Palette.text2)),
      const SizedBox(height: 14),
      const SectionTitle(S.risoluzione),
      SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text(S.risoluzionePersonalizzata), value: ex.customSize, onChanged: (v) => st.update(() => ex.customSize = v)),
      if (ex.customSize)
        Wrap(spacing: 8, children: [
          for (final v in [128, 192, 256, 432, 512, 1024])
            ChoiceChip(label: Text('$v px'), selected: ex.size == v, onSelected: (_) => st.update(() => ex.size = v)),
        ]),
      const SizedBox(height: 14),
      const SectionTitle(S.nomiFile),
      DropdownButtonFormField<ExportNaming>(
        key: ValueKey(ex.naming),
        initialValue: ex.naming,
        items: const [
          DropdownMenuItem(value: ExportNaming.original, child: Text(S.nomeOriginale)),
          DropdownMenuItem(value: ExportNaming.withSize, child: Text(S.nomeDimensione)),
          DropdownMenuItem(value: ExportNaming.prefixed, child: Text(S.prefissoNome)),
        ],
        onChanged: (v) => st.update(() => ex.naming = v!),
      ),
      if (ex.naming == ExportNaming.prefixed)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: TextFormField(initialValue: ex.prefix, decoration: const InputDecoration(labelText: S.prefisso), onChanged: (v) => st.update(() => ex.prefix = v)),
        ),
      Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Text(S.esempio(ex.fileName('whatsapp', ex.size)), style: const TextStyle(fontSize: 12, color: Palette.text3)),
      ),
      const SizedBox(height: 14),
      const SectionTitle(S.destinazione),
      Text(ex.destination ?? S.sceltaOgniEsportazione, style: const TextStyle(fontSize: 12, color: Palette.text2)),
      const Text(S.windowsDialogNativoAndroidStorage,
          style: TextStyle(fontSize: 11, color: Palette.text3)),
      SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text(S.preferisciZip), value: ex.zip, onChanged: (v) => st.update(() => ex.zip = v)),
    ]);
  }
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
      const SectionTitle(S.cache),
      ListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text(S.fileTemporaneiImportZipEstratti),
        subtitle: Text(cache == null ? '…' : formatBytes(cache!)),
        trailing: OutlinedButton(
          onPressed: () async {
            await AppPaths.I.clearCache();
            _refresh();
          },
          child: const Text(S.svuota),
        ),
      ),
      ListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text(S.risultatiDelleSessioni),
        subtitle: Text(outputs == null ? '…' : formatBytes(outputs!)),
        trailing: OutlinedButton(
          onPressed: () async {
            if (await confirm(context, S.eliminareRisultatiInterni, S.esportazioniGiaSalvateAltroveNon, ok: S.elimina)) {
              await AppPaths.I.clearOutputs();
              _refresh();
            }
          },
          child: const Text(S.svuota),
        ),
      ),
      const SizedBox(height: 14),
      const SectionTitle(S.performance),
      Text(S.coreRustElaborazioneParallelaRayon(AppState.I.threads == 0 ? 'automatici' : AppState.I.threads),
          style: const TextStyle(fontSize: 12, color: Palette.text2)),
      const SizedBox(height: 14),
      const SectionTitle(S.ripristino),
      OutlinedButton(
        onPressed: () async {
          if (await confirm(context, S.ripristinareImpostazioni, S.presetAspettoEdExportTornano, ok: S.ripristina)) {
            await AppState.I.resetAll();
          }
        },
        child: const Text(S.ripristinaImpostazioniPredefinite),
      ),
      const SizedBox(height: 14),
      const SectionTitle(S.versione),
      Text(S.iconFormatterCore(appVersion, coreVersion()), style: const TextStyle(fontSize: 12, color: Palette.text2)),
      Text(S.datiApp(AppPaths.I.root.path), style: const TextStyle(fontSize: 11, color: Palette.text3)),
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
      const Text(S.providerRimozioneSfondo, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Palette.text)),
      const SizedBox(height: 4),
      // every option visible with what it means (no hidden dropdown)
      ChoiceRows<BgProvider>(
        options: const [
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
        const Text(
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
            child: const Text(S.salvaChiave),
          ),
          if (hasKey)
            OutlinedButton(
              onPressed: () async {
                await BgRemovalService.writeKey(null);
                await _load();
              },
              child: const Text(S.rimuovi),
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
            child: const Text(S.testCrediti),
          ),
          TextButton(
            onPressed: () => launchUrl(Uri.parse(BgRemovalService.pricingUrl), mode: LaunchMode.externalApplication),
            child: const Text(S.listino),
          ),
        ]),
        if (status != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(status!, style: TextStyle(fontSize: 12, color: status!.startsWith('Errore') ? Palette.danger : Palette.ok)),
          ),
        const SizedBox(height: 4),
        const Text(BgRemovalService.costNote, style: TextStyle(fontSize: 11, color: Palette.text3)),
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
              border: Border.all(color: a.accent == c ? Colors.white : Colors.transparent, width: 2.5),
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

class GlassPreview extends StatelessWidget {
  const GlassPreview({super.key});

  @override
  Widget build(BuildContext context) {
    final accent = AppState.I.appearance.accentColor;
    return ClipRRect(
      key: const ValueKey('glass-preview'),
      borderRadius: BorderRadius.circular(AppState.I.appearance.radius + 10),
      child: SizedBox(
        height: 146,
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
          Positioned(
            left: 12,
            right: 12,
            bottom: 10,
            height: 62,
            child: LiquidGlass(
              radius: 31,
              role: GlassRole.nav,
              live: true,
              child: Row(children: [
                const SizedBox(width: 5),
                SizedBox(
                  width: 74,
                  height: 52,
                  child: LiquidGlass(
                    radius: 26,
                    dark: true,
                    chromatic: 1,
                    role: GlassRole.lens,
                    live: true,
                    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      const Icon(Icons.auto_awesome_mosaic_outlined, color: Colors.white, size: 20),
                      Text(S.studio, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Colors.white, shadows: glassTextShadows())),
                    ]),
                  ),
                ),
                for (final i in const [Icons.auto_awesome_outlined, Icons.dashboard_customize_outlined, Icons.apps_rounded, Icons.settings_outlined])
                  Expanded(child: Icon(i, color: Colors.white70, size: 20, shadows: glassTextShadows())),
              ]),
            ),
          ),
        ]),
      ),
    );
  }
}

/// Liquid Glass controls (Impostazioni › Vetro). Every value is read by
/// [appGlassSettings], [LiquidGlass], the bottom bar, dialogs and the theme.
List<Widget> glassControls(BuildContext context) {
  final st = AppState.I;
  final g = st.glass;
  final a = st.appearance;
  void set(VoidCallback f) => st.update(f);
  return [
    const SectionTitle(S.materiale),
    ChoiceRows<GlassQualityLevel>(
      options: const [
        (GlassQualityLevel.fast, S.vetroVeloce),
        (GlassQualityLevel.balanced, S.vetroBilanciato),
        (GlassQualityLevel.quality, S.qualita),
      ],
      value: g.quality,
      onChanged: (v) => set(() => g.quality = v),
    ),
    SliderRow(icon: Icons.blur_on_rounded, label: S.blur, value: g.blur, min: 0, max: 30, format: (v) => v.toStringAsFixed(1), onChanged: (v) => set(() => g.blur = v)),
    SliderRow(icon: Icons.ac_unit_rounded, label: S.frost, value: g.frost, onChanged: (v) => set(() => g.frost = v)),
    SliderRow(icon: Icons.invert_colors_rounded, label: S.saturazione, value: g.saturation, min: 0.5, max: 2.5, format: (v) => v.toStringAsFixed(2), onChanged: (v) => set(() => g.saturation = v)),
    const SectionTitle(S.colore),
    _TintPicker(value: g.tintColor, onChanged: (c) => set(() => g.tintColor = c)),
    SliderRow(icon: Icons.water_drop_outlined, label: S.tintaVetro, value: g.tint, max: 0.5, onChanged: (v) => set(() => g.tint = v)),
    const SectionTitle(S.bordoProfondita),
    SliderRow(icon: Icons.layers_outlined, label: S.spessore, value: g.thickness, min: 0, max: 60, format: (v) => '${v.round()} dp', onChanged: (v) => set(() => g.thickness = v)),
    SliderRow(icon: Icons.rounded_corner_rounded, label: S.curvatura, value: a.radius, min: 4, max: 32, format: (v) => '${v.round()} dp', onChanged: (v) => set(() => a.radius = v)),
    SliderRow(icon: Icons.lens_blur_rounded, label: S.rifrazione, value: g.refractiveIndex, min: 1.0, max: 2.0, format: (v) => v.toStringAsFixed(2), onChanged: (v) => set(() => g.refractiveIndex = v)),
    SliderRow(icon: Icons.gradient_rounded, label: S.aberrCromatica, value: g.chromatic, min: 0, max: 0.05, format: (v) => (v * 1000).round().toString(), onChanged: (v) => set(() => g.chromatic = v)),
    SettingSwitch(icon: Icons.layers_rounded, title: S.profondita, subtitle: S.profonditaSub, value: g.depth, onChanged: (v) => set(() => g.depth = v)),
    if (g.quality != GlassQualityLevel.quality) const Text(S.vetroNotaQualita, style: TextStyle(fontSize: 11.5, color: Palette.text3)),
    const SectionTitle(S.luce),
    SliderRow(icon: Icons.light_mode_outlined, label: S.intensita, value: g.lightIntensity, max: 1.5, onChanged: (v) => set(() => g.lightIntensity = v)),
    SliderRow(icon: Icons.explore_outlined, label: S.angoloLuce, value: g.lightAngle, min: 0, max: 360, format: (v) => '${v.round()}°', onChanged: (v) => set(() => g.lightAngle = v)),
    SliderRow(icon: Icons.highlight_rounded, label: S.rimLight, value: g.rimLight, onChanged: (v) => set(() => g.rimLight = v)),
    SettingSwitch(icon: Icons.auto_awesome_outlined, title: S.bordoLucido, subtitle: S.riflessoSpeculareSulBordoPiu, value: g.gloss, onChanged: (v) => set(() => g.gloss = v)),
    if (g.gloss) SliderRow(icon: Icons.flare_rounded, label: S.lucentezza, value: g.glossIntensity, onChanged: (v) => set(() => g.glossIntensity = v)),
    const SectionTitle(S.leggibilita),
    SliderRow(icon: Icons.text_fields_rounded, label: S.ombraTesto, value: g.textShadow, onChanged: (v) => set(() => g.textShadow = v)),
    SliderRow(icon: Icons.blur_linear_rounded, label: S.sfocaturaOmbra, value: g.textShadowBlur, min: 0, max: 16, format: (v) => v.toStringAsFixed(1), onChanged: (v) => set(() => g.textShadowBlur = v)),
    SliderRow(icon: Icons.contrast_rounded, label: S.scurezzaLente, value: g.lensDarkness, max: 0.8, onChanged: (v) => set(() => g.lensDarkness = v)),
    const SectionTitle(S.doveUsarlo),
    SettingSwitch(icon: Icons.view_agenda_outlined, title: S.vetroBarra, value: g.useNav, onChanged: (v) => set(() => g.useNav = v)),
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
        const Expanded(child: Text(S.tinta, style: TextStyle(fontSize: 15, color: Palette.text))),
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
                border: Border.all(color: (value | 0xFF000000) == c ? Colors.white : Colors.transparent, width: 2.5),
              ),
            ),
          ),
      ]),
      const SizedBox(height: 4),
    ]);
  }
}
