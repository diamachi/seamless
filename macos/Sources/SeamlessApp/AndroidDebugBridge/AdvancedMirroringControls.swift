import SwiftUI
import SeamlessCore

struct AdvancedMirroringControls: View {
    @ObservedObject var controller: AdvancedMirroringController

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("App windows · optional ADB").font(.headline)
            Text("Choose an app above and share its virtual display here. Use Pop out to move it to a separate window. With verified USB and debugging, the main Share app over ADB button starts it directly here.")
                .font(.caption).foregroundStyle(.secondary)
            Text(controller.message).font(.caption).foregroundStyle(.secondary)
        }
    }
}
