import AppKit
import SwiftUI
import SeamlessCore

@MainActor
private final class CallDialEditor: ObservableObject {
    @Published var number = ""
    @Published var contactName = ""
    @Published var showContacts = false
}

struct CallsWorkspaceView: View {
    @ObservedObject var preferencesStore: PreferencesStore
    @ObservedObject var calls: CallsCoordinator
    @StateObject private var editor = CallDialEditor()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                WorkspaceHeading(title: "Calls", subtitle: "1 · Connect Bluetooth   2 · Choose audio   3 · Call or answer")
                Text("Keep call controls connected to receive incoming calls on your Mac. Your phone keeps its SIM and mobile service.")
                    .foregroundStyle(.secondary)
                if let phone = preferencesStore.preferences.selectedPhone {
                    if calls.activePhoneID == phone.id && calls.state.isConnected {
                        DisclosureGroup("Bluetooth setup · connected") { connectionCard(phoneID: phone.id, name: phone.displayName) }
                    } else {
                        connectionCard(phoneID: phone.id, name: phone.displayName)
                    }
                    if calls.activePhoneID == phone.id && calls.state.isConnected {
                        CallAudioControls(calls: calls, audio: calls.audio, devices: calls.devices, phoneID: phone.id)
                        callCard
                    }
                } else {
                    ContentUnavailableView("Choose a phone first", systemImage: "iphone")
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(WorkspaceButtonStyle())
        .task { calls.devices.start() }
        .sheet(isPresented: $editor.showContacts) {
            if let phoneID = preferencesStore.preferences.selectedPhoneID {
                PhoneContactsPicker(contacts: preferencesStore.connections.phoneContacts, phoneID: phoneID) { contact in
                    editor.number = contact.number
                    editor.contactName = contact.name
                }
            }
        }
    }

    private func connectionCard(phoneID: String, name: String) -> some View {
        WorkspaceCard {
            HStack {
                Label(name, systemImage: "iphone").font(.headline)
                Spacer()
                Text(calls.state.isConnected && calls.activePhoneID == phoneID ? "Bluetooth ready" : "Bluetooth setup")
                    .font(.caption.weight(.medium)).foregroundStyle(.secondary)
            }
            Text("Pair this Android phone in macOS Bluetooth settings, then explicitly match it below. Bluetooth calls work separately from the Wi-Fi or USB connection; debugging is not required.")
                .foregroundStyle(.secondary)
            HStack(spacing: 12) {
                Button("Bluetooth settings") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.BluetoothSettings") { NSWorkspace.shared.open(url) }
                }
                Button(calls.isDiscovering ? "Checking paired phones…" : "Find paired phones") { calls.discoverPairedPhones() }
                    .disabled(calls.isDiscovering)
            }
            WorkspaceMenuPicker(title: "Bluetooth phone", symbol: "iphone", selection: addressBinding(phoneID),
                                choices: phoneChoices(phoneID: phoneID))
                .disabled(calls.state.hasCall)
            Button("Review incoming-call alerts") { MacNotificationDelivery.shared.reviewAccess() }
            Toggle("Reconnect call controls when Seamless opens", isOn: Binding(
                get: { calls.options(for: phoneID).reconnectOnLaunch },
                set: { value in calls.updateOptions(phoneID: phoneID) { $0.reconnectOnLaunch = value } }
            ))
            HStack {
                Text(calls.message).font(.callout).foregroundStyle(.secondary)
                Spacer()
                if calls.activePhoneID != nil {
                    Button("Disconnect calls") { calls.disconnect() }
                }
                Button(calls.isConnecting ? "Connecting…" : "Connect calls") { calls.connect(phoneID: phoneID) }
                    .buttonStyle(WorkspaceButtonStyle(prominent: true))
                    .disabled(calls.isConnecting || calls.state.hasCall || calls.options(for: phoneID).bluetoothAddress.isEmpty || (calls.activePhoneID == phoneID && calls.state.isConnected))
            }
            if let otherID = calls.activePhoneID, otherID != phoneID {
                Text("Another phone owns the calling session. Disconnect it before connecting this phone.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var callCard: some View {
        WorkspaceCard {
            Text(calls.state.title).font(.title2.weight(.semibold))
            if !calls.state.caller.isEmpty { Text(calls.state.caller).font(.title3).textSelection(.enabled) }
            if calls.state.hasCall {
                HStack(spacing: 12) {
                    if calls.state.canAnswer {
                        Button("Answer on Mac") { calls.answer() }.buttonStyle(WorkspaceButtonStyle(prominent: true))
                    }
                    Button(calls.state.canAnswer ? "Decline" : "End call") { calls.end() }
                    Button("Use Mac audio") { calls.useMacAudio() }.disabled(calls.isAudioConnected)
                    Button("Use phone audio") { calls.usePhoneAudio() }
                }
                if calls.state.isActive {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 10) {
                        ForEach(["1", "2", "3", "4", "5", "6", "7", "8", "9", "*", "0", "#"], id: \.self) { tone in
                            Button(tone) { calls.sendTone(tone) }.frame(maxWidth: .infinity).accessibilityLabel("Send tone \(tone)")
                        }
                    }
                }
            } else {
                if !editor.contactName.isEmpty { Text(editor.contactName).font(.headline) }
                HStack {
                    TextField("Phone number", text: $editor.number).textFieldStyle(WorkspaceTextFieldStyle())
                    Button { editor.showContacts = true } label: { Label("Contacts", systemImage: "person.crop.circle") }
                        .disabled(preferencesStore.sessions.state(for: preferencesStore.preferences.selectedPhoneID ?? "") != .connected)
                        .help("Connect Seamless over Wi-Fi or USB to load Android contacts")
                    Button { calls.dial(editor.number) } label: { Label("Call", systemImage: "phone.fill") }
                        .buttonStyle(WorkspaceButtonStyle(prominent: true))
                        .disabled(PhoneCallState.dialNumber(editor.number) == nil)
                }
                Text("The dial field starts cellular calls on your phone. Incoming calls from other apps appear only if that app exposes them through Bluetooth. No recording or transcription is enabled.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func phoneChoices(phoneID: String) -> [(String, String)] {
        var choices = [("", "Choose the intended phone…")]
        let saved = calls.options(for: phoneID).bluetoothAddress
        if !saved.isEmpty && !calls.pairedPhones.contains(where: { $0.id == saved }) {
            choices.append((saved, "Saved phone · \(saved.suffix(5))"))
        }
        choices.append(contentsOf: calls.pairedPhones.map { ($0.id, "\($0.name) · \($0.id.suffix(5))") })
        return choices
    }

    private func addressBinding(_ phoneID: String) -> Binding<String> {
        Binding(get: { calls.options(for: phoneID).bluetoothAddress },
                set: { value in calls.updateOptions(phoneID: phoneID) { $0.bluetoothAddress = value } })
    }
}
