import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icon_formatter/widgets/glassfix_premium_gate.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

void main() {
  testWidgets('premium surfaces are admitted a few per frame', (tester) async {
    const count = 8;
    final last = List<GlassQuality?>.filled(count, null);
    await tester.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: Column(children: [
        for (var i = 0; i < count; i++)
          GlassStagedQuality(
            quality: GlassQuality.premium,
            builder: (q) {
              last[i] = q;
              return const SizedBox();
            },
          ),
      ]),
    ));
    // the first build draws standard everywhere
    expect(last.every((q) => q == GlassQuality.standard), isTrue);

    await tester.pump();
    final admitted = last.where((q) => q == GlassQuality.premium).length;
    expect(admitted, lessThanOrEqualTo(GlassPremiumGate.perFrame));
    expect(admitted, greaterThan(0));

    await tester.pumpAndSettle();
    expect(last.every((q) => q == GlassQuality.premium), isTrue);
  });
}
