# Development plan

## Implemented foundations

Native SwiftUI/AppKit Mac application and Kotlin/Compose Android companion; pinned local TLS, explicit pairing, Keychain/Keystore-backed credentials, saved-phone discovery, separate device preferences, background connection service and guided setup. Normal Wi-Fi features operate without ADB. Optional USB and direct app mirroring require active debugging.

Feature paths include filtered notifications, clipboard sharing, screen/control, live camera, streaming file transfers, selected folder ZIP sending, storage/media browsing, menu-bar controls, hardware details and phone ringing. Reconnect from Android is physically accepted with Mac 0.6.6 and companion 0.6.5. Consult VALIDATION.md before describing any other path as device-tested.

## Current priorities

1. Reliability: long-running background operation, reboot/network-change recovery, interrupted transfers, cancellation and large batches.
2. Screen/camera: frame pacing, measured latency, rotation, capability-driven profiles and responsive input under network load.
3. Compatibility: Android API 24/26/29/34/36 boundaries, Android 16 baseline, multiple physical phones and simultaneous sessions.
4. Webcam: harden the experimental OBS bridge; separately build/sign/notarize a standalone camera extension if feasible.
5. Calls: verify real HFP/SCO call audio and independent input/output routing using an explicitly authorized test call.
6. Release: source license, distribution signing, notarization, clean installer testing and privacy review.

## Proposals, not working features

Resumable transfers; guaranteed 100 GB throughput; automatic remote hotspot activation; unrestricted background Android clipboard capture; guaranteed 120 fps presentation; cloud or internet relays; production-ready calling. QR pairing is implemented in 0.6.10; real camera/network acceptance is pending.

## Acceptance policy

Use only explicitly authorized test devices and data. Do not place/answer calls, enable permissions, clear existing trust or operate unrelated phones just to complete a test. Build checks establish compilation and regression behavior; physical tests establish the hardware/network behavior recorded in VALIDATION.md. Keep implemented, proposed and physically verified outcomes separate.
