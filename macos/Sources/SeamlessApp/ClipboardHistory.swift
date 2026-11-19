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
    @Published private(set) var items: [ClipboardHistoryItem] = []
    func record(text: String, source: String, phoneID: String) {
        guard !text.isEmpty, text.count <= 32_000 else { return }
        guard items.first?.text != text || items.first?.phoneID != phoneID else { return }
        items.insert(ClipboardHistoryItem(text: text, source: source, phoneID: phoneID), at: 0)
        items = Array(items.prefix(30))
    }
    func delete(_ item: ClipboardHistoryItem) { items.removeAll { $0.id == item.id } }
    func clear(phoneID: String?) { items.removeAll { $0.phoneID == phoneID } }
    func clear() { items = [] }
    func copy(_ item: ClipboardHistoryItem) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(item.text, forType: .string)
    }
}
