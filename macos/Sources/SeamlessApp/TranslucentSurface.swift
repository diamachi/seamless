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

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        updateNSView(view, context: context)
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
        view.blendingMode = .behindWindow
        view.state = .followsWindowActiveState
    }
}

struct WindowSurfaceConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> WindowSurfaceView { WindowSurfaceView() }
    func updateNSView(_ view: WindowSurfaceView, context: Context) {}
}

final class WindowSurfaceView: NSView {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        // Native material must see the desktop rather than an opaque window backing.
        window?.isOpaque = false
        window?.backgroundColor = .clear
    }
}
