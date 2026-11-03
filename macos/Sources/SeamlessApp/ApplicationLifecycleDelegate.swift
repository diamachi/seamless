import AppKit

@MainActor
final class ApplicationLifecycleDelegate: NSObject, NSApplicationDelegate {
    weak var preferencesStore: PreferencesStore?
    var openMainWindow: (() -> Void)?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NotificationCenter.default.addObserver(self, selector: #selector(windowWillClose(_:)),
            name: NSWindow.willCloseNotification, object: nil)
    }

    @objc private func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, window.identifier?.rawValue == "main" else { return }
        Task { @MainActor in
            // willClose arrives before visibility changes; check after the close completes.
            await Task.yield()
            let hasVisibleWindow = NSApplication.shared.windows.contains { candidate in
                candidate.isVisible && candidate.styleMask.contains(.titled)
            }
            if !hasVisibleWindow { NSApplication.shared.setActivationPolicy(.accessory) }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        if !hasVisibleWindows { openMainWindow?() }
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        NotificationCenter.default.removeObserver(self)
        // App-lifetime cleanup also runs when the main window was already closed.
        preferencesStore?.calls.shutdown()
        preferencesStore?.connections.shutdown()
    }
}
