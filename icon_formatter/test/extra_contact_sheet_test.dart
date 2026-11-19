import 'package:flutter_test/flutter_test.dart';
import 'package:icon_formatter/services/extra_contact_sheet.dart';

void main() {
  test('no icons: one empty row, no pages', () {
    expect(contactSheetPages(0), isEmpty);
    expect(contactSheetLayout(0).rows, 1);
  });

  test('fewer than 6 icons: one row, as many columns as icons', () {
    final l = contactSheetLayout(3);
    expect(l.columns, 3);
    expect(l.rows, 1);
    expect(l.width, 3 * l.cellWidth);
    expect(l.height, l.cellHeight);
  });

  test('6 or more icons: 6 columns, rows round up', () {
    final l = contactSheetLayout(13);
    expect(l.columns, 6);
    expect(l.rows, 3);
    expect(l.height, 3 * l.cellHeight);
    expect(contactSheetLayout(12).rows, 2);
  });

  test('cell fits the icon and its label', () {
    final l = contactSheetLayout(6);
    expect(l.cellWidth, greaterThan(contactSheetIcon));
    expect(l.cellHeight, greaterThan(contactSheetIcon));
  });

  test('pages: split at 96, total capped at 400', () {
    expect(contactSheetPages(96), [96]);
    expect(contactSheetPages(97), [96, 1]);
    expect(contactSheetPages(250), [96, 96, 58]);
    final capped = contactSheetPages(1000);
    expect(capped.fold<int>(0, (a, b) => a + b), contactSheetMaxIcons);
    expect(capped.every((n) => n <= contactSheetPerSheet), isTrue);
  });
}
