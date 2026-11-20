# Icon Formatter (app)

This folder holds the Flutter app. The project overview, the screenshots and the release notes are in the [root README](../README.md).

Icon Formatter turns app icons into one uniform style and builds icon packs you can install. It runs on Android.

## Features

- **Studio.** Import images, a folder, an icon pack (ZIP or APK) or the apps on the phone. The Studio isolates the symbol of each icon and places it on a consistent background: original composition, the translucent "Lucent" plate, or one of your presets.
- **Pack.** Matches new icons to the installed apps, shows what is missing or needs a check, and builds the icon pack. On Android it installs and applies the pack in the launcher.
- **Your apps (Android).** Lists the installed apps with the icon the launcher shows, and lets you process them in one tap.
- **Pack cleanup.** Cleans up an existing icon pack and keeps its names, paths and `appfilter.xml`.
- **Dynamic calendar.** From an icon pack, takes only the calendar icons (one day per icon). In the generated pack the launcher shows today's day by itself.

## Requirements

- **Recommended:** Nothing OS 5.0 (Android 16), the system the Lucent style and the automatic application were designed for. Minimum: Android 7.0 (API 24).
- To install and apply the pack without a PC, [Shizuku](https://shizuku.rikka.app/) must be running (Wireless debugging). Without Shizuku, the pack is installed through the system confirmation, and you choose it by hand in the launcher settings.

## Appearance

One style for now, the **Nothing style**: black, grey cards, serif titles and red as the accent colour. The Glass style was removed for now and will come back later.

The indicator of the bottom bar slides between the tabs like a drop.

## How it works

| Layer | Path | Role |
|---|---|---|
| Rust engine | `native/icon_core` | Symbol isolation, plates and shapes, composition, icon matching, reading and writing icon packs, cancellable parallel processing. |
| Bridge | `rust/` | `flutter_rust_bridge` 2.13 between Rust and Flutter. |
| Interface | `lib/` | Flutter UI: floating bottom bar on phones, navigation rail on wide screens. |
| Android | `android/app/src/main/kotlin/…` | Installed apps, file access (SAF), building, signing and installing the pack on the phone, automatic updates, sharing. |

### Symbol isolation

Isolation is deterministic and uses no machine-learning model. The background is filled from the edges, the "plate" (rounded or semi-transparent backgrounds) is detected and removed, and anti-aliased edges are separated without halos. Uncertain cases are flagged for a manual check.

For difficult backgrounds there are two alternatives, in Settings › Processing:

- **AI on the device:** an optional U²-Net-p model (4.6 MB, Apache-2.0). It is downloaded only when you ask, and it runs offline on the CPU.
- **remove.bg:** an online service that uses your own API key, stored in the operating system's secure storage. Each image uses one credit.

### Icon packs on the phone

The pack is a separate app (`com.iconformatter.pack.device`). It is built on the phone from a base APK with 2,000 icon slots, signed with a key that stays in the Android Keystore, and installed with Shizuku. The version number adjusts automatically to the one Android remembers, even after an uninstall that kept the data.

Hand-made corrections in the Pack are saved and reapplied each time the pack is rebuilt.

### Automatic updates (Android)

A periodic check (every 6, 12 or 24 hours, and when the phone is unlocked) finds installed, removed or changed apps. It lists them in the Pack with a silent notification, and **Redo** processes only those apps. The app does not use root and does not declare `QUERY_ALL_PACKAGES`. Long jobs run as a foreground service (`ProcessingService`) with a progress notification.

## Known limits

- On Android, only apps with an icon on the home screen are listed. Apps without one, and apps in the work profile, do not appear.
- A pack built on the phone holds at most 2,000 icons.
- Without Shizuku, Android does not allow a silent install or selecting the pack in the launcher.

## Build

```bash
cargo test --release --manifest-path native/icon_core/Cargo.toml
flutter test test
flutter build apk --release
```

The full build instructions, including the requirements and the support scripts, are in the [root README](../README.md#build-from-source). Tests are described in [docs/TESTING.md](docs/TESTING.md).

## Licence

AGPL-3.0-only (see [LICENSE](../LICENSE)). Third-party components and fonts, with their licences: [THIRD_PARTY_NOTICES.md](../THIRD_PARTY_NOTICES.md).

Icon Formatter is an independent project. Manufacturer and launcher names are trademarks of their owners and are cited only to indicate compatibility. The app works on the icons present on the user's device and distributes none of them.
