import SwiftUI
import SeamlessCore

struct ConnectionSettingsView: View {
    @ObservedObject var connections: PhoneConnections
    @StateObject private var qrPairing = MacQrPairingCoordinator()

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Label("Connect a new phone", systemImage: "plus.circle.fill")
                .font(.title2.weight(.semibold))
            Label("Pair over Wi-Fi", systemImage: "wifi").font(.headline)
            Text("Recommended · Keep the Mac and phone on the same reachable local network. No USB debugging is needed.")
                .font(.callout).foregroundStyle(.secondary)
            MacQrPairingView(pairing: qrPairing)
            DisclosureGroup("Use the full pairing code instead") {
                VStack(alignment: .leading, spacing: 14) {
                    pairingStep("1", title: "On Android, choose Use full code instead",
                                detail: "Tap Create full pairing code. The app shows the code and a Copy button.")
                    pairingStep("2", title: "Paste the complete code here",
                                detail: "This fallback is for a code you can transfer privately to the Mac. The QR method avoids copying between unpaired devices.")
                    TextField("Paste full Android pairing code", text: $connections.pairingCode, axis: .vertical)
                        .lineLimit(2...4).textFieldStyle(WorkspaceTextFieldStyle()).privacySensitive()
                    HStack {
                        Button("Paste code", systemImage: "doc.on.clipboard") {
                            if let code = NSPasteboard.general.string(forType: .string) { connections.pairingCode = code }
                        }
                        Spacer()
                        Button("Pair phone", systemImage: "link") { connections.pair() }
                            .buttonStyle(WorkspaceButtonStyle(prominent: true))
                            .disabled(connections.pairingCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    Text("Pair phone becomes available after you paste a code. Approve the named Mac on Android afterward.")
                        .font(.caption).foregroundStyle(.secondary)
                }.padding(.top, 12)
            }
            DisclosureGroup("Wi-Fi troubleshooting · manual address") {
                VStack(alignment: .leading, spacing: 10) {
                    Text("If local discovery fails, enter the phone's local IP address. This changes the route only; the pairing code and phone approval are still required.")
                        .foregroundStyle(.secondary)
                    TextField("Phone IP address override", text: $connections.hostOverride)
                        .textFieldStyle(WorkspaceTextFieldStyle())
                }.padding(.top, 10)
            }.font(.callout)
            Text("USB is available after pairing. See the cable option below your saved phones.")
                .font(.caption).foregroundStyle(.secondary)
            if !connections.message.isEmpty {
                Text(connections.message).font(.callout).foregroundStyle(.secondary)
            }
        }
        .onAppear {
            qrPairing.onInvitation = { invitation in
                connections.pairingCode = invitation
                connections.pair()
            }
        }
        .onDisappear { qrPairing.stop() }
    }

    private func pairingStep(_ number: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(number).font(.callout.weight(.semibold))
                .frame(width: 28, height: 28)
                .background(.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.callout.weight(.semibold))
                Text(detail).font(.callout).foregroundStyle(.secondary)
            }
        }
    }
}
