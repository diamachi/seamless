# Architecture and developer guide

## Scope and status

Seamless is a native macOS app and Android companion for local device continuity. Android apps execute on the phone; the Mac displays their streams. A Mac can remember multiple phones, maintain independent trust/preferences, and select the target for interactive actions. Transfers and streams stay bound to their initiating peer.

Implemented paths include pinned TLS pairing/reconnect, notifications, clipboard, files/storage/media, screen/control, live camera, device details, ringing and optional ADB USB/app mirroring. Calls and OBS webcam routing are experimental. Automatic hotspot activation, persistent transfer resume and a standalone native camera extension are not implemented. QR pairing is implemented in 0.6.10 with physical acceptance pending. [VALIDATION.md](VALIDATION.md) distinguishes physical evidence from source/build coverage.

macOS package minimum is 14; Swift tools version is 6. Android minSdk is 24 and target/compile SDK is 36. Features use API gates; older-device compatibility must be physically tested rather than inferred from minSdk. Normal Wi-Fi operation does not require debugging. Optional ADB integration requires debugging throughout use.

## Entry points and ownership

### Mac

- `SeamlessApp.swift` creates app-lifetime stores, windows, notification delivery and the menu-bar dashboard.
- `PreferencesStore.swift` loads/saves preferences, owns feature coordinators, applies appearance and initiates saved-phone connections. `SeamlessCore/PreferencesRepository.swift` owns on-disk preference serialization; Keychain credentials are separate.
- `MainWindow.swift` owns workspace navigation. Its persistent **Connect new phone** sidebar action opens Devices. Workspace views observe feature state rather than owning network operations.
- `DeviceManagementView.swift` presents new-device pairing first, saved phones second and optional USB setup last. `Connection/ConnectionSettingsView.swift` explains Wi-Fi pairing and manual-address troubleshooting; `AndroidDebugBridge/USBConnectionSettings.swift` handles already-paired cable transport.
- `PhoneSwitcherView.swift` selects a saved phone. `PhoneOverviewCard.swift`, `DeviceDetailsCard.swift` and `ClipboardTextEditor.swift` compose the overview. Appearance and per-phone settings remain in their dedicated stores.
- `Connection/PhoneConnections.swift` coordinates authenticated clients, session state, per-peer policies, capabilities and feature dispatch. `PhoneControlClient.swift` handles framed control I/O, generation-bound connection lifecycle, heartbeat and a 15-second authentication deadline.
- `Connection/PhoneDiscovery.swift` resolves saved-phone DNS-SD services and monitors TXT changes. Core `DiscoveredPhoneEndpoint.swift` validates routing data and preserves the pinned certificate. `ReconnectRequestGate.swift` bounds explicit reconnect request replay/rate behavior.
- `Connection/BulkTransfers.swift` owns modern transfer offers, streamed jobs, timers, checksum acceptance and Downloads destinations. `BulkSocket.swift` owns binary TLS I/O. `FileTransfers.swift` retains the bounded legacy compatibility path. `FolderDownloads.swift` queues authorized folder-tree downloads; storage browsing uses peer-scoped tokens.
- `Screen/` owns native video rendering, screen requests and input mapping. `AndroidDebugBridge/` owns optional tool discovery, USB tunnels and direct app streams, separately from the debugging-free capture path.
- `Notifications/` owns native notification delivery. `NotificationSettingsView.swift` manages the relayed inbox and per-app policy. `ClipboardHistory.swift` stores optional bounded session-only text history.
- `Webcam/` owns the experimental direct OBS camera sink. `CameraWorkspaceView.swift` presents session controls and camera workflow. A standalone camera extension is not shipped.
- `Calls/CallsCoordinator.swift` owns explicit phone-to-Bluetooth mapping and HFP controls; `HandsFreeEvents.swift` translates callbacks. `CallAudioDeviceCatalog.swift` enumerates Core Audio endpoints; `CallAudioRouter.swift` validates/selects routes; `CallAudioPipe.swift` handles the experimental bidirectional audio pipes. Views observe these services.
- `Onboarding/SetupCoordinator.swift` tracks setup progress and native permission states. `SetupGuideView.swift` renders the optional guide. Existing pairings survive upgrades.
- `ActivityPopup.swift` shows live transfer state and transient notices. `MenuBarDashboard.swift` owns the status item, file drops and compact controls.

