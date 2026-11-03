# NectarLink reference and feature feasibility

Reviewed 2026-11-02 against the public main branch. This is a source/documentation review, not an independent physical test of NectarLink. Seamless implementation status is recorded separately in VALIDATION.md.

## Design direction

The design uses NectarLink as the main design reference, while retaining the O+ Connect flat wallpaper phone illustration. Reviewed the Hive light and Bloom dashboard screenshots and the design guide. Adopt the composition: a compact device overview, adjacent action cards, grouped navigation, tonal surfaces and consistent Light/Dark modes. Seamless uses a warm honey/paper and charcoal palette with native SwiftUI typography and controls. It does not bundle NectarLink's brand graphics, textures, fonts or source components. Unimplemented capabilities do not appear as working dashboard buttons.

References:

- Project and platform matrix: https://github.com/thtbee/nectarlink
- Design principles: https://github.com/thtbee/nectarlink/blob/main/docs/design/README.md
- Hive light screenshot: https://github.com/thtbee/nectarlink/blob/main/docs/screenshots/desktop-hive-light.png
- Bloom screenshot: https://github.com/thtbee/nectarlink/blob/main/docs/screenshots/desktop-bloom-home.png

## The important debugging distinction

NectarLink documents Standard, Assist and Elevated capability levels. Its Elevated.kt starts a shell helper over ADB and grants WRITE_SECURE_SETTINGS; `turnOnWirelessDebugging()` can subsequently set `adb_wifi_enabled` back to 1. It also has a banking-app pause mechanism. Therefore, its one-time *setup* does not establish permanent debugging-off operation for elevated features. This conflicts with the user's preferred default. Seamless's tested default remains ordinary app permissions plus optional accessibility and approved capture, with debugging off. Any future privileged companion would need a separate explicit product decision; this review does not authorize enabling one.

Sources: https://github.com/thtbee/nectarlink/blob/main/android/app/src/main/kotlin/app/nectarlink/android/elevated/Elevated.kt ; https://github.com/thtbee/nectarlink/blob/main/docs/guide/known-limitations.md ; https://github.com/thtbee/nectarlink/blob/main/docs/guide/mirroring.md .

## Feasibility for Seamless on macOS + Android

The assessments below are engineering inferences from the source paths and platform APIs. “Feasible” means a credible implementation path, not implemented or physically accepted. Keep sensitive features opt-in per device and preserve explicit target identity.

