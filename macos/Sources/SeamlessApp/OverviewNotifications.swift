import SwiftUI
import SeamlessCore

@MainActor
private final class OverviewNotificationState: ObservableObject {
    @Published var showingApps = false
}

struct OverviewNotifications: View {
    @ObservedObject var preferencesStore: PreferencesStore
    @ObservedObject var connections: PhoneConnections
    @StateObject private var presentation = OverviewNotificationState()

    var body: some View {
        WorkspaceCard {
            HStack {
                Text("Phone notifications").font(.headline)
                Spacer()
                Button("Choose apps") { presentation.showingApps = true }
            }
            Button("Clear list") {
                if let phoneID = preferencesStore.preferences.selectedPhoneID { connections.clearNotifications(phoneID: phoneID) }
            }
            let notifications = connections.notifications.filter { $0.phoneID == preferencesStore.preferences.selectedPhoneID }
            if notifications.isEmpty {
                Text("No phone notifications yet. Choose apps to receive here.").foregroundStyle(.secondary)
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(notifications) { notification in
                        let application = connections.applications[notification.phoneID]?.first { $0.identity == notification.application }
                        HStack(alignment: .top, spacing: 10) {
                            ApplicationIcon(image: application?.icon ?? notification.icon,
                                            name: application?.name ?? notification.application.packageName)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(application?.name ?? notification.application.packageName).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                Text(notification.title).font(.callout.weight(.medium)).lineLimit(2)
                                Text(notification.text).font(.caption).foregroundStyle(.secondary).lineLimit(4)
                            }
                        }
                        Divider()
                    }
                }
            }.frame(height: notifications.isEmpty ? 20 : 320)
            Text("To test phone → Mac, allow Seamless in Choose apps, then tap Send test in the Android Overview.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .sheet(isPresented: $presentation.showingApps) {
            VStack {
                HStack { Spacer(); Button("Done") { presentation.showingApps = false } }
                NotificationSettingsView(preferencesStore: preferencesStore, connections: connections, initiallyShowApplications: true)
            }.padding(24).frame(width: 760, height: 600)
        }
    }
}
