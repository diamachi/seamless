import AppKit
import CoreWLAN
import CoreLocation
import SwiftUI

@MainActor
private final class HotspotConnection: NSObject, ObservableObject {
    private let location = CLLocationManager()
    @Published var networkName = ""
    @Published var password = ""
    @Published var isConnecting = false
    @Published var message = "Enable the phone’s hotspot, then join its Wi-Fi network here."

    func join() {
        guard !networkName.isEmpty, !isConnecting else { return }
        if location.authorizationStatus == .notDetermined {
            location.requestWhenInUseAuthorization()
            message = "Allow location access for Wi-Fi scanning, then choose Join hotspot again."
            return
        }
        let name = networkName
        let secret = password
        isConnecting = true
        message = "Joining \(name)… Your current Wi-Fi connection may disconnect."
        Task {
            do {
                let result = try await Task.detached {
                    guard let interface = CWWiFiClient.shared().interface() else { throw NSError(domain: "SeamlessHotspot", code: 1, userInfo: [NSLocalizedDescriptionKey: "No Wi-Fi interface is available."]) }
                    let networks = try interface.scanForNetworks(withSSID: Data(name.utf8))
                    guard let network = networks.first else { throw NSError(domain: "SeamlessHotspot", code: 2, userInfo: [NSLocalizedDescriptionKey: "Network not found. Check the hotspot and macOS Wi-Fi/location access, or join it in System Settings."]) }
                    try interface.associate(to: network, password: secret.isEmpty ? nil : secret)
                    return "Joined \(name). Seamless will reconnect when the phone is reachable."
                }.value
                message = result
                password = ""
            } catch { message = error.localizedDescription }
            isConnecting = false
        }
    }
}

struct HotspotView: View {
    @ObservedObject var preferencesStore: PreferencesStore
    @StateObject private var connection = HotspotConnection()
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                WorkspaceHeading(title: "Hotspot", subtitle: "Use your phone’s mobile connection.")
                WorkspaceCard {
                    HStack {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("1 · Enable phone hotspot").font(.headline)
                            Text("Turn on your phone’s hotspot, then enter its network name and password below. You can also use the mirrored phone controls.").foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Show setup on phone") {
                            if let phoneID = preferencesStore.preferences.selectedPhoneID {
                                preferencesStore.connections.requestHotspotHelp(phoneID: phoneID)
                                connection.message = "Setup requested. Open Seamless → Connect on your phone, then tap Open hotspot settings."
                            }
                        }.buttonStyle(WorkspaceButtonStyle(prominent: true)).disabled(!isConnected)
                    }
                }
                WorkspaceCard {
                    Text("2 · Join from your Mac").font(.headline)
                    TextField("Hotspot network name", text: $connection.networkName).textFieldStyle(WorkspaceTextFieldStyle())
                    SecureField("Hotspot password", text: $connection.password).textFieldStyle(WorkspaceTextFieldStyle())
                    HStack {
                        Text("Joining changes this Mac’s active Wi-Fi network.").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button("Wi-Fi settings") {
                            if let url = URL(string: "x-apple.systempreferences:com.apple.wifi-settings-extension") { NSWorkspace.shared.open(url) }
                        }
                        Button(connection.isConnecting ? "Joining…" : "Join hotspot") { connection.join() }
                            .buttonStyle(WorkspaceButtonStyle(prominent: true)).disabled(connection.networkName.isEmpty || connection.isConnecting)
                    }
                    Text(connection.message).font(.callout).foregroundStyle(.secondary)
                    Text("Passwords stay in memory and are cleared after joining.").font(.caption).foregroundStyle(.secondary)
                }
            }
        }.buttonStyle(WorkspaceButtonStyle())
    }
    private var isConnected: Bool {
        guard let phoneID = preferencesStore.preferences.selectedPhoneID else { return false }
        return preferencesStore.sessions.state(for: phoneID) == .connected
    }
}
