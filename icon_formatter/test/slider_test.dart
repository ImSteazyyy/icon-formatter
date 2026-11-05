import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icon_formatter/app/models.dart';
import 'package:icon_formatter/widgets/common.dart';
import 'package:icon_formatter/src/rust/api/engine.dart';

void main() {
  group('SliderNumber', () {
    String pct(double v) => (v * 100).round().toString();
    String fixed2(double v) => v.toStringAsFixed(2);
    String deg(double v) => '${v.round()}°';

    test('percent display maps back to the value', () {
      final n = SliderNumber(pct, 0, 1, null);
      expect(n.valueOf('40')!.value, closeTo(0.40, 1e-9));
      expect(n.editText(0.4), '40');
    });

    test('comma decimals and precision', () {
      final n = SliderNumber(fixed2, 0.03, 0.30, null);
      expect(n.valueOf('0,12')!.value, closeTo(0.12, 1e-9));
      expect(n.editText(0.1), '0,10');
      expect(n.decimals(0.1), 2);
    });

    test('out of range is clamped and reported', () {
      final n = SliderNumber(pct, 0, 1, null);
      final r = n.valueOf('150')!;
      expect(r.value, 1.0);
      expect(r.clamped, isTrue);
      expect(n.valueOf('-5')!.value, 0.0);
    });

    test('suffixes are ignored, garbage rejected', () {
      final n = SliderNumber(deg, 0, 360, null);
      expect(n.valueOf('90°')!.value, closeTo(90, 1e-9));
      expect(n.valueOf('abc'), isNull);
    });

    test('divisions snap', () {
      final n = SliderNumber((v) => v.round().toString(), 0, 10, 10);
      expect(n.valueOf('3.4')!.value, 3);
    });
  });

  testWidgets('tap number, type, Enter commits; Esc cancels', (tester) async {
    var value = 0.4;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: StatefulBuilder(
          builder: (context, set) => SliderRow(label: 'Opacità', value: value, onChanged: (v) => set(() => value = v)),
        ),
      ),
    ));
    expect(find.text('40'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('slider-value')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('slider-edit')), '75');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(value, closeTo(0.75, 1e-9));
    expect(find.text('75'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('slider-value')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('slider-edit')), '10');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(value, closeTo(0.75, 1e-9), reason: 'Esc must not change the value');
  });

  test('Lucent and local AI settings persist', () {
    final l = LucentConfig()
      ..dark = false
      ..shape = LucentShape.circle
      ..backdropAlpha = 0.7
      ..glyphScale = 1.2;
    final l2 = LucentConfig()..load(l.toJson());
    expect(l2.dark, false);
    expect(l2.shape, LucentShape.circle);
    expect(l2.backdropAlpha, 0.7);
    expect(l2.glyphScale, 1.2);
    final a = LocalAiConfig()
      ..low = 0.2
      ..high = 0.7;
    final a2 = LocalAiConfig()..load(a.toJson());
    expect(a2.low, 0.2);
    expect(a2.high, 0.7);
  });
}
