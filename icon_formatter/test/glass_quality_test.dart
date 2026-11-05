import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icon_formatter/app/models.dart';
import 'package:icon_formatter/app/state.dart';
import 'package:icon_formatter/widgets/liquid_glass.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

/// Every glass quality must render the app's glass surfaces (static and
/// live) without throwing, including "Qualità" (premium) on renderers that
/// have no shader filters (Windows/Skia, the test renderer).
void main() {
  for (final q in GlassQualityLevel.values) {
    testWidgets('glass renders with quality ${q.name}', (t) async {
      AppState.I.glass.quality = q;
      await t.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Stack(children: [
            const Positioned.fill(child: ColoredBox(color: Colors.black)),
            const Positioned(left: 20, top: 20, width: 200, height: 80, child: LiquidGlass(child: Text('statico'))),
            const Positioned(left: 20, top: 120, width: 200, height: 80, child: LiquidGlass(live: true, child: Text('vivo'))),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: GlassTabBar.bottom(
                selectedIndex: 0,
                onTabSelected: (_) {},
                settings: appGlassSettings(),
                quality: appGlassQuality,
                tabs: const [GlassTab(icon: Icon(Icons.home), label: 'A'), GlassTab(icon: Icon(Icons.settings), label: 'B')],
              ),
            ),
          ]),
        ),
      ));
      for (var i = 0; i < 5; i++) {
        await t.pump(const Duration(milliseconds: 50));
      }
      expect(t.takeException(), isNull);
      expect(find.text('vivo'), findsOneWidget);
    });
  }
}
