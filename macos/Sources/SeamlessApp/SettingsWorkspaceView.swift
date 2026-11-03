import SwiftUI

struct SettingsWorkspaceView: View {
    @ObservedObject var preferencesStore: PreferencesStore
    @StateObject private var extensions = ExtensionManager()
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                WorkspaceHeading(title: "Settings", subtitle: "Make Seamless feel at home.")
                WorkspaceCard {
                    HStack {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Setup & permissions").font(.headline)
                            Text("Pair devices and review optional access on both sides.").foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Open setup guide") { preferencesStore.setup.present() }
                            .buttonStyle(WorkspaceButtonStyle(prominent: true))
                    }
                }
                WorkspaceCard {
                    Text("Appearance").font(.headline)
                    AppearanceSelector(preferencesStore: preferencesStore).frame(maxWidth: 340)
                }
                WorkspaceCard {
                    Text("Incoming files").font(.headline)
                    Toggle("Automatically save files from this phone to Downloads", isOn: preferencesStore.featurePreferences.automaticallyAcceptFiles)
                    Text("Received files go to Downloads with unique names. Turn this on once for a trusted phone to skip per-file acceptance. It is off by default.").font(.caption).foregroundStyle(.secondary)
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