| Feature family | Feasibility with debugging off | Seamless direction |
| --- | --- | --- |
| Notifications, app filters, actions, progress/live updates | Feasible with notification access. Android can redact sensitive content. | Existing relay/filter/actions; add progress presentation and optional grouping. Do not promise OTP extraction from redacted alerts. |
| SMS/MMS, contacts and call history | Conditional: Android permissions/default-handler roles and distribution requirements. | Separate opt-in module; start with compose/dial intents or a clearly scoped viewer. Do not request all permissions during pairing. |
| WhatsApp/Signal/Telegram/RCS unified inbox | Partial: receive/reply to exposed notifications; no general public access to their historical databases or arbitrary new threads. | Notification-backed conversations are plausible; label coverage honestly. |
| Call alerts/dial/answer controls | Conditional on Android API, permissions and role. Full cellular audio routing to Mac is a distinct unresolved problem. | Investigate call metadata and dial intent first; do not treat Windows call controls as a Mac audio implementation. |
| Clipboard text, images and optional history | Mac automatic sync and explicit Android foreground/share actions are feasible. Unattended Android clipboard reads are restricted on Android 10+. | Existing text paths; add image sharing and Quick Settings/explicit foreground action. Optional encrypted history needs retention controls; never store secrets/OTPs by default. |
| Large files/folders, resume, file-manager integration | Feasible. User-selected Android documents/tree access; a separate bounded bulk channel; macOS File Provider or share extension for native integration. | Replace 20 MiB control-channel prototype with resumable transport before claiming production folder/drive support. |
| Photos and albums | Feasible with Android selected-photo/media access and explicit permissions. | Read-only gallery with bounded thumbnails and downloads; no broad storage privilege needed for a first version. |
| Handoff links/maps/videos | Links feasible using validated http/https intents; timestamps require provider-specific URLs. | Add explicit Open on phone/Mac. Validate schemes and ask before unusual destinations. |
| Mirror audio, screenshot and recording | Feasible during approved capture, within Android playback-capture policy; protected content remains excluded. | Existing video transport; add opt-in audio/recording with visible stop state. Never claim banking/DRM content is capturable. |
| Independent phone apps in their own windows, screen off while streaming, raw multitouch/UHID | NectarLink uses Elevated. General debugging-off availability is not established. | Keep whole-screen streaming + optional accessibility as the default. Treat these as a separately gated research track. |
| Type on phone without mirroring | Feasible with an explicitly approved accessibility session or active custom input method; full physical-key behavior varies. | Current focused-field replacement exists only during a stream. A standalone typing session needs separate visible consent, stop and expiry. |
| Phone quick controls | Flashlight/media volume/media sessions are plausible; DND and brightness require special access. Wi-Fi/Bluetooth/hotspot toggles are restricted on current Android. | Add only individually supported controls and capability reporting; keep guided settings fallbacks. |
| Phone as Mac touchpad, keyboard, presentation remote and macro deck | Feasible with macOS Accessibility permission and explicit phone/device opt-in. Voice input needs microphone/recognition permission. | Dedicated remote-input channel, consent and emergency stop. Shell commands remain a separate disabled-by-default capability. |
| Reverse Mac screen sharing | Feasible with ScreenCaptureKit and macOS Screen Recording approval; remote control separately gated. | Separate capture service and per-phone session approval; never bundle viewing permission with input. |
| Webcam and continuity capture/document scan | In-app preview already verified. System webcam needs a signed/deployed CoreMediaIO camera extension. Still capture/scan can use CameraX/Camera2 plus local processing. | Prioritize still photo/scan next to the existing camera pipeline; full webcam remains blocked on full Xcode/signing setup. |
| Phone speaker, mic and voice recorder | Feasible with explicit audio permissions and visible streaming/recording. Cellular-call audio is not ordinary media playback capture. | Add separate bounded audio sessions, echo/latency handling, route selection and recording consent. |
| Media controls and battery alerts | Feasible via Android media-session notification access, Mac media adapters and current status channel. | Good next additions; configurable thresholds with deduplication. |
| Find device, lock/sleep/wake | Reachable-device ringing feasible; Mac locking/sleep need explicit commands. Wake depends on Mac hardware/network settings, not guaranteed powered-off wake. | Existing nearby phone ring; reverse ring and sleep/lock can follow explicit approval. No remote-location promise. |
| Timeline, command palette, shelf, widgets, connection diagnostics | Feasible and largely independent of Android privileges. | Strong next usability work: metadata-only event timeline, searchable actions, network/permission diagnostics. History should be opt-in and bounded. |
| Real phone wallpaper / wallpaper colors | Colors have a public API on API 27+. Direct wallpaper image reads are restricted on modern Android; vendor/system access differs. | Current local per-phone image choice; investigate vendor-specific paths separately. NectarLink SystemMonitors uses wallpaper **colors**, which does not establish automatic image extraction. |

## Platform evidence and useful source pointers

NectarLink's README marks macOS as Preview and does not claim parity with its Windows mirror/virtual-camera/file-manager feature set. Keep a native Mac implementation plan; a Windows feature screenshot is not proof that the needed macOS adapter exists.

- Clipboard limitations: https://github.com/thtbee/nectarlink/blob/main/docs/guide/clipboard.md
- Input/quick controls: https://github.com/thtbee/nectarlink/blob/main/docs/guide/input-and-control.md
- Messages: https://github.com/thtbee/nectarlink/blob/main/docs/guide/messages.md
- Calls, including phone-side voice audio: https://github.com/thtbee/nectarlink/blob/main/docs/guide/calls.md
- Wallpaper color sampling: https://github.com/thtbee/nectarlink/blob/main/android/app/src/main/kotlin/app/nectarlink/android/core/SystemMonitors.kt
- Android media/audio capture: https://developer.android.com/media/platform/av-capture
- Android Wi-Fi restrictions: https://developer.android.com/reference/android/net/wifi/WifiManager#setWifiEnabled(boolean)
- Default handler guidance: https://developer.android.com/guide/topics/permissions/default-handlers

## Suggested order after the current design/device-details slice

1. Capability reporting and connection diagnostics, media controls, configurable battery alerts, explicit URL handoff.
2. Dedicated resumable file transport, selected-photo browsing and image clipboard.
3. Still camera/document scanning and signed virtual webcam packaging.
4. Optional remote Mac input, reverse screen sharing and audio sessions.
5. Separately scoped calls/messages permissions and native file-manager integration.

Independent displays and privileged control remain outside the default debugging-off path. Do not add dead controls to imitate feature breadth.
