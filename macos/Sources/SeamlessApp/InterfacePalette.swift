import SwiftUI

struct InterfacePalette {
    let scheme: ColorScheme

    var canvas: Color { adaptive(light: 0xFFF5EC, dark: 0x231719) }
    var sidebar: Color { adaptive(light: 0xF6E4D8, dark: 0x2C1C1F) }
    var surface: Color { adaptive(light: 0xFFFAF5, dark: 0x342125) }
    var raisedSurface: Color { adaptive(light: 0xFED7B8, dark: 0x432A2E) }
    var accent: Color { adaptive(light: 0x59171B, dark: 0xFED7B8) }
    var accentWash: Color { adaptive(light: 0xF5DCD0, dark: 0x512E33) }
    var text: Color { adaptive(light: 0x391D22, dark: 0xFFF1E7) }
    var secondaryText: Color { adaptive(light: 0x795C5D, dark: 0xD0ACAB) }
    var border: Color { adaptive(light: 0xE8C7BD, dark: 0x604047) }

    private func adaptive(light: UInt32, dark: UInt32) -> Color {
        if scheme == .dark {
            return Color(rgb: dark)
        } else {
            return Color(rgb: light)
        }
    }
}

extension Color {
    init(rgb: UInt32) {
        self.init(.sRGB, red: Double((rgb >> 16) & 255) / 255,
                  green: Double((rgb >> 8) & 255) / 255,
                  blue: Double(rgb & 255) / 255, opacity: 1)
    }
}
