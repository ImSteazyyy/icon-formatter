# Changelog

## 1.1.0 — 2026-11-05

### Added
- **Lucent rendering (Nothing OS 5.0)**: a new Rust module (`lucent.rs`) ports the method of [Nothing IconGen](https://github.com/linuxct/nothing-icongen) (commit `02c915f`, AGPL-3.0). It includes the frosted plate `#66000000` / `#66FFFFFF`, the launcher's luminance→ink conversion (optional), and the `PackIconEncoder` compensation for Nothing Launcher.
  - The glyph keeps its original colours.
  - The plate is the reference squircle. The circle or the silhouette of the uploaded icon are also available.
  - Content is clipped to the plate edge.
  - Preview and export use the same function.
- **"Icon inside the icon"**: when an icon is itself a full tile with a dark background (already themed icons), that background is removed with region growing (shadows and gradients included). Objects are kept whole and reach the plate edge. Soft edges use a luminance matte, and dark greys or white glyphs are made readable on both dark and light plates.
- **Icon Pack Builder**:
  - Originals can come from installed apps, a folder, a ZIP or an APK. APK support covers binary `appfilter.xml` and keeps the highest density.
  - Icons are generated with the Studio or imported.
  - Automatic matching uses app name, package, file name and visual similarity.
  - Results appear in a Before/After grid with Sicura/Dubbia/Mancante/Esclusa/Verificata states.
  - Associations can be corrected by search, replaced with a file, excluded, verified or re-processed. Corrections are saved between sessions.
  - Export to a folder or ZIP with `appfilter.xml`.
- **Icon pack APK** (Windows, with Android SDK + JDK): "Crea APK" builds an installable icon pack (ADW/Nova/Lawnchair… intents). Inside it, an icon browser in the app's own style shows each icon's app and package, and whether the app is installed.
- **Local AI background removal**: optional U²-Net-p model (4.6 MB, Apache-2.0) run with `tract` (pure Rust, CPU) on Windows and Android.
  - The model is downloaded and loaded on demand, and stays cached in memory.
  - Removal is skipped when the background is already transparent.
  - An alpha mask preview offers adjustable thresholds.
  - Uncertain results are flagged.
- **Android automation**: a light check using a persisted JobScheduler job (6 h) and an on-unlock check while the app is in memory.
  - `getChangedPackages` skips all work when nothing has changed.
  - Detects installed, uninstalled and updated apps, and changed icons.
  - Silent notification, "Controlla ora" button, and re-processing of only the changed apps.
- **Sliders with numeric input**: tap the value, type, then Enter or tap outside to confirm, Esc to cancel. Includes min/max validation, decimal comma support and snapping to divisions.
- Centralised Italian strings (`lib/l10n/strings.dart`), with every screen translated.
- New app icon (Windows `.ico`, Android adaptive icon with a transparent background, title bar).

### Changed
- Bottom navigation: dark grey selection lens with a desaturated pink-lilac accent.
- "ZIP" import buttons are now "ZIP o APK".
- Composition on a base: glyphs that reach the edge (or tiles) are mapped to the plate and clipped to its shape.
- License: AGPL-3.0-only (because of the code derived from Nothing IconGen).

### Notes and limits
- Silent refresh of the pack in the launcher is not available: see README › Limiti.
- Silueta / IS-Net models were evaluated with `tract`: about 93 s per icon on CPU, so they are not offered.
