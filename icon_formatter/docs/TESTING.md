# Testing

There are three levels: unit tests, integration tests (app flows), and a stress test with 5,000 icons. Run the commands from the `icon_formatter` folder, with `flutter` on your PATH.

## Unit tests

```
flutter test test
```

They check the pure logic: models, packs, l10n, the calendar, and so on.

## Integration tests (flows)

Files in `integration_test/`. Shared helpers are in `integration_test/e2e_support.dart`.

```
export MSYS_NO_PATHCONV=1
flutter test integration_test/app_flow_test.dart -d emulator-5554
```

Run them on an Android device or emulator (`-d <device>`). The Apps tab exists only on Android.

`app_flow_test.dart` covers:

- a: the Studio, Pack and Settings tabs open without exceptions, and the navigation bar is visible.
- b: Settings › Appearance: Nothing and Glass, dark and light theme, then back to the initial state.
- c: Studio: imports 13 synthetic icons (drawn by the test, with no third-party artwork), runs **Process all**, checks that every icon has a result without errors and that the output exists, then **Send to Pack**.
- d: **Send to Pack** really reaches the Pack builder. The check reads the builder's data, not the text on screen, because the Pack tab shows the apps of the catalogue. **Match** runs without exceptions.
- e: Settings › System: the cache rows are visible.

The test forces the language to Italian and skips the onboarding and the tour. The Apps tab opens the Shizuku permission request, so it is not opened unless you pass `--dart-define=E2E_APPS=true`.

Tolerated Flutter errors are listed in the constant `allowedFlutterErrors` in `e2e_support.dart`. The list is currently empty. If a known error appears, add it there with a note, and remove the entry once the cause is fixed.

Each test starts from a freshly launched app. Error messages name the step that failed.

Other integration tests in the same folder:

- `pack_edit_flow_test.dart` opens the edit page ("Edit icon") on a synthetic icon. It checks the treatment tiles, Cancel, Confirm, Change, and the pack-wide plate opacity against the real engine, then reads the saved correction back from the pack store. Run it with `flutter test integration_test/pack_edit_flow_test.dart -d emulator-5554`.
- `ffi_test.dart` checks the Rust core through flutter_rust_bridge. Run it with `flutter test integration_test/ffi_test.dart -d <device>` on an Android device or emulator.

## Stress test: 5,000 icons

File: `integration_test/stress_5000_test.dart`. The test generates its own images in the app cache (`.../cache/IconFormatterCache/stress_in`), with a distinct colour and 16-bit code for each icon, so the cutout cache cannot reuse them. No file has to exist on the device. Generation happens outside the measured time, but it is reported on the first line.

```
flutter test integration_test/stress_5000_test.dart -d emulator-5554 \
  --dart-define=STRESS=true \
  --dart-define=STRESS_N=5000 \
  --dart-define=STRESS_BUDGET_MB=1536
```

For a quick run, use `--dart-define=STRESS_N=500`. Without `STRESS=true`, the test is skipped, so the normal integration command does not run it.

The test imports the folder into the Studio, presses **Process all**, and every 100 icons it records: elapsed time, time per 100 icons, the process RSS (MB), total frames, "janky" frames (more than 16.7 ms between build and raster), the worst frame, and errors.

### What the budgets mean

- `STRESS_BUDGET_MB` (default 1536): the peak process RSS above which the test fails. It is a chosen threshold, not a measurement of the phone. The x86_64 emulator has little RAM, so a result above the budget there is a number to compare with earlier versions.
- Janky frames: the percentage of frames longer than 16.7 ms during processing. They do not fail the test. Use them to compare versions.
- The test also fails if any icon ends with an error, if not all icons are imported, or if the app crashes.

### Where the results are

- File: `<app cache>/IconFormatterCache/stress_results.txt`. On Android it is in `/data/user/0/com.iconformatter.icon_formatter/cache/IconFormatterCache/`. Read it with `adb shell run-as com.iconformatter.icon_formatter cat ...` (debug builds only).
- Printed to the console with the prefix `E2E_STRESS`.

The file is updated every 100 icons, so it stays readable even if the app closes halfway.

## Test images

The generated images are not stored in the repository and are not copied to the device. They exist only in the app cache during the test. Do not put emulator screenshots in the repository.
