import SwiftUI

@MainActor
private final class DeviceManagementState: ObservableObject {
    @Published var renameID: String?
    @Published var name = ""
    @Published var phoneToForget: String?
}

struct DeviceManagementView: View {
    @ObservedObject var preferencesStore: PreferencesStore
    @StateObject private var state = DeviceManagementState()

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            WorkspaceHeading(title: "Devices", subtitle: "Connect another phone, or manage the ones you already trust.")
            WorkspaceCard {
                ConnectionSettingsView(connections: preferencesStore.connections)
            }
            Text("Your phones · \(preferencesStore.preferences.rememberedPhones.count)")
                .font(.title3.weight(.semibold))
            if preferencesStore.preferences.rememberedPhones.isEmpty {
                WorkspaceCard {
                    Label("Your paired phones will appear here", systemImage: "iphone")
                        .font(.headline)
                    Text("Use the pairing steps above to connect your first Android phone.")
                        .foregroundStyle(.secondary)
                }
            }
            ForEach(preferencesStore.preferences.rememberedPhones) { phone in
                WorkspaceCard {
                    HStack {
                        Label(phone.displayName, systemImage: "iphone").font(.headline)
                        Spacer()
                        ConnectionBadge(isConnected: preferencesStore.sessions.state(for: phone.id) == .connected)
                    }
                    HStack {
                        if preferencesStore.preferences.selectedPhoneID == phone.id {
                            Label("Selected", systemImage: "checkmark.circle.fill").foregroundStyle(.tint).font(.headline)
                        } else {
                            Button("Select phone") { preferencesStore.selectPhone(id: phone.id) }
                                .buttonStyle(WorkspaceButtonStyle(prominent: true))
                        }
                        Button("Rename") { state.renameID = phone.id; state.name = phone.displayName }
                        if preferencesStore.sessions.state(for: phone.id) == .connected {
                            Button("Disconnect") { preferencesStore.connections.disconnect(phoneID: phone.id) }
                        } else {
                            Button("Reconnect") { preferencesStore.connections.reconnect(phone) }
                        }
                        Spacer()
                        Button("Forget…", role: .destructive) { state.phoneToForget = phone.id }
                    }
                }
            }
            DisclosureGroup("Use a USB cable · optional") {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Pair over Wi-Fi first. Then connect the selected phone by cable, enable USB debugging on that phone, and choose Find USB phones. Debugging must stay enabled while USB is in use.")
                        .font(.callout).foregroundStyle(.secondary)
                    USBConnectionSettings(connections: preferencesStore.connections, usb: preferencesStore.connections.usb, phone: preferencesStore.preferences.selectedPhone)
                }.padding(.top, 12)
            }
            .disabled(preferencesStore.preferences.selectedPhone == nil)
        }
        .sheet(isPresented: Binding(get: { state.renameID != nil }, set: { if !$0 { state.renameID = nil } })) {
            VStack(alignment: .leading, spacing: 20) {
                Text("Name your phone").font(.title2.weight(.semibold))
                TextField("Phone name", text: $state.name).textFieldStyle(WorkspaceTextFieldStyle())
                HStack {
                    Button("Cancel") { state.renameID = nil }
                    Spacer()
                    Button("Save name") {
                        if let id = state.renameID { preferencesStore.renamePhone(id: id, name: state.name) }
                        state.renameID = nil
                    }.buttonStyle(WorkspaceButtonStyle(prominent: true))
                        .disabled(state.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || state.name.count > 80)
                }
            }.padding(28).frame(width: 380).buttonStyle(WorkspaceButtonStyle())
        }
        .confirmationDialog("Forget this phone?", isPresented: forgetConfirmation, titleVisibility: .visible) {
            Button("Forget phone", role: .destructive) {
                if let phoneID = state.phoneToForget {
                    preferencesStore.connections.forget(phoneID: phoneID)
                }
                state.phoneToForget = nil
            }
            Button("Cancel", role: .cancel) { state.phoneToForget = nil }
        } message: {
            Text("Remove this phone and its saved credential from this Mac, even if offline. When connected, Seamless also asks the phone to revoke trust. An offline phone may retain its old pairing.")
        }
    }

    private var forgetConfirmation: Binding<Bool> {
        Binding(get: { state.phoneToForget != nil }, set: { isPresented in
            if !isPresented { state.phoneToForget = nil }
        })
    }
}
