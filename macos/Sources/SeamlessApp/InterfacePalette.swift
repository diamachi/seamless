// macOS application presentation and coordination for interface palette.
// See docs/ARCHITECTURE.md for the owning subsystem and cross-platform call flow.

import SwiftUI
import AppKit

struct InterfacePalette {
    let scheme: ColorScheme
    var colorName: String = "sage"

    var canvas: Color { neutral(light: 0xF6F7F8, dark: 0x1D1F22) }
    var sidebar: Color { neutral(light: 0xEEF0F2, dark: 0x24262A) }
    var surface: Color { neutral(light: 0xFFFFFF, dark: 0x272A2E) }
    var raisedSurface: Color { neutral(light: 0xE9ECEF, dark: 0x32363B) }
    var accent: Color { adaptive(light: 0x495B56, dark: 0xC4D8D1) }
    var accentWash: Color { neutral(light: 0xE9ECEF, dark: 0x353A40) }
    var text: Color { neutral(light: 0x20252B, dark: 0xF1F3F5) }
    var secondaryText: Color { neutral(light: 0x58616B, dark: 0xB9C0C8) }
    var border: Color { neutral(light: 0xD7DCE1, dark: 0x41464D) }

    /// Performs neutral for interface palette.
    private func neutral(light: UInt32, dark: UInt32) -> Color {
        if scheme == .dark { return Color(nsColor: NSColor(Color(rgb: dark)).blended(withFraction: 0.035, of: NSColor(accent)) ?? NSColor(Color(rgb: dark))) }
        return Color(nsColor: NSColor(Color(rgb: light)).blended(withFraction: 0.045, of: NSColor(accent)) ?? NSColor(Color(rgb: light)))
    }

    /// Performs adaptive for interface palette.
    private func adaptive(light: UInt32, dark: UInt32) -> Color {
        if scheme == .dark {
            return themed(dark)
        } else {
            return themed(light)
        }
    }
    /// Performs themed for interface palette.
    private func themed(_ value: UInt32) -> Color {
        let original = NSColor(Color(rgb: value)).usingColorSpace(.deviceRGB) ?? .gray
        let hue: CGFloat
        switch colorName {
        case "ocean": hue = 0.58
        case "lavender": hue = 0.74
        case "rose": hue = 0.96
        case "amber": hue = 0.10
        default: hue = 0.40
        }
        return Color(nsColor: NSColor(hue: hue, saturation: min(original.saturationComponent * 0.45, 0.16),
                                      brightness: original.brightnessComponent, alpha: 1))
    }

}

extension Color {
    /// Constructs InterfacePalette with the dependencies and initial values supplied by its caller.
    init(rgb: UInt32) {
        self.init(.sRGB, red: Double((rgb >> 16) & 255) / 255,
                  green: Double((rgb >> 8) & 255) / 255,
                  blue: Double(rgb & 255) / 255, opacity: 1)
    }
}

private struct PhoneThemeColorKey: EnvironmentKey {
    static let defaultValue = "sage"
}
extension EnvironmentValues {
    var phoneThemeColor: String {
        get { self[PhoneThemeColorKey.self] }
        set { self[PhoneThemeColorKey.self] = newValue }
    }
}