### Android

- `MainActivity.kt` owns activity lifecycle, native permission/capture results and external Share intents. `ui/CompanionAppRoot.kt` owns themed navigation, first-run welcome and global pairing approval.
- `ui/ConnectionPanel.kt` renders Overview, explicit sharing requests, file/folder actions and in-app transfer progress. `ConnectionOverviewCards.kt` and `MacDetailsCard.kt` display authenticated device summaries. `CompanionSettingsPanel.kt` exposes setup, background behavior and developer diagnostics.
- `ui/CompanionSetupFlow.kt`, `PermissionSetupPanel.kt` and `RecommendedAccessFlow.kt` guide runtime and special-access setup. `features/CompanionPermissions.kt` reads actual grants; `SetupAccessPolicy.kt` determines which steps remain.
- `connection/ConnectionService.kt` owns the foreground connected-device service and serializes start/reconnect/stop work. Its persistent system notification is distinct from transfer result alerts.
- `connection/PhoneServer.kt` owns the TLS listener, authenticated Mac peers, protocol dispatch, feature workers and short-lived media grants. `SecureIdentity.kt` owns Keystore identity and encrypted saved-peer credentials. `ControlChannel.kt` owns framed control/binary streams.
- `connection/ConnectionState.kt` defines observable state and `ConnectionRuntime`; updates are synchronized. `DeviceDetails.kt` reports available hardware/platform details. `PhoneAdvertisement.kt` publishes local DNS-SD discovery.
- `features/BulkExchange.kt` owns peer-bound transfers and the outgoing selection queue. `FolderArchive.kt` creates selected-folder ZIPs; `PendingDownload.kt` publishes verified incoming files into Android Downloads on supported versions. `TransferNotifications.kt` posts terminal results only.
- `features/StorageBrowser.kt` resolves authorized shared-storage or SAF tokens for browse/media/download requests. `FileExchange.kt` remains the legacy compatibility path. Screen/camera services own their respective foreground capture sessions; optional Accessibility control is separately granted.

## Pairing and connection flow

1. Android creates an expiring private invitation containing the phone identity, addresses, certificate pin and one-use pairing secret.
2. Mac Devices accepts the invitation and optionally a manual IP override, then starts pinned TLS.
3. Android displays the requesting Mac's name for approval. Saved credentials are committed only through this trust flow. macOS stores its credential in Keychain; Android protects saved-peer credentials through Keystore-backed encryption.
4. Saved connections authenticate with credentials. DNS-SD updates routing only, never trust. No cloud identity or relay is used.
5. Status advertises feature versions; dispatch gates optional payloads by those capabilities for older-companion compatibility.

The Mac new-phone flow is QR-first Wi-Fi pairing, with a full-code fallback. Manual IP is routing troubleshooting, not a second trust mechanism. USB appears separately for an already-paired phone and requires active debugging plus compatible local adb/scrcpy tools. QR pairing generates on Mac and scans on Android; see the 0.6.10 protocol below.

### Android-initiated reconnect

Android Overview exposes Reconnect when no Mac is connected. ACTION_RECONNECT replaces the disconnected PhoneServer through the service's worker; it rechecks connected state before teardown and preserves saved trust. The replacement listener sets reuseAddress before binding.

An explicit reconnect adds a fresh UUID `reconnect` TXT attribute to DNS-SD. Mac watches address and TXT callbacks, accepts only remembered phone IDs, filters recent UUID replays, and bounds attempts to one per phone per ten seconds. Numeric IPv4 is preferred when resolved, with hostname fallback. Numeric NSD collision suffixes are validated; retirement of an older service does not clear a newer endpoint.

