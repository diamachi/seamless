// macOS application presentation and coordination for seamless app.
// See docs/ARCHITECTURE.md for the owning subsystem and cross-platform call flow.

import SwiftUI
import SeamlessCore

@main
struct SeamlessApp: App {
    @NSApplicationDelegateAdaptor(ApplicationLifecycleDelegate.self) private var applicationDelegate
    @StateObject private var preferencesStore = PreferencesStore()

    var body: some Scene {
        Window("Seamless", id: "main") {
            MainWindow(preferencesStore: preferencesStore, applicationDelegate: applicationDelegate)
                .environment(\.phoneThemeColor, preferencesStore.preferences.selectedPhone?.preferences.previewColor ?? "sage")
                .frame(minWidth: 860, minHeight: 620)
                .task {
                    applicationDelegate.preferencesStore = preferencesStore
                    preferencesStore.startConnections()
                    AppIconController.shared.configure()
                    MacNotificationDelivery.shared.configure()
                }
        }
        .defaultSize(width: 1160, height: 820)
        .windowStyle(.titleBar)


    }
}
