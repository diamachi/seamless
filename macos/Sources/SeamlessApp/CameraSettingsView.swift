import SwiftUI
import SeamlessCore

struct CameraSettingsView: View {
    @Binding var preferences: CameraPreferences
    var body: some View {
        WorkspaceCard {
            Text("Camera profile").font(.headline)
            WorkspaceSegments(options: [(CameraPreferences.Facing.back, "Back"), (.front, "Front")], selection: $preferences.facing)
            Picker("Resolution", selection: $preferences.resolutionHeight) {
                ForEach([720, 1080, 1440, 2160], id: \.self) { value in Text("\(value)p").tag(value) }
            }
            WorkspaceSegments(options: [(24, "24 fps"), (30, "30 fps"), (60, "60 fps")], selection: $preferences.framesPerSecond)
            Divider()
            Text("Exposure · \(preferences.exposureEV, specifier: "%.1f") EV").font(.callout)
            Slider(value: $preferences.exposureEV, in: -3...3, step: 0.25)
            Text("Zoom · \(preferences.zoom, specifier: "%.1f")×").font(.callout)
            Slider(value: $preferences.zoom, in: 1...4, step: 0.1)
            Toggle("Torch", isOn: $preferences.torch)
            Picker("White balance", selection: $preferences.whiteBalance) {
                ForEach(["auto", "daylight", "cloudy", "incandescent", "fluorescent"], id: \.self) { value in Text(value.capitalized).tag(value) }
            }
            Text("Saved for this phone. Changes apply on the next camera start. Android clamps exposure/zoom to the camera’s supported range; unsupported torch and white-balance modes fall back safely. Hue and saturation are not standard Camera2 controls.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}
