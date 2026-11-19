import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Shortcuts must keep working after a text field loses focus (the Shell layout).
void main() {
  testWidgets('Ctrl+1 still fires after a text field is unfocused', (tester) async {
    var hits = 0;
    await tester.pumpWidget(MaterialApp(
      home: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.digit1, control: true): () => hits++,
        },
        // same wrapper as the desktop Shell
        child: FocusScope(
          autofocus: true,
          child: const Scaffold(body: Center(child: TextField())),
        ),
      ),
    ));
    await tester.pump();

    await tester.tap(find.byType(TextField));
    await tester.pump();
    FocusManager.instance.primaryFocus!.unfocus();
    await tester.pump();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.digit1);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    expect(hits, 1);
  });
}