A new endpoint or explicit request can replace a waiting attempt but never tears down an authenticated connection. The generation-bound authentication deadline returns stalled attempts to retry handling. Mac must be running on the reachable network. Discovery cannot bypass the saved certificate pin or credential checks.

## Feature flows

### Transfers and storage

Control metadata precedes a separate authenticated binary TLS connection. Offers bind random IDs to the correct peer, direction, expiry and one-time claim. Senders hash in bounded chunks; receivers stream and validate SHA-256 before committing a final file. JSON byte counts use the exact integer range through 2^53−1; disk space and platform limits still apply. There is no product cap, but 100 GB operation and persistent resume are unverified/unimplemented respectively.

Mac receives into a unique Downloads filename by default. Finder file promises or explicitly selected destinations override this. New-phone defaults enable automatic receiving; existing saved choices remain honored. Incomplete Mac files use sibling `.part` staging and are cleaned on failure. Android 10+ uses pending MediaStore Downloads; older versions use explicit save fallback.

Android OpenMultipleDocuments selections and external shares enter a serial outgoing queue bound to exactly one Mac. Hashing occurs off the UI thread; completion/cancellation advances the queue and honors the active-slot bound. Queue state is in memory, not persisted across process death.

OpenDocumentTree selects a folder. FolderArchive walks only that granted tree, validates names and nesting/cycles, and streams a ZIP into cache; empty directories and relative paths are preserved. Preparation needs free cache storage and shows indeterminate progress. The ZIP uses the ordinary transfer queue and temporary cleanup; the Mac does not automatically extract it.

Live progress stays inside both apps. OS notifications announce completion/failure only. Android outgoing “Sent to Mac” means bytes written; the Mac's result follows its own verification. Missing notification permission never blocks a transfer. Android retires the earlier progress channel. Its required connection-service notification stays visible.

Storage uses optional shared All files access or selected folder/media grants. Mac requests opaque, session/peer-scoped tokens, not arbitrary raw phone paths. Private app storage is not exposed. Listing and thumbnail workers are bounded. See [FILE_SHARING.md](FILE_SHARING.md).

### Screen, camera and input

Normal screen capture uses Android MediaProjection with per-session OS consent. The stream uses a separate authenticated media connection, hardware encoder and native Mac decoder/rendering path. Requested 60/120 fps is a profile, not a guarantee of unique panel-presented frames or latency. Optional Accessibility input is limited to approved sessions. Single-app standard capture still uses Android's chooser.

Optional ADB app mirroring runs separately and requires debugging throughout use. USB tunnels carry the existing authenticated connection and do not establish trust with an arbitrary cable-connected phone. Native stream embedding and pop-out windows share feature state.

Camera capture follows camera permission and an explicit paired-Mac request, with supported profiles/controls. Persisted per-phone choices do not override OS camera/background restrictions. OBS virtual-camera integration requires the installed driver and remains experimental; no native standalone camera extension is bundled. See [OBS_BACKEND_REVIEW.md](OBS_BACKEND_REVIEW.md).

### Notifications, clipboard and calls

Notification policy is per phone/app/profile. Supported actions/replies dispatch back to their originating peer. Mac foreground delivery uses a UNUserNotificationCenter delegate; macOS display-sharing/Focus settings may still suppress banners.

Clipboard UI sends explicit text or supported Android share actions; automatic Mac polling is opt-in. Android restricts unattended background reads. Optional history is bounded and session-only.

Calls uses public IOBluetooth HFP with explicit phone mapping. Input/output selectors expose actual Core Audio devices and prevent feedback routes. Microphone permission is requested before audio capture. Bluetooth control readiness is not proof of SCO PCM or live call audio. WhatsApp call handling has not been verified; the dial field is ordinary phone dialing. No WhatsApp-specific backend exists. See [CALLING_SETUP.md](CALLING_SETUP.md).

