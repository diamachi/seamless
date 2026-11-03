# Validation record

## Scope

Physical checks used a dedicated Android test phone (Phone (1)/A063, Android 17/API 37, 1080×2400) and a development Mac. Model/API details describe coverage, not a supported-device guarantee. No personal account, phone serial, network address or certificate identifier is retained here.

Latest reconnect regression suite: 30 core tests and 9 Mac app tests passed. Android build, JVM tests and lint passed for companion 0.6.5. The Mac 0.6.6 signed build passed. Compilation alone is not hardware acceptance.

## Physically verified

| Area | Evidence | Limits |
| --- | --- | --- |
| Pairing | Phone-approved pinned-TLS pairing, saved-credential reconnect and live status; invalid credential and consumed invitation rejected | Wider network/device coverage pending |
| Debugging-free operation | Wi-Fi reconnect, screen capture, visible control and live status with USB/wireless debugging off | No conclusion about banking apps or every vendor build |
| Screen throughput | Controlled animation: approximately 60 fps received/enqueued; experimental request observed 118 fps at one moment | Not minimum sustained presentation or latency guarantees |
| Files | Generated 32 MiB transfers in both directions, checksum comparisons, automatic Downloads path and duplicate-safe destination behavior | 100 GB and persistent resume not tested |
| Android file UI | Multi-selection/folder workflow reported working on 0.6.3 | No separately enumerated large folder corpus acceptance |
| Transfer notifications | Android receive progress/verified result and Mac completion confirmed for generated 32 MiB transfer | Progress OS alerts intentionally removed in 0.6.4; terminal alerts retained |
| Android reconnect | After a deliberate Mac disconnect with automatic retries paused, Android Reconnect restored authenticated Connected state | Mac 0.6.6 + Android 0.6.5, same reachable local network |
| Storage | Granted shared-storage browsing, Download listing and generated-file retrieval | No private app data access |
| Camera | 1080p30 preview; OBS virtual camera visible in local QuickTime preview and browser camera selection after browser restart | 1080p60 normal-session mode rejected on this phone; conferencing reliability pending |
| Calls | Bluetooth HFP control connection and Mac device selector inventory | No successful live call, SCO PCM or two-way audio acceptance |
| Setup | Existing-pairing upgrade and live permission rows; native setup pages inspected | Fresh-install walkthrough still needs clean-install acceptance |
| Notifications | Local Mac test reached Notification Center after notifications enabled | Global display-sharing settings can suppress banners |

## Screen measurements

- Initial 864×1920 encoder run: 1,927 frames across 45 approximate one-second samples; session average 42.68 fps, peak interval 60.88 fps. Motion was not labeled separately from startup/static content.
- Controlled 60 fps run: final 20 encoder intervals averaged 59.27 fps (55.69–60.68); 109-second session average 58.45 fps.
- Experimental 120 fps run: final 20 retained encoder intervals averaged 116.04 fps (104.85–120.61); 101-second session average 109.8 fps. The log retains 78 samples, not every interval.

Numeric-only fixtures are in [test-results](test-results/). They do not contain screen content or device identity. Encoder, transport and panel presentation are distinct measurements.

## Reconnect correction

Earlier Android reconnect builds restarted the listener but did not restore a deliberately disconnected Mac. Read-only discovery checks confirmed the phone emitted a reconnect UUID. The correction combines TXT update monitoring, numeric IPv4 preference, replacement of waiting connection attempts, and a 15-second authentication deadline. The final controlled Android-button test succeeded without re-pairing and was independently confirmed in the Mac Devices UI.

## Packaging

The 0.6.6 DMG was checksum-verified, mounted read-only and inspected for Seamless.app plus an Applications shortcut. Its staged app passed signature verification with ad-hoc identity and no signing team. It is not notarized. Installer/first-launch acceptance on another Mac remains pending.

## Still required

Long thermal runs and latency measurements; all older Android/macOS compatibility targets; multi-phone concurrency; interrupt/resume and 100 GB transfers; broad folder/provider/error cases; system camera-extension distribution; real call audio; automatic hotspot switching; production release signing and clean-machine installation.

## 0.6.7 cleanup and Devices UI

