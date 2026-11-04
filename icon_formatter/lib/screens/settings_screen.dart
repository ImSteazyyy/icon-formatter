import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app/models.dart';
import '../app/state.dart';
import '../app/storage.dart';
import '../app/theme.dart';
import '../services/ai_service.dart';
import '../services/bg_removal_service.dart';
import '../src/rust/api/engine.dart';
import '../widgets/common.dart';
import '../widgets/liquid_glass.dart';
import '../workspace/adjust_panel.dart';
import 'bases_screen.dart';

const appVersion = '1.0.0';

enum SettingsCat { appearance, processing, bases, ai, pack, export, system }

extension on SettingsCat {
  String get label => switch (this) {
        SettingsCat.appearance => 'Appearance',
        SettingsCat.processing => 'Processing',
        SettingsCat.bases => 'Base Icons',
        SettingsCat.ai => 'AI Provider',
        SettingsCat.pack => 'Pack Cleanup',
        SettingsCat.export => 'Export',
        SettingsCat.system => 'System',
      };

  IconData get icon => switch (this) {
        SettingsCat.appearance => Icons.palette_outlined,
        SettingsCat.processing => Icons.tune,
        SettingsCat.bases => Icons.crop_square_rounded,
        SettingsCat.ai => Icons.auto_awesome_outlined,
        SettingsCat.pack => Icons.cleaning_services_outlined,
        SettingsCat.export => Icons.ios_share,
        SettingsCat.system => Icons.memory_outlined,
      };
}

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, this.initial});

  final SettingsCat? initial;

  @override
  State<SettingsScreen> createState() => SettingsScreenState();
}

class SettingsScreenState extends State<SettingsScreen> {
  late SettingsCat cat = widget.initial ?? SettingsCat.appearance;

  void open(SettingsCat c) => setState(() => cat = c);

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.of(context).size.width >= 900;
    if (wide) {
      return Padding(
        padding: const EdgeInsets.all(20),
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SizedBox(
            width: 220,
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text('Impostazioni', style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 14),
              for (final c in SettingsCat.values)
                ListTile(
                  dense: true,
                  selected: c == cat,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  leading: Icon(c.icon, size: 20),
                  title: Text(c.label),
                  onTap: () => setState(() => cat = c),
                ),
            ]),
          ),
          const SizedBox(width: 16),
          Expanded(child: Glass(padding: EdgeInsets.zero, child: _Page(cat: cat))),
        ]),
      );
    }
    return SafeArea(
      bottom: false,
      child: ListView(padding: EdgeInsets.fromLTRB(12, 12, 12, 12 + GlassInsets.of(context)), children: [
        Text('Impostazioni', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        for (final c in SettingsCat.values)
          ListTile(
            leading: Icon(c.icon),
            title: Text(c.label),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => Scaffold(
                appBar: AppBar(title: Text(c.label), backgroundColor: Colors.transparent),
                body: SafeArea(child: _Page(cat: c)),
              ),
            )),
          ),
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
        SettingsCat.bases => SingleChildScrollView(padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + GlassInsets.of(context)), child: BasesScreen(embedded: true)),
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
    return ListView(padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + GlassInsets.of(context)), children: [
      const SectionTitle('Curvatura pannelli'),
      SliderRow(label: 'Raggio', value: a.radius, min: 4, max: 32, format: (v) => v.round().toString(), onChanged: (v) => st.update(() => a.radius = v)),
      const SizedBox(height: 10),
      const SectionTitle('Accento'),
      const _AccentPicker(),
      const SizedBox(height: 10),
      SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Animazioni'), value: a.animations, onChanged: (v) => st.update(() => a.animations = v)),
      SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Densità compatta'), value: a.compact, onChanged: (v) => st.update(() => a.compact = v)),
      const SizedBox(height: 18),
      ...glassControls(context),
    ]);
  }
}

class _ProcessingPage extends StatelessWidget {
  const _ProcessingPage();

