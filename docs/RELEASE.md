# Publishing a release

This guide explains how Icon Formatter is built, signed and published on GitHub. The workflows live in `.github/workflows/`:

- `ci.yml` runs on every push and pull request: `flutter analyze`, `flutter test`, `cargo test` on `native/icon_core`, and the translation check (`tool/l10n_gen.py --check`).
- `release.yml` runs when you push a tag `v*`. It builds the Android APKs (split per ABI, plus a universal one), signs the APKs with the release key, and creates or updates the GitHub release with the assets and with the notes taken from `CHANGELOG.md`.

## Asset names

For version `1.0.0`, the release contains these files:

- `IconFormatter-1.0.0-arm64-v8a.apk`
- `IconFormatter-1.0.0-armeabi-v7a.apk`
- `IconFormatter-1.0.0-x86_64.apk`
- `IconFormatter-1.0.0-universal.apk`

## How to publish a release

1. Update the version in `icon_formatter/pubspec.yaml`, for example `version: 1.0.1+8`. The number after the `+` is the build number. It is not part of the tag.
2. Add a new section at the top of `CHANGELOG.md`, with the heading `## 1.0.1 — YYYY-MM-DD`. Keep the heading format exactly: the workflow uses it to find the notes. The text of the section becomes the body of the release.
3. Commit and push to `main`, and wait for CI to pass.
4. Create and push the tag, using the same number as the version:

   ```
   git tag v1.0.1
   git push origin v1.0.1
   ```

5. Go to **Actions**, open the **Release** workflow, and check that the two jobs (android, publish) finish green. If the tag does not match `version:` in `pubspec.yaml`, the job fails at once with a clear message. In that case, delete the remote tag (`git push --delete origin v1.0.1`), fix the version, and create the tag again.
6. Open the **Releases** page. You should see the release with the five files. You can publish the same tag again: assets with the same name are replaced.

## Secrets to configure (once)

In GitHub, go to the repository **Settings › Secrets and variables › Actions › New repository secret**, and add these four secrets:

| Name | Value |
| --- | --- |
| `ANDROID_KEYSTORE_BASE64` | the keystore, encoded in base64 (see below) |
| `ANDROID_KEYSTORE_PASSWORD` | the keystore password, from `KEYSTORE-INFO.txt` |
| `ANDROID_KEY_ALIAS` | `iconformatter` |
| `ANDROID_KEY_PASSWORD` | the key password, from `KEYSTORE-INFO.txt` (it is the same as the keystore password) |

To encode the keystore in base64, run this in PowerShell:

```powershell
[Convert]::ToBase64String([IO.File]::ReadAllBytes("$env:USERPROFILE\.icon-formatter-keys\release.jks")) | Set-Clipboard
```

Then paste the clipboard into the `ANDROID_KEYSTORE_BASE64` field. Never save this value in a file inside the repository.

If a secret is missing, the android job stops and lists the missing ones. No APK is ever signed with a key other than the release key.

## Signing key: keep it safe

The key is at `$env:USERPROFILE\.icon-formatter-keys\release.jks`. Its passwords and SHA-256 fingerprint are in `KEYSTORE-INFO.txt`, in the same folder. Both stay outside the repository and must never be committed.

Keep a backup of both files somewhere safe, such as a USB drive or a password manager. If you lose them, you cannot publish updates that install over existing versions, and users would have to uninstall and reinstall the app.

## Verifying the signature of an APK

With the build-tools of the Android SDK:

```
apksigner verify --print-certs IconFormatter-1.0.1-universal.apk
```

The `SHA-256 digest` field must match the fingerprint in `KEYSTORE-INFO.txt`.

## Note for users updating from a debug-signed build

Builds before build 5 were signed with the debug key. Builds from build 5 onward are signed with the release key. Android refuses an update signed with a different key, so the first install shows "signatures do not match". Users must uninstall the app once and install the new one. The installed icon pack stays on the phone. After that step, updates install over the previous version as usual. The README explains the backup steps for users.

## Local build

Without `android/key.properties`, a local release build uses the debug key, so `flutter run --release` keeps working. With `key.properties` (which is git-ignored and already present on the development PC), the build uses the release key. On CI, the variable `CI=true` makes the key mandatory: without it, the build fails instead of signing with the debug key.
