// macOS application presentation and coordination for clipboard text editor.
// See docs/ARCHITECTURE.md for the owning subsystem and cross-platform call flow.

import AppKit
import SwiftUI

struct ClipboardTextEditor: NSViewRepresentable {
    /// Creates the delegate bridge that forwards native callbacks into SwiftUI state.
    @Binding var text: String

    /// Handles make coordinator callback by translating the native window event into the owning app action.
    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

    /// Creates the native AppKit view hosted by SwiftUI.
    func makeNSView(context: Context) -> NSScrollView {
        let editor = PlaceholderTextView()
        editor.font = .systemFont(ofSize: 14)
        editor.textColor = .labelColor
        editor.insertionPointColor = .labelColor
        editor.drawsBackground = false
        editor.isRichText = false
        editor.isAutomaticQuoteSubstitutionEnabled = false
        editor.isAutomaticDashSubstitutionEnabled = false
        editor.textContainerInset = NSSize(width: 12, height: 12)
        editor.textContainer?.lineFragmentPadding = 0
        editor.isVerticallyResizable = true
        editor.isHorizontallyResizable = false
        editor.autoresizingMask = [.width]
        editor.textContainer?.widthTracksTextView = true
        editor.delegate = context.coordinator
        editor.setAccessibilityLabel("Text or a link")
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.documentView = editor
        return scroll
    }

    /// Applies the latest SwiftUI state to the existing native view without recreating it.
    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.text = $text
        guard let editor = scroll.documentView as? PlaceholderTextView else { return }
        if editor.string != text { editor.string = text }
        editor.needsDisplay = true
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>
        /// Constructs ClipboardTextEditor with the dependencies and initial values supplied by its caller.
        init(text: Binding<String>) { self.text = text }
        /// Performs text did change for clipboard text editor.
        func textDidChange(_ notification: Notification) {
            guard let editor = notification.object as? NSTextView else { return }
            text.wrappedValue = editor.string
            editor.needsDisplay = true
        }
    }
}

private final class PlaceholderTextView: NSTextView {
    /// Performs draw for clipboard text editor.
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard string.isEmpty else { return }
        // Use the text view's own origin and font so placeholder and insertion point share an inset.
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font ?? NSFont.systemFont(ofSize: 14), .foregroundColor: NSColor.placeholderTextColor
        ]
        ("Write text or paste a link…" as NSString).draw(at: textContainerOrigin, withAttributes: attributes)
    }
}
