import SwiftUI

struct NotificationDeliveryCard: View {
    @ObservedObject private var delivery = MacNotificationDelivery.shared
    var body: some View {
        WorkspaceCard {
            HStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Mac banners", systemImage: "bell.badge").font(.headline)
                    Text(delivery.status).font(.callout).foregroundStyle(.secondary)
                    if !delivery.lastError.isEmpty { Text(delivery.lastError).font(.caption).foregroundStyle(.secondary) }
                }
                Spacer()
                Button("Review access") { delivery.reviewAccess() }
                Button("Test Mac banner") { delivery.postLocalTest() }
                    .buttonStyle(WorkspaceButtonStyle(prominent: true)).disabled(!delivery.canShowBanners)
            }
            Text("Also select phone apps below and allow notification sharing on Android. macOS Focus or banner settings can silence an otherwise delivered alert.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .buttonStyle(WorkspaceButtonStyle())
        .task { await delivery.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in Task { await delivery.refresh() } }
    }
}
