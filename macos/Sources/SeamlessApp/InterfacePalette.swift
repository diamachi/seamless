import SwiftUI

struct InterfacePalette {
    let scheme: ColorScheme

    var canvas: Color { adaptive(light: 0xF7F5EF, dark: 0x1D1C1A) }
    var sidebar: Color { adaptive(light: 0xF0ECE3, dark: 0x24221F) }
    var surface: Color { adaptive(light: 0xFFFDFA, dark: 0x2B2824) }
    var raisedSurface: Color { adaptive(light: 0xF4EDDE, dark: 0x342F28) }
    var accent: Color { adaptive(light: 0x8C5C25, dark: 0xE6BC7A) }
    var accentWash: Color { adaptive(light: 0xF1E4CD, dark: 0x403529) }
    var text: Color { adaptive(light: 0x302D27, dark: 0xEEE9DF) }
    var secondaryText: Color { adaptive(light: 0x777166, dark: 0xB7B0A3) }
    var border: Color { adaptive(light: 0xE4DED2, dark: 0x423D35) }

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
