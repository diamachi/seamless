import AppKit
import SwiftUI

struct CameraSetupGuide: View {
    @ObservedObject var controller: PhoneVideoStreamController

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            WorkspaceCard {
                Text("1 · Connect your phone camera").font(.headline)
                Text(controller.isStreaming ? "Phone video is arriving. You can now enable the webcam output." : "Choose quality below, click Start camera, then approve camera sharing in Seamless on your phone. Wait for the preview.")
                    .foregroundStyle(.secondary)
            }
            WebcamDriverStep(output: controller.webcamOutput, cameraIsStreaming: controller.isStreaming)
            WorkspaceCard {
                Text("3 · Select it in your meeting app").font(.headline)
                Text("In Google Meet, open Settings → Video → Camera and select OBS Virtual Camera. Keep the phone camera and webcam output running; the OBS app stays closed.")
                    .foregroundStyle(.secondary)
                DisclosureGroup("Camera missing in Edge or Meet?") {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Check macOS System Settings → Privacy & Security → Camera allows Microsoft Edge. Then allow camera access for meet.google.com in Edge. Review these permissions yourself.")
                        Button("Open macOS camera permissions") {
                            open("x-apple.systempreferences:com.apple.preference.security?Privacy_Camera")
                        }
                        Text("After enabling the camera extension, fully quit and reopen Edge when you have saved your work. Reload Meet and check its Video settings again. Seamless does not restart your browser or join a meeting.")
                        Text("If still missing, check System Settings → General → Login Items & Extensions → Camera Extensions for OBS. The OBS extension must be installed and enabled; a live Seamless preview alone does not register a webcam.")
                    }.font(.callout).padding(.top, 10)
                }
            }
        }
    }

    private func open(_ address: String) {
        if let url = URL(string: address) { NSWorkspace.shared.open(url) }
    }
}

private struct WebcamDriverStep: View {
    @ObservedObject var output: DirectWebcamOutput
    let cameraIsStreaming: Bool

    var body: some View {
        WorkspaceCard {
            Text("2 · Enable system webcam").font(.headline)
            Text("One-time setup: install OBS from obsproject.com and approve its camera extension. For this direct output, quit OBS before enabling the driver here.")
                .foregroundStyle(.secondary)
            Link("OBS camera setup help", destination: URL(string: "https://obsproject.com/kb/virtual-camera-troubleshooting")!)
            if output.isActive {
                Button("Stop webcam output") { output.stop() }
            } else {
                Button(output.isStarting ? "Connecting to driver…" : "Enable system webcam") { output.start() }
                    .buttonStyle(WorkspaceButtonStyle(prominent: true))
                    .disabled(!cameraIsStreaming || output.isStarting)
            }
            Text(output.message).font(.caption).foregroundStyle(.secondary)
            Text("Direct output is experimental. If your camera app receives no image, stop this output, open the clean output window and capture that window in OBS, then start OBS Virtual Camera there.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}
