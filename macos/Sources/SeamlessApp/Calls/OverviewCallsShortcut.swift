import SwiftUI

struct OverviewCallsShortcut: View {
    @ObservedObject var calls: CallsCoordinator
    let phoneID: String?
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            WorkspaceCard {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "phone").font(.title3).foregroundStyle(.tint)
                        Spacer(minLength: 0)
                        Image(systemName: "arrow.up.right").foregroundStyle(.secondary).font(.caption)
                    }
                    Text("Calls").font(.system(size: 13, weight: .semibold))
                    if calls.activePhoneID == phoneID && calls.state.isConnected {
                        Text(calls.state.title).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                    }
                }.frame(minHeight: 72, alignment: .center)
            }
        }.buttonStyle(.plain)
    }
}
