import SwiftUI

struct CallAudioControls: View {
    @ObservedObject var calls: CallsCoordinator
    @ObservedObject var audio: CallAudioRouter
    @ObservedObject var devices: CallAudioDeviceCatalog
    let phoneID: String

    var body: some View {
        WorkspaceCard {
            HStack {
                Text("Call audio").font(.headline)
                Spacer()
                Button("Refresh audio devices") { devices.refresh() }
            }
            HStack(spacing: 20) {
                devicePicker("Microphone", input: true, keyPath: \.microphoneUID)
                devicePicker("Speaker", input: false, keyPath: \.speakerUID)
            }
            HStack {
                Button(audio.isStarting ? "Starting audio…" : "Apply selected devices") {
                    Task { await calls.applySelectedAudio(phoneID: phoneID) }
                }
                .buttonStyle(WorkspaceButtonStyle(prominent: true))
                .disabled(!canBridge || audio.isStarting)
                if audio.isRunning {
                    Button(audio.isMuted ? "Unmute microphone" : "Mute microphone") { audio.toggleMute() }
                    Button("Return audio to phone") { calls.usePhoneAudio() }
                }
            }
            Text(audio.message).font(.callout).foregroundStyle(.secondary)
            Text("Headphones are recommended while speaker echo handling is being validated.")
                .font(.caption).foregroundStyle(.secondary)
            if !canBridge {
                Text("First open Mac audio during a call. Selected-device routing also needs a phone audio endpoint exposed by macOS; a connected call-control link alone is insufficient.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            DisclosureGroup("Audio routing details") {
                VStack(alignment: .leading, spacing: 12) {
                    Text("If automatic matching fails, select only this phone's Bluetooth audio endpoints. Leave these on Auto-match unless you can identify them. Headphones connected to the Mac belong in the microphone/speaker selectors above.")
                        .font(.caption).foregroundStyle(.secondary)
                    endpointPicker("From phone", input: true, keyPath: \.phoneInputUID)
                    endpointPicker("To phone", input: false, keyPath: \.phoneOutputUID)
                    Text("Current phone input: \(phoneInput?.name ?? "Not exposed")\nCurrent phone output: \(phoneOutput?.name ?? "Not exposed")")
                        .font(.caption).foregroundStyle(.secondary)
                    Text("Changing a device stops the custom bridge and requests phone audio. Disconnecting a selected device never deliberately falls back to Mac speakers. Bluetooth audio support is experimental until verified on your devices.")
                        .font(.caption).foregroundStyle(.secondary)
                }.padding(.top, 12)
            }
        }
    }

    private var phoneInput: CallAudioDevice? { calls.phoneEndpoint(options: calls.options(for: phoneID), input: true) }
    private var phoneOutput: CallAudioDevice? { calls.phoneEndpoint(options: calls.options(for: phoneID), input: false) }
    private var canBridge: Bool { calls.state.hasCall && calls.isAudioConnected && phoneInput != nil && phoneOutput != nil }

    private func devicePicker(_ title: String, input: Bool, keyPath: WritableKeyPath<PhoneCallingOptions, String>) -> some View {
        var choices = [("system", "System default")]
        choices.append(contentsOf: missingChoice(keyPath))
        choices.append(contentsOf: devices.devices.filter { input ? $0.hasInput : $0.hasOutput }.map { ($0.uid, $0.name) })
        return WorkspaceMenuPicker(title: title, symbol: input ? "mic" : "speaker.wave.2",
                                   selection: binding(keyPath), choices: choices)
    }

    private func endpointPicker(_ title: String, input: Bool, keyPath: WritableKeyPath<PhoneCallingOptions, String>) -> some View {
        var choices = [("", "Auto-match phone")]
        choices.append(contentsOf: missingChoice(keyPath))
        choices.append(contentsOf: devices.devices.filter { $0.isBluetooth && (input ? $0.hasInput : $0.hasOutput) }.map { ($0.uid, $0.name) })
        return WorkspaceMenuPicker(title: title, symbol: "waveform", selection: binding(keyPath), choices: choices)
    }

    private func missingChoice(_ keyPath: WritableKeyPath<PhoneCallingOptions, String>) -> [(String, String)] {
        let saved = calls.options(for: phoneID)[keyPath: keyPath]
        if !saved.isEmpty && saved != "system" && !devices.devices.contains(where: { $0.uid == saved }) {
            return [(saved, "Saved device unavailable")]
        }
        return []
    }

    private func binding(_ keyPath: WritableKeyPath<PhoneCallingOptions, String>) -> Binding<String> {
        Binding(get: { calls.options(for: phoneID)[keyPath: keyPath] },
                set: { value in calls.updateOptions(phoneID: phoneID) { $0[keyPath: keyPath] = value } })
    }
}
