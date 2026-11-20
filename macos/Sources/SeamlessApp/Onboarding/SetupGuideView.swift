// macOS application presentation and coordination for setup guide view.
// See docs/ARCHITECTURE.md for the owning subsystem and cross-platform call flow.

import SwiftUI
import SeamlessCore

struct SetupGuideView: View {
    @ObservedObject var preferencesStore: PreferencesStore
    @ObservedObject var setup: SetupCoordinator
    let openDevices: () -> Void

    private let steps = ["Welcome", "Pair devices", "Permissions", "Choose apps", "Verify", "Ready"]
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack {
                Label("Set up Seamless", systemImage: "point.3.connected.trianglepath.dotted").font(.title2.weight(.semibold))
                Spacer()
                Button("Set up later") { setup.isPresented = false }
            }
            HStack(spacing: 10) {
                ForEach(Array(steps.enumerated()), id: \.offset) { index, title in
                    Label(title, systemImage: index < setup.step ? "checkmark.circle.fill" : "\(index + 1).circle")
                        .font(.caption.weight(.medium)).foregroundStyle(index == setup.step ? InterfacePalette(scheme: colorScheme, colorName: phoneThemeColor).accent : InterfacePalette(scheme: colorScheme, colorName: phoneThemeColor).secondaryText)
                }
            }
            Text(steps[setup.step]).font(.title.weight(.semibold))
            ScrollView {
                VStack(alignment: .leading, spacing: 20) { stepContent }
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack {
                if setup.step > 0 { Button("Back") { setup.step -= 1 } }
                Spacer()
                Text("Optional features can be configured later.").font(.caption).foregroundStyle(.secondary)
                if setup.step < 5 {
                    Button("Continue") { setup.step += 1 }.buttonStyle(WorkspaceButtonStyle(prominent: true))
                        .disabled(setup.step == 1 && !preferencesStore.preferences.rememberedPhones.contains { preferencesStore.sessions.state(for: $0.id) == .connected })
                } else {
                    Button("Finish setup") { setup.finish() }.buttonStyle(WorkspaceButtonStyle(prominent: true))
                }
            }
        }
        .padding(28).frame(width: 740, height: 600)
        .background(InterfacePalette(scheme: colorScheme, colorName: phoneThemeColor).canvas)
        .buttonStyle(WorkspaceButtonStyle())
        .tint(InterfacePalette(scheme: colorScheme, colorName: phoneThemeColor).accent)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in setup.refresh() }
        .task { setup.refresh() }
        .onReceive(preferencesStore.calls.$isDiscovering) { _ in setup.refresh() }
    }
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.phoneThemeColor) private var phoneThemeColor

    @ViewBuilder private var stepContent: some View {
        switch setup.step {
        case 0:
            WorkspaceCard {
                Text("Your phone, at home on your Mac.").font(.largeTitle.weight(.semibold))
                Text("Pair once, then choose the features you want. Your devices connect directly; setup never grants permissions or starts sharing by itself.").foregroundStyle(.secondary)
                Label("Wi-Fi works with debugging off", systemImage: "wifi")
                Label("USB and direct app windows are optional", systemImage: "cable.connector")
                Label("Each phone keeps its own settings", systemImage: "iphone.gen3.radiowaves.left.and.right")
            }
        case 1:
            WorkspaceCard {
                ConnectionSettingsView(connections: preferencesStore.connections)
                Text("Keep the Android setup guide open and scan this QR. Continue once the phone is connected.").font(.caption)
            }
        case 2:
            SetupMacPermissions(preferencesStore: preferencesStore, setup: setup)
            DownloadsSetupCard(preferencesStore: preferencesStore)
            phonePermissions
        case 3:
            WorkspaceCard {
                Text("Which phone apps may notify this Mac?").font(.title2.weight(.semibold))
                Text("Choose the Android apps you want to hear from. Your selections are saved for this phone and can be changed later in Notifications.")
                if let phone = preferencesStore.preferences.selectedPhone {
                    Text("\(phone.preferences.notifications.allowedApplications.count) apps allowed")
                        .font(.callout.weight(.medium)).foregroundStyle(.secondary)
                }
            }
            NotificationSettingsView(preferencesStore: preferencesStore, connections: preferencesStore.connections, initiallyShowApplications: true)
                .frame(height: 350)
        case 4:
            WorkspaceCard {
                Text("Verify both devices").font(.title2)
                Text("On Android, test alert sounds, then tap Send test in notification settings. Allow Seamless in the previous app-selection step to mirror that test. Share a small file and text in each direction.")
                Text("Screen sharing needs approval for each session. Calls require Bluetooth pairing.")
            }
        default:
            WorkspaceCard {
                Text("Make it yours.").font(.title.weight(.semibold))
                Text("Overview brings together clipboard, files, photos, camera and calls. Reopen this guide from Settings whenever you add a device or change permissions.").foregroundStyle(.secondary)
                Text("Screen sharing needs fresh Android consent for each session. Camera permission does not start a camera stream; sharing still follows your phone's approval settings.")
                    .font(.callout).foregroundStyle(.secondary)
                AppearanceSelector(preferencesStore: preferencesStore).frame(maxWidth: 340)
            }
        }
    }

    private var phonePermissions: some View {
        WorkspaceCard {
            Text("On your Android phone").font(.headline)
            Text("Open Seamless → Settings → Setup & permissions. Notification sharing, optional phone control, camera, storage and battery settings are managed there.").foregroundStyle(.secondary)
            Text("Choose which apps can notify this Mac in Notifications → App settings; permission alone does not select apps.")
                .font(.caption).foregroundStyle(.secondary)
            if let phoneID = preferencesStore.preferences.selectedPhoneID,
               preferencesStore.sessions.state(for: phoneID) == .connected,
               let permissions = preferencesStore.connections.phonePermissions[phoneID] {
                ForEach(permissions.sorted(by: { $0.key < $1.key }), id: \.key) { permission in
                    HStack { Text(permission.key); Spacer(); Text(permission.value ? "Allowed" : "Not allowed").foregroundStyle(.secondary) }
                        .font(.callout)
                }
            } else {
                Text("Connect an updated companion to see its live permission status here.").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

private struct SetupMacPermissions: View {
    @ObservedObject var preferencesStore: PreferencesStore
    @ObservedObject var setup: SetupCoordinator
    var body: some View {
        WorkspaceCard {
            HStack {
                Text("On this Mac").font(.headline)
                Spacer()
                Button(setup.isRequestingAccess ? "Requesting access…" : "Set up recommended access") {
                    setup.requestRecommendedAccess(calls: preferencesStore.calls)
                }.buttonStyle(WorkspaceButtonStyle(prominent: true)).disabled(setup.isRequestingAccess)
            }
            Text("Walk through notification, microphone and Bluetooth prompts once. You can decline optional features; no call or capture starts.")
                .font(.caption).foregroundStyle(.secondary)
            permission("Notification banners", purpose: "Show shared phone notifications outside Seamless.", status: setup.notificationStatus,
                       action: "Review access", perform: setup.requestNotifications)
            Divider()
            permission("Bluetooth · calls", purpose: "Find the paired phone for call controls. Does not connect or start a call.", status: setup.bluetoothStatus,
                       action: "Review access") {
                if setup.bluetoothStatus == "Not allowed" { setup.openSettings("Privacy_Bluetooth") }
                else { preferencesStore.calls.discoverPairedPhones() }
                setup.refresh()
            }
            Divider()
            permission("Microphone · calls", purpose: "Send your voice during a call. Optional until you use Mac audio.", status: setup.microphoneStatus,
                       action: "Review access", perform: setup.requestMicrophone)
            Text("Phone camera preview does not need access to this Mac's camera. OBS manages its own camera extension and recording permissions.")
                .font(.caption).foregroundStyle(.secondary)
            if !setup.message.isEmpty { Text(setup.message).font(.caption).foregroundStyle(.secondary) }
        }
    }
    /// Performs permission for setup guide view.
    private func permission(_ title: String, purpose: String, status: String, action: String, perform: @escaping () -> Void) -> some View {
        HStack(spacing: 20) {
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(purpose).font(.caption).foregroundStyle(.secondary)
                Text(status).font(.caption.weight(.medium)).foregroundStyle(.tint)
            }
            Spacer()
            Button(action, action: perform)
        }
    }
}

@MainActor
private final class DownloadsAccessStatus: ObservableObject {
    @Published var message = ""
}

private struct DownloadsSetupCard: View {
    @ObservedObject var preferencesStore: PreferencesStore
    @StateObject private var access = DownloadsAccessStatus()

    var body: some View {
        WorkspaceCard {
            Text("Downloads access").font(.headline)
                .disabled(preferencesStore.preferences.selectedPhoneID == nil)
            Text("Files use unique names and never replace existing downloads. Choose a paired phone first. macOS controls folder access separately.")
                .font(.caption).foregroundStyle(.secondary)
            Button("Check Downloads access") { checkDownloadsAccess() }
            if !access.message.isEmpty { Text(access.message).font(.caption).foregroundStyle(.secondary) }
        }
    }

    /// Performs check downloads access for setup guide view.
    private func checkDownloadsAccess() {
        do {
            let directory = try FileManager.default.url(for: .downloadsDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            let probe = directory.appendingPathComponent(".seamless-access-" + UUID().uuidString)
            // Exercise the real receiving location so macOS can request access during setup.
            try Data().write(to: probe, options: .withoutOverwriting)
            try FileManager.default.removeItem(at: probe)
            access.message = "Downloads is writable. Received files can save here automatically."
        } catch {
            access.message = "Downloads access is unavailable. Review System Settings → Privacy & Security → Files and Folders for Seamless. " + error.localizedDescription
        }
    }
}
