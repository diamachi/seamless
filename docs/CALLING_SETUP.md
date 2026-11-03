# Calls: experimental Bluetooth setup

Implemented in the macOS app; no cellular call/audio physical acceptance yet. Use a dedicated, explicitly authorized test phone for development. Do not assume another phone's TLS pairing authorizes Bluetooth calling.

1. Pair the intended Android phone with this Mac using normal Bluetooth settings. Debugging is not required. Review any phone call-audio profile switch if the phone exposes one.
2. Open Seamless → Calls and choose the saved phone. Click Find paired phones, review macOS Bluetooth permission yourself, and select the matching phone explicitly. Click Connect calls.
3. A connected control link enables the dial field and incoming call controls. It does not prove audio works. Dialing/answering is an explicit user action and uses the phone's plan. Initial testing needs a separately approved call destination/partner, not an emergency or arbitrary number.
4. During a call, Use Mac audio asks Android/macOS to open Bluetooth voice audio; Use phone audio returns it. The native route may use OS-managed devices until a custom bridge is started.
5. For independent input/output, choose Microphone and Speaker, then Apply selected devices. Review the Mac microphone request yourself. The action is unavailable until both phone audio endpoints exist and a call/SCO session is open. Audio routing details shows any missing endpoint; advanced explicit endpoint selection is only for a positively identified phone device.
6. Verify both directions and mute with the call partner. If no audio arrives, return it to the phone. Disconnect calls closes the link while leaving the actual call on the phone; End call explicitly hangs up.

Selections are remembered per phone by Core Audio UID. Missing devices are shown as unavailable. Changed selections and unplugged devices stop the custom bridge and request phone audio; they do not deliberately switch to Mac speakers. Speaker echo cancellation, Bluetooth-headset coexistence, mSBC/codec negotiation, multi-SIM choice and all current Mac/Android combinations remain unverified. One active phone session is supported. No recording, transcription, contacts or call-history storage is implemented.
