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
  Widget app() => MaterialApp(
    navigatorObservers: [NoticeRouteObserver()],
    builder: (c, child) => ToastHost(child: child!),
    home: const Scaffold(body: SizedBox.expand()),
  );

  testWidgets('one notice at a time: a new one replaces the old, a repeat only restarts', (t) async {
    await t.pumpWidget(app());
    Toasts.show('First notice');
    Toasts.show('Second notice');
    await frames(t);
    expect(find.text('First notice'), findsNothing);
    expect(find.text('Second notice'), findsOneWidget);
    // the same notice again is not stacked
    Toasts.show('Second notice');
    await frames(t);
    expect(find.text('Second notice'), findsOneWidget);
    // above the bottom edge, at the bottom centre
    expect(t.getBottomLeft(find.text('Second notice')).dy, lessThan(t.view.physicalSize.height / t.view.devicePixelRatio));
    expect(t.getBottomLeft(find.text('Second notice')).dy, greaterThan(400));
    Toasts.dismiss();
    await frames(t);
  });

  testWidgets('a plain notice closes after 3 s, one with an action after 6 s', (t) async {
    await t.pumpWidget(app());
    Toasts.show('Breve');
    await frames(t);
    expect(find.text('Breve'), findsOneWidget);
    await t.pump(const Duration(seconds: 2));
    expect(find.text('Breve'), findsOneWidget);
    await t.pump(const Duration(seconds: 2));
    await frames(t);
    expect(find.text('Breve'), findsNothing);

    Toasts.show('Annullato', actionLabel: 'Annulla', onAction: () {});
    await frames(t);
    await t.pump(const Duration(seconds: 5));
    expect(find.text('Annullato'), findsOneWidget);
    await t.pump(const Duration(seconds: 2));
    await frames(t);
    expect(find.text('Annullato'), findsNothing);
    Toasts.dismiss();
    await frames(t);
  });

  testWidgets('a notice leaves with a swipe, an error with its x', (t) async {
    await t.pumpWidget(app());
    Toasts.show('Swipe me');
    await frames(t);
    await t.fling(find.text('Swipe me'), const Offset(400, 0), 1500);
    await frames(t);
    expect(find.text('Swipe me'), findsNothing);
    expect(Toasts.current.value, isNull);

    Toasts.show('Broken', kind: ToastKind.error);
    await frames(t);
    expect(find.byIcon(Icons.close_rounded), findsOneWidget);
    await t.tap(find.byIcon(Icons.close_rounded));
    expect(Toasts.current.value, isNull);
    await frames(t);
    expect(find.text('Broken'), findsNothing);
  });

  testWidgets('opening a route clears the notice and closes the keyboard', (t) async {
    final focus = FocusNode();
    final nav = GlobalKey<NavigatorState>();
    await t.pumpWidget(MaterialApp(
      navigatorKey: nav,
      navigatorObservers: [NoticeRouteObserver()],
      builder: (c, child) => ToastHost(child: child!),
      home: Scaffold(body: TextField(focusNode: focus, autofocus: true)),
    ));
    await frames(t);
    expect(focus.hasFocus, isTrue);
    Toasts.show('Visibile');
    await frames(t);
    expect(find.text('Visibile'), findsOneWidget);

    nav.currentState!.push(MaterialPageRoute(builder: (_) => const Scaffold(body: SizedBox())));
    await t.pumpAndSettle();
    expect(focus.hasFocus, isFalse);
    expect(Toasts.current.value, isNull);
    focus.dispose();
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
