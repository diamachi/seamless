# GitHub Actions builds

`.github/workflows/build.yml` runs on pushes to main, pull requests and manual dispatch. Documentation-only changes are skipped for push/PR events; manual dispatch always remains available. The jobs have read-only repository permission; checkout does not persist credentials. Official actions are pinned to commit SHAs, with version comments for maintenance. Pull requests do not receive signing secrets. A new run cancels an obsolete run for the same ref.

## macOS

The macos-26 Apple-silicon runner selects Xcode 26.3 explicitly, checks architecture/source privacy, runs native tests, builds the app and packages/verifies a DMG. SEAMLESS_SIGNING_IDENTITY is explicitly ad-hoc. The job uploads only the DMG and its checksum, not a workspace, debug symbols, credentials or build cache.

The resulting app is an Apple-silicon test build, not universal, Developer ID signed or notarized. Installing a differently signed copy can request fresh macOS/Keychain approval. Minimum OS metadata is not proof of compatibility with every supported system.

## Android

The Ubuntu job installs Temurin JDK 21, SDK platform 36 and build tools 35.0.0. On main (push or manual dispatch), it restores the stable Android distribution key from encrypted repository Actions secrets into runner.temp, then builds/tests/lints the release variant. The key is removed by an EXIT trap and is never an artifact or Gradle cache input. Required secrets: ANDROID_KEYSTORE_BASE64, ANDROID_STORE_PASSWORD, ANDROID_KEY_PASSWORD and ANDROID_KEY_ALIAS. Missing secrets fail main builds instead of silently substituting another signer.

Pull requests and non-main refs build/test/lint the debug variant without receiving signing secrets. Their APKs are development builds and cannot be treated as a stable update channel. Only the trusted main signing step receives secrets. Repository administrators and code merged into that step must be trusted with the key.

Local builds use ignored `.tools/android-signing.properties` when present; SEAMLESS_ANDROID_RELEASE=0 explicitly selects debug. The release script verifies the APK with apksigner and compares its public certificate SHA-256 against `android/signing-certificate.sha256` before copying to dist. Version codes must increase for upgrades. Signing alone does not notarize macOS or publish a release.

Earlier CI debug APKs used ephemeral signing keys. Moving to the distribution key may require one final uninstall/reinstall, resetting app data/pairings/permissions; subsequent main builds retain the same signer. Keep a protected backup of the private keystore and local properties/passwords. See DEVELOPMENT_SIGNING.md.

## Downloading

Open Actions → Build test installers → a completed run. Download `Seamless-macos-arm64` or `Seamless-android` from Artifacts and extract the archive. Each includes a SHA-256 checksum file. Installer artifacts expire after 14 days; failure reports after 7 days.

This build workflow does not automatically create a GitHub Release, and no installer is committed to Git. Maintainers can publish a separately reviewed preview release. Release publishing and notarization remain separate. Hosted acceptance of each signing change is recorded in VALIDATION.md.

Native icon packaging: CI sets SEAMLESS_REQUIRE_NATIVE_ICON=1 and compiles the original layered Seamless.icon through Xcode actool. Local Command Line Tools builds have an explicit ICNS fallback and cannot establish native clear/tinted icon validation. The app does not override a compiled catalog's system-selected appearance.

Installer naming: local builds and GitHub Actions use `Seamless_<version>.dmg` and `Seamless_<version>.apk`. Android packaging removes the development-only `-dev` suffix from the filename; signing and the installed version are unchanged. Workflow artifact archives retain platform labels, while installer files use this shared naming convention.
