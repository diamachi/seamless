// macOS application presentation and coordination for incoming file drag handle.
// See docs/ARCHITECTURE.md for the owning subsystem and cross-platform call flow.

import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct IncomingFileDragHandle: NSViewRepresentable {
    let offer: BulkOffer
    let transfers: BulkTransfers

    /// Creates the native AppKit view hosted by SwiftUI.
    func makeNSView(context: Context) -> IncomingFileDragView {
        IncomingFileDragView(offer: offer, transfers: transfers)
    }
    /// Applies the latest SwiftUI state to the existing native view without recreating it.
    func updateNSView(_ view: IncomingFileDragView, context: Context) {}
}

final class IncomingFileDragView: NSView, NSDraggingSource, @preconcurrency NSFilePromiseProviderDelegate {
    private let offer: BulkOffer
    private let transfers: BulkTransfers
    private var promise: NSFilePromiseProvider?

    /// Constructs IncomingFileDragHandle with the dependencies and initial values supplied by its caller.
    init(offer: BulkOffer, transfers: BulkTransfers) {
        self.offer = offer
        self.transfers = transfers
        super.init(frame: NSRect(x: 0, y: 0, width: 32, height: 32))
        toolTip = "Drag into Finder to receive this file"
        setAccessibilityLabel("Drag \(offer.name) into Finder to receive")
    }
    /// Constructs IncomingFileDragHandle with the dependencies and initial values supplied by its caller.
    required init?(coder: NSCoder) { nil }
    /// Performs draw for incoming file drag handle.
    override func draw(_ dirtyRect: NSRect) {
        NSImage(systemSymbolName: "hand.draw", accessibilityDescription: nil)?.draw(in: bounds.insetBy(dx: 4, dy: 4))
    }
    /// Performs mouse down for incoming file drag handle.
    override func mouseDown(with event: NSEvent) {}
    /// Performs mouse dragged for incoming file drag handle.
    override func mouseDragged(with event: NSEvent) {
        guard promise == nil else { return }
        let type = UTType(filenameExtension: (offer.name as NSString).pathExtension) ?? .data
        let provider = NSFilePromiseProvider(fileType: type.identifier, delegate: self)
        promise = provider
        let item = NSDraggingItem(pasteboardWriter: provider)
        item.setDraggingFrame(bounds, contents: NSWorkspace.shared.icon(for: type))
        beginDraggingSession(with: [item], event: event, source: self)
    }
    /// Performs dragging session for incoming file drag handle.
    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation { .copy }
    /// Performs dragging session for incoming file drag handle.
    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) { promise = nil }
    /// Performs file promise provider for incoming file drag handle.
    func filePromiseProvider(_ filePromiseProvider: NSFilePromiseProvider, fileNameForType fileType: String) -> String { offer.name }
    /// Performs operation queue for incoming file drag handle.
    func operationQueue(for filePromiseProvider: NSFilePromiseProvider) -> OperationQueue { .main }
    /// Performs file promise provider for incoming file drag handle.
    func filePromiseProvider(_ filePromiseProvider: NSFilePromiseProvider, writePromiseTo url: URL, completionHandler: @escaping ((any Error)?) -> Void) {
        let completion = FilePromiseCompletion(completionHandler)
        MainActor.assumeIsolated {
            transfers.accept(offer, promisedURL: url) { error in completion.finish(error) }
        }
    }
}

// AppKit supplies a legacy callback; the promise must complete exactly once, including cancellation.
private final class FilePromiseCompletion: @unchecked Sendable {
    private let lock = NSLock()
    private var handler: (((any Error)?) -> Void)?
    /// Constructs IncomingFileDragHandle with the dependencies and initial values supplied by its caller.
    init(_ handler: @escaping ((any Error)?) -> Void) { self.handler = handler }
    /// Completes the current workflow and publishes its resulting state.
    func finish(_ error: (any Error)?) {
        lock.lock()
        let callback = handler
        handler = nil
        lock.unlock()
        callback?(error)
    }
}
