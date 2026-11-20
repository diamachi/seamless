// macOS application presentation and coordination for settings workspace view.
// See docs/ARCHITECTURE.md for the owning subsystem and cross-platform call flow.

import SwiftUI

struct SettingsWorkspaceView: View {
    @ObservedObject var preferencesStore: PreferencesStore
    @StateObject private var extensions = ExtensionManager()
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                DiagnosticsConsoleView()
                WorkspaceHeading(title: "Settings", subtitle: "Make Seamless feel at home.")
                WorkspaceCard {
                    HStack {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Setup & permissions").font(.headline)
                            Text("Pair devices and review optional access on both sides.").foregroundStyle(.secondary)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 8) {
                            Button("Open setup guide") { preferencesStore.setup.present() }
                            Button("Restart onboarding") { preferencesStore.setup.restart() }
                                .help("Start at Welcome while keeping your paired devices and granted permissions")
                        }
                            .buttonStyle(WorkspaceButtonStyle(prominent: true))
                    }
                }
                WorkspaceCard {
                    Text("Appearance").font(.headline)
                    AppearanceSelector(preferencesStore: preferencesStore).frame(maxWidth: 340)
                }
                WorkspaceCard {
                    Text("Incoming files").font(.headline)
                    Text("Incoming files appear in the menu-bar popup. Choose Downloads, another folder, or Decline. Saved files use unique names.").font(.caption).foregroundStyle(.secondary)
                }
                WorkspaceCard {
                    HStack {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Seamless Camera").font(.headline)
                            Text("A system webcam for Teams, Meet, OBS and other camera apps.").foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Install / reinstall") { extensions.install() }
                            .buttonStyle(WorkspaceButtonStyle(prominent: true)).disabled(!extensions.isBundled)
                        Button("Uninstall") { extensions.uninstall() }.disabled(!extensions.isBundled)
                    }
                    Text(extensions.message).font(.callout).foregroundStyle(.secondary)
                    HStack {
                        Text("With the official OBS camera extension installed, Live camera can feed OBS Virtual Camera directly while OBS stays closed. The clean output window remains an alternative.").font(.callout).foregroundStyle(.secondary)
                        Spacer()
                        Button("OBS setup guide") {
                            if let url = URL(string: "https://obsproject.com/kb/virtual-camera-guide") { NSWorkspace.shared.open(url) }
                        }
                    }
                    if !extensions.isBundled {
                        Text("Live camera preview works separately. A signed camera-extension build is required before installation can be offered.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                WorkspaceCard {
                    Text("Android background connection").font(.headline)
                    Text("The companion’s connection service runs in the background with an ongoing notification. You can leave its screen. Android battery restrictions, Force stop and reboot can still interrupt it.").foregroundStyle(.secondary)
                    Text("On the phone, use Settings → Background connection to review battery access. Performance lab is also inside the phone’s Settings.").font(.caption).foregroundStyle(.secondary)
                }
            }
        }.buttonStyle(WorkspaceButtonStyle())
    }
}
