// macOS application presentation and coordination for clipboard sharing view.
// See docs/ARCHITECTURE.md for the owning subsystem and cross-platform call flow.

import SwiftUI

@MainActor
final class ClipboardEditor: ObservableObject { @Published var text = "" }

struct ClipboardSharingView: View {
    @ObservedObject var preferencesStore: PreferencesStore
    @StateObject private var editor = ClipboardEditor()
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.phoneThemeColor) private var phoneThemeColor
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Share text").font(.title2.weight(.semibold))
            ViewThatFits(in: .horizontal) {
                EqualHeightCardRow {
                    historyCard
                    composerCard
                }
                VStack(alignment: .leading, spacing: 20) {
                    composerCard
                    historyCard
                }
            }
        }.buttonStyle(WorkspaceButtonStyle())
    }

    private var historyCard: some View {
        WorkspaceCard(fillsHeight: true) {
            ClipboardHistoryView(history: preferencesStore.connections.clipboardHistory,
                                 phoneID: preferencesStore.preferences.selectedPhoneID)
        }
    }

    private var composerCard: some View {
        WorkspaceCard(fillsHeight: true) {
            Text("Mac → phone").font(.headline)
            Text("Copy text on this Mac, then send it below. Tap Copy in the phone notification to use it.")
                .font(.caption).foregroundStyle(.secondary)
            textEditor
            if let phoneID = preferencesStore.preferences.selectedPhoneID {
                HStack {
                    Spacer()
                    Button("Send copied text") { preferencesStore.connections.sendClipboard(phoneID: phoneID) }
                    Button("Send text") { preferencesStore.connections.sendText(editor.text, phoneID: phoneID) }
                        .buttonStyle(WorkspaceButtonStyle(prominent: true))
                        .disabled(editor.text.isEmpty || editor.text.utf16.count > 32_000)
                }.disabled(preferencesStore.sessions.state(for: phoneID) != .connected)
            }
            if let phoneID = preferencesStore.preferences.selectedPhoneID {
                Text(preferencesStore.connections.clipboardStatus[phoneID] ?? "Ready · copy text or write a message above")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Text("On Android, select text → Share → Seamless. Received text appears here.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var textEditor: some View {
        let palette = InterfacePalette(scheme: colorScheme, colorName: phoneThemeColor)
        return ClipboardTextEditor(text: $editor.text)
        .frame(minHeight: 110, idealHeight: 130, maxHeight: 170)
        .background(palette.canvas, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(palette.border))
        .accessibilityLabel("Text or a link")
    }
}

private struct ClipboardHistoryView: View {
    @ObservedObject var history: ClipboardHistory
    let phoneID: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Received text").font(.headline)
                Spacer()
                Button("Clear all") { history.clear(phoneID: phoneID) }
            }
            Text("Text shared from your phone. Cards stay until deleted or Seamless quits.")
                .font(.caption).foregroundStyle(.secondary)
            if visibleItems.isEmpty {
                ContentUnavailableView("Text shared from your phone appears here", systemImage: "doc.on.clipboard")
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            } else {
                ScrollView(.horizontal) {
                    HStack(alignment: .top, spacing: 14) {
                        ForEach(visibleItems) { item in
                            WorkspaceCard(fillsHeight: true) {
                                Label(item.source, systemImage: item.source == "Mac" ? "laptopcomputer" : "iphone")
                                    .font(.caption).foregroundStyle(.secondary)
                                Text(item.text).lineLimit(8)
                                    .frame(maxWidth: .infinity, minHeight: 140, alignment: .topLeading)
                                    .textSelection(.enabled)
                                HStack {
                                    Button("Copy to clipboard") { history.copy(item) }
                                    Button("Delete") { history.delete(item) }
                                }
                            }.frame(width: 240)
                        }
                    }
                }
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private var visibleItems: [ClipboardHistoryItem] {
        history.items.filter { $0.phoneID == phoneID }
    }

}
