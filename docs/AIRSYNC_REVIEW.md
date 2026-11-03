# AirSync reference review

Reviewed 2026-11-02. This is a documentation/repository-metadata review, not a source-code security audit or physical-device test.

## Relevance

AirSync closely overlaps this product: native SwiftUI macOS app, Kotlin/Compose Android companion, local network communication, notifications and replies, clipboard bridge, files, media controls, phone status, screen/app mirroring and desktop mode. It is a useful baseline to evaluate before independently rebuilding those features.

Current repositories are `sameerasw/airsync-mac` and `sameerasw/airsync-android`. The older `AirSync` and `AirSyncMac` repositories are discontinued and should not be used as current implementation evidence.

## Debugging constraint

The official mirroring instructions require scrcpy, ADB, Developer Options and enabled Wireless Debugging. Pairing is described as once per device pair; that does not mean debugging can be disabled during mirroring. The instructions explicitly describe re-enabling wireless debugging after network changes. AirSync does not establish a solution to our preferred debugging-off screen-control requirement.

The current feature page describes Mac-to-Android copy/paste and sending text back. Older official documentation describes Android-to-Mac sharing through the Android share sheet. Fully automatic bidirectional background clipboard behavior has not been confirmed in the current source or on a device. Do not infer it from the phrase "clipboard sync."

## Gaps and reuse decision

Webcam/live camera, hotspot automation, and find-phone behavior were not established by the reviewed feature listings. Absence from these pages is not proof of absence from the app.

The macOS LICENSE currently includes MPL 2.0 text plus additional terms explicitly prohibiting distributing modified builds, including free builds. Therefore do not adopt its code as the basis for our planned publicly distributed app without resolving permissions. The Android license contains different additional terms; review each component separately. This review records the actual published wording rather than determining legal enforceability.

Official protocol documentation describes WebSocket/JSON and optional AES-256-GCM encryption, with a symmetric key stored in UserDefaults. This is documentation evidence only and may lag code. Do not copy that security design or treat the marketing encryption claim as an audit. Our proposed secure platform key storage, authenticated pairing and encrypted transport remain independent decisions.

The website lists paid AirSync+ features and a free self-compile option. Personal self-compilation and public redistribution are separate questions.

## Recommendation

Use AirSync as a behavioral reference and possible personal-use baseline. Before choosing a new build versus contribution, evaluate actual device reliability, clipboard directionality and the debugging-off feature set. Maintain an independent implementation path for the planned free public app unless explicit reuse permission and component licensing are resolved.

## Sources

- Product/features/build options: https://www.sameerasw.com/airsync
- Mirroring setup: https://sameerasw.com/docs/airsync/getting-started/adb-mirroring
- Current Android repository: https://github.com/sameerasw/airsync-android
- Current Mac repository: https://github.com/sameerasw/airsync-mac
- Mac license: https://github.com/sameerasw/airsync-mac/blob/main/LICENSE
- Android license: https://github.com/sameerasw/airsync-android/blob/main/LICENSE
- Protocol documentation: https://github.com/sameerasw/airsync-mac/blob/main/DOCUMENTATION.md
- Historical clipboard explanation (discontinued repository): https://github.com/sameerasw/AirSync
