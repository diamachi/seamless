import SwiftUI
import SeamlessCore

struct SetupGuideView: View {
    @ObservedObject var preferencesStore: PreferencesStore
    @ObservedObject var setup: SetupCoordinator
    let openDevices: () -> Void

    private let steps = ["Welcome", "Pair devices", "Permissions", "Ready"]
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack {
                Label("Set up Seamless", systemImage: "point.3.connected.trianglepath.dotted").font(.title2.weight(.semibold))
                Spacer()
                Button("Set up later") { setup.isPresented = false }
            }
            HStack(spacing: 16) {
                ForEach(Array(steps.enumerated()), id: \.offset) { index, title in
                    Label(title, systemImage: index < setup.step ? "checkmark.circle.fill" : "\(index + 1).circle")
                        .font(.caption.weight(.medium)).foregroundStyle(index == setup.step ? InterfacePalette(scheme: colorScheme).accent : InterfacePalette(scheme: colorScheme).secondaryText)
                }
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 20) { stepContent }
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack {
                if setup.step > 0 { Button("Back") { setup.step -= 1 } }
                Spacer()
                Text("Optional features can be configured later.").font(.caption).foregroundStyle(.secondary)
                if setup.step < 3 {
                    Button("Continue") { setup.step += 1 }.buttonStyle(WorkspaceButtonStyle(prominent: true))
                } else {
                    Button("Finish setup") { setup.finish() }.buttonStyle(WorkspaceButtonStyle(prominent: true))
                }
            }
        }
        .padding(28).frame(width: 740, height: 600)
        .background(InterfacePalette(scheme: colorScheme).canvas)
        .buttonStyle(WorkspaceButtonStyle())
        .tint(InterfacePalette(scheme: colorScheme).accent)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in setup.refresh() }
        .task { setup.refresh() }
        .onReceive(preferencesStore.calls.$isDiscovering) { _ in setup.refresh() }
    }
    @Environment(\.colorScheme) private var colorScheme

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
                Text("Pair your Android phone").font(.title2.weight(.semibold))
                Text("1. In Devices on this Mac, choose Create pairing QR.\n2. On Android, choose Pair a Mac → Scan Mac QR code.\n3. Scan this Mac’s QR and approve the trust request on your phone.").lineSpacing(8)
                Text(preferencesStore.preferences.rememberedPhones.isEmpty ? "No phone paired yet" : "\(preferencesStore.preferences.rememberedPhones.count) phone(s) remembered")
                    .font(.callout).foregroundStyle(.secondary)
                Button("Open device pairing") { setup.isPresented = false; openDevices() }
                    .buttonStyle(WorkspaceButtonStyle(prominent: true))
                Text("If macOS asks for Local Network access while connecting, review and allow it for Seamless. There is no reliable general permission-status check here; a successful connection confirms access.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        case 2:
            SetupMacPermissions(preferencesStore: preferencesStore, setup: setup)
            phonePermissions
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
            Text("Phone camera preview does not need access to this Mac's camera. OBS manages its own camera extension and recording permissions. Hotspot network scanning may separately ask for location when you use that feature.")
                .font(.caption).foregroundStyle(.secondary)
            if !setup.message.isEmpty { Text(setup.message).font(.caption).foregroundStyle(.secondary) }
        }
    }
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