  @override
  Widget build(BuildContext context) {
    final st = AppState.I;
    final s = st.segment;
    return ListView(padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + GlassInsets.of(context)), children: [
      const SectionTitle('Dimensioni'),
      Text('Original Composition usa la dimensione del base selezionato; Translucent/Preset usano:', style: const TextStyle(fontSize: 12, color: Palette.text2)),
      Wrap(spacing: 8, children: [
        for (final v in [192, 256, 432, 512, 1024])
          ChoiceChip(label: Text('$v px'), selected: st.translucentSize == v, onSelected: (_) => st.update(() => st.translucentSize = v)),
      ]),
      const SizedBox(height: 14),
      const SectionTitle('Scala e posizione predefinite'),
      SliderRow(label: 'Scala', value: st.scaleMul, min: 0.5, max: 1.6, format: (v) => '${(v * 100).round()}%', onChanged: (v) => st.update(() => st.scaleMul = v)),
      SliderRow(label: 'Posizione X', value: st.offsetX, min: -0.15, max: 0.15, format: (v) => (v * 100).toStringAsFixed(1), onChanged: (v) => st.update(() => st.offsetX = v)),
      SliderRow(label: 'Posizione Y', value: st.offsetY, min: -0.15, max: 0.15, format: (v) => (v * 100).toStringAsFixed(1), onChanged: (v) => st.update(() => st.offsetY = v)),
      const Text('I margini derivano dalla calibrazione del base (Base Icons).', style: TextStyle(fontSize: 11, color: Palette.text3)),
      const SizedBox(height: 14),
      const SectionTitle('Rimozione sfondo e isolamento'),
      const _BgProviderBox(),
      const SizedBox(height: 10),
      DropdownButtonFormField<SegMode>(
        key: ValueKey(s.mode),
        initialValue: s.mode,
        items: [for (final m in SegMode.values) DropdownMenuItem(value: m, child: Text(segModeLabel(m)))],
        onChanged: (v) => st.update(() => st.segment = copySegment(s, mode: v)),
      ),
      SliderRow(label: 'Sensibilità', value: s.tolerance, min: 0.03, max: 0.3, format: (v) => v.toStringAsFixed(2), onChanged: (v) => st.update(() => st.segment = copySegment(s, tolerance: v))),
      SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Rimuovi sfondo racchiuso (buchi)'), value: s.removeHoles, onChanged: (v) => st.update(() => st.segment = copySegment(s, removeHoles: v))),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Qualità: rifinitura bordi anti-alias'),
        subtitle: const Text('Separa i pixel di bordo dallo sfondo per evitare aloni'),
        value: s.refineEdges,
        onChanged: (v) => st.update(() => st.segment = copySegment(s, refineEdges: v)),
      ),
      const SizedBox(height: 14),
      const SectionTitle('Batch'),
      SliderRow(
        label: 'Thread',
        value: st.threads.toDouble(),
        min: 0,
        max: 16,
        divisions: 16,
        format: (v) => v == 0 ? 'auto' : v.round().toString(),
        onChanged: (v) => st.update(() => st.threads = v.round()),
      ),
      const SizedBox(height: 14),
      const SectionTitle('Preset di stile'),
      for (final pr in st.presets)
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(pr.name),
          subtitle: Text(pr.builtIn ? 'predefinito, modificabile' : 'personalizzato'),
          trailing: Wrap(children: [
            IconButton(
              tooltip: 'Modifica',
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
              IconButton(tooltip: 'Ripristina', icon: const Icon(Icons.restart_alt), onPressed: () => st.resetPreset(pr.id))
            else
              IconButton(tooltip: 'Elimina', icon: const Icon(Icons.delete_outline), onPressed: () => st.deletePreset(pr.id)),
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
    return ListView(padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + GlassInsets.of(context)), children: [
      const SectionTitle('Provider'),
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
        decoration: const InputDecoration(labelText: 'Modello'),
        onChanged: (v) => st.update(() => ai.model = v.trim()),
      ),
      const SizedBox(height: 10),
      if (ai.provider == AiProviderKind.openaiCompatible)
        TextFormField(
          initialValue: ai.baseUrl,
          decoration: const InputDecoration(labelText: 'Base URL (es. https://api.example.com)'),
          onChanged: (v) => st.update(() => ai.baseUrl = v.trim()),
        ),
      if (ai.provider != AiProviderKind.gemini) ...[
        const SizedBox(height: 10),
        DropdownButtonFormField<String>(
          initialValue: ai.quality,
          decoration: const InputDecoration(labelText: 'Qualità (gpt-image)'),
          items: const [
            DropdownMenuItem(value: 'low', child: Text('low')),
            DropdownMenuItem(value: 'medium', child: Text('medium')),
            DropdownMenuItem(value: 'high', child: Text('high')),
          ],
          onChanged: (v) => st.update(() => ai.quality = v!),
        ),
      ],
      const SizedBox(height: 18),
      const SectionTitle('API key'),
      Text(hasKey ? 'Una chiave è salvata nell\'archivio protetto del sistema.' : 'Nessuna chiave salvata.', style: const TextStyle(fontSize: 12, color: Palette.text2)),
      const SizedBox(height: 8),
      TextField(
        controller: key,
        obscureText: obscure,
        decoration: InputDecoration(
          hintText: hasKey ? 'Inserisci per sostituire' : 'Incolla la API key',
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
            if (context.mounted) showMsg(context, 'API key salvata');
          },
          child: const Text('Salva chiave'),
        ),
        if (hasKey)
          OutlinedButton(
            onPressed: () async {
              await AiService.writeKey(ai.provider, null);
              await _load();
              st.update();
            },
            child: const Text('Rimuovi'),
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
                    setState(() => status = 'Errore: $e');
                  } finally {
                    setState(() => testing = false);
                  }
                },
          icon: testing ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.wifi_tethering),
          label: const Text('Test connessione'),
        ),
      ]),
      if (status != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(status!, style: TextStyle(color: status!.startsWith('Errore') ? Palette.danger : Palette.ok))),
      const SizedBox(height: 18),
      const SectionTitle('Costi e limiti'),
      Text(info.costNote, style: const TextStyle(fontSize: 12, color: Palette.text2)),
      if (info.pricingUrl.isNotEmpty)
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => launchUrl(Uri.parse(info.pricingUrl), mode: LaunchMode.externalApplication),
            icon: const Icon(Icons.open_in_new, size: 16),
            label: const Text('Listino ufficiale'),
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
    return ListView(padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + GlassInsets.of(context)), children: [
      const SectionTitle('Segmentazione per Pack Cleanup'),
      DropdownButtonFormField<SegMode>(
        key: ValueKey(s.mode),
        initialValue: s.mode,
        items: [for (final m in SegMode.values) DropdownMenuItem(value: m, child: Text(segModeLabel(m)))],
        onChanged: (v) => st.update(() => st.packSegment = copySegment(s, mode: v)),
      ),
      SliderRow(label: 'Sensibilità', value: s.tolerance, min: 0.03, max: 0.3, format: (v) => v.toStringAsFixed(2), onChanged: (v) => st.update(() => st.packSegment = copySegment(s, tolerance: v))),
      SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Rimuovi sfondo racchiuso'), value: s.removeHoles, onChanged: (v) => st.update(() => st.packSegment = copySegment(s, removeHoles: v))),
      SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Rifinisci bordi'), value: s.refineEdges, onChanged: (v) => st.update(() => st.packSegment = copySegment(s, refineEdges: v))),
      const SizedBox(height: 14),
      const SectionTitle('Stile di destinazione'),
      DropdownButtonFormField<StudioMode>(
        key: ValueKey(st.packMode),
        initialValue: st.packMode,
        items: const [
          DropdownMenuItem(value: StudioMode.original, child: Text('Original Composition (base selezionato)')),
          DropdownMenuItem(value: StudioMode.translucent, child: Text('Nothing Translucent')),
          DropdownMenuItem(value: StudioMode.preset, child: Text('Preset')),
        ],
        onChanged: (v) => st.update(() => st.packMode = v!),
      ),
      const SizedBox(height: 10),
      DropdownButtonFormField<String>(
        key: ValueKey('pp${st.packPresetId}${st.presets.length}'),
        initialValue: st.packPresetId,
        decoration: const InputDecoration(labelText: 'Preset (modalità Preset)'),
        items: [for (final p in st.presets) DropdownMenuItem(value: p.id, child: Text(p.name))],
        onChanged: (v) => st.update(() => st.packPresetId = v!),
      ),
      const SizedBox(height: 10),
      const Text(
        'I risultati ambigui (glyph simile allo sfondo, sfondi complessi) vengono segnalati in giallo per la correzione manuale.',
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
    return ListView(padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + GlassInsets.of(context)), children: [
      const SectionTitle('Formato'),
      const Text('PNG RGBA con trasparenza reale (8 bit per canale).', style: TextStyle(fontSize: 12, color: Palette.text2)),
      const SizedBox(height: 14),
      const SectionTitle('Risoluzione'),
      SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Risoluzione personalizzata'), value: ex.customSize, onChanged: (v) => st.update(() => ex.customSize = v)),
      if (ex.customSize)
        Wrap(spacing: 8, children: [
          for (final v in [128, 192, 256, 432, 512, 1024])
            ChoiceChip(label: Text('$v px'), selected: ex.size == v, onSelected: (_) => st.update(() => ex.size = v)),
        ]),
      const SizedBox(height: 14),
      const SectionTitle('Nomi file'),
      DropdownButtonFormField<ExportNaming>(
        key: ValueKey(ex.naming),
        initialValue: ex.naming,
        items: const [
          DropdownMenuItem(value: ExportNaming.original, child: Text('Nome originale')),
          DropdownMenuItem(value: ExportNaming.withSize, child: Text('Nome + dimensione')),
          DropdownMenuItem(value: ExportNaming.prefixed, child: Text('Prefisso + nome')),
        ],
        onChanged: (v) => st.update(() => ex.naming = v!),
      ),
      if (ex.naming == ExportNaming.prefixed)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: TextFormField(initialValue: ex.prefix, decoration: const InputDecoration(labelText: 'Prefisso'), onChanged: (v) => st.update(() => ex.prefix = v)),
        ),
      Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Text('Esempio: ${ex.fileName('whatsapp', ex.size)}', style: const TextStyle(fontSize: 12, color: Palette.text3)),
      ),
      const SizedBox(height: 14),
      const SectionTitle('Destinazione'),
      Text(ex.destination ?? 'Scelta a ogni esportazione', style: const TextStyle(fontSize: 12, color: Palette.text2)),
      const Text('Windows: dialog nativo. Android: Storage Access Framework, salvataggio ZIP o Share Sheet. I file esistenti non vengono mai sovrascritti.',
          style: TextStyle(fontSize: 11, color: Palette.text3)),
      SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Preferisci ZIP'), value: ex.zip, onChanged: (v) => st.update(() => ex.zip = v)),
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
    return ListView(padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + GlassInsets.of(context)), children: [
      const SectionTitle('Cache'),
      ListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('File temporanei (import, ZIP estratti)'),
        subtitle: Text(cache == null ? '…' : formatBytes(cache!)),
        trailing: OutlinedButton(
          onPressed: () async {
            await AppPaths.I.clearCache();
            _refresh();
          },
          child: const Text('Svuota'),
        ),
      ),
      ListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Risultati delle sessioni'),
        subtitle: Text(outputs == null ? '…' : formatBytes(outputs!)),
        trailing: OutlinedButton(
          onPressed: () async {
            if (await confirm(context, 'Eliminare i risultati interni?', 'Le esportazioni già salvate altrove non vengono toccate.', ok: 'Elimina')) {
              await AppPaths.I.clearOutputs();
              _refresh();
            }
          },
          child: const Text('Svuota'),
        ),
      ),
      const SizedBox(height: 14),
      const SectionTitle('Performance'),
      Text('Core Rust: elaborazione parallela (rayon), thread: ${AppState.I.threads == 0 ? 'automatici' : AppState.I.threads}.',
          style: const TextStyle(fontSize: 12, color: Palette.text2)),
      const SizedBox(height: 14),
      const SectionTitle('Ripristino'),
      OutlinedButton(
        onPressed: () async {
          if (await confirm(context, 'Ripristinare le impostazioni?', 'Preset, aspetto ed export tornano ai valori predefiniti. I base icon restano.', ok: 'Ripristina')) {
            await AppState.I.resetAll();
          }
        },
        child: const Text('Ripristina impostazioni predefinite'),
      ),
      const SizedBox(height: 14),
      const SectionTitle('Versione'),
      Text('Icon Formatter $appVersion · core ${coreVersion()}', style: const TextStyle(fontSize: 12, color: Palette.text2)),
      Text('Dati app: ${AppPaths.I.root.path}', style: const TextStyle(fontSize: 11, color: Palette.text3)),
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
      DropdownButtonFormField<BgProvider>(
        key: ValueKey(st.bgProvider),
        initialValue: st.bgProvider,
        decoration: const InputDecoration(labelText: 'Provider rimozione sfondo'),
        items: [for (final b in BgProvider.values) DropdownMenuItem(value: b, child: Text(bgProviderLabel(b)))],
        onChanged: (v) => st.update(() => st.bgProvider = v!),
      ),
      if (st.bgProvider == BgProvider.removeBg) ...[
        const SizedBox(height: 8),
        const Text(
          'Ogni immagine viene inviata a remove.bg; il risultato trasparente viene poi centrato e composto in locale. '
          'Il glyph isolato in cloud non passa dalla segmentazione locale.',
          style: TextStyle(fontSize: 11, color: Palette.text3),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: key,
          obscureText: true,
          decoration: InputDecoration(hintText: hasKey ? 'Chiave salvata · inserisci per sostituire' : 'API key remove.bg'),
        ),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [
          FilledButton(
            onPressed: () async {
              await BgRemovalService.writeKey(key.text.trim());
              key.clear();
              await _load();
              if (context.mounted) showMsg(context, 'API key remove.bg salvata');
            },
            child: const Text('Salva chiave'),
          ),
          if (hasKey)
            OutlinedButton(
              onPressed: () async {
                await BgRemovalService.writeKey(null);
                await _load();
              },
              child: const Text('Rimuovi'),
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
                      setState(() => status = 'Errore: $e');
                    } finally {
                      setState(() => testing = false);
                    }
                  },
            child: const Text('Test e crediti'),
          ),
          TextButton(
            onPressed: () => launchUrl(Uri.parse(BgRemovalService.pricingUrl), mode: LaunchMode.externalApplication),
            child: const Text('Listino'),
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
  late final TextEditingController hex = TextEditingController(text: _toHex(AppState.I.appearance.accent));
  String? error;

  static String _toHex(int argb) => '#${(argb & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

  static int? _parse(String s) {
    var v = s.trim().replaceAll('#', '');
    if (v.length == 3) v = v.split('').map((c) => '$c$c').join();
    if (v.length != 6 || int.tryParse(v, radix: 16) == null) return null;
    return 0xFF000000 | int.parse(v, radix: 16);
  }

  void _set(int argb, {bool fromField = false}) {
    AppState.I.update(() => AppState.I.appearance.accent = argb);
    if (!fromField) hex.text = _toHex(argb);
    setState(() => error = null);
  }

  @override
  Widget build(BuildContext context) {
    final a = AppState.I.appearance;
    final hsl = HSLColor.fromColor(a.accentColor);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Wrap(spacing: 10, runSpacing: 10, children: [
        for (final c in _AppearancePage.accents)
          GestureDetector(
            onTap: () => _set(c),
            child: Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: Color(c),
                shape: BoxShape.circle,
                border: Border.all(color: a.accent == c ? Colors.white : Colors.transparent, width: 2),
              ),
            ),
          ),
      ]),
      const SizedBox(height: 12),
      Row(children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: a.accentColor,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
          ),
        ),
        const SizedBox(width: 12),
        SizedBox(
          width: 160,
          child: TextField(
            controller: hex,
            decoration: InputDecoration(labelText: 'Hex', hintText: '#BA4CD4', errorText: error),
            style: const TextStyle(fontFamily: 'Consolas', letterSpacing: 1),
            onChanged: (v) {
              final c = _parse(v);
              if (c != null) {
                _set(c, fromField: true);
              } else {
                setState(() => error = v.trim().isEmpty ? null : 'Formato #RRGGBB');
              }
            },
          ),
        ),
        const SizedBox(width: 8),
        TextButton(onPressed: () => _set(Appearance.defaultAccent), child: const Text('Predefinito')),
      ]),
      const SizedBox(height: 8),
      SliderRow(
        label: 'Tonalità',
        value: hsl.hue,
        min: 0,
        max: 360,
        format: (v) => '${v.round()}°',
        onChanged: (v) => _set(hsl.withHue(v).toColor().toARGB32()),
      ),
      SliderRow(
        label: 'Saturazione',
        value: hsl.saturation,
        onChanged: (v) => _set(hsl.withSaturation(v).toColor().toARGB32()),
      ),
      SliderRow(
        label: 'Luminosità',
        value: hsl.lightness,
        min: 0.2,
        max: 0.85,
        onChanged: (v) => _set(hsl.withLightness(v).toColor().toARGB32()),
      ),
    ]);
  }
}


