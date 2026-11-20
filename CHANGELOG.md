# Changelog

## Unreleased

### Changes
- **Windows app removed.** Icon Formatter is now Android only. The Windows build, its ZIP in the release workflow and the desktop-only code and dependencies are gone. Android behaviour is unchanged.
- **Glass style removed for now.** The app has the Nothing style only: the style selector in Settings and the style page of the tour are gone. A saved Glass choice loads as Nothing. The Glass settings page and the liquid_glass_widgets dependency are removed.
- **Notices redesigned.** One notice at a time, just above the bottom bar, with one icon and at most one action. It leaves by itself, with a swipe, or when you change section or open a sheet, dialog or page. Routine confirmations (copied, saved, selection) are no longer shown.
- **Keyboard closes** when you change section or when a sheet, dialog or page opens over a search field.

## 1.0.0 — 2026-11-19

First public release.

### What it does

- **Studio:** import images, folders, icon packs or the apps on your phone and turn them all into the same style, with adjustments for each icon and background removal.
- **Pack:** match new icons to your installed apps, check every match and build the icon pack. On Android, with Shizuku, it installs and applies the pack directly. Without Shizuku, you export it and install it by hand.
- **Your apps:** process the icons of the installed apps and send them to the pack.
- **Dynamic calendar:** the calendar icon changes with the day. The pack declares both the dynamic entry and a fixed icon for today. If the launcher does not change the day by itself, the pack updates every morning with Shizuku, or right away with "Update day".
- **Background like the pack:** brings the background transparency of an icon, such as calendar pages, to the level of the other icons in the pack.
- **Automatic update:** when you install a new app, the pack updates itself.

## Appearance

- **Two styles:** Nothing (default) and Glass, with an adjustable liquid glass material.
- **Light and dark modes** for both styles. The change starts as a circle from the point you touch.
- Bottom bar that bends while you scroll, with compact actions next to it.
- Base icons Circle and Squircle included, plus any base you import.

## Languages

Italian, English, Spanish, French, German and Portuguese. The app follows the language of the phone. You can change it in Settings › Appearance.

## Notes

- On first launch, a short setup asks for the language, automatic updates and, optionally, Shizuku.
- AI is used only for background removal. The local model downloads only if you ask for it.
- The licences of third-party components are listed in `THIRD_PARTY_NOTICES.md` and on the Licences page of the app.
