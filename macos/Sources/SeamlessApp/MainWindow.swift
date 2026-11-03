import SwiftUI
import SeamlessCore

private enum Destination: String, CaseIterable, Identifiable {
    case overview = "Overview"
    case calls = "Calls"
    case devices = "Devices"
    case notifications = "Notifications"
    case files = "Files"
    case hotspot = "Hotspot"
    case screen = "Phone screen"
    case webcam = "Live camera"
    case settings = "Settings"
    case photos = "Photos"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .overview: return "iphone"
        case .calls: return "phone"
        case .devices: return "laptopcomputer.and.iphone"
        case .notifications: return "bell"
        case .files: return "folder"
        case .hotspot: return "personalhotspot"
        case .screen: return "rectangle.on.rectangle"
        case .webcam: return "video"
        case .settings: return "gearshape"
        case .photos: return "photo.on.rectangle"
        }
    }
}

@MainActor
private final class WindowNavigation: ObservableObject {
    @Published var destination: Destination? = .overview
}

struct MainWindow: View {
    @ObservedObject var preferencesStore: PreferencesStore
    let applicationDelegate: ApplicationLifecycleDelegate
    @Environment(\.openWindow) private var openWindow
    @StateObject private var navigation = WindowNavigation()
    @StateObject private var notices = AppNotices()
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        NavigationSplitView {
            sidebar

                .navigationSplitViewColumnWidth(min: 230, ideal: sidebarWidth, max: 500)
        } detail: {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Text(preferencesStore.preferences.selectedPhone?.displayName ?? "Seamless")
                        .font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
                    Spacer()
                    if let phoneID = preferencesStore.preferences.selectedPhoneID {
                        ConnectionBadge(isConnected: preferencesStore.sessions.state(for: phoneID) == .connected,
                            connectionName: preferencesStore.connections.usb.verifiedSerial(phoneID: phoneID) == nil ? "Connected" : "USB connected")
                    }
                }
                detailContent
                    .buttonStyle(WorkspaceButtonStyle())
                    .id(preferencesStore.preferences.selectedPhoneID)
            }
            .padding(24)
            .background(TranslucentSurface(material: .underWindowBackground, tint: InterfacePalette(scheme: colorScheme).canvas))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .disabled(!preferencesStore.canSave)
            .tint(InterfacePalette(scheme: colorScheme).accent)
        }
        .modifier(SetupPresentation(preferencesStore: preferencesStore, setup: preferencesStore.setup) {
            navigation.destination = .devices
        })
        .overlay(alignment: .topTrailing) {
            IncomingCallBanner(calls: preferencesStore.calls, preferencesStore: preferencesStore) {
                if let phoneID = preferencesStore.calls.activePhoneID { preferencesStore.selectPhone(id: phoneID) }
                navigation.destination = .calls
            }
        }
        .overlay(alignment: .bottomTrailing) {
            ActivityPopup(bulk: preferencesStore.connections.bulk,
                          legacy: preferencesStore.connections.files,
                          folders: preferencesStore.connections.storage.folderDownloads,
                          notices: notices)
        }
        .onChange(of: preferencesStore.connections.bulk.message) { _, message in notices.show(message) }
        .onChange(of: preferencesStore.connections.files.message) { _, message in notices.show(message) }
        .onChange(of: preferencesStore.connections.storage.folderDownloads.message) { _, message in notices.show(message) }
        .onChange(of: preferencesStore.errorMessage) { _, message in
            if let message { notices.show(message) }
        }
        .modifier(FileDropTarget(phoneID: preferencesStore.preferences.selectedPhoneID, bulk: preferencesStore.connections.bulk))
        .accentColor(InterfacePalette(scheme: colorScheme).accent)
        .toolbarBackground(.hidden, for: .windowToolbar)
        .background(WindowSurfaceConfigurator())
        .task {
            let reopen = {
                openWindow(id: "main")
                NSApplication.shared.activate(ignoringOtherApps: true)
            }
            applicationDelegate.openMainWindow = reopen
            MenuBarDashboard.shared.configure(preferencesStore: preferencesStore, openMainWindow: reopen)
        }
    }

    private var sidebarWidth: CGFloat {
        let name = preferencesStore.preferences.selectedPhone?.displayName ?? "Choose a phone"
        let width = (name as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 13, weight: .semibold)]).width + 130
        return min(450, max(250, width))
    }

    private var sidebar: some View {
        let palette = InterfacePalette(scheme: colorScheme)
        return VStack(alignment: .leading, spacing: 24) {
            HStack(spacing: 10) {
                Image(systemName: "point.3.connected.trianglepath.dotted")
                    .font(.system(size: 21, weight: .medium)).foregroundStyle(palette.accent)
                Text("Seamless").font(.system(size: 19, weight: .semibold, design: .rounded))
            }.padding(.horizontal, 8).padding(.top, 12)
            PhoneSwitcherView(preferencesStore: preferencesStore)
            Button { navigation.destination = .devices } label: {
                Label("Connect new phone", systemImage: "plus.circle")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(WorkspaceButtonStyle(prominent: true))
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    sidebarCaption("WORKSPACE")
                    sidebarItem(.overview)
                    sidebarItem(.calls)
                    sidebarItem(.screen)
                    sidebarItem(.files)
                    sidebarItem(.photos)
                    sidebarItem(.notifications)
                    sidebarItem(.webcam)
                    sidebarCaption("MANAGE").padding(.top, 20)
                    sidebarItem(.devices)
                    sidebarItem(.hotspot)
                }
            }
            Spacer(minLength: 0)
            VStack(alignment: .leading, spacing: 8) {
                sidebarItem(.settings)
                QuitApplicationButton()
                    .buttonStyle(WorkspaceButtonStyle())
            }

        }
        .padding(.horizontal, 18)
        .padding(.bottom, 20)
        .background(TranslucentSurface(material: .sidebar, tint: palette.sidebar))
        .foregroundStyle(palette.text)
    }

    private func sidebarCaption(_ title: String) -> some View {
        Text(title).font(.system(size: 9, weight: .semibold)).tracking(1.3)
            .foregroundStyle(InterfacePalette(scheme: colorScheme).secondaryText)
            .padding(.horizontal, 12).padding(.bottom, 8)
    }

    private func sidebarItem(_ destination: Destination) -> some View {
        let palette = InterfacePalette(scheme: colorScheme)
        let isSelected = navigation.destination == destination
        return Button {
            navigation.destination = destination
        } label: {
            HStack(spacing: 12) {
                Image(systemName: destination.symbol).font(.system(size: 16, weight: .regular)).frame(width: 22)
                Text(destination.rawValue).font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                Spacer(minLength: 0)
            }
            .foregroundStyle(isSelected ? palette.accent : palette.secondaryText)
            .padding(.horizontal, 12).padding(.vertical, 12)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 12).fill(palette.accentWash)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    @ViewBuilder
    private var detailContent: some View {
        switch navigation.destination {
        case .calls: CallsWorkspaceView(preferencesStore: preferencesStore, calls: preferencesStore.calls)
        case .settings: SettingsWorkspaceView(preferencesStore: preferencesStore)
        case .photos: PhotosWorkspaceView(preferencesStore: preferencesStore, browser: preferencesStore.connections.storage, bulk: preferencesStore.connections.bulk)
        case .hotspot: HotspotView(preferencesStore: preferencesStore)
        case .files:
            FilesWorkspaceView(preferencesStore: preferencesStore, bulk: preferencesStore.connections.bulk, browser: preferencesStore.connections.storage)
        case .notifications:
            NotificationSettingsView(preferencesStore: preferencesStore, connections: preferencesStore.connections)
        case .screen:
            PhoneScreenView(preferencesStore: preferencesStore, controller: preferencesStore.connections.screen)
        case .webcam:
            CameraWorkspaceView(preferencesStore: preferencesStore, controller: preferencesStore.connections.camera)
        case .devices:
            ScrollView {
                DeviceManagementView(preferencesStore: preferencesStore)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        case .overview, nil:
            ScrollView {
                OverviewView(preferencesStore: preferencesStore, openDestination: { navigation.destination = $0 })
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

private struct OverviewView: View {
    @ObservedObject var preferencesStore: PreferencesStore
    let openDestination: (Destination) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            WorkspaceHeading(title: "Overview", subtitle: "Everything you need, close at hand.")
            if let phone = preferencesStore.preferences.selectedPhone {
                PhoneOverviewCard(phone: phone, status: preferencesStore.connections.statuses[phone.id],
                    isConnected: preferencesStore.sessions.state(for: phone.id) == .connected,
                    reconnect: { preferencesStore.connections.reconnect(phone) }, openScreen: { openDestination(.screen) },
                    isRinging: preferencesStore.connections.ringingPhones.contains(phone.id),
                    ringPhone: {
                        preferencesStore.connections.ring(phoneID: phone.id,
                            stop: preferencesStore.connections.ringingPhones.contains(phone.id))
                    }, colorName: preferencesStore.featurePreferences.previewColor)
                deviceAndQuickAccess(status: preferencesStore.connections.statuses[phone.id])
                ClipboardSharingView(preferencesStore: preferencesStore)

            } else {
                WorkspaceCard {
                    Text(preferencesStore.preferences.rememberedPhones.isEmpty ? "Connect your first phone" : "Choose a phone in the sidebar").font(.title2)
                    Button("Manage devices") { openDestination(.devices) }.buttonStyle(WorkspaceButtonStyle(prominent: true))
                }
            }
        }
    }

    private func deviceAndQuickAccess(status: ConnectedPhoneStatus?) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: 16) {
                DeviceDetailsCard(status: status).frame(minWidth: 500, maxWidth: .infinity)
                quickAccessCards.frame(width: 560)
            }
            VStack(spacing: 16) {
                DeviceDetailsCard(status: status)
                quickAccessCards
            }
        }.frame(maxWidth: .infinity)
    }

    private var quickAccessCards: some View {
        HStack(spacing: 12) {
            quickAction("Files", symbol: "folder", destination: .files)
            quickAction("Photos", symbol: "photo", destination: .photos)
            quickAction("Live camera", symbol: "video", destination: .webcam)
            OverviewCallsShortcut(calls: preferencesStore.calls, phoneID: preferencesStore.preferences.selectedPhoneID) {
                openDestination(.calls)
            }
        }
    }

    private func quickAction(_ title: String, symbol: String, destination: Destination) -> some View {
        Button { openDestination(destination) } label: {
            WorkspaceCard {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: symbol).font(.title3).foregroundStyle(.tint)
                        Spacer(minLength: 0)
                        Image(systemName: "arrow.up.right").foregroundStyle(.secondary).font(.caption)
                    }
                    Text(title).font(.system(size: 13, weight: .semibold))
                }.frame(minHeight: 72, alignment: .center)
            }
        }.buttonStyle(.plain)
    }

}
