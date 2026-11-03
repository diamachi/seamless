import SwiftUI

@MainActor
final class ClipboardEditor: ObservableObject { @Published var text = "" }

struct ClipboardSharingView: View {
    @ObservedObject var preferencesStore: PreferencesStore
    @StateObject private var editor = ClipboardEditor()
    @Environment(\.colorScheme) private var colorScheme
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Clipboard").font(.title2.weight(.semibold))
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
            Text("Send to phone").font(.headline)
            textEditor
            if let phoneID = preferencesStore.preferences.selectedPhoneID {
                HStack {
                    Spacer()
                    Button("Send clipboard") { preferencesStore.connections.sendClipboard(phoneID: phoneID) }
                    Button("Send text") { preferencesStore.connections.sendText(editor.text, phoneID: phoneID) }
                        .buttonStyle(WorkspaceButtonStyle(prominent: true))
                        .disabled(editor.text.isEmpty || editor.text.count > 32_000)
                }.disabled(preferencesStore.sessions.state(for: phoneID) != .connected)
            }
            Toggle("Automatically send new Mac clipboard text", isOn: preferencesStore.featurePreferences.automaticallyShareMacClipboard)
            Text("From Android, use Share → Seamless or Send phone clipboard. Android 10+ restricts unattended background clipboard reads.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var textEditor: some View {
        let palette = InterfacePalette(scheme: colorScheme)
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
                Text("Clipboard shelf").font(.headline)
                Spacer()
                Button("Clear") { history.clear() }
            }
            Toggle("Keep history during this app session", isOn: $history.isEnabled)
            Text("Up to 30 text clips from either device. History stays in memory and disappears when Seamless quits. Avoid enabling it while copying sensitive text.")
                .font(.caption).foregroundStyle(.secondary)
            if visibleItems.isEmpty {
                ContentUnavailableView("Your next clips appear here", systemImage: "doc.on.clipboard")
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
                                Button("Copy") { history.copy(item) }
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
