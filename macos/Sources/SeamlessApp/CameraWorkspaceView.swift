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
                Button(action: startCamera) {
                    Label("Start camera", systemImage: "video.fill")
                }
                .buttonStyle(WorkspaceButtonStyle(prominent: true))
                .disabled(!isConnected || controller.isStreaming)
            }
            HStack(alignment: .top, spacing: 24) {
                ScrollView {
                    CameraSetupGuide(controller: controller)
                }.frame(width: 320)
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        previewCard
                        CameraSettingsView(preferences: preferencesStore.featurePreferences.camera)
                    }.frame(maxWidth: .infinity)
                }
            }
        }
        .task(id: preferencesStore.preferences.selectedPhone?.preferences.camera) {
            // Coalesce slider movement without restarting capture or interrupting webcam output.
            do {
                try await Task.sleep(for: .milliseconds(120))
            } catch {
                return
            }
            guard let phone = preferencesStore.preferences.selectedPhone else { return }
            controller.updateCameraControls(phoneID: phone.id, preferences: phone.preferences.camera)
        }
        .buttonStyle(WorkspaceButtonStyle())
    }

    private var previewCard: some View {
        WorkspaceCard {
            HStack {
                Label("Camera preview", systemImage: "video").font(.headline)
                Spacer()
                if controller.isStreaming {
                    Text(String(format: "%.0f × %.0f · %.1f fps", controller.videoSize.width,
                                controller.videoSize.height, controller.receivedFramesPerSecond))
                        .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
            }
            Group {
                if controller.isDetached {
                    ContentUnavailableView("Preview in output window", systemImage: "macwindow")
                } else {
                    PhoneVideoSurface(controller: controller)
                }
            }
            .aspectRatio(previewRatio, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay {
                if !controller.isStreaming {
                    Image(systemName: "video").font(.largeTitle).foregroundStyle(.white.opacity(0.4))
                }
            }
            HStack {
                Button {
                    CameraOutputWindow.shared.show(controller: controller)
                } label: { Label("Clean output", systemImage: "macwindow") }
                Spacer()
                Button { controller.stop() } label: { Label("Stop camera", systemImage: "stop.fill") }
                    .disabled(!controller.isStreaming)
            }
            Text(controller.message).font(.caption).foregroundStyle(.secondary)
        }
    }

    private func startCamera() {
        guard let phone = preferencesStore.preferences.selectedPhone else { return }
        controller.requestCamera(phoneID: phone.id, preferences: phone.preferences.camera)
    }

    private var previewRatio: CGFloat {
        if controller.videoSize.height > 1 {
            return controller.videoSize.width / controller.videoSize.height
        }
        return 16.0 / 9.0
    }

    private var isConnected: Bool {
        guard let phoneID = preferencesStore.preferences.selectedPhoneID else { return false }
        return preferencesStore.sessions.state(for: phoneID) == .connected
    }
}
