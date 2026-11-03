import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct IncomingFileDragHandle: NSViewRepresentable {
    let offer: BulkOffer
    let transfers: BulkTransfers

    func makeNSView(context: Context) -> IncomingFileDragView {
        IncomingFileDragView(offer: offer, transfers: transfers)
    }
    func updateNSView(_ view: IncomingFileDragView, context: Context) {}
}

final class IncomingFileDragView: NSView, NSDraggingSource, @preconcurrency NSFilePromiseProviderDelegate {
    private let offer: BulkOffer
    private let transfers: BulkTransfers
    private var promise: NSFilePromiseProvider?

    init(offer: BulkOffer, transfers: BulkTransfers) {
        self.offer = offer
        self.transfers = transfers
        super.init(frame: NSRect(x: 0, y: 0, width: 32, height: 32))
        toolTip = "Drag into Finder to receive this file"
        setAccessibilityLabel("Drag \(offer.name) into Finder to receive")
    }
    required init?(coder: NSCoder) { nil }
    override func draw(_ dirtyRect: NSRect) {
        NSImage(systemSymbolName: "hand.draw", accessibilityDescription: nil)?.draw(in: bounds.insetBy(dx: 4, dy: 4))
    }
    override func mouseDown(with event: NSEvent) {}
    override func mouseDragged(with event: NSEvent) {
        guard promise == nil else { return }
        let type = UTType(filenameExtension: (offer.name as NSString).pathExtension) ?? .data
        let provider = NSFilePromiseProvider(fileType: type.identifier, delegate: self)
        promise = provider
        let item = NSDraggingItem(pasteboardWriter: provider)
        item.setDraggingFrame(bounds, contents: NSWorkspace.shared.icon(for: type))
        beginDraggingSession(with: [item], event: event, source: self)
    }
    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation { .copy }
    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) { promise = nil }
    func filePromiseProvider(_ filePromiseProvider: NSFilePromiseProvider, fileNameForType fileType: String) -> String { offer.name }
    func operationQueue(for filePromiseProvider: NSFilePromiseProvider) -> OperationQueue { .main }
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
    init(_ handler: @escaping ((any Error)?) -> Void) { self.handler = handler }
    func finish(_ error: (any Error)?) {
        lock.lock()
        let callback = handler
        handler = nil
        lock.unlock()
        callback?(error)
    }
}
