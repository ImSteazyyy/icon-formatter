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
- **Nothing Translucent**: procedural background (neutral charcoal, frosting, rim, reflections, depth) rendered into the PNG.
- **Custom Presets**: Liquid Glass, Nothing Translucent, Minimal, Dark Flat, Custom, plus user presets (editable and persisted).
- **AI Icon Theme**: external provider (OpenAI Images, Google Gemini, OpenAI-compatible endpoint). The key lives in the system secure storage. Without a key, nothing is generated or simulated.
- **Pack Cleanup**: opens a folder/ZIP, keeps relative paths and file names, copies `appfilter.xml` and the other metadata, flags drawables that are missing or ambiguous.
- **Installed Apps** (Android only): launcher activity list through `<queries>` MAIN/LAUNCHER, with no `QUERY_ALL_PACKAGES` and no root. Exports an icon pack as res/assets + `appfilter.xml`.

## UI

- **Liquid glass**: [`liquid_glass_widgets`](https://github.com/sdegenaar/liquid_glass_widgets) 1.16 (refraction, chromatic aberration, specular light). On Android the navigation is a floating `GlassTabBar.bottom` with a dark lens; the action bars float above it and content scrolls underneath. Every parameter (blur, thickness, refraction, aberration, light, gloss rim, text shadow, lens, Standard/Premium quality) lives in Settings › Liquid Glass.
- **Windows**: custom title bar (`window_manager` 0.5, native caption hidden).
- **Accent**: default pink #BA4CD4 (sampled from the Windows Start icon), with presets, hex entry and HSL sliders.

## Background removal

Default: local Rust (offline, free). Option: **remove.bg** (Settings › Processing), with the API key in secure storage, a test that shows the remaining credits, and one call per image cached for the session. In a batch, the calls run first (3 in parallel, cancellable), then Rust composites the cutout without re-segmenting it.

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

## Known limits

- **Android icon pack**: the app generates the standard layout (`res/drawable-nodpi`, `res/xml/appfilter.xml`, `assets/appfilter.xml`, `drawable.xml`) and plain PNGs. An APK that launchers can install requires building that layout inside a template (Blueprint, CandyBar, …). Without root, Android does not let an app replace other apps' icons, and support depends on the launcher.
- **Installed Apps**: only apps with a launcher activity are visible (Android 11+ package visibility policy). Apps without a readable icon are reported and skipped. "Not themed" means not yet processed by this app; the presence of a system monochrome icon (Android 13+) is detected.
- **AI**: costs and limits shown are indicative and depend on the provider; check the official price list.
- **Live transparency**: the "Simulated transparency" parameter lowers the alpha of the rendered PNG; it does not reproduce the launcher's live blur.

## Build

```bash
cargo test --release --manifest-path native/icon_core/Cargo.toml
flutter test test
flutter test integration_test/ffi_test.dart -d windows
flutter build windows --release
flutter build apk --release
```
