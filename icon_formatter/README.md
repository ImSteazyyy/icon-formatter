# Icon Formatter

Windows and Android app for composing, styling and cleaning up launcher icons.

## Architecture

| Layer | Path | Role |
|---|---|---|
| Rust core | `native/icon_core` | Segmentation/glyph isolation, squircle, "Nothing Translucent" render, composition, calibration, parallel batch (rayon) with cancellation, pack I/O (folder/ZIP, `appfilter.xml`), Android icon pack export. Pure Rust, testable with `cargo test`. |
| FFI bridge | `rust/` (crate `icon_bridge`) | `flutter_rust_bridge` 2.13: DTOs, async functions on worker threads, `Stream` for batch progress, opaque `CancelToken`. |
| Flutter UI | `lib/` | Windows (sidebar, drag-and-drop, native dialogs) and Android (bottom nav / rail, edge-to-edge, SAF, Share Sheet). |
| Android native | `android/app/src/main/kotlin/.../MainActivity.kt` | Installed Apps Scanner (PackageManager, adaptive icons), Storage Access Framework (folder picker, writing/reading trees). |

Images cross the FFI as file paths whenever possible (batches read and write directly in Rust). PNG bytes are used only for previews and for icons coming from Android.

## Pipelines

- **Original Composition**: glyph isolated and composed on the selected base icon, using that base's calibration.
- **Lucent (Nothing OS 5.0)** — `native/icon_core/src/lucent.rs`, port of the method of [Nothing IconGen](https://github.com/linuxct/nothing-icongen) (AGPL-3.0, commit `02c915f`):
  - frosted plate `container_frosted_backdrop` (`#66000000` dark / `#66FFFFFF` light);
  - optional luminance → ink conversion (`PortableMonochrome`);
  - optional `PackIconEncoder` compensation for Nothing Launcher (source → shadows → source, round-trip tested).

  The glyph keeps its own colours. The plate is the reference squircle (circle and source silhouette available), and content is clipped to it. "Icon inside the icon" (themed icons with a dark tile) is unwrapped by region growing, and the content reaches the plate edge.
- **Custom Presets**: Liquid Glass, Nothing Translucent, Minimal, Dark Flat, Custom, plus user presets (editable and persisted).
- **AI Icon Theme**: external provider (OpenAI Images, Google Gemini, OpenAI-compatible endpoint). The key lives in the system secure storage. Without a key, nothing is generated or simulated.
- **Pack Cleanup**: opens a folder/ZIP, keeps relative paths and file names, copies `appfilter.xml` and the other metadata, flags drawables that are missing or ambiguous.
- **Installed Apps** (Android only): launcher activity list through `<queries>` MAIN/LAUNCHER, with no `QUERY_ALL_PACKAGES` and no root. Exports an icon pack as res/assets + `appfilter.xml`.

## UI

- **Liquid glass**: [`liquid_glass_widgets`](https://github.com/sdegenaar/liquid_glass_widgets) 1.16 (refraction, chromatic aberration, specular light).
  - On Android the navigation is a floating `GlassTabBar.bottom` with a dark lens; the action bars float above it and content scrolls underneath.
  - One `GlassConfig` (Impostazioni › Vetro) drives every glass surface (`LiquidGlass` with a `GlassRole`: panel, button, nav, lens), the bottom bar, dialogs (`showAppDialog` blurs the screen behind) and the theme (dialogs, sheets, menus), live.
  - Each surface can switch to a solid anthracite one.
  - Quality levels: Più veloce = `minimal`, Bilanciato = `standard`, Qualità = `premium`. Refraction and aberration are complete only in Qualità.
- **Layout**:
  - Impostazioni is a grid home with nested pages (`SettingsList` + `SettingsCard`).
  - Shared kit in `widgets/common.dart`: `IconChip`, `LargeHeader`, `SettingSwitch`, `ChoiceRows`, `StepCard`.
- **Windows**: custom title bar (`window_manager` 0.5, native caption hidden).
- **Accent**: default pink #BA4CD4 (sampled from the Windows Start icon), with presets, hex entry and HSL sliders.

## Background removal

Engines (Settings › Elaborazione):
- **Local Rust (default)**: deterministic segmentation, offline, free.
- **Local AI**: optional U²-Net-p model (4.6 MB, Apache-2.0, downloaded from the rembg releases), run with `tract` (pure Rust, CPU, no native runtime).
  - Measured at about 0.8 s per icon (i5-13500H), roughly 350 MB of RAM in use.
  - The model is loaded once and reused.
  - Removal is skipped when the background is already transparent.
  - Mask preview with thresholds; uncertain results are flagged.
  - ISNet General (170 MB, 1024 px input) is offered on Windows only: ~7.5 s per icon on the same PC, too slow for a phone.
  - Silueta took about 89 s per icon with `tract`, so it is not offered. No GPU path with `tract`.

Option: Option: **remove.bg** (Settings › Processing), with the API key in secure storage, a test that shows the remaining credits, and one call per image cached for the session. In a batch, the calls run first (3 in parallel, cancellable), then Rust composites the cutout without re-segmenting it.

## Glyph isolation

Deterministic, no ML model: flood fill from the edges using border colour clusters (OKLab + alpha), "plate" detection (rounded/semi-transparent backgrounds), optional hole removal, and premultiplied un-mixing of anti-aliased edges. Glyph parts with colours similar to the background survive whenever they are separated by an edge. Uncertain cases are flagged (yellow) for manual correction.

ONNX Runtime (U²-Net/BiRefNet type models) was evaluated and left out. It adds 20–40 MB of native runtime per ABI plus 40–170 MB of model, while being trained on photos and not on flat logos. On the reference icons the deterministic segmentation isolates all 26 glyphs; 2 (`apk toolbox 2`, `tiktok plugin`) are flagged for manual review because of large internal areas matching the background colour.

## Reference icons

The 26 icons in `D:\Icon Formatter` (192 px, squircle 0.93 × exponent 4.25, semi-transparent black plate α 105→176) are the test material: `native/icon_core/tests/reference.rs`. The "Reference Translucent" base (`assets/bases/`) is the empty icon provided by the user; its calibration (glyph 66.9 %, centre 0.500/0.500, 26/26 samples) was measured with the same algorithm the app uses.

## Benchmark (i5-13500H, `cargo run --release --example bench`)

| Output | Threads | Throughput | Per icon |
|---|---|---|---|
| 512 px | 1 | 13.9 icons/s | 71.9 ms |
| 512 px | all | 124.8 icons/s | 8.0 ms |
| 192 px | all | 303.3 icons/s | 3.3 ms |

208 icons (26 references × 8): decode, isolation, resize, composition, PNG encode and write.

## Icon Pack Builder

Originals come from installed apps, a folder, a ZIP or an APK (binary `appfilter.xml` decoded by `axml.rs`, highest density kept).

Generated icons are produced with the Studio or imported. Matching (`matching.rs`) scores package, app name, file name and visual similarity (glyph silhouette IoU + hue histogram). It is one-to-one and greedy, and ambiguous visual matches are flagged.

Manual corrections are stored in `state.json` (`packCorrections`).

Export: folder or ZIP (`res/drawable-nodpi`, `appfilter.xml`, `mapping.json`). On Windows, **Crea APK** fills `assets/iconpack_template.zip` (source in `iconpack_template/`, rebuild with `python tool/make_template_zip.py`) and runs Gradle with the local Android SDK and JDK. The result is an installable icon pack with its own icon browser, signed with the local debug key.

### On the phone, with Shizuku (`DevicePack.kt`)

**Install and apply.** The pack is the separate app `com.iconformatter.pack.device`. It is built on the phone from `assets/iconpack_base.apk`, which `tool/make_base_apk.py` creates with 2000 empty drawable slots:
- the slots get the PNGs;
- binary `appfilter.xml` and `drawable.xml` are written (an AXML writer validated with `aapt2 dump xmltree`), together with `mapping.json` and `pack.json`;
- `versionCode` / `versionName` are patched in the manifest (1.0, 1.1, …);
- the APK is signed with apksig (Android Keystore key).

Shizuku (shell identity) then runs `pm install -r` and IconGen's selection sequence: open `com.nothing.launcher.icon_pack_picker` behind the task, write `nothing_icon_pack` = `THEMED_ICONS_NOTHING`, then the pack package after 500 ms. The previous value is saved for "Ripristina".

Shizuku starts on the phone itself (Wireless debugging, Android 11+). Without it, the APK goes through the system installer and the pack is chosen by hand.

**Verified on the emulator (API 35):**
- Shizuku 13.6 is started as shell and the permission is granted in the app dialog.
- A stub `com.nothing.launcher` (5.0) has the picker activity.
- Results: install, update 1.1 → 1.2 → 1.3, the temporary value seen by polling, the final selector equal to the pack, `aapt2` and `apksigner` checks.

**Not verified:** how a real Nothing Launcher on Nothing OS 5.0 redraws the icons. That needs the phone.

## Android automation

- A persisted JobScheduler job (every 6 h, battery not low; survives reboots, subject to Doze) plus an immediate check on unlock (`USER_PRESENT`) while the process is alive.
- `PackageManager.getChangedPackages` skips all work when nothing changed. Only changed launcher apps get their icon hashed.
- Changes (installed, uninstalled, updated, icon changed) are listed in the Pack Builder, with a silent notification. "Rielabora" re-processes only those apps.
- Permissions: `RECEIVE_BOOT_COMPLETED`, `POST_NOTIFICATIONS` (asked when the switch is turned on). No root, no foreground service, no `QUERY_ALL_PACKAGES`.

## Known limits

- **Launcher refresh**:
  - With Shizuku, Icon Formatter installs and selects its pack the way IconGen does. The shell identity may write the non-public `nothing_icon_pack` key, which apps with `targetSdk` ≥ 23 cannot.
  - Shizuku must be running when the pack is applied, and after a reboot it must be started again from the Shizuku app.
  - The icon redraw by the real Nothing Launcher could not be verified without the phone.

- **Android icon pack**:
  - The phone build holds up to 2000 icons, and its label is fixed ("Icon Formatter Pack"); name and accent shown inside come from `pack.json`.
  - Without root, Android does not let an app replace other apps' icons, and support depends on the launcher.
- **Installed Apps**: only apps with a launcher activity are visible (Android 11+ package visibility policy). Apps without a readable icon are reported and skipped. "Not themed" means not yet processed by this app; the presence of a system monochrome icon (Android 13+) is detected.
- **AI**: costs and limits shown are indicative and depend on the provider; check the official price list.
- **Live transparency**: the "Simulated transparency" parameter lowers the alpha of the rendered PNG; it does not reproduce the launcher's live blur.

## License

AGPL-3.0-only (see `LICENSE`). `lucent.rs` contains code derived from Nothing IconGen (© linuxct, AGPL-3.0). The U²-Net-p model (Apache-2.0) is not bundled; it is downloaded on request.

## Build

```bash
cargo test --release --manifest-path native/icon_core/Cargo.toml
flutter test test
flutter test integration_test/ffi_test.dart -d windows
flutter build windows --release
flutter build apk --release
```
