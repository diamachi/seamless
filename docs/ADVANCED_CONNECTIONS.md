# Optional ADB and USB modes

Implemented in development, physical validation pending unless recorded in VALIDATION.md. Default Wi-Fi pairing remains debugging-free.

## USB transport

Devices → Find USB phones explicitly runs `adb devices -l`; it does not automatically choose or operate the first connected phone. The user selects an authorized USB serial and chooses Connect over USB for an already paired Seamless phone. USBConnectionController asks ADB for an ephemeral localhost forward to the companion's saved TLS port. PhoneConnections gives this runtime-only profile priority over discovery; it retains the paired certificate pin and Keychain credential and verifies the returned phoneID. Localhost profiles are never written to remembered-phone settings. Screen, camera, files and other channels all open through the same forwarded TLS endpoint.

USB verification gates the advanced app-window launcher. A forwarding success alone is not proof of phone identity. Disconnect/Forget clears verification and stops that phone's app windows. Unplug/transport failure removes only Seamless's owned forward and falls back to saved Wi-Fi. Shutdown launches cleanup for each owned forward; no global ADB kill-server or forward --remove-all is used. Debugging must remain enabled for this transport. Debugging-free Android Open Accessory transport is not implemented.

## Native in-app ADB sharing

Phone screen → select an application → Share app over ADB starts a separate virtual display inside the existing phone preview. Pop out moves the same AVSampleBufferDisplayLayer into a separate window, and closing the popout returns it. The superseded external scrcpy GUI launcher is removed. Native rendering fits the encoded aspect to the available bounds; it never uses scrcpy's flexible-display default unscaled renderer that caused cropped output in the initial external-window test.

The backend is version-pinned to the scrcpy5.0.1 server, obtained from the installed tool. It pushes a uniquely named helper JAR to /data/local/tmp on the verified test device, owns an ephemeral ADB forward to a unique localabstract socket, and executes app_process as the already-authorized shell user. No companion APK update is needed for this backend. Video/control use two localhost connections through that owned forward. ScrcpySocketSession waits for the forward readiness byte, negotiates control, and launches the selected package only after the virtual display's session dimensions arrive, avoiding launching it on the physical phone display.

ScrcpyProtocol.swift parses the5.0.1 device/codec/session metadata and packet flags, bounds frame allocations, converts config packets to the existing H264 renderer format, and serializes app launch, key, text and touch messages. Standard Mac taps/swipes/navigation are routed to this control socket while the external stream is active. Clipboard autosync and audio are disabled for this first backend. Primary Android profile only; one active in-app ADB stream. App/DRM/virtual-display compatibility varies. No MediaProjection consent dialog is auto-clicked: this path uses explicit ADB shell authorization. Stop/USB failure/disconnect/shutdown close sockets, terminate the helper session, remove only its owned forward and temporary helper file. Default Wi-Fi functionality remains debugging-free.

## Files and entry points

- SeamlessCore/AndroidDebugBridgePlan.swift parses device metadata and validates argument plans. No shell interpolation.
- AndroidDebugBridge/AndroidToolRunner.swift locates project-bundled tools or known Homebrew paths and runs bounded, timed commands off the main thread.
- USBConnectionController.swift owns transient forwards/verification. USBConnectionSettings.swift is its Devices UI.
- AdvancedMirroringController.swift owns version checks, temporary helper deployment, the shell process and scoped cleanup. AdvancedMirroringControls.swift explains the mode in the screen-page UI.
- ScrcpySocketSession.swift owns bounded localhost video/control reads, startup retries, gestures and socket teardown.
- SeamlessCore/ScrcpyProtocol.swift supplies the version-specific parser and serializers.
- PhoneVideoStreamController.beginExternal/receiveExternal route native ADB records through the existing decoder surface and Pop out lifecycle.
- PhoneConnections.reconnect chooses USB overrides, markAuthenticated verifies the serial-to-paired-phone association, and its lifecycle removes transport overrides on failure.

Development dependency: Android platform-tools (`adb`) and scrcpy5.0.1 installed on Mac; tested tool discovery paths include /opt/homebrew/bin and /usr/local/bin. scrcpy5.0.1 was installed from Homebrew during this development run. The app supplies the ADB executable explicitly to scrcpy. Release packaging of these tools/dependencies and their notices is not yet implemented; no claim that a redistributed standalone bundle includes them.