/// Liquid glass controls (part of Appearance) with a live preview over
/// coloured content so refraction and blur are visible.
List<Widget> glassControls(BuildContext context) {
    final st = AppState.I;
    final g = st.glass;
    final accent = st.appearance.accentColor;
    void set(VoidCallback f) => st.update(f);
    return [
      const SectionTitle('Liquid Glass · anteprima'),
      ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: SizedBox(
          height: 220,
          child: Stack(children: [
            // coloured content behind the glass, to show refraction and blur
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [accent, const Color(0xFF2A6CF0), const Color(0xFFF2994A)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
              ),
            ),
            Positioned.fill(
              child: Wrap(spacing: 18, runSpacing: 10, alignment: WrapAlignment.center, children: [
                for (var i = 0; i < 18; i++)
                  Icon(
                    const [Icons.apps_rounded, Icons.music_note_rounded, Icons.camera_alt_rounded, Icons.star_rounded][i % 4],
                    size: 40,
                    color: Colors.white.withValues(alpha: 0.9),
                  ),
              ]),
            ),
            const Positioned(
              left: 16,
              right: 16,
              top: 28,
              child: LiquidGlass(
                radius: 30,
                padding: EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                child: Row(children: [
                  Icon(Icons.blur_on, color: Colors.white),
                  SizedBox(width: 12),
                  Text('Barra in vetro', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 16)),
                ]),
              ),
            ),
            const Positioned(
              left: 16,
              right: 16,
              bottom: 24,
              height: 64,
              child: LiquidGlass(
                radius: 32,
                child: Row(children: [
                  SizedBox(width: 6),
                  SizedBox(
                    width: 96,
                    height: 54,
                    child: LiquidGlass(radius: 27, dark: true, chromatic: 1, child: Center(child: Icon(Icons.home_rounded, color: Colors.white))),
                  ),
                  Expanded(child: Icon(Icons.grid_view_rounded, color: Colors.white70)),
                  Expanded(child: Icon(Icons.search_rounded, color: Colors.white70)),
                ]),
              ),
            ),
          ]),
        ),
      ),
      const SizedBox(height: 18),
      Row(children: [
        const Expanded(child: SectionTitle('Liquid Glass · materiale')),
        TextButton(onPressed: () => set(g.reset), child: const Text('Ripristina')),
      ]),
      SliderRow(label: 'Blur', value: g.blur, min: 0, max: 30, format: (v) => v.toStringAsFixed(1), onChanged: (v) => set(() => g.blur = v)),
      SliderRow(label: 'Spessore', value: g.thickness, min: 0, max: 60, format: (v) => v.round().toString(), onChanged: (v) => set(() => g.thickness = v)),
      SliderRow(label: 'Rifrazione', value: g.refractiveIndex, min: 1.0, max: 2.0, format: (v) => v.toStringAsFixed(2), onChanged: (v) => set(() => g.refractiveIndex = v)),
      SliderRow(label: 'Aberr. cromatica', value: g.chromatic, min: 0, max: 0.05, format: (v) => (v * 1000).round().toString(), onChanged: (v) => set(() => g.chromatic = v)),
      SliderRow(label: 'Saturazione', value: g.saturation, min: 0.5, max: 2.5, format: (v) => v.toStringAsFixed(2), onChanged: (v) => set(() => g.saturation = v)),
      SliderRow(label: 'Frost', value: g.frost, onChanged: (v) => set(() => g.frost = v)),
      SliderRow(label: 'Tinta vetro', value: g.tint, max: 0.5, onChanged: (v) => set(() => g.tint = v)),
      const SizedBox(height: 10),
      const SectionTitle('Luce'),
      SliderRow(label: 'Intensità', value: g.lightIntensity, max: 1.5, onChanged: (v) => set(() => g.lightIntensity = v)),
      SliderRow(label: 'Angolo luce', value: g.lightAngle, min: 0, max: 360, format: (v) => '${v.round()}°', onChanged: (v) => set(() => g.lightAngle = v)),
      SliderRow(label: 'Rim light', value: g.rimLight, onChanged: (v) => set(() => g.rimLight = v)),
      const SizedBox(height: 10),
      const SectionTitle('Lucentezza'),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Bordo lucido'),
        subtitle: const Text('Riflesso speculare sul bordo, più forte dal lato della luce (come le icone di esempio)'),
        value: g.gloss,
        onChanged: (v) => set(() => g.gloss = v),
      ),
      if (g.gloss) SliderRow(label: 'Intensità', value: g.glossIntensity, onChanged: (v) => set(() => g.glossIntensity = v)),
      const SizedBox(height: 10),
      const SectionTitle('Leggibilità'),
      SliderRow(label: 'Ombra testo', value: g.textShadow, onChanged: (v) => set(() => g.textShadow = v)),
      SliderRow(label: 'Sfocatura ombra', value: g.textShadowBlur, min: 0, max: 16, format: (v) => v.toStringAsFixed(1), onChanged: (v) => set(() => g.textShadowBlur = v)),
      const Text('Ombra dietro testi e icone sulle superfici in vetro; 0 la disattiva.', style: TextStyle(fontSize: 11, color: Palette.text3)),
      const SizedBox(height: 10),
      const SectionTitle('Lente selezione'),
      SliderRow(label: 'Scurezza lente', value: g.lensDarkness, max: 0.8, onChanged: (v) => set(() => g.lensDarkness = v)),
      const SizedBox(height: 10),
      const SectionTitle('Qualità'),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Qualità Premium'),
        subtitle: const Text('Pipeline shader completa con aberrazione cromatica reale (Impeller). Più pesante; su Windows resta Standard.'),
        value: g.premium,
        onChanged: (v) => set(() => g.premium = v),
      ),
    ];
}
