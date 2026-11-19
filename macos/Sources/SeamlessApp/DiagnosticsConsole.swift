import AppKit
import SwiftUI

/// Keeps a bounded, memory-only event trail. Payloads are excluded so reports can be shared safely.
@MainActor
final class DiagnosticsConsole: ObservableObject {
    static let shared = DiagnosticsConsole()
    @Published var isEnabled = false
    @Published private(set) var lines: [String] = []

    func record(_ event: String) {
        guard isEnabled else { return }
        let timestamp = Date().formatted(date: .omitted, time: .standard)
        lines.append(timestamp + "  " + event)
        if lines.count > 500 { lines.removeFirst(lines.count - 500) }
    }

    func clear() { lines = [] }

    func copyReport() {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
        let report = "Seamless " + version + "\n" + ProcessInfo.processInfo.operatingSystemVersionString
            + "\nPayloads and device identifiers omitted\n\n" + lines.joined(separator: "\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(report, forType: .string)
    }
}

struct DiagnosticsConsoleView: View {
    @ObservedObject private var console = DiagnosticsConsole.shared

    var body: some View {
        WorkspaceCard {
            HStack {
                Toggle("Debug mode", isOn: $console.isEnabled)
                Spacer()
                Button("Copy report") { console.copyReport() }
                Button("Clear") { console.clear() }
            }
            Text("Turn on, reproduce the issue, then copy the report. Up to 500 events stay in memory until Seamless quits. Message contents, file paths and credentials are excluded.")
                .font(.caption).foregroundStyle(.secondary)
            if console.isEnabled || !console.lines.isEmpty {
                ScrollView {
                    Text(console.lines.isEmpty ? "Waiting for activity…" : console.lines.joined(separator: "\n"))
                        .font(.system(size: 11, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .topLeading).padding(12)
                }.frame(height: 230).background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
            }
        }
    }
}
