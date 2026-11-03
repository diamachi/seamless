# Taking Android phone calls in Seamless

Research/proposal, 2026-11-03. Follow-up: an experimental HFP backend, Calls UI and conditional Core Audio bridge are now implemented; see ARCHITECTURE.md and CALLING_SETUP.md. No call has yet been placed, answered, recorded or routed during agent testing. The API feasibility findings and hardware gates below still apply.

## Recommendation

Start with a feasibility prototype of **Bluetooth Hands-Free Profile (HFP)**. Android is the Audio Gateway (phone); the Mac is the Hands-Free unit, like a car kit or headset. Keep the existing pinned-TLS companion connection for other features. This route does not inherently require USB debugging, replacing the Android dialer or streaming protected cellular audio through the companion.

Apple's public IOBluetoothHandsFreeDevice API and the locally installed macOS 27 SDK expose dialNumber, acceptCall, endCall, currentCallList, sendDTMF, transferAudioToComputer and transferAudioToPhone. The superclass exposes a service-level connection, SCO connection and audio connection callbacks. These establish a credible API path; they do **not** prove working bidirectional audio on the current Mac/phone combination. The SDK does not provide a simple per-call input/output device picker on this class.

Sources: [Apple HFP device](https://developer.apple.com/documentation/iobluetooth/iobluetoothhandsfreedevice), [SCO connection](https://developer.apple.com/documentation/iobluetooth/iobluetoothhandsfree/connectsco()), [transfer audio to computer](https://developer.apple.com/documentation/iobluetooth/iobluetoothhandsfreedevice/transferaudiotocomputer()). Local reference: macOS27.0.sdk, IOBluetooth.framework/Versions/A/Headers/objc/IOBluetoothHandsFree{,Device}.h.

## What is feasible, and what is unresolved

| Capability | Assessment |
| --- | --- |
| Incoming call state, answer, reject/hang up, keypad | Public HFP API path exists; device prototype required. |
| Talk through the Mac | Conditional on a functioning HFP/SCO audio path on current macOS. This is the first major gate. |
| Independent microphone and speaker selectors | Core Audio supports choosing device IDs. Conditional on being able to bridge the phone's audio endpoint, rather than only triggering macOS's automatic route. |
| Built-in mic, USB mic, speakers or USB headset | Intended selectable Mac endpoints, subject to available stream formats and physical tests. |
| Bluetooth headphones paired with Mac | Additional compatibility/latency test; simultaneous Bluetooth links and headset mode changes can affect quality. |
| Wi-Fi/USB-only relay of arbitrary SIM calls | No supported ordinary-companion path established. Existing screen/file/camera transports do not grant call-audio access. |
| WhatsApp/Signal/other VoIP calls | Separate compatibility scope. Do not assume every app exposes equivalent HFP call controls. |
| Several paired phones | Keep identity/state isolated, but start with one active audio call. Dual-SIM selection and concurrent-call behavior require separate tests. |

For independent audio selection, enumerate Core Audio devices by input/output capability, retain stable device UIDs rather than transient numeric IDs, and provide System default options. Use separate capture/playback paths and sample conversion where needed. Hot-unplug must mute/pause and present an explicit fallback instead of silently switching a private call to speakers. Acoustic echo cancellation is necessary to evaluate for speaker use. HFP is a voice link; resampling will not turn it into full-bandwidth music audio.

Core Audio source: [Apple AUHAL device selection](https://developer.apple.com/library/archive/technotes/tn2091/).

## Why ordinary Android audio capture is insufficient

Android documents protected call capture separately from microphone capture: capturing cellular uplink/downlink requires privileged preinstalled access with CAPTURE_AUDIO_OUTPUT. Becoming the default dialer gives call management, not a general unrestricted cellular PCM bridge. MediaProjection playback capture is limited to eligible playback usages and is not a general call-audio tunnel. Do not promise that ADB, Accessibility or microphone permission alone solves this.

Sources: [Android sharing audio input, Voice call + ordinary app](https://developer.android.com/media/platform/sharing-audio-input), [MediaRecorder audio sources](https://developer.android.com/reference/android/media/MediaRecorder.AudioSource), [playback capture](https://developer.android.com/media/platform/av-capture).

InCallService is a possible separate control backend if the owner deliberately chooses a default-dialer implementation. Android also documents companion InCallService access for physical wearable associations; that is not blanket permission to classify a Mac as a wearable. AOSP CallStreamingService is marked hidden/SystemApi and describes VoIP streaming, so it is not a public generic SIM-audio solution for our companion.

Sources: [InCallService](https://developer.android.com/reference/android/telecom/InCallService), [AOSP streaming service](https://android.googlesource.com/platform/frameworks/base/+/refs/heads/main/telecomm/java/android/telecom/CallStreamingService.java).

## Proposed architecture and acceptance gates

1. **HFP capability probe:** explicitly select/associate the intended test phone, establish its service connection and report supported controls. Never infer trusted phone identity solely from its Bluetooth display name. Pairing and Bluetooth permission are separate from existing TLS trust.
2. **Audio feasibility gate:** with a future user-authorized test call, confirm SCO setup and identify whether readable/writable Core Audio streams are exposed. Verify both directions with Mac built-in audio first. If only control works, label it control-only; do not ship a nonfunctional device selector.
3. **Audio routing:** proposed CallAudioRouter owns input/output selection, bounded buffers, format changes and echo handling; AudioDeviceCatalog owns hot-plug observation and device UID persistence. These are proposed components, not source files currently present.
4. **Call UI:** proposed CallsCoordinator owns per-phone ringing/active/ended state and capability checks. An incoming-call card offers Answer/Decline; an active-call panel offers Mute, keypad, Hang up, Phone/Mac transfer, separate Microphone and Speaker selectors, and device levels. Keep calls out of the video renderer.
5. **Acceptance:** test answer/end on both devices, caller audio in both directions, mute, DTMF, selected-device persistence, device removal, phone lock, debugging off, disconnect recovery, competing headsets and one-active-phone policy. No call recording/transcription is part of this feature.

Permission/setup proposal: explicit Bluetooth pairing and Mac Bluetooth access; Mac microphone access only when enabling audio capture. Request any additional Android roles/permissions only if a proven backend needs them. No new permissions were requested during this research. The authorized Nothing phone is the development device; a SIM-capable test setup and approved test destination will be required for cellular acceptance. Additional physical devices require explicit test authorization.
