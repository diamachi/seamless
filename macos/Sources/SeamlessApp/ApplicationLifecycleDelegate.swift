import AppKit

@MainActor
final class ApplicationLifecycleDelegate: NSObject, NSApplicationDelegate {
    weak var preferencesStore: PreferencesStore?
    var openMainWindow: (() -> Void)?

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        if !hasVisibleWindows { openMainWindow?() }
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        // App-lifetime cleanup also runs when the main window was already closed.
        preferencesStore?.calls.shutdown()
        preferencesStore?.connections.shutdown()
    }
}