- Mac signed release build and all 39 Swift tests passed. Android assemble, JVM tests and lint passed.
- Source privacy checks and targeted identifier/vendor-name scans passed; all local Markdown links resolved. Generated caches and local signing/SDK files are excluded from the source audit, not distributed as source.
- Connect new phone was clicked in the running Mac app and opened Devices. Numbered pairing steps, themed code field, saved phones below and collapsed optional USB section were visually inspected. No new phone pairing or permission grant was performed.
- DMG checksum and staged app signature passed. Read-only mount confirmed Applications shortcut and ad-hoc signature with no signing team. Packaged Mac executable had no personal home paths or local username; APK entries scanned had no personal home paths or local username. Clean-machine installation still needs acceptance.
- Removed debug pairing-code cache export and the vendor-specific OS-name entry/UI wording. Existing OS-stored trust and local development signing configuration were preserved.
- Test packages: `dist/Seamless-0.6.7-macos.dmg` and `dist/Seamless-Android-0.6.7-dev.apk`.

## macOS 0.6.8 Quit controls

Built the shared QuitApplicationButton in the main sidebar and menu-bar dashboard; source privacy scan passed. Clicked the sidebar Quit control and independently checked that no Seamless process remained, then reopened the app. Menu-bar control uses the same action but was not clicked: menu-bar host UI automation timed out. The 0.6.8 DMG checksum verification passed. Android is unchanged from 0.6.7.

## GitHub build setup and macOS 0.6.9

Local Mac tests passed (30 core + 9 app); native release build passed with explicit legacy-icon fallback because actool is not installed locally. The Android CI packaging script completed assemble/JVM tests/lint and produced its versioned APK. actionlint, shell syntax and source privacy checks passed. Native clear/tinted icon compilation is required in the hosted full-Xcode job and remains pending its first run. Translucency and app-lifetime window restoration are implemented; physical close/reopen acceptance is recorded separately when checked. No production signing keys were added.

macOS 0.6.9 lifetime check: closed the main window and independently confirmed the process remained alive. Tester confirmed the menu-bar Open app action restored the main window and that the menu panel is translucent. Screenshot feedback identified an excessively transparent title-bar strip; the toolbar now uses an opaque matching palette background. Dock accessory-mode switching was added after the initial check and requires its own acceptance.

Hosted build acceptance: https://github.com/diamachi/seamless/actions/runs/41605666272 passed both macOS and Android jobs at commit 682064c. Downloaded and mounted the hosted 0.6.9 DMG read-only: checksum/signature passed, Assets.car was present and CFBundleIconName/CFBundleIconFile both identify Seamless. Native clear/tinted icon compilation is verified; its appearance under the system clear mode has not been physically selected/tested. The initial SDK PATH/older-runner icon failures were corrected before this pass.

The final local title-bar correction was built and visually inspected: the wallpaper-colored strip is replaced by an opaque matching app background. Menu-bar restore and panel translucency were confirmed by the tester. Final source adds accessory-mode switching when all titled windows close and restores regular mode on Open app.

Final hosted installer run https://github.com/diamachi/seamless/actions/runs/41606443073 passed both jobs at source commit ec0e498, including the title-bar and accessory-mode corrections. Downloaded both artifacts and verified their published SHA-256 checksums independently. Artifacts: Seamless-macos-arm64 (13217207446) and Seamless-android-debug (13217181792). No release signing/notarization is implied. A further main-window close preserved the app process, and reopening restored the connected workspace. Native system clear-mode appearance remains an explicit physical visual check; compiled native icon resources are verified.

GitHub preview release acceptance: https://github.com/diamachi/seamless/releases/tag/v0.6.9 is published (not a draft), marked prerelease, and explicitly labeled unnotarized. API inspection confirmed the approved macOS DMG, Android CI-debug APK and checksum file are attached with expected sizes. Original notarized-release request could not be completed because no Developer ID Application identity was available; publication of the unnotarized alternative was explicitly approved. No notarization submission or claim of Apple acceptance was made.

## 0.6.10 Mac-generated QR pairing

Implemented Mac-generated QR → Android camera scan → encrypted local invitation handoff → existing pinned-TLS pairing and phone approval. Full-code fallback now shows/selects the phone invitation and explains button availability. QR creation and fallback failures have visible status; no Mac camera permission is requested.

Local checks passed: 32 core tests and 10 app tests, including a synthetic live TCP round trip that decodes the rendered QR, rejects an old session, authenticates the acknowledgement and confirms one-use consumption. Android build/JVM tests/lint passed; its AES-GCM fixture decrypts the same synthetic Swift envelope and rejects tampering/role confusion. These are automated synthetic tests, not physical camera/phone pairing acceptance. Real Android scanning, permission denial/retry, expiry and fresh-device upgrade acceptance remain pending.