## Build and package

```sh
sh scripts/test-macos.sh
sh scripts/build-macos.sh
sh scripts/package-macos.sh
```

The Mac script uses project-local caches, Swift 6 and the available macOS SDK. `SEAMLESS_SIGNING_IDENTITY`, then ignored `.tools/signing-identity`, selects development signing; otherwise it is ad-hoc. Credentials/configuration must not be committed. The stable installed development identity is separate from distribution packaging.

Packaging reads the built bundle version, stages a copy plus Applications shortcut, strips debug symbols, ad-hoc signs only the copy, verifies it, creates a compressed UDZO DMG and verifies its checksum. Staging is removed on exit. The test image excludes the local signing certificate and is not notarized. Installing a differently signed copy can trigger renewed permission/Keychain approval.

Android uses JDK 21, SDK platform 36, build tools 35.0.0 and the checked-in Gradle wrapper. Run assembleDebug, testDebugUnitTest and lintDebug from `android/`. APK signing is for development; release signing/licensing/store distribution remain separate work.

## Maintenance and privacy

Keep UI, state, protocol and platform side effects separate. Use descriptive names and readable branches; comments explain why. Changes to entry points, permissions, wire contracts, dependencies or behavior must update this guide and the relevant feature document.

Source/docs must not contain personal paths, phone serials, network addresses, signing identities or live trust material. Generated caches, installers, local.properties and keystores are ignored. Pairing invitations are no longer exported into a debug cache file. The build tree can still contain machine-specific compiler metadata; never distribute caches or an unreviewed workspace archive. Preserve credentials in their OS stores rather than deleting user trust as part of source cleanup.

### Explicit app quit controls (macOS 0.6.8)
`QuitApplicationButton.swift` is shared by the main sidebar footer and menu-bar dashboard footer. Both call NSApplication.terminate, preserving the existing willTerminate cleanup in SeamlessApp for calls, connections, media/ADB sessions and USB tunnels. These controls quit the process rather than merely closing the main window. Android behavior is unchanged.

### Hosted builds and menu-bar lifetime (macOS 0.6.9)
`.github/workflows/build.yml` runs read-only-permission jobs for main pushes, pull requests and manual dispatch. Mac tests/build/DMG verification run on Apple-silicon macos-26 with Xcode 26.3; Android tests/lint/debug packaging run on Ubuntu/JDK21 with SDK36. Official actions are SHA-pinned. Only installers/checksums and failure reports are uploaded; no workspace, trust data or signing identity is distributed. Artifacts expire; no automatic Release is published. See CI.md for development signing/update constraints.

ApplicationLifecycleDelegate now owns process-termination cleanup and explicitly keeps the process alive after the last window closes. The main scene is a single Window, not a WindowGroup. MainWindow registers an openWindow callback with both the delegate and MenuBarDashboard. Open app dismisses the menu popover, recreates/restores the main scene, and activates the app; Dock reopening also restores the window. When the last titled window closes, the app switches to accessory mode so only its menu-bar presence remains; opening the main window restores the Dock presence. Preferences, connections and menu dashboard remain app-lifetime objects. Quit still terminates all sessions even after the window has closed.

TranslucentSurface wraps NSVisualEffectView with native sidebar/under-window/popover materials and a quiet palette tint. WindowSurfaceConfigurator provides a transparent window backing; cards retain readable surfaces. Reduce Transparency selects an opaque fallback. The title-bar toolbar uses an opaque matching canvas color so wallpaper cannot create a bright strip above the content. No glassEffect or Liquid Glass control styling was added.

The original three-point artwork has a layered `Support/Seamless.icon` source. Full-Xcode builds compile it using actool and merge generated icon metadata, enabling system default/dark/clear/tinted rendition selection. AppIconController stops overriding the system icon for catalog builds. Command-Line-Tools-only builds retain legacy ICNS; CI requires native icon compilation and fails rather than silently omitting it. Native clear-icon compilation/appearance and hosted workflow status must be recorded separately from the local fallback build.

