# Screenshots and GIFs for the README

This is the list of images the README needs. Each entry gives the file name, the size, the screen, the state, the theme and the data. Read the rules in [PLAN.md](PLAN.md) first: synthetic icons only, English UI, no personal data, no third-party icons.

File names marked **keep** already exist in this folder and keep their name. Files marked **new** must be created with the name shown. If a file is missing, the README still reads correctly, because each image has alt text.

Themes: use **Nothing dark** unless a shot says otherwise. Use **light** only for `appearance-light.png`.

## Hero

### hero.png (keep, re-capture)

- **README:** top of the page, width 800.
- **Size:** PNG, 1600x600, under 800 KB.
- **Screen:** Studio on an Android phone, cropped to the content.
- **Content:** left half shows 8 synthetic icons as imported (different backgrounds and shapes). Right half shows the same 8 icons after **Process all**, Lucent style, squircle plate. Compose the two halves from two captures on a neutral background.
- **Theme:** Nothing dark.
- **Data:** 8 synthetic icons, with a mix of circle and square backgrounds.

## Studio

### studio-import.gif (keep, re-capture)

- **README:** Studio section, width 320.
- **Size:** GIF, 360x800, about 8 seconds.
- **Screen:** Studio, emulator.
- **Steps:** empty Studio → **Import icons** → **Images or icon pack** → select 6 synthetic PNGs from the sample folder → **Add 6** → the grid fills with thumbnails → **Process all** → the list shows the status **Done**.
- **Avoid:** **Use the phone's apps**, which would show real app icons.
- **Theme:** Nothing dark.

### studio-before-after.png (new)

- **File name:** `studio-before-after.png`
- **README:** Studio section, width 320.
- **Size:** PNG, 360x800.
- **Screen:** Studio, one synthetic icon open in the preview, with the comparison line in the middle.
- **Steps:** process the icons with the Lucent style, open one icon, and drag the white line to about the middle of the screen. The left side shows the original, the right side the processed icon.
- **Theme:** Nothing dark.
- **Data:** one synthetic icon with a coloured square background.

### studio-corrections.png (keep, re-capture)

- **README:** Studio section, width 320.
- **Size:** PNG, 360x800.
- **Screen:** Studio, one icon open in the preview with the correction controls visible.
- **Steps:** press and hold a synthetic icon in the Studio, then open the adjustment controls. Show **Optical centring** or **Symbol colour**, with the comparison line visible.
- **Theme:** Nothing dark.

### studio-style.gif (keep, re-capture)

- **README:** Styles section, width 320.
- **Size:** GIF, 360x800, about 10 seconds.
- **Screen:** Studio, the **Customise** panel.
- **Steps:** open **Customise** → choose **Lucent** → move the **Symbol size** slider → change the plate shape to **Squircle** → **Process all** → drag the comparison line.
- **Theme:** Nothing dark.

## Pack

### pack-tab.png (new)

- **README:** Pack section, width 320.
- **Size:** PNG, 360x800.
- **Screen:** the **Pack** tab (Icon Pack Builder), after **Match**.
- **Content:** the list of installed demo apps with their status badges: one each of **Matched**, **Checked**, **Uncertain**, **To check** and **Icon missing**. Show the coverage line "N of M apps have their icon" at the top.
- **Theme:** Nothing dark.
- **Data:** 6 to 8 demo apps installed on the emulator, each with a synthetic icon, so that every status appears at least once. Exclude real apps: use the clean emulator image.

### pack-more-sheet.png (new)

- **README:** Pack section, width 320.
- **Size:** PNG, 360x800.
- **Screen:** the **Pack** tab with the **More** sheet open.
- **Content:** the sections of the sheet: **Checks**, **Export and share**, **Pack log**, **Saved packs**, **Open a pack**, **Import**, **Pack cleanup**, **Preview**, **Share**, **Build APK**. Scroll so that as many as possible are visible.
- **Theme:** Nothing dark.
- **Data:** demo apps only.

### edit-page.png (new)

- **README:** Pack section, width 320, under the edit-page text.
- **Size:** PNG, 360x800.
- **Screen:** **Edit icon** page for one synthetic icon.
- **Content:** the **How the icon looks** section with the four main tiles: **Automatic** (selected, marked **Recommended**), **Symbol only**, **Plate colour**, **Full edge**. Each tile shows its live thumbnail. Leave **More options** collapsed.
- **Theme:** Nothing dark.
- **Data:** one synthetic icon with a coloured background.

### calendar-day-variants.png (new)

