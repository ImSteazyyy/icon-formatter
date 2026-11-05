# Changelog

## 1.2.0 — 2026-11-05

### Added
- **Apply the pack on the phone with Shizuku (no PC, no root).** Icon Formatter builds the icon pack APK on the phone, signs it, installs it and selects it in Nothing Launcher.
  - **Build:** the base APK (`assets/iconpack_base.apk`, 2000 empty drawable slots, built by `tool/make_base_apk.py`) is filled with the pack's PNGs, plus binary `appfilter.xml` / `drawable.xml`, `mapping.json` and `pack.json`. It is then signed with apksig, using a key kept in the Android Keystore.
  - **Install and select:** `pm install`, then IconGen's sequence: the Nothing Launcher icon pack picker opens behind the app, and `nothing_icon_pack` is written to `THEMED_ICONS_NOTHING` and back to the pack 0.5 s later.
  - **A separate app:** the pack is its own package (`com.iconformatter.pack.device`), so system packs are untouched. Each build updates it in place with a progressive version (1.0, 1.1, 1.2, …), and "Ripristina pack precedente" restores the previous selection.
  - **Permissions:** the Shizuku permission is requested on launch, only when it is missing.
  - **Without Shizuku:** installation goes through the system installer with user confirmation, and the pack is chosen by hand in the launcher.
- **Studio → Pack:** a "Manda al Pack" button, and an optional automatic hand-off after "Elabora tutte", both feeding step 2 of the Pack and matching right away.
- **Rigenera con modalità… (per icon):**
  - Automatica.
  - Colore del piatto: the symbol takes the colour of the original plate.
  - Bordo pieno: edge to edge, like Maps or Gboard.
  - Normale.
- **Automatic recolouring:** a dark, neutral symbol on a coloured disc or tile (for example a dark tag on a yellow disc) takes the plate colour, and holes inside the symbol become transparent. White symbols stay white.
- **AI tab › Local models:**
  - U²-Net-p, for phone and Windows (~0.9 s per icon on a PC).
  - ISNet General, Windows only (~7.5 s per icon, 1024 px input).
  - Download, delete and choose the model, with an optional "Usa il modello AI locale" switch. The classic algorithm stays the default.
- **New icons:** the app icon and the pack icon have transparent backgrounds, clean edges and the same proportions as other app icons.

### Changed
- **New UI**, following the reference screenshots:
  - Impostazioni: a home with a large title, a profile card and a two-column grid of categories. Pages have a round back button and a large title, sections are dark cards with thin separators, sliders have an icon, name and value on top with the control below, and switches and choice lists are modern.
  - Pack: numbered steps.
  - Studio: when empty, it shows a 3-step guide.
  - Everywhere: large titles, glass header buttons, and redesigned dialogs, sheets and menus.
- **Global Liquid Glass (Impostazioni › Vetro):**
  - The parameters drive every glass surface: bottom bar, panels and cards, buttons, and dialogs (the screen behind is blurred).
  - The effect applies in real time without a restart.
  - The settings are: quality (Più veloce / Bilanciato / Qualità), blur, frost, saturation, tint colour and amount, thickness, curvature, refraction, chromatic aberration, depth (shadow), light, gloss rim, legibility, lens, and where to use it.
  - The sticky preview at the top reproduces the Studio base screen.
  - The package's automatic quality downgrade is off, so the chosen quality is respected.
- **Edge-to-edge icons:** a full tile with a transparent margin (as launchers return them) is now recognised, so Maps- and Gboard-like icons are no longer rendered small inside the plate.
- **Performance on Android:** grid icons are decoded at display size (`cacheWidth`) inside a `RepaintBoundary`.

### Fixed
- **Scrolling action bars:** in Studio, AI and App, the actions no longer get cut by a straight line and now follow the rounded edge.
- **Progress strip:** the finished strip closes with a swipe down (or ×).

## 1.1.1 — 2026-11-05

### Fixed
- Lucent: icons taken from installed apps (adaptive icons rendered as a full rounded tile, e.g. Google Maps or Gboard) lost most of their content, because the outer segmentation treated the whole tile as a bare logo. When the source is itself a full tile, its inner background is now removed directly. Content (roads, keys, figures) is kept whole, reaches the plate edge and is clipped to it, both in the preview and in the export.

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
