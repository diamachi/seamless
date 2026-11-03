import SwiftUI
import SeamlessCore

struct ConnectionSettingsView: View {
    @ObservedObject var connections: PhoneConnections

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Label("Connect a new phone", systemImage: "plus.circle.fill")
                .font(.title2.weight(.semibold))
            Label("Pair over Wi-Fi", systemImage: "wifi").font(.headline)
            Text("Recommended · Keep the Mac and phone on the same reachable local network. No USB debugging is needed.")
                .font(.callout).foregroundStyle(.secondary)
            pairingStep("1", title: "Open Seamless on Android",
                        detail: "Choose Pair a Mac, then Create pairing code. Setup can also guide you here.")
            pairingStep("2", title: "Paste the private code below",
                        detail: "The code expires in five minutes. Keep it private and use the full code.")
            pairingStep("3", title: "Approve this Mac on your phone",
                        detail: "Choose Pair phone, then approve the request naming your Mac. Later connections use saved trust.")
            TextField("Paste Android pairing code", text: $connections.pairingCode, axis: .vertical)
                .lineLimit(2...4)
                .textFieldStyle(WorkspaceTextFieldStyle())
                .privacySensitive()
            DisclosureGroup("Wi-Fi troubleshooting · manual address") {
                VStack(alignment: .leading, spacing: 10) {
                    Text("If local discovery fails, enter the phone's local IP address. This changes the route only; the pairing code and phone approval are still required.")
                        .foregroundStyle(.secondary)
                    TextField("Phone IP address override", text: $connections.hostOverride)
                        .textFieldStyle(WorkspaceTextFieldStyle())
                }.padding(.top, 10)
            }.font(.callout)
            HStack {
                Text("USB is available after pairing. See the cable option below your saved phones.")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Pair phone", systemImage: "link") { connections.pair() }
                    .buttonStyle(WorkspaceButtonStyle(prominent: true))
                    .disabled(connections.pairingCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            if !connections.message.isEmpty {
                Text(connections.message).font(.callout).foregroundStyle(.secondary)
            }
        }
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
