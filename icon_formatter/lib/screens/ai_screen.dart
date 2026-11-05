import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../app/state.dart';
import '../app/theme.dart';
import '../services/ai_service.dart';
import '../services/bg_removal_service.dart';
import '../services/export_service.dart';
import '../src/rust/api/engine.dart';
import '../widgets/ai_mask.dart';
import '../widgets/common.dart';
import '../widgets/liquid_glass.dart';
import '../l10n/strings.dart';

class _AiItem {
  _AiItem(this.name, this.original);

  final String name;
  final Uint8List original;
  final List<Uint8List> versions = [];
  int current = -1;
  bool? accepted;
  String? error;

  Uint8List? get result => current >= 0 ? versions[current] : null;
}

/// AI Icon Theme: separate pipeline, external provider, no simulated output.
class AiScreen extends StatefulWidget {
  const AiScreen({super.key, required this.onOpenSettings});

  final VoidCallback onOpenSettings;

  @override
  State<AiScreen> createState() => _AiScreenState();
}

class _AiScreenState extends State<AiScreen> with AutomaticKeepAliveClientMixin {
  /// Phones: 0 = online theme generator, 1 = local AI models.
  int tab = 0;

  final List<_AiItem> items = [];
  int sel = -1;
  String theme = aiThemes.keys.first;
  final custom = TextEditingController();
  final comment = TextEditingController();
  bool compose = true;
  bool busy = false;
  bool? configured;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _check();
    AppState.I.addListener(_check);
  }

  @override
  void dispose() {
    AppState.I.removeListener(_check);
    super.dispose();
  }

  Future<void> _check() async {
    final c = await AiService.isConfigured();
    if (mounted) setState(() => configured = c);
  }

  _AiItem? get cur => sel >= 0 && sel < items.length ? items[sel] : null;

  Future<void> _import() async {
    final r = await FilePicker.platform.pickFiles(allowMultiple: true, type: FileType.custom, allowedExtensions: ['png', 'jpg', 'jpeg', 'webp']);
    if (r == null) return;
    for (final f in r.files) {
      if (f.path == null) continue;
      final bytes = await File(f.path!).readAsBytes();
      items.add(_AiItem(p.basenameWithoutExtension(f.path!), bytes));
    }
    setState(() => sel = sel < 0 && items.isNotEmpty ? 0 : sel);
  }

  Future<void> _generate({required bool regenerate}) async {
    final it = cur;
    if (it == null || busy) return;
    if (configured != true) {
      showMsg(context, S.aiNonConfigurataImpostaProvider, error: true);
      return;
    }
    setState(() {
      busy = true;
      it.error = null;
    });
    try {
      final refs = <Uint8List>[it.original];
      if (regenerate && it.result != null) refs.add(it.result!);
      final prompt = AiService.buildPrompt(
        theme: aiThemes[theme] ?? '',
        custom: custom.text.trim(),
        comment: comment.text.trim(),
        regeneration: regenerate && it.result != null,
      );
      var png = await AiService.generate(references: refs, prompt: prompt);
      if (compose) {
        final s = AppState.I.settingsFor(StudioMode.translucent);
        png = (await previewBytes(bytes: png, settings: s)).png;
      }
      setState(() {
        it.versions.add(png);
        it.current = it.versions.length - 1;
        it.accepted = null;
      });
      comment.clear();
    } catch (e) {
      setState(() => it.error = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _save() async {
    final it = cur;
    if (it?.result == null) return;
    final r = await ExportService.saveSingle(it!.result!, '${it.name}_ai.png');
    if (r != null && mounted) showMsg(context, '${r.message}${r.location != null ? ': ${r.location}' : ''}');
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final wide = MediaQuery.of(context).size.width >= 900;
    final it = cur;
    final info = aiProviders[AppState.I.ai.provider]!;
    final banner = configured == false
        ? Tile(
            padding: const EdgeInsets.all(12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Row(children: [
                Icon(Icons.key_off_outlined, color: Palette.warn),
                SizedBox(width: 10),
                Expanded(child: Text(S.aiNessunaChiave)),
              ]),
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 8, children: [
                FilledButton.tonalIcon(onPressed: widget.onOpenSettings, icon: const Icon(Icons.key_outlined, size: 18), label: const Text(S.configura)),
                if (!wide)
                  OutlinedButton.icon(
                    onPressed: () => setState(() => tab = 1),
                    icon: const Icon(Icons.memory_rounded, size: 18),
                    label: const Text(S.aiProvaLocale),
                  ),
              ]),
            ]),
          )
        : const SizedBox.shrink();

    final list = Glass(
      padding: const EdgeInsets.all(8),
      child: Column(children: [
        Row(children: [
          const Expanded(child: SectionTitle(S.icone)),
          IconButton(tooltip: S.importa, onPressed: _import, icon: const Icon(Icons.add)),
        ]),
        Expanded(
          child: items.isEmpty
              ? const Center(child: Text(S.importaOPiuIcone, style: TextStyle(color: Palette.text3)))
              : ListView.builder(
                  itemCount: items.length,
                  itemBuilder: (_, i) => ListTile(
                    selected: i == sel,
                    leading: SizedBox(width: 36, height: 36, child: IconImage(bytes: items[i].result ?? items[i].original)),
                    title: Text(items[i].name, overflow: TextOverflow.ellipsis),
                    subtitle: Text(
                      items[i].accepted == true ? 'accettata' : (items[i].versions.isEmpty ? S.generare : '${items[i].versions.length} versioni'),
                      style: const TextStyle(fontSize: 11),
                    ),
                    onTap: () => setState(() => sel = i),
                  ),
                ),
        ),
      ]),
    );

    final preview = Glass(
      child: it == null
          ? Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.auto_awesome_outlined, size: 40, color: Palette.text3),
                const SizedBox(height: 10),
                const Text(S.aiVuotoTitolo, textAlign: TextAlign.center, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Palette.text)),
                const SizedBox(height: 4),
                const Padding(padding: EdgeInsets.symmetric(horizontal: 24), child: Text(S.aiVuotoSub, textAlign: TextAlign.center, style: TextStyle(fontSize: 12.5, color: Palette.text2))),
                const SizedBox(height: 14),
                FilledButton.icon(onPressed: _import, icon: const Icon(Icons.add_photo_alternate_outlined), label: const Text(S.importaIcona)),
              ]),
            )
          : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Expanded(
                child: Center(
                  child: AspectRatio(
                    aspectRatio: 1,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: BeforeAfter(
                        before: Padding(padding: const EdgeInsets.all(16), child: IconImage(bytes: it.original)),
                        after: busy
                            ? const Center(child: CircularProgressIndicator())
                            : it.result != null
                                ? IconImage(bytes: it.result)
                                : Center(child: Text(it.error ?? S.nessunaGenerazione, textAlign: TextAlign.center, style: TextStyle(color: it.error != null ? Palette.danger : Palette.text3))),
                      ),
                    ),
                  ),
                ),
              ),
              if (it.error != null && it.result != null) Text(it.error!, style: const TextStyle(color: Palette.danger, fontSize: 12)),
              if (it.versions.length > 1)
                SizedBox(
                  height: 56,
                  child: ListView(scrollDirection: Axis.horizontal, clipBehavior: Clip.none, children: [
                    for (var v = 0; v < it.versions.length; v++)
                      GestureDetector(
                        onTap: () => setState(() => it.current = v),
                        child: Container(
                          width: 48,
                          margin: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            border: Border.all(color: v == it.current ? Theme.of(context).colorScheme.primary : Colors.transparent),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: IconImage(bytes: it.versions[v]),
                        ),
                      ),
                  ]),
                ),
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 8, children: [
                OutlinedButton.icon(
                  onPressed: it.result == null ? null : () => setState(() => it.accepted = true),
                  icon: const Icon(Icons.check),
                  label: Text(it.accepted == true ? S.accettata : S.accetta),
                ),
                OutlinedButton.icon(
                  onPressed: it.result == null
                      ? null
                      : () => setState(() {
                            it.versions.removeAt(it.current);
                            it.current = it.versions.length - 1;
                            it.accepted = false;
                          }),
                  icon: const Icon(Icons.close),
                  label: const Text(S.rifiuta),
                ),
                OutlinedButton.icon(onPressed: it.result == null ? null : _save, icon: const Icon(Icons.download_outlined), label: const Text(S.salva)),
                IconButton(
                  tooltip: S.ingrandisci,
                  onPressed: it.result == null ? null : () => showZoom(context, bytes: it.result, title: it.name),
                  icon: const Icon(Icons.zoom_in),
                ),
              ]),
            ]),
    );

    final controls = Glass(
      padding: EdgeInsets.zero,
      child: ListView(padding: const EdgeInsets.all(16), children: [
        const SectionTitle(S.tema),
        DropdownButtonFormField<String>(
          initialValue: theme,
          isExpanded: true,
          items: [for (final k in aiThemes.keys) DropdownMenuItem(value: k, child: Text(k))],
          onChanged: (v) => setState(() => theme = v!),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: custom,
          minLines: 2,
          maxLines: 4,
          decoration: InputDecoration(hintText: theme == S.personalizzato ? S.descriviStileDesiderato : S.istruzioniAggiuntiveOpzionale),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: const Text(S.normalizzaSulBaseNothingTranslucent, style: TextStyle(fontSize: 13)),
          subtitle: const Text(S.isolaGlyphGeneratoComponeCalibrazione, style: TextStyle(fontSize: 11)),
          value: compose,
          onChanged: (v) => setState(() => compose = v),
        ),
        const SizedBox(height: 8),
        FilledButton.icon(
          onPressed: it == null || busy || configured != true ? null : () => _generate(regenerate: false),
          icon: const Icon(Icons.auto_awesome),
          label: const Text(S.genera),
        ),
        const SizedBox(height: 18),
        const SectionTitle(S.rigenera),
        TextField(controller: comment, minLines: 2, maxLines: 4, decoration: const InputDecoration(hintText: S.commentoCosaCambiareRispettoAl)),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: it?.result == null || busy || configured != true ? null : () => _generate(regenerate: true),
          icon: const Icon(Icons.refresh),
          label: const Text(S.rigeneraDallaVersioneCorrente),
        ),
        const SizedBox(height: 18),
        const SectionTitle(S.provider),
        Text(S.modello(info.name, AppState.I.ai.model), style: const TextStyle(fontSize: 12)),
        const SizedBox(height: 4),
        Text(info.costNote, style: const TextStyle(fontSize: 11, color: Palette.text3)),
      ]),
    );

    if (wide) {
      return Padding(
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(S.aiIconTheme, style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 12),
          banner,
          if (configured == false) const SizedBox(height: 12),
          Expanded(
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              SizedBox(width: 260, child: list),
              const SizedBox(width: 16),
              Expanded(child: preview),
              const SizedBox(width: 16),
              SizedBox(
                width: 340,
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Expanded(child: controls),
                  const SizedBox(height: 12),
                  const SizedBox(height: 300, child: SingleChildScrollView(child: _LocalModelsCard())),
                ]),
              ),
            ]),
          ),
        ]),
      );
    }
    // phones: two clear tabs, the online theme generator and the local AI
    final tabs = SizedBox(
      width: double.infinity,
      child: SegmentedButton<int>(
        key: const ValueKey('ai-tabs'),
        showSelectedIcon: false,
        segments: const [
          ButtonSegment(value: 0, icon: Icon(Icons.cloud_outlined), label: Text(S.aiTabOnline)),
          ButtonSegment(value: 1, icon: Icon(Icons.memory_rounded), label: Text(S.aiTabLocale)),
        ],
        selected: {tab},
        onSelectionChanged: (v) => setState(() => tab = v.first),
      ),
    );
    if (tab == 1) {
      return SafeArea(
        bottom: false,
        child: ListView(padding: EdgeInsets.fromLTRB(20, 12, 20, 12 + GlassInsets.of(context)), children: [
          const LargeHeader(S.aiIconTheme, subtitle: S.aiSottotitolo),
          tabs,
          const SizedBox(height: 12),
          const Text(S.aiLocaleCosaFa, style: TextStyle(fontSize: 13, color: Palette.text2)),
          const SizedBox(height: 12),
          const _LocalModelsCard(),
        ]),
      );
    }
    return SafeArea(
      bottom: false,
      child: ListView(padding: EdgeInsets.fromLTRB(20, 12, 20, 12 + GlassInsets.of(context)), children: [
        LargeHeader(
          S.aiIconTheme,
          subtitle: S.aiSottotitolo,
          trailing: items.isEmpty ? null : GlassIconButton(onPressed: _import, size: 44, tooltip: S.importaIcona, icon: Icons.add_rounded),
        ),
        tabs,
        const SizedBox(height: 8),
        banner,
        const SizedBox(height: 8),
        if (items.isNotEmpty)
          SizedBox(
            height: 64,
            child: ListView(scrollDirection: Axis.horizontal, clipBehavior: Clip.none, children: [
              for (var i = 0; i < items.length; i++)
                GestureDetector(
                  onTap: () => setState(() => sel = i),
                  child: Container(
                    width: 56,
                    margin: const EdgeInsets.all(4),
                    decoration: BoxDecoration(border: Border.all(color: i == sel ? Theme.of(context).colorScheme.primary : Colors.white12), borderRadius: BorderRadius.circular(10)),
                    child: IconImage(bytes: items[i].result ?? items[i].original),
                  ),
                ),
            ]),
          ),
        SizedBox(height: 420, child: preview),
        const SizedBox(height: 12),
        SizedBox(height: 560, child: controls),
      ]),
    );
  }
}


/// Local background-removal models (download / delete / choose) in the AI tab.
class _LocalModelsCard extends StatelessWidget {
  const _LocalModelsCard();

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppState.I,
      builder: (context, _) {
        final st = AppState.I;
        final ready = st.modelReady(st.localAi.model);
        return StepCard(
          key: const ValueKey('ai-local-models'),
          step: 0,
          title: S.aiModelliLocali,
          subtitle: S.aiModelliLocaliInfo,
          children: [
            SizedBox(
              width: double.infinity,
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                // optional: the classic algorithm stays the default
                SettingSwitch(
                  key: const ValueKey('ai-local-use'),
                  title: S.aiUsaLocale,
                  subtitle: ready ? S.aiUsaLocaleSub : S.aiModelloMancante,
                  value: st.bgProvider == BgProvider.localAi,
                  onChanged: ready || st.bgProvider == BgProvider.localAi
                      ? (v) => st.update(() => st.bgProvider = v ? BgProvider.localAi : BgProvider.local)
                      : null,
                ),
                const LocalAiBox(),
              ]),
            ),
          ],
        );
      },
    );
  }
}
