// macOS application presentation and coordination for application lifecycle delegate.
// See docs/ARCHITECTURE.md for the owning subsystem and cross-platform call flow.

import AppKit

@MainActor
final class ApplicationLifecycleDelegate: NSObject, NSApplicationDelegate {
    weak var preferencesStore: PreferencesStore?
    var openMainWindow: (() -> Void)?

    /// Performs application did finish launching for application lifecycle delegate.
    func applicationDidFinishLaunching(_ notification: Notification) {
        NotificationCenter.default.addObserver(self, selector: #selector(windowWillClose(_:)),
            name: NSWindow.willCloseNotification, object: nil)
    }

    /// Handles window will close callback by translating the native window event into the owning app action.
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

    /// Keeps the menu-bar application alive after the last ordinary window closes.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    /// Restores the main window when the user explicitly reopens the application.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        if !hasVisibleWindows { openMainWindow?() }
        return true
    }

    /// Shuts down connection and media resources before the application exits.
    func applicationWillTerminate(_ notification: Notification) {
        NotificationCenter.default.removeObserver(self)
        // App-lifetime cleanup also runs when the main window was already closed.
        preferencesStore?.calls.shutdown()
        preferencesStore?.connections.shutdown()
    }
}
