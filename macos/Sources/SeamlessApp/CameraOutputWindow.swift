import AppKit
import SwiftUI

@MainActor
final class CameraOutputWindow: NSObject, NSWindowDelegate {
    static let shared = CameraOutputWindow()
    private var window: NSWindow?
    private weak var controller: PhoneVideoStreamController?

    func show(controller: PhoneVideoStreamController) {
        if let window { window.makeKeyAndOrderFront(nil); return }
        self.controller = controller
        controller.isDetached = true
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 960, height: 540), styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "Seamless Camera Output"
        window.contentView = NSHostingView(rootView: CameraOutputSurface(controller: controller))
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        window.makeKeyAndOrderFront(nil)
        self.window = window
    }

    func windowWillClose(_ notification: Notification) {
        controller?.isDetached = false
        window = nil
    }
}

private struct CameraOutputSurface: View {
    @ObservedObject var controller: PhoneVideoStreamController
    var body: some View {
        PhoneVideoSurface(controller: controller)
            .aspectRatio(controller.videoSize.width / max(1, controller.videoSize.height), contentMode: .fit)
            .frame(maxWidth: .infinity, maxHeight: .infinity).background(.black)
    }
}
