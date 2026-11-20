// macOS application presentation and coordination for translucent surface.
// See docs/ARCHITECTURE.md for the owning subsystem and cross-platform call flow.

import AppKit
import SwiftUI

struct TranslucentSurface: View {
    let material: NSVisualEffectView.Material
    let tint: Color
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        if reduceTransparency {
            tint
        } else {
            NativeVisualEffect(material: material)
                .overlay(tint.opacity(0.62))
                .allowsHitTesting(false)
        }
    }
}

private struct NativeVisualEffect: NSViewRepresentable {
    let material: NSVisualEffectView.Material

    /// Creates the native AppKit view hosted by SwiftUI.
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        updateNSView(view, context: context)
        return view
    }

    /// Applies the latest SwiftUI state to the existing native view without recreating it.
    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
        view.blendingMode = .behindWindow
        view.state = .followsWindowActiveState
    }
}

struct WindowSurfaceConfigurator: NSViewRepresentable {
    /// Creates the native AppKit view hosted by SwiftUI.
    func makeNSView(context: Context) -> WindowSurfaceView { WindowSurfaceView() }
    /// Applies the latest SwiftUI state to the existing native view without recreating it.
    func updateNSView(_ view: WindowSurfaceView, context: Context) {}
}

final class WindowSurfaceView: NSView {
    /// Configures the native window after AppKit attaches this view to it.
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        // Native material must see the desktop rather than an opaque window backing.
        window?.isOpaque = false
        window?.backgroundColor = .clear
        window?.titlebarAppearsTransparent = true
        window?.titleVisibility = .hidden
        window?.titlebarSeparatorStyle = .none
        window?.styleMask.insert(.fullSizeContentView)
        for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            window?.standardWindowButton(button)?.isHidden = false
        }
    }
}