0.6.10 hosted acceptance: https://github.com/diamachi/seamless/actions/runs/41614246809 passed both installer jobs at d894ace. Downloaded Mac/Android artifacts and independently verified their SHA-256 manifests. The first hosted Mac attempt exposed an existing fixed-sleep expiry-test race under concurrent QR/vision load; replaced that sleep with a bounded wait for the actual cancellation event. No production transfer timeout was changed. Running Mac UI confirmed an enabled Create pairing QR action and a generated one-use QR with a five-minute countdown. Physical Android scanning remains pending. The owner approved publication of the unnotarized preview with simplified installer filenames. Installer checksums were reverified after renaming; future local and CI builds use Seamless_<version>.dmg and Seamless_<version>.apk.

## 0.6.11 palette, camera and sharing changes

Implemented: burgundy/peach light and dark palettes; flexible camera preview and profile beneath it; live cameraControls routing; larger themed screen navigation/pop-out controls; Settings under Manage; hotspot removed including its Mac location purpose string; paired-session power leases; high-importance Android sharing requests and foreground approval dialogs; automatic one-Mac share-sheet sends and multi-Mac selection; folder ZIP within the sharing card; setup Downloads choices and Mac access check; Mac sound-status reporting.

Local macOS tests passed (32 core, 10 app). The initial sandboxed QR loopback test could not listen; rerunning with local-network access passed without changing its assertions. Android assemble, nine JVM tests and lint passed. Mac release build passed. Native UI inspection confirmed the palette, expanded preview, profile below it, themed dropdown/torch controls and sidebar ordering in the new build. No camera request, file browsing or phone control was initiated on the primary phone. Screen-off endurance, wake-lock battery use, actual Camera2 adjustments, Android approval dialogs, external share-sheet transfers and automatic Downloads onboarding remain physical acceptance checks on the Nothing test phone. These are not claimed fixed on hardware yet.

Local testing artifacts: `dist/Seamless_0.6.11.dmg` (hdiutil integrity verification passed) and `dist/Seamless_0.6.11.apk`. Local Mac builds use the existing development identity; packaged DMG copies are ad-hoc signed and unnotarized. No 0.6.11 GitHub release has been published.

## 0.6.12 removal, notifications, capture recovery and stable Android signing

The reported stale-pairing issue was resolved by the owner re-pairing; the earlier Mac error was TLS bad-certificate-format. No certificate validation bypass was added. Offline forgetting now completes locally; a new isolated regression test passes without a peer or network acknowledgement. Local Mac coverage: 32 core + 11 app tests pass. Android release assemble/JVM tests/lint and the stable signer check pass. Main workflow syntax passes actionlint; private signing files are Git-ignored and the source privacy scan passes. The DMG passes hdiutil integrity verification.

The owner explicitly approved storing the new Android distribution key/passwords in encrypted Actions secrets for diamachi/seamless. Four signing secrets were configured without printing their values. Local release APK verification reports the certificate digest recorded publicly in android/signing-certificate.sha256. Switching from prior debug keys can require one final reinstall; no personal-phone uninstall has been performed. Hosted signing acceptance will be recorded after the new main build completes.

Camera regression is reported in Seamless’s own preview at both 30/60 fps, rather than only OBS output. Candidate changes bound Android frame/TCP buffering, request keyframes after display backpressure and avoid redundant/animated video layout changes. These are code/build-verified, not a physical resolution claim. Actual OPPO camera latency, audible request/transfer channels, banner actions, Android per-Mac disconnect/resume and connected two-sided trust revocation remain hardware acceptance checks. No OPPO control/camera session was initiated by the agent.

Hosted signing acceptance: https://github.com/diamachi/seamless/actions/runs/41647713026 passed both jobs at 94ed1de. Downloaded both artifacts and independently checked their SHA-256 manifests. apksigner verified the hosted Android release APK and reported certificate SHA-256 matching android/signing-certificate.sha256 and the local release build. The checked hosted APK/DMG are copied into dist/Seamless_0.6.12.apk and dist/Seamless_0.6.12.dmg with a local SHA256SUMS-0.6.12.txt. CI distribution-key consistency is verified; hardware acceptance remains pending as described above. No new GitHub Release has been published.
