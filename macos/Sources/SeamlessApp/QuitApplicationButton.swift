import AppKit
import SwiftUI

struct QuitApplicationButton: View {
    var body: some View {
        Button {
            // Use the normal lifecycle so existing connection and call cleanup also runs.
            NSApplication.shared.terminate(nil)
        } label: {
            Label("Quit Seamless", systemImage: "power")
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .help("Quit the app and disconnect its active sessions")
    }
}
