import SwiftUI

struct IncomingCallBanner: View {
    @ObservedObject var calls: CallsCoordinator
    @ObservedObject var preferencesStore: PreferencesStore
    let openCalls: () -> Void

    var body: some View {
        if calls.state.canAnswer {
            WorkspaceCard {
                Label("Incoming call", systemImage: "phone.arrow.down.left.fill").font(.headline)
                if let phoneID = calls.activePhoneID {
                    Text(preferencesStore.preferences.rememberedPhones.first { $0.id == phoneID }?.displayName ?? "Connected phone")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Text(calls.state.caller.isEmpty ? "Unknown caller" : calls.state.caller).font(.title3)
                HStack {
                    Button("Decline") { calls.end() }
                    Button("Answer") { calls.answer() }.buttonStyle(WorkspaceButtonStyle(prominent: true))
                    Button("Open calls", action: openCalls)
                }
            }
            .frame(width: 380)
            .shadow(color: .black.opacity(0.15), radius: 16, y: 8)
            .padding(20)
            .buttonStyle(WorkspaceButtonStyle())
        }
    }
}
