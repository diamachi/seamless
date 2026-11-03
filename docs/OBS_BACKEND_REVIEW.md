# Signed webcam backend options

Reviewed 2026-11-02 from primary OBS/Apple sources. This is a feasibility review, not a working direct-frame adapter or a verified signed-release integration.

## Recommendation without a Developer membership

Use the official OBS installation to own/install its signed camera extension. Seamless must not silently extract/rebrand/repackage that extension into its own ad-hoc app. Apple normally requires the host and system extension to share a signing Team ID (with a specific redistributable-entitlement exception); the reviewed OBS extension entitlements do not include that exception.

Two integration paths are credible:

1. Existing implementation: the clean Seamless Camera Output window can be captured as a source in OBS, then OBS Virtual Camera can feed conferencing apps. This requires OBS running and its capture/camera approvals. It is a fallback and still needs physical acceptance here.
2. Research path: send decoded frames to the installed OBS extension's CMIO sink directly. Current OBS `OBSCameraStreamSink` exposes a sink and its `authorizedToStartStream` implementation accepts clients. `OBSCameraDeviceSource` supplies a 1920x1080 BGRA/60 fps format and forwards consumed sink samples to its camera source. This suggests an independent Seamless CMIO client may be possible without a running OBS UI. It remains an engineering inference until verified against an actual official signed release. It is not a stable cross-vendor camera-injection contract. Stream discovery, format negotiation, queue ownership/backpressure, decoder/GPU conversion, concurrent-writer handling, stop/restart and Teams/Meet acceptance require tests. The output would retain the OBS Virtual Camera identity.

An OBS source plugin is a separate possibility: Seamless feeds frames to a plugin loaded by OBS, which routes to its virtual camera. This requires OBS running. Embedding/rebuilding libobs or a copy of its extension does not confer OBS's signing identity; distribution and GPL obligations need a deliberate review before bundling. No OBS source was copied into this project.

## Account distinction

Free Apple developer registration exists. The paid Apple Developer Program (US$99/year or regional pricing) provides the normal Developer ID signing/distribution path. A free account alone does not resolve this project's standalone camera-extension signing need. Do not suggest disabling SIP as a normal app setup step. Owner currently has no membership/signing identity, and no purchase is needed to continue the rest of Seamless.

## Sources

- OBS official installation/compatibility: https://obsproject.com/kb/virtual-camera-troubleshooting
- OBS virtual camera guide: https://obsproject.com/kb/virtual-camera-guide
- Sink/client authorization: https://github.com/obsproject/obs-studio/blob/master/plugins/mac-virtualcam/src/camera-extension/OBSCameraStreamSink.swift
- Sink-to-source forwarding/format: https://github.com/obsproject/obs-studio/blob/master/plugins/mac-virtualcam/src/camera-extension/OBSCameraDeviceSource.swift
- OBS extension entitlements: https://github.com/obsproject/obs-studio/blob/master/plugins/mac-virtualcam/src/camera-extension/cmake/macos/entitlements.plist
- OBS frontend API: https://docs.obsproject.com/reference-frontend-api
- Apple signing/host requirements: https://developer.apple.com/documentation/systemextensions
- Apple account/program comparison: https://developer.apple.com/programs/

Physical test preparation: official OBS33.0.1 Apple Silicon DMG downloaded from the OBS download page, mounted read-only, deep signature verified outside the sandbox and Gatekeeper assessed as accepted/Notarized Developer ID. Installed /Applications/OBS.app for the user's requested test. Initial permission review is open. Screen recording and virtual-camera extension approvals are awaiting owner choice; no camera, microphone or Input Monitoring grants were made. A sandboxed signature check initially failed to access trust correctly; the elevated verification passed without modifying OBS.

Alternative without a Mac camera extension: Android14QPR1+ includes DeviceAsWebcam/UVC support when enabled by the phone manufacturer. USB preferences must actually offer Webcam; Android version alone does not establish support. It appears as a standard USB camera to macOS. Seamless cannot add the required USB gadget/kernel/OS integration as an ordinary Android app. Source: https://source.android.com/docs/core/camera/webcam . Support on the authorized Nothing phone is not established.

OBS test update: owner reports permissions enabled. systemextensionsctl confirms OBS Virtual Camera33.0.1 activated/enabled. First Start Virtual Camera failed with “Could not find the virtual camera system process.” Restarting OBS, without logout/reboot, resolved that error: the control changed to Stop Virtual Camera. This verifies driver startup only, not the phone-output capture or conferencing client frames. The pending phone camera request has not produced frames; owner reports only Connected on the phone. No broadcast, recording or meeting was started. Clean output window opening is now allowed while idle to permit configuring OBS before starting a phone session.

2026-11-03 live source acceptance: owner-approved phone camera received1920×1080 at30fps. Rebinding OBS to the current Seamless Camera Output window produced the actual phone image in OBS. Old captured window IDs became invalid across Seamless restarts. For this960×540logical-content window, capture includes56physical pixels of title bar; top crop56 yields the camera-only image. Keep window size stable with this crop. OBS Virtual Camera started with the live source at30fps. QuickTime consumer check pending owner action after automation bind timeouts. No Teams/Meet success claim, broadcast, recording or meeting. A future chrome-free output/direct CMIO bridge would avoid manual window rebinding/cropping.
