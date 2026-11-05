import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icon_formatter/screens/pack_builder_screen.dart';
import 'package:icon_formatter/src/rust/api/engine.dart';
import 'package:icon_formatter/widgets/toasts.dart';

Future<void> frames(WidgetTester t) async {
  for (var i = 0; i < 20; i++) {
    await t.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  Widget app() => MaterialApp(builder: (c, child) => ToastHost(child: child!), home: const Scaffold(body: SizedBox.expand()));

  testWidgets('notices appear at the top and leave with a sideways swipe', (t) async {
    await t.pumpWidget(app());
    var work = 0;
    // a "job" running while notices come and go
    void tick() {
      if (++work < 20) Future.delayed(const Duration(milliseconds: 100), tick);
    }
    tick();
    Toasts.show('Prima notifica');
    Toasts.show('Seconda notifica');
    await frames(t);
    expect(find.text('Prima notifica'), findsOneWidget);
    // top of the screen
    expect(t.getTopLeft(find.text('Prima notifica')).dy, lessThan(120));

    await t.fling(find.text('Prima notifica'), const Offset(400, 0), 1500);
    await frames(t);
    expect(find.text('Prima notifica'), findsNothing);
    expect(find.text('Seconda notifica'), findsOneWidget);
    await t.fling(find.text('Seconda notifica'), const Offset(-400, 0), 1500);
    await frames(t);
    expect(Toasts.items.value, isEmpty);

    // removing notices does not stop the work that is running
    await t.pump(const Duration(seconds: 3));
    expect(work, 20);
  });

  testWidgets('notices close by themselves', (t) async {
    await t.pumpWidget(app());
    Toasts.show('Breve');
    await frames(t);
    expect(find.text('Breve'), findsOneWidget);
    await t.pump(const Duration(seconds: 5));
    await frames(t);
    expect(find.text('Breve'), findsNothing);
  });

  test('pack states: matched, to check, doubtful, missing', () {
    PbRow row(MatchState s, {String? g}) => PbRow(PbIcon(id: 'o', package: 'com.x'))
      ..generatedId = g
      ..auto = s;
    expect(row(MatchState.confident, g: 'g').state, PbState.confident);
    expect(row(MatchState.review, g: 'g').state, PbState.review);
    expect(row(MatchState.doubtful, g: 'g').state, PbState.doubtful);
    expect(row(MatchState.missing).state, PbState.missing);
    expect((row(MatchState.doubtful, g: 'g')..custom = true).state, PbState.verified);
  });
}
