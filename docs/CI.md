# GitHub Actions builds

`.github/workflows/build.yml` runs on pushes to main, pull requests and manual dispatch. The jobs have read-only repository permission; checkout does not persist credentials. Official actions are pinned to commit SHAs, with version comments for maintenance. Pull requests do not receive signing secrets. A new run cancels an obsolete run for the same ref.

## macOS

The macos-26 Apple-silicon runner selects Xcode 26.3 explicitly, checks architecture/source privacy, runs native tests, builds the app and packages/verifies a DMG. SEAMLESS_SIGNING_IDENTITY is explicitly ad-hoc. The job uploads only the DMG and its checksum, not a workspace, debug symbols, credentials or build cache.

The resulting app is an Apple-silicon test build, not universal, Developer ID signed or notarized. Installing a differently signed copy can request fresh macOS/Keychain approval. Minimum OS metadata is not proof of compatibility with every supported system.

## Android

The Ubuntu job installs Temurin JDK 21, SDK platform 36 and build tools 35.0.0. `scripts/build-android.sh` runs assembleDebug, JVM tests and lint, then copies the APK to dist with its configured versionName. Gradle dependency caching does not include an Android signing keystore. On failure, test/lint reports are available separately.

The APK is debug-signed using the runner's generated development key. It is installable, but is not a stable update channel: another run or local build may have a different key. Preserve your data before replacing an existing differently signed development install. A dedicated release key and repository secrets are separate future setup; no local private signing key is uploaded by this workflow.

## Downloading

Open Actions → Build test installers → a completed run. Download `Seamless-macos-arm64` or `Seamless-android-debug` from Artifacts and extract the archive. Each includes a SHA-256 checksum file. Installer artifacts expire after 14 days; failure reports after 7 days.

No GitHub Release is created and no installer is committed to Git. Release publishing, stable signing and notarization remain separate. The workflow is implemented locally until a hosted run is recorded in VALIDATION.md.

Native icon packaging: CI sets SEAMLESS_REQUIRE_NATIVE_ICON=1 and compiles the original layered Seamless.icon through Xcode actool. Local Command Line Tools builds have an explicit ICNS fallback and cannot establish native clear/tinted icon validation. The app does not override a compiled catalog's system-selected appearance.
