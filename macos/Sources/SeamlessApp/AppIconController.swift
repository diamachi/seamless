import AppKit

@MainActor
final class AppIconController {
    static let shared = AppIconController()

    func configure() { update() }

    func update() {
        if Bundle.main.url(forResource: "Assets", withExtension: "car") != nil {
            // Let macOS select the native default/dark/clear/tinted rendition.
            NSApplication.shared.applicationIconImage = nil
            return
        }
        guard let path = Bundle.main.path(forResource: "Seamless", ofType: "icns"),
              let image = NSImage(contentsOfFile: path) else { return }
        // Keep the chosen dark pastel identity consistent even when the app appearance changes.
        NSApplication.shared.applicationIconImage = image
    }
}
