import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

/// Grid of one contact sheet, in pixels.
class ContactSheetLayout {
  const ContactSheetLayout({required this.columns, required this.rows, required this.cellWidth, required this.cellHeight});

  final int columns;
  final int rows;
  final int cellWidth;
  final int cellHeight;

  int get width => columns * cellWidth;
  int get height => rows * cellHeight;
}

const contactSheetIcon = 128;
const contactSheetColumns = 6;
const contactSheetPerSheet = 96; // 16 rows: keeps the sheet well under texture limits
const contactSheetMaxIcons = 400;
const _gap = 12;
const _labelHeight = 16;

/// Grid for [count] icons on one sheet: up to 6 columns, fewer when there are
/// fewer icons. Pure, so it can be tested without drawing anything.
ContactSheetLayout contactSheetLayout(int count) {
  final columns = count < 1 ? 1 : (count < contactSheetColumns ? count : contactSheetColumns);
  final rows = count < 1 ? 1 : (count + columns - 1) ~/ columns;
  return ContactSheetLayout(
    columns: columns,
    rows: rows,
    cellWidth: contactSheetIcon + 2 * _gap,
    cellHeight: _gap + contactSheetIcon + 4 + _labelHeight + _gap,
  );
}

/// Icons per sheet, in order: the total is capped at [contactSheetMaxIcons]
/// and split into sheets of at most [contactSheetPerSheet].
List<int> contactSheetPages(int count) {
  var left = count.clamp(0, contactSheetMaxIcons).toInt();
  final pages = <int>[];
  while (left > 0) {
    final n = left < contactSheetPerSheet ? left : contactSheetPerSheet;
    pages.add(n);
    left -= n;
  }
  return pages;
}

/// Draws one sheet as PNG. Each icon is decoded at 128 px by the engine, one at
/// a time; the loop yields after every row so frames keep flowing.
/// shortcut: drawing runs on the UI isolate, fine for <= 96 small icons per
/// sheet; move to a Rust function if sheets grow.
Future<Uint8List?> renderContactSheet(List<({String name, Uint8List png})> icons) async {
  if (icons.isEmpty) return null;
  final layout = contactSheetLayout(icons.length);
  final w = layout.width.toDouble(), h = layout.height.toDouble();
  final rec = ui.PictureRecorder();
  final canvas = ui.Canvas(rec, ui.Rect.fromLTWH(0, 0, w, h));
  canvas.drawRect(ui.Rect.fromLTWH(0, 0, w, h), ui.Paint()..color = const Color(0xFF111114));
  final labelStyle = const TextStyle(fontSize: 11, color: Color(0xFFD6D6DC));

  for (var i = 0; i < icons.length; i++) {
    final col = i % layout.columns;
    final row = i ~/ layout.columns;
    final x = (col * layout.cellWidth).toDouble();
    final y = (row * layout.cellHeight).toDouble();

    final codec = await ui.instantiateImageCodec(icons[i].png, targetWidth: contactSheetIcon);
    final img = (await codec.getNextFrame()).image;
    canvas.drawImageRect(
      img,
      ui.Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
      ui.Rect.fromLTWH(x + _gap, y + _gap, contactSheetIcon.toDouble(), contactSheetIcon.toDouble()),
      ui.Paint()..filterQuality = ui.FilterQuality.medium,
    );
    img.dispose();
    codec.dispose();

    final label = TextPainter(
      text: TextSpan(text: icons[i].name, style: labelStyle),
      maxLines: 1,
      ellipsis: '…',
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: layout.cellWidth - 8.0);
    label.paint(canvas, ui.Offset(x + 4, y + _gap + contactSheetIcon + 4));
    label.dispose();

    if (col == layout.columns - 1) await Future.delayed(Duration.zero);
  }

  final picture = rec.endRecording();
  final out = await picture.toImage(w.toInt(), h.toInt());
  final data = await out.toByteData(format: ui.ImageByteFormat.png);
  picture.dispose();
  out.dispose();
  return data?.buffer.asUint8List();
}
