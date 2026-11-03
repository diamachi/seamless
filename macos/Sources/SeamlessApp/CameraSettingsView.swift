import SwiftUI
import SeamlessCore

struct CameraSettingsView: View {
    @Binding var preferences: CameraPreferences

    var body: some View {
        WorkspaceCard {
            Label("Camera profile", systemImage: "slider.horizontal.3").font(.headline)
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 28) {
                    captureQuality.frame(minWidth: 250)
                    Divider()
                    liveControls.frame(minWidth: 250)
                }
                VStack(alignment: .leading, spacing: 24) {
                    captureQuality
                    Divider()
                    liveControls
                }
            }
            Text("Saved for this phone. Android limits controls to the selected camera’s supported range. Front cameras usually have no torch; unsupported white-balance modes use Auto.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var captureQuality: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Capture quality").font(.subheadline.weight(.semibold))
            Text("Stop and start the camera after changing these settings.")
                .font(.caption).foregroundStyle(.secondary)
            WorkspaceSegments(options: [(CameraPreferences.Facing.back, "Back"), (.front, "Front")], selection: $preferences.facing)
            WorkspaceMenuPicker(title: "Resolution", symbol: "viewfinder", selection: Binding(
                get: { String(preferences.resolutionHeight) },
                set: { if let height = Int($0) { preferences.resolutionHeight = height } }
            ), choices: [720, 1080, 1440, 2160].map { (String($0), "\($0)p") })
            WorkspaceSegments(options: [(24, "24 fps"), (30, "30 fps"), (60, "60 fps")], selection: $preferences.framesPerSecond)
        }
    }

    private var liveControls: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Live controls").font(.subheadline.weight(.semibold))
            Text("Changes apply while the camera is running.").font(.caption).foregroundStyle(.secondary)
            Text("Exposure · \(preferences.exposureEV, specifier: "%.1f") EV").font(.callout)
            Slider(value: $preferences.exposureEV, in: -3...3, step: 0.25)
            Text("Zoom · \(preferences.zoom, specifier: "%.1f")×").font(.callout)
            Slider(value: $preferences.zoom, in: 1...4, step: 0.1)
            Button {
                preferences.torch.toggle()
            } label: {
                Label(preferences.torch ? "Torch on" : "Torch off", systemImage: preferences.torch ? "flashlight.on.fill" : "flashlight.off.fill")
                    .frame(maxWidth: .infinity, minHeight: 24)
            }
            .buttonStyle(WorkspaceButtonStyle(prominent: preferences.torch))
            WorkspaceMenuPicker(title: "White balance", symbol: "sun.max", selection: $preferences.whiteBalance,
                                choices: ["auto", "daylight", "cloudy", "incandescent", "fluorescent"].map { ($0, $0.capitalized) })
        }
    }
}
