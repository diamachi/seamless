// macOS application presentation and coordination for quit application button.
// See docs/ARCHITECTURE.md for the owning subsystem and cross-platform call flow.

import AppKit
import SwiftUI

struct QuitApplicationButton: View {
    var compact = false

    var body: some View {
        Button {
            // Use the normal lifecycle so existing connection and call cleanup also runs.
            NSApplication.shared.terminate(nil)
        } label: {
            Label("Quit Seamless", systemImage: "power")
                .frame(maxWidth: compact ? nil : .infinity, alignment: .leading)
        }
        .help("Quit the app and disconnect its active sessions")
    }
}
