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