- **README:** Android section, after the calendar GIF, width 320.
- **Size:** PNG, 960x600 (a composite, shown at width 320).
- **Screen:** the **Pack** tab, the calendar entry, and the home preview.
- **Content:** three thumbnails of the same calendar entry, each showing a different day (for example 3, 17 and 28), side by side. Above them, show the line "Calendar in the pack (1 app): the launcher shows today's date". Build the composite from three crops of the home preview.
- **Theme:** Nothing dark.
- **Data:** a synthetic calendar icon pack with 31 icons, one per day, drawn with the day number on each. These are invented icons, not a real calendar app.

### apply-launcher.gif (new)

- **README:** Android section, width 320, after the calendar GIF. This replaces the earlier plan's `android-apply.gif`.
- **Size:** GIF, 360x800, about 10 seconds, under 3 MB.
- **Screen:** the **Apply in the launcher** sheet.
- **Steps:** open **Apply in the launcher** → **Install and apply** → let the progress steps show ("Building the pack on the phone…", "Installing the pack…", "Selecting the pack in the launcher…") → the result "Pack applied: N icons."
- **Shizuku:** the status line should read "Shizuku running and authorised". If Shizuku is not on the emulator, you can use the status text only. Crop out the Shizuku logo. Do not show the Shizuku store page.
- **System dialog:** the system install confirmation may stay in the frame, because it shows only the Icon Formatter icon.
- **Theme:** Nothing dark.
- **Data:** the synthetic pack from the Pack tab.

### pack-autosync.png (new)

- **README:** Android section, width 320, next to the automatic-update text.
- **Size:** PNG, 360x800.
- **Screen:** the **Pack** tab, scrolled to the **Automatic update** section.
- **Content:** the section title **Automatic update**, the line "Last check: …", the **Automatic check** setting with the interval "Check every 6 hours" and **Only while charging**, the **Check now** button, and a **Redo 2** button with the line "…and 1 more" below it.
- **Steps:** install one extra demo app, then tap **Check now**. Keep one demo app removed, so the list shows a change.
- **Theme:** Nothing dark.
- **Data:** demo apps only.

### calendar.gif (keep, re-capture)

- **README:** Android section, width 320.
- **Size:** GIF, 360x800, about 8 seconds.
- **Screen:** the **Pack** tab, **Calendar day** section, then the home preview.
- **Steps:** set **Update the day at** to a time → **Update day** → the line "Day updated on N icons" → show the home preview with the calendar icon showing a different day.
- **Shizuku:** **Update day** needs Shizuku. If Shizuku is not running on the emulator, show the section and the message "Shizuku is needed to update the pack on its own" instead. Do not show the Shizuku store page.
- **Theme:** Nothing dark.
- **Data:** the synthetic 31-icon calendar pack.

## Appearance and settings

### themes-nothing-glass.png (obsolete: the Glass style was removed, do not capture)

- **README:** Appearance section, width 640.
- **Size:** PNG, 720x800, two 360x800 captures side by side with a small gap.
- **Screen:** **Settings › Appearance**, in dark mode.
- **Content:** left, the **Nothing** style. Right, the **Glass** style.
- **Steps:** open **Settings › Appearance** → choose **Nothing** → capture → choose **Glass** → capture → place them side by side.
- **Theme:** dark, for both.

### appearance-light.png (new)

- **README:** Appearance section, width 320.
- **Size:** PNG, 360x800.
- **Screen:** the **Studio** in light mode, Nothing style.
- **Content:** six processed synthetic icons in the grid. The frosted bottom bar and the cards are visible.
- **Theme:** Nothing, light.
- **Data:** six synthetic icons.

### onboarding.gif (keep, re-capture)

- **README:** Appearance section, width 320.
- **Size:** GIF, 360x800, about 12 seconds.
- **Screen:** first launch, after clearing the app data.
- **Steps:** "Welcome" → language screen (English) → "Automatic update" → "Shizuku (optional)" (text only, logo cropped) → **Start** → tour pages: welcome, style (Nothing or Glass), permissions with the status "Not granted", then "All set".
- **Avoid:** the Shizuku store page.
- **Theme:** Nothing dark for the first half, and the style page shows both styles.

### settings.png (keep, re-capture)

- **README:** Appearance section, width 320.
- **Size:** PNG, 360x800.
- **Screen:** **Settings**, top of the grid of sections.
- **Content:** the sections **Appearance**, **Processing**, **Base icons**, **Pack**, **Export**, **System**, **About**.
- **Avoid:** the **Support the project** card (the Ko-fi link).
- **Theme:** Nothing dark.

## Optional

- `pack-home-preview.png`: the home preview in light and dark, side by side. It is not used by the README now. Capture it only if a section needs it.

## Done checklist

- [ ] All files above exist with the exact names and sizes.
- [ ] Each file has been checked for third-party icons, logos and real app names, including status bars and menus.
- [ ] No personal data and no paths with a user name.
- [ ] GIFs loop without stutter.
