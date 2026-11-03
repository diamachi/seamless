import SwiftUI
import SeamlessCore

@MainActor
private final class NotificationViewState: ObservableObject {
    @Published var search = ""
    @Published var showApplications = false
}

struct NotificationSettingsView: View {
    @ObservedObject var preferencesStore: PreferencesStore
    @ObservedObject var connections: PhoneConnections
    @StateObject private var viewState = NotificationViewState()

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                WorkspaceHeading(title: "Notifications", subtitle: "Stay in touch, without the noise.")
                if let phoneID = preferencesStore.preferences.selectedPhoneID {
                    NotificationDeliveryCard()
                    notificationControls
                    if viewState.showApplications {
                        applicationSettings(phoneID: phoneID)
                    } else {
                        notificationFeed(phoneID: phoneID)
                    }
                } else {
                    ContentUnavailableView("Connect a phone to get started", systemImage: "bell.badge")
                }
            }
            .padding(.bottom, 24)
        }
    }

    private var notificationControls: some View {
        WorkspaceCard {
            HStack(spacing: 16) {
                WorkspaceSegments(options: [(false, "Inbox"), (true, "App settings")], selection: $viewState.showApplications)
                Spacer(minLength: 0)
                Toggle("Pause", isOn: preferencesStore.featurePreferences.notifications.isPaused)
                    .toggleStyle(.switch).fixedSize()
            }
            if viewState.showApplications {
                HStack {
                    Text("Choose which apps can notify this Mac.").foregroundStyle(.secondary)
                    Spacer()
                    Button("Mac notification permission") { connections.requestNotificationPermission() }
                }
            }
        }
    }

    private func applicationSettings(phoneID: String) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            TextField("Find an app", text: $viewState.search)
                .textFieldStyle(WorkspaceTextFieldStyle())
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: 14)], spacing: 14) {
                ForEach(filteredApplications(phoneID: phoneID)) { application in
                    WorkspaceCard {
                        HStack(spacing: 12) {
                            ApplicationIcon(image: application.icon, name: application.name)
                            Text(application.name).font(.system(size: 13, weight: .medium)).lineLimit(2)
                            Spacer(minLength: 8)
                            Toggle(application.name, isOn: applicationBinding(application.identity))
                                .labelsHidden().toggleStyle(.switch)
                        }
                    }
                }
            }
            Text("Only enabled apps are forwarded. Notification access is managed on your phone.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func notificationFeed(phoneID: String) -> some View {
        let notifications = connections.notifications.filter { $0.phoneID == phoneID }
        return VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Recent").font(.headline)
                Text("\(notifications.count)").font(.caption).foregroundStyle(.secondary)
            }
            if notifications.isEmpty {
                WorkspaceCard {
                    VStack(spacing: 12) {
                        Image(systemName: "bell.badge").font(.system(size: 28, weight: .light)).foregroundStyle(.tint)
                        Text("All caught up").font(.title3.weight(.semibold))
                        Text("New notifications from your enabled apps will appear here.")
                            .foregroundStyle(.secondary).multilineTextAlignment(.center)
                        Button("Choose apps") { viewState.showApplications = true }
                    }.frame(maxWidth: .infinity).padding(.vertical, 40)
                }
            } else {
                LazyVStack(spacing: 14) {
                    ForEach(notifications) { notification in
                        NotificationRow(notification: notification, connections: connections)
                            .id(phoneID + ":" + notification.id)
                    }
                }
            }
        }
    }

    private func filteredApplications(phoneID: String) -> [PhoneApplication] {
        (connections.applications[phoneID] ?? []).filter {
            viewState.search.isEmpty || $0.name.localizedCaseInsensitiveContains(viewState.search)
        }
    }

    private func applicationBinding(_ application: AndroidApplicationIdentity) -> Binding<Bool> {
        Binding(
            get: { preferencesStore.preferences.selectedPhone?.preferences.notifications.allowedApplications.contains(application) ?? false },
            set: { preferencesStore.setNotificationApplication(application, enabled: $0) }
        )
    }
}


@MainActor
private final class NotificationReplyDraft: ObservableObject {
    @Published var text = ""
}

private struct NotificationRow: View {
    let notification: RelayedNotification
    @ObservedObject var connections: PhoneConnections
    @StateObject private var draft = NotificationReplyDraft()

    private var application: PhoneApplication? {
        connections.applications[notification.phoneID]?.first { $0.identity == notification.application }
    }

    var body: some View {
        WorkspaceCard {
            HStack(alignment: .top, spacing: 14) {
                ApplicationIcon(image: application?.icon ?? notification.icon, name: application?.name ?? notification.application.packageName)
                VStack(alignment: .leading, spacing: 8) {
                    Text(application?.name ?? notification.application.packageName)
                        .font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                    Text(notification.title).font(.system(size: 14, weight: .semibold))
                    if !notification.text.isEmpty {
                        Text(notification.text).font(.system(size: 13)).foregroundStyle(.secondary)
                            .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), alignment: .leading)], alignment: .leading, spacing: 10) {
                Button("Dismiss") { connections.notificationAction(notification, dismiss: true) }
                ForEach(notification.actions.indices, id: \.self) { index in
                    if notification.actions[index]["supportsReply"].boolean != true {
                        Button(notification.actions[index]["title"].string ?? "Action") {
                            connections.notificationAction(notification, index: index)
                        }
                    }
                }
            }
            if let action = notification.actions.first(where: { $0["supportsReply"].boolean == true }),
               let index = action["index"].number {
                HStack {
                    TextField("Reply", text: $draft.text).textFieldStyle(WorkspaceTextFieldStyle())
                    Button("Send") {
                        connections.notificationAction(notification, index: Int(index), reply: draft.text)
                        draft.text = ""
                    }.disabled(draft.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .accessibilityElement(children: .contain)
    }
}

private struct ApplicationIcon: View {
    let image: NSImage?
    let name: String
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image).resizable().scaledToFit()
            } else {
                Text(String(name.prefix(1)).uppercased())
                    .font(.system(size: 19, weight: .semibold, design: .rounded))
                    .foregroundStyle(InterfacePalette(scheme: colorScheme).accent)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(InterfacePalette(scheme: colorScheme).accentWash)
            }
        }
        .frame(width: 38, height: 38)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .accessibilityHidden(true)
    }
}
