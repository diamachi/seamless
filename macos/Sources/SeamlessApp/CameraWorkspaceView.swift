import SwiftUI
import SeamlessCore

struct CameraWorkspaceView: View {
    @ObservedObject var preferencesStore: PreferencesStore
    @ObservedObject var controller: PhoneVideoStreamController
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(alignment: .top) {
                WorkspaceHeading(title: "Live camera", subtitle: "A camera that travels with you.")
                Spacer()
                Button {
                    if let phone = preferencesStore.preferences.selectedPhone { controller.requestCamera(phoneID: phone.id, preferences: phone.preferences.camera) }
                } label: { Label("Start camera", systemImage: "video.fill") }
                    .buttonStyle(WorkspaceButtonStyle(prominent: true)).disabled(!isConnected)
            }
            HStack(alignment: .top, spacing: 28) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        CameraSetupGuide(controller: controller)
                        CameraSettingsView(preferences: preferencesStore.featurePreferences.camera)

                    }
                }.frame(minWidth: 280, idealWidth: 320, maxWidth: 440)
                VStack(alignment: .center, spacing: 18) {
                    Group {
                        if controller.isDetached { ContentUnavailableView("Preview in output window", systemImage: "macwindow") }
                        else { PhoneVideoSurface(controller: controller) }
                    }
                        .aspectRatio(previewRatio, contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 20))
                        .overlay { if !controller.isStreaming { Image(systemName: "video").font(.largeTitle).foregroundStyle(.white.opacity(0.4)) } }
                    Button("Open clean output for OBS") { CameraOutputWindow.shared.show(controller: controller) }
                    Button("Stop camera") { controller.stop() }.disabled(!controller.isStreaming)
                    Text(controller.message).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    if controller.isStreaming { Text(String(format: "%.0f × %.0f · %.1f fps received", controller.videoSize.width, controller.videoSize.height, controller.receivedFramesPerSecond)).font(.caption).foregroundStyle(.secondary) }
                    if controller.isStreaming && !controller.encoderName.isEmpty { Text(controller.encoderName).font(.caption2).foregroundStyle(.secondary) }
                }.frame(maxWidth: 600)
            }
            Spacer(minLength: 0)
        }.buttonStyle(WorkspaceButtonStyle())
    }
    private var previewRatio: CGFloat {
        if controller.videoSize.height > 1 { return controller.videoSize.width / controller.videoSize.height }
        return 16.0 / 9.0
    }
    private var isConnected: Bool {
        guard let phoneID = preferencesStore.preferences.selectedPhoneID else { return false }
        return preferencesStore.sessions.state(for: phoneID) == .connected
    }
}
