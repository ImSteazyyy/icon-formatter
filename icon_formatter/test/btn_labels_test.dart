import 'dart:io';

import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icon_formatter/l10n/strings.dart';
import 'package:icon_formatter/widgets/common.dart';

// Phone 360 dp: page padding 20 per side, StepCard padding 14 per side,
// two columns of ButtonRows with an 8 dp gap.
const double _cardInner = 360 - 2 * 20 - 2 * 14;
const double _halfWidth = (_cardInner - 8) / 2;
// Label budget = button width minus padding both sides, icon and gap.
const double _twoPerRowText = _halfWidth - 2 * kToolButtonPadding - kToolButtonIconSize - kToolButtonIconGap;
// A lone button in a ButtonRows spans the whole card inner width.
const double _loneText = _cardInner - 2 * kToolButtonPadding - kToolButtonIconSize - kToolButtonIconGap;
// Dialog actions (pack builder detail sheet): OutlinedButton, padding 10 per side,
// icon 18, gap 6, two per row in an assumed 312 dp dialog.
const double _dialogText = (((312 - 2 * 22) - 8) / 2) - 2 * 10 - 18 - 6;
// The variable Inter font may measure a little wider at w500 on device than in the test.
const double _margin = 2;

// Every ToolButton label of the app, by S key. Counts use 128 (3 digits, the worst case).
final _twoPerRow = <String, String Function()>{
  'importaBase': () => S.importaBase,
  'creaDaPreset': () => S.creaDaPreset,
  'pbAggiornaCatalogo': () => S.pbAggiornaCatalogo,
  'pbDaFile': () => S.pbDaFile,
  'pbOriginali': () => S.pbOriginali,
  'pbGeneraDaStudio': () => S.pbGeneraDaStudio,
  'pbImportaGenerate': () => S.pbImportaGenerate,
  'pbApriPack': () => S.pbApriPack,
  'pbAbbina': () => S.pbAbbina,
  'packMancanti(128)': () => S.packMancanti(128),
  'pbEsporta': () => S.pbEsporta,
  'anteprimaHome': () => S.anteprimaHome,
  'pack2Anteprima': () => S.pack2Anteprima,
  'pbCondividiApk': () => S.pbCondividiApk,
  'apkCrea': () => S.apkCrea,
  'packQualita': () => S.packQualita,
  'pack3Conflitti': () => S.pack3Conflitti,
  'btnRegistro': () => S.btnRegistro,
  'packProfili': () => S.packProfili,
  'pbScegliImmagine': () => S.pbScegliImmagine,
  'pbCambiaImmagine': () => S.pbCambiaImmagine,
  'calAggiornaOra': () => S.calAggiornaOra,
  'asControllaOra': () => S.asControllaOra,
  'wireAppIgnorate': () => S.wireAppIgnorate,
  'wireAppIgnorateN(128)': () => S.wireAppIgnorateN(128),
  'asSegnaViste': () => S.asSegnaViste,
  'asRielabora(128)': () => S.asRielabora(128),
  'apriCartella': () => S.apriCartella,
  'apriZip': () => S.apriZip,
  // Studio toolbar: a Wrap on medium layouts (bounded, half width each)
  'aggiungi': () => S.aggiungi,
  'svuota': () => S.svuota,
  'btnAnnulla': () => S.btnAnnulla,
  'btnRipristina': () => S.btnRipristina,
  'btnDuplicati': () => S.btnDuplicati,
};

final _lone = <String, String Function()>{
  'stile': () => S.stile,
};

final _dialog = <String, String Function()>{
  'btnScegliIcona': () => S.btnScegliIcona,
  'btnRielabora': () => S.btnRielabora,
  'btnSegnaVerificata': () => S.btnSegnaVerificata,
  'btnEscludi': () => S.btnEscludi,
  'pack2UsaPerAltre': () => S.pack2UsaPerAltre,
  'pack2Rinomina': () => S.pack2Rinomina,
  'pack3Suggerisci': () => S.pack3Suggerisci,
};

double _width(String text) {
  final tp = TextPainter(
    text: TextSpan(
      text: text,
      style: const TextStyle(fontFamily: 'Inter', fontSize: kToolButtonFontSize, fontWeight: FontWeight.w500),
    ),
    textDirection: TextDirection.ltr,
    maxLines: 1,
  )..layout();
  final w = tp.width;
  tp.dispose();
  return w;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    final loader = FontLoader('Inter');
    final bytes = await File('assets/fonts/Inter-Variable.ttf').readAsBytes();
    loader.addFont(Future.value(ByteData.sublistView(Uint8List.fromList(bytes))));
    await loader.load();
  });

  test('every ToolButton label fits its slot at the same size in every language', () {
    final offenders = <String>[];
    void check(String code, String slot, Map<String, String Function()> labels, double budget) {
      final limit = budget - _margin;
      labels.forEach((key, text) {
        final t = text();
        final w = _width(t);
        if (w > limit) offenders.add('[$code] $slot $key "$t": ${w.toStringAsFixed(1)} > ${limit.toStringAsFixed(1)} px');
      });
    }

    for (final code in appLanguages.keys) {
      S.current = stringsFor(code);
      check(code, 'two-per-row', _twoPerRow, _twoPerRowText);
      check(code, 'lone', _lone, _loneText);
      check(code, 'dialog', _dialog, _dialogText);
    }
    S.current = stringsFor('it');
    expect(offenders, isEmpty, reason: 'labels too wide:\n${offenders.join('\n')}');
  });
}
