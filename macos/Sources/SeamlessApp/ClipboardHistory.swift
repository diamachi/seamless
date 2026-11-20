// macOS application presentation and coordination for clipboard history.
// See docs/ARCHITECTURE.md for the owning subsystem and cross-platform call flow.

import AppKit
import Foundation

struct ClipboardHistoryItem: Identifiable {
    let id = UUID()
    let text: String
    let source: String
    let phoneID: String
    let date = Date()
}

@MainActor
final class ClipboardHistory: ObservableObject {
    /// Performs record for clipboard history.
    @Published private(set) var items: [ClipboardHistoryItem] = []
    /// Handles record callback by translating the native window event into the owning app action.
    func record(text: String, source: String, phoneID: String) {
        guard !text.isEmpty, text.count <= 32_000 else { return }
        guard items.first?.text != text || items.first?.phoneID != phoneID else { return }
        items.insert(ClipboardHistoryItem(text: text, source: source, phoneID: phoneID), at: 0)
        items = Array(items.prefix(30))
    }
    /// Performs delete for clipboard history.
    func delete(_ item: ClipboardHistoryItem) { items.removeAll { $0.id == item.id } }
    /// Clears the collection owned by this component.
    func clear(phoneID: String?) { items.removeAll { $0.phoneID == phoneID } }
    /// Clears the collection owned by this component.
    func clear() { items = [] }
    /// Copies the selected text to the local system clipboard.
    func copy(_ item: ClipboardHistoryItem) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(item.text, forType: .string)
    }
}
