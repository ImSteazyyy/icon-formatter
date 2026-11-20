# README media plan

All files go in `docs/media/`. The README references them with relative paths. Every image has alt text, so the README still reads correctly when a file is missing.

The file-by-file list (names, sizes, screen, state, theme and data) is in [SHOTS.md](SHOTS.md). This file holds the rules and the capture method.

## Rules for every capture

- **No third-party icons or logos.** Do not show icons of real apps, the launcher's own app icons from other vendors, app stores, social networks, or the Shizuku logo. In Shizuku screens, show only the status text, with the logo cropped out.
- **Synthetic icons only.** Use 8 to 10 simple demo icons (geometric shapes, two colours) with invented names such as "Weather Demo", "Notes Demo" or "Maps Demo". The approved input set is the folder `D:/Claude/cleanroom-lucent/shared/inputs/`. Copy the files you need to a sample folder outside the repository, and do not commit them.
- **Demo apps on the phone.** The Pack lists the apps installed on the phone with their icons. To show a realistic Pack, install a few demo apps with synthetic icons on the emulator. Use an emulator image without Google apps, or hide the system apps, and check every screenshot for any third-party icon, including the status bar and menus.
- **English.** Set the app and the phone to English, so the screenshots match the English README.
- **No personal data.** No names, e-mail addresses, accounts, remove.bg keys or personal links. Do not show paths that contain a user name. Blur them, or use a sample folder.
- **Phone.** Android emulator with a clean profile, only the demo apps and Icon Formatter installed. Capture at 1080x2400 and scale to 360x800 (the phone ratio). For a clean status bar:
  ```
  adb shell settings put global sysui_demo_allowed 1
  adb shell am broadcast -a com.android.systemui.demo -e command enter
  adb shell am broadcast -a com.android.systemui.demo -e command clock -e hhmm 0941
  adb shell am broadcast -a com.android.systemui.demo -e command battery -e level 100 -e plugged false
  adb shell am broadcast -a com.android.systemui.demo -e command network -e wifi show -e level 4
  ```
- **File size.** GIFs under 3 MB, PNGs under 500 KB, the hero under 800 KB.
- **GIFs.** Record with `adb shell screenrecord --size 1080x2400 /sdcard/capture.mp4` (then `adb pull`), or with scrcpy. Convert with:
  ```
  ffmpeg -i capture.mp4 -vf "fps=12,scale=360:-1:flags=lanczos,split[a][b];[a]palettegen=max_colors=128[p];[b][p]paletteuse=dither=bayer" out.gif
  ```
  For GIFs, record the cropped phone screen with ffmpeg, then use the same command with `scale=960:-1`.

## Files already in the repository

These were captured with build 1, in Italian. The README still references them, so re-capture them in English. Replace them if the screen has changed since:

- `hero.png`, `studio-import.gif`, `studio-style.gif`, `studio-corrections.png`, `calendar.gif`, `themes-nothing-glass.png`, `onboarding.gif`, `settings.png`

## Files still to capture

The new files are listed in [SHOTS.md](SHOTS.md), with their README sections:

- `studio-before-after.png`, `pack-tab.png`, `pack-more-sheet.png`, `pack-autosync.png`, `edit-page.png`, `calendar-day-variants.png`, `apply-launcher.gif`, `appearance-light.png`

The earlier plan included `pack-matching.gif`, `pack-details.png`, `pack-preview-home.png`, `android-apply.gif` and `pack-app.png`. They are replaced by the files above. `android-apply.gif` is now `apply-launcher.gif`.

## Checks before publishing

- Every file has the exact name in SHOTS.md and sits in `docs/media/`.
- No third-party icon, logo or real app name is visible, including status bars and menus.
- No personal data and no paths with a user name.
- File sizes are within the limits. GIFs loop without stutter.
- The README renders on GitHub with every image (alt text shows for missing files).