### Manual GitHub preview release
`v0.6.9` is a manually published GitHub prerelease, explicitly approved for unnotarized distribution. It attaches the checked macOS 0.6.9 ad-hoc DMG, Android 0.6.7 CI-debug APK and SHA256SUMS.txt. This is separate from the read-only build workflow and does not configure automatic publishing, stable release keys or Apple notarization. All distribution remains through GitHub; no App Store submission is involved.

Unnotarized release installation guidance is maintained in RELEASE_TEMPLATE.md and mirrored in the README. Project rules require including it in every unnotarized GitHub release. It documents an explicit user-run quarantine-attribute removal command for the installed Seamless bundle; app code/installers never execute it and no system-wide Gatekeeper setting is changed.

### Mac-generated QR pairing (0.6.10)
Mac Devices now leads with Create pairing QR; Android Overview/setup leads with Scan Mac QR code. The old full-code flow remains in an explicit fallback, where Android shows a selectable invitation, Copy action, expiry and creation errors. Mac Paste/Pair labels explain when manual pairing becomes available.

`Pairing/MacQrPairingCoordinator.swift` opens an ephemeral local TCP listener only for the visible pairing page, with a 15-second startup deadline and five-minute session lifetime. `LocalPairingAddresses.swift` enumerates active non-loopback, non-point-to-point IPv4 routes. The QR (`seamlessmac1:` + base64 JSON) contains version, random session UUID, Mac display name, up to eight local addresses, ephemeral port and a cryptographically random 256-bit key. Core Image renders it; nothing is uploaded, logged or persisted. Closing/hiding/regenerating the QR invalidates its listener/key.

Android parses the QR using `MacQrPairingOffer.kt`. `PairingQrCameraPreview.kt` uses lifecycle-bound CameraX 1.6.2 and ZXing core 3.5.4, processing luminance frames locally at most four times a second. Camera permission is requested only upon opening the scanner; no Mac camera access is needed. Frames are neither saved nor sent. Preview/analyzer resources are unbound on completion/dismissal. The scanner ignores unrelated QR payloads.

`PhoneServer.pairUsingMacQr` creates a normal fresh phone invitation. `MacQrPairingTask.kt` encrypts it with AES-256-GCM using the QR key, a random 96-bit nonce and a 128-bit tag. AAD is UTF-8 `Seamless QR pairing v1:<sessionID>:request`. Only the session ID and sealed nonce+ciphertext+tag travel over TCP. The authenticated acknowledgement seals `accepted` with purpose `ack`, preventing reflection. The QR key never travels on this network connection. Requests are bounded to 32 KiB, replies to 1 KiB; Android uses finite connect/read timeouts and a cancellable socket, while Mac permits at most three simultaneous connections with ten-second deadlines.

Core `MacQrPairingOffer.swift` validates/decrypts a complete phone invitation, including its certificate pin and existing strong pairing secret. The coordinator consumes the QR once, sends its encrypted acknowledgement, then invokes the existing pinned-TLS pair flow. Phone approval and credential storage are unchanged. QR discovery/bootstrap does not grant trust or weaken TLS; no short low-entropy authentication code replaces the invitation. This does not depend on an Internet service, ADB or cloud account.

Swift/Kotlin share a deterministic synthetic AES-GCM test vector. Regression coverage verifies tamper rejection, purpose/session separation and complete invitation validation. Build checks and physical scanning acceptance are tracked separately in VALIDATION.md. New third-party dependencies use Apache-2.0 licensing; see THIRD_PARTY_NOTICES.md.

Installer naming: local builds and GitHub Actions use `Seamless_<version>.dmg` and `Seamless_<version>.apk`. Android packaging removes the development-only `-dev` suffix from the filename; signing and the installed version are unchanged. Workflow artifact archives retain platform labels, while installer files use this shared naming convention.
