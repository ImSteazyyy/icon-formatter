import 'package:flutter_test/flutter_test.dart';
import 'package:icon_formatter/services/batch_controller.dart';

// Regression for "after switching the cut-out provider back to Standard, nothing
// can be processed": a cancel left over from an earlier run (or pressed while
// idle) stayed set and made the next processing return before it started.
void main() {
  test('cancel while idle does not stick to the next processing', () {
    final b = BatchController();
    b.cancel();
    expect(b.cancelRequested, isFalse);
    b.clearCancel();
    expect(b.cancelRequested, isFalse);
  });

  test('a cancel during the remove.bg pre-pass still stops the batch after it', () {
    final b = BatchController();
    b.external(phase: 'remove.bg', done: 0, total: 3, errors: 0, running: true);
    b.cancel();
    expect(b.cancelRequested, isTrue);
    b.external(phase: 'remove.bg', done: 3, total: 3, errors: 0, running: false);
    expect(b.cancelRequested, isTrue, reason: 'the batch after the pre-pass must not start');
    // the next processing re-arms the flag
    b.clearCancel();
    expect(b.cancelRequested, isFalse);
  });

  test('notice is kept until the strip is dismissed', () {
    final b = BatchController();
    b.setNotice('fallback');
    expect(b.notice, 'fallback');
    b.dismissProgress();
    expect(b.notice, isNull);
  });
}
