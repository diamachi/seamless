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
    @Published var isEnabled = false
    @Published private(set) var items: [ClipboardHistoryItem] = []
    func record(text: String, source: String, phoneID: String) {
        guard isEnabled, !text.isEmpty, text.count <= 32_000 else { return }
        guard items.first?.text != text || items.first?.phoneID != phoneID else { return }
        items.insert(ClipboardHistoryItem(text: text, source: source, phoneID: phoneID), at: 0)
        items = Array(items.prefix(30))
    }
    func clear() { items = [] }
    func copy(_ item: ClipboardHistoryItem) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(item.text, forType: .string)
    }
}
