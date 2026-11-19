import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/state.dart';
import '../app/theme.dart';
import '../l10n/strings.dart';
import '../widgets/liquid_glass.dart';

/// After an app version change: shows the notes once. A fresh install only
/// records the version. Called once after the first frame.
void checkWhatsNew(BuildContext context, String version) {
  final st = AppState.I;
  if (st.lastSeenBuild == version) return;
  final fresh = st.lastSeenBuild.isEmpty;
  st.update(() => st.lastSeenBuild = version);
  if (!fresh) showWhatsNew(context);
}

/// Opens the notes in the app language (Italian, es/fr/de/pt, or English as fallback).
Future<void> showWhatsNew(BuildContext context) async {
  final lang = AppState.I.appearance.languageCode;
  const translated = {'es', 'fr', 'de', 'pt'};
  final file = lang == 'it' ? 'whats_new.md' : (translated.contains(lang) ? 'whats_new_$lang.md' : 'whats_new_en.md');
  var text = '';
  try {
    // read only now, when the sheet is about to open
    text = await rootBundle.loadString('assets/$file');
  } catch (_) {
    // no notes to show
  }
  if (!context.mounted) return;
  final lines = [for (final l in text.split('\n')) if (l.trim().isNotEmpty) l.trim()];
  await showAppSheet<void>(
    context: context,
    builder: (ctx) => Padding(
      padding: const EdgeInsets.fromLTRB(22, 4, 22, 26),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(S.extra2NovitaTitolo, style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700, color: Palette.text)),
            const SizedBox(height: 12),
            for (final l in lines)
              if (l.startsWith('#'))
                const SizedBox.shrink()
              else if (l.startsWith('- '))
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('• ', style: TextStyle(fontSize: 14, color: Palette.text2)),
                    Expanded(child: Text(l.substring(2), style: TextStyle(fontSize: 14, color: Palette.text2))),
                  ]),
                )
              else
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(l, style: TextStyle(fontSize: 14, color: Palette.text2)),
                ),
          ],
        ),
      ),
    ),
  );
}
