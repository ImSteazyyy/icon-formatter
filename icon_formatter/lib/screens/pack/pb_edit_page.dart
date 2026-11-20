import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../app/state.dart';
import '../../workspace/adjust_panel.dart';
import '../../workspace/workspace_controller.dart';
import '../../app/storage.dart';
import '../../app/theme.dart';
import '../../l10n/strings.dart';
import '../../widgets/common.dart';
import '../../widgets/liquid_glass.dart';
import 'pb_model.dart';
import 'pb_controller.dart';
import 'pb_treatment_picker.dart';

/// Edge of the treatment thumbnails, in engine pixels (shown at 60 dp).
const int _kThumbPx = 128;

/// "Edit icon": pick an image, process it with the pack pipeline,
/// compare Before/After, then confirm (returns the PNG) or cancel (null).
class IconEditPage extends StatefulWidget {
  const IconEditPage({
    super.key,
    required this.controller,
    required this.row,
    this.initialSource,
    this.pickSource,
  });

  final PackBuilderController controller;
  final PbRow row;

  /// Test seams: a source already chosen, and a replacement for the file dialog.
  final String? initialSource;
  final Future<String?> Function()? pickSource;

  @override
  State<IconEditPage> createState() => _IconEditPageState();
}

class _IconEditPageState extends State<IconEditPage> {
  /// The pack's generation settings (same panel as Studio > Personalizza).
  late final WorkspaceController _style = WorkspaceController(
    tag: 'edit',
    mode: AppState.I.packMode,
    packSettings: true,
  );

  /// Thumbnails of the picked image per treatment, rendered on first use.
  /// Cleared when the image or the pack settings change.
  final Map<EditTreatment, Future<Uint8List>> _thumbs = {};

  @override
  void initState() {
    super.initState();
    source = widget.initialSource;
    if (source != null)
      WidgetsBinding.instance.addPostFrameCallback((_) => _render());
  }

  @override
  void dispose() {
    _style.dispose();
    super.dispose();
  }

  Future<void> _openStyle() async {
    await showAppSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => SizedBox(
        height: MediaQuery.of(ctx).size.height * 0.80,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 4),
              child: Text(
                S.stileTitolo,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: Palette.text,
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(
                S.stileSpiegazioneModifica,
                style: TextStyle(fontSize: 13, color: Palette.text2),
              ),
            ),
            Expanded(child: AdjustPanel(c: _style)),
          ],
        ),
      ),
    );
    // the new settings apply to the icon right away
    _thumbs.clear();
    await _render();
  }

  String? source;
  EditTreatment treatment = EditTreatment.auto;
  Uint8List? result;
  bool working = false;
  String? error;
  int _seq = 0;

  Future<String?> _chooseFile() async {
    final r = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['png', 'jpg', 'jpeg', 'webp'],
    );
    return r?.files.single.path;
  }

  Future<void> _pickImage() async {
    final path = await (widget.pickSource ?? _chooseFile)();
    if (path == null) return;
    // the picked file may be a temporary copy: keep our own one
    final dest = p.join(
      await AppPaths.I.workDir('edit'),
      'source${p.extension(path).toLowerCase()}',
    );
    await File(path).copy(dest);
    setState(() {
      source = dest;
      _thumbs.clear();
    });
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

  Future<Uint8List> _thumb(EditTreatment t) => _thumbs.putIfAbsent(
    t,
    () => widget.controller.renderEditThumb(source!, t, _kThumbPx),
  );

  /// No image yet: a muted placeholder and the hint, no before/after split.
  Widget _emptyPreview() => Center(
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(color: Palette.fg.withValues(alpha: 0.06), borderRadius: BorderRadius.circular(12)),
                child: Icon(Icons.image_outlined, size: 20, color: Palette.text3),
              ),
              const SizedBox(height: 6),
              Text(
                S.pbScegliImmagineHint,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 13, color: Palette.text2),
              ),
            ],
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final row = widget.row;
    final current = widget.controller.generatedById(row.generatedId);
    final before = current ?? row.original;
    return Scaffold(
      body: Backdrop(
        child: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 4),
                  children: [
                    LargeHeader(
                      S.pbModificaIcona,
                      subtitle:
                          '${row.original.title}${row.original.package.isEmpty ? '' : ' · ${row.original.package}'}',
                      onBack: () => Navigator.pop(context),
                    ),
                    Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 360),
                        child: AspectRatio(
                          aspectRatio: 2.9,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(20),
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                if (source == null)
                                  _emptyPreview()
                                else
                                BeforeAfter(
                                  key: const ValueKey('edit-before-after'),
                                  before: Padding(
                                    padding: const EdgeInsets.all(18),
                                    child: IconImage(
                                      bytes: before.bytes,
                                      path: before.path,
                                    ),
                                  ),
                                  after: Padding(
                                    padding: const EdgeInsets.all(18),
                                    child: result == null
                                        ? Center(
                                            child: Text(
                                              S.pbScegliImmagineHint,
                                              textAlign: TextAlign.center,
                                              style: TextStyle(
                                                color: Palette.text3,
                                              ),
                                            ),
                                          )
                                        : IconImage(bytes: result),
                                  ),
                                ),
                                if (working)
                                  const Center(
                                    child: CircularProgressIndicator(),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    if (error != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          error!,
                          style: TextStyle(color: Palette.danger, fontSize: 12),
                        ),
                      ),
                    const SizedBox(height: 10),
                    ButtonRows(
                      children: [
                        ToolButton(
                          key: const ValueKey('edit-pick'),
                          icon: Icons.photo_library_outlined,
                          label: source == null
                              ? S.pbScegliImmagine
                              : S.pbCambiaImmagine,
                          onTap: working ? null : _pickImage,
                        ),
                        ToolButton(
                          key: const ValueKey('edit-style'),
                          icon: Icons.tune_rounded,
                          label: S.stile,
                          onTap: working ? null : _openStyle,
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      source == null ? S.ux1bPickFirst : S.pbEditComeAppare,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Palette.text2,
                      ),
                    ),
                    const SizedBox(height: 6),
                    TreatmentPicker(
                      enabled: source != null,
                      value: treatment,
                      thumbnail: source == null ? null : _thumb,
                      onChanged: (v) {
                        setState(() => treatment = v);
                        _render();
                      },
                    ),
                  ],
                ),
              ),
              // confirm and cancel stay in view while the options scroll
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        key: const ValueKey('edit-cancel'),
                        onPressed: () => Navigator.pop(context),
                        child: Text(S.annulla),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton.icon(
                        key: const ValueKey('edit-confirm'),
                        icon: const Icon(Icons.check_rounded),
                        label: Text(S.pbConfermaSostituzione),
                        onPressed: result == null || working
                            ? null
                            : () => Navigator.pop(context, result),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
