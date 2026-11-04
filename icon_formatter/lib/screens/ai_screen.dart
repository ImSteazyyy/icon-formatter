import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../app/state.dart';
import '../app/theme.dart';
import '../services/ai_service.dart';
import '../services/export_service.dart';
import '../src/rust/api/engine.dart';
import '../widgets/common.dart';
import '../widgets/liquid_glass.dart';

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
      showMsg(context, 'AI non configurata: imposta provider e API key.', error: true);
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
        ? Glass(
            padding: const EdgeInsets.all(12),
            child: Row(children: [
              const Icon(Icons.key_off_outlined, color: Palette.warn),
              const SizedBox(width: 10),
              const Expanded(child: Text('AI non configurata. Nessuna generazione viene simulata: configura provider e API key.')),
              TextButton(onPressed: widget.onOpenSettings, child: const Text('Configura')),
            ]),
          )
        : const SizedBox.shrink();

    final list = Glass(
      padding: const EdgeInsets.all(8),
      child: Column(children: [
        Row(children: [
          const Expanded(child: SectionTitle('Icone')),
          IconButton(tooltip: 'Importa', onPressed: _import, icon: const Icon(Icons.add)),
        ]),
        Expanded(
          child: items.isEmpty
              ? const Center(child: Text('Importa una o più icone', style: TextStyle(color: Palette.text3)))
              : ListView.builder(
                  itemCount: items.length,
                  itemBuilder: (_, i) => ListTile(
                    selected: i == sel,
                    leading: SizedBox(width: 36, height: 36, child: IconImage(bytes: items[i].result ?? items[i].original)),
                    title: Text(items[i].name, overflow: TextOverflow.ellipsis),
                    subtitle: Text(
                      items[i].accepted == true ? 'accettata' : (items[i].versions.isEmpty ? 'da generare' : '${items[i].versions.length} versioni'),
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
          ? const Center(child: Text('Nessuna icona selezionata', style: TextStyle(color: Palette.text3)))
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
                                : Center(child: Text(it.error ?? 'Nessuna generazione', textAlign: TextAlign.center, style: TextStyle(color: it.error != null ? Palette.danger : Palette.text3))),
                      ),
                    ),
                  ),
                ),
              ),
              if (it.error != null && it.result != null) Text(it.error!, style: const TextStyle(color: Palette.danger, fontSize: 12)),
              if (it.versions.length > 1)
                SizedBox(
                  height: 56,
                  child: ListView(scrollDirection: Axis.horizontal, children: [
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
                  label: Text(it.accepted == true ? 'Accettata' : 'Accetta'),
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
                  label: const Text('Rifiuta'),
                ),
                OutlinedButton.icon(onPressed: it.result == null ? null : _save, icon: const Icon(Icons.download_outlined), label: const Text('Salva')),
                IconButton(
                  tooltip: 'Ingrandisci',
                  onPressed: it.result == null ? null : () => showZoom(context, bytes: it.result, title: it.name),
                  icon: const Icon(Icons.zoom_in),
                ),
              ]),
            ]),
    );

    final controls = Glass(
      padding: EdgeInsets.zero,
      child: ListView(padding: const EdgeInsets.all(16), children: [
        const SectionTitle('Tema'),
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
          decoration: InputDecoration(hintText: theme == 'Personalizzato' ? 'Descrivi lo stile desiderato' : 'Istruzioni aggiuntive (opzionale)'),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: const Text('Normalizza sul base Nothing Translucent', style: TextStyle(fontSize: 13)),
          subtitle: const Text('Isola il glyph generato e lo compone con la calibrazione', style: TextStyle(fontSize: 11)),
          value: compose,
          onChanged: (v) => setState(() => compose = v),
        ),
        const SizedBox(height: 8),
        FilledButton.icon(
          onPressed: it == null || busy || configured != true ? null : () => _generate(regenerate: false),
          icon: const Icon(Icons.auto_awesome),
          label: const Text('Genera'),
        ),
        const SizedBox(height: 18),
        const SectionTitle('Rigenera'),
        TextField(controller: comment, minLines: 2, maxLines: 4, decoration: const InputDecoration(hintText: 'Commento: cosa cambiare rispetto al risultato precedente')),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: it?.result == null || busy || configured != true ? null : () => _generate(regenerate: true),
          icon: const Icon(Icons.refresh),
          label: const Text('Rigenera dalla versione corrente'),
        ),
        const SizedBox(height: 18),
        const SectionTitle('Provider'),
        Text('${info.name} · modello ${AppState.I.ai.model}', style: const TextStyle(fontSize: 12)),
        const SizedBox(height: 4),
        Text(info.costNote, style: const TextStyle(fontSize: 11, color: Palette.text3)),
      ]),
    );

    if (wide) {
      return Padding(
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('AI Icon Theme', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 12),
          banner,
          if (configured == false) const SizedBox(height: 12),
          Expanded(
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              SizedBox(width: 260, child: list),
              const SizedBox(width: 16),
              Expanded(child: preview),
              const SizedBox(width: 16),
              SizedBox(width: 340, child: controls),
            ]),
          ),
        ]),
      );
    }
    return SafeArea(
      bottom: false,
      child: ListView(padding: EdgeInsets.fromLTRB(12, 12, 12, 12 + GlassInsets.of(context)), children: [
        Row(children: [
          Expanded(child: Text('AI Icon Theme', style: Theme.of(context).textTheme.titleLarge)),
          IconButton(onPressed: _import, icon: const Icon(Icons.add_photo_alternate_outlined)),
        ]),
        banner,
        const SizedBox(height: 8),
        if (items.isNotEmpty)
          SizedBox(
            height: 64,
            child: ListView(scrollDirection: Axis.horizontal, children: [
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
