import SwiftUI

struct PhoneIllustration: View {
    let wallpaper: NSImage?
    var colorName = "sage"
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let bezel = width * 0.035
            let cornerRadius = width * 0.14
            ZStack {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(Color(rgb: 0x303C3D))
                wallpaperContent
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius - bezel))
                    .padding(bezel)
                VStack {
                    Circle().fill(Color.black.opacity(0.8))
                        .frame(width: width * 0.065, height: width * 0.065)
                        .padding(.top, width * 0.10)
                    Spacer()
                    Capsule().fill(.white.opacity(0.8))
                        .frame(width: width * 0.48, height: width * 0.025)
                        .padding(.bottom, width * 0.10)
                }
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(.white.opacity(0.18), lineWidth: 1)
            }
        }
        .aspectRatio(0.47, contentMode: .fit)
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.24 : 0.10), radius: 18, x: 0, y: 10)
        .accessibilityLabel(wallpaper == nil ? "Phone illustration with a sample background" : "Phone illustration with your selected wallpaper")
    }

    @ViewBuilder
    private var wallpaperContent: some View {
        if let wallpaper {
            GeometryReader { geometry in
                Image(nsImage: wallpaper)
                    .resizable()
                    .scaledToFill()
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .clipped()
            }
        } else {
            SamplePhoneBackground(colorName: colorName)
        }
    }
}

private struct SamplePhoneBackground: View {
    let colorName: String
    private var colors: [Color] {
        switch colorName {
        case "ocean": return [Color(rgb: 0xD0E6F3), Color(rgb: 0x558BB6), Color(rgb: 0x203F69)]
        case "lavender": return [Color(rgb: 0xE4DDF3), Color(rgb: 0xA18EC7), Color(rgb: 0x4A386E)]
        case "rose": return [Color(rgb: 0xF3E0DC), Color(rgb: 0xC98D9A), Color(rgb: 0x703B55)]
        case "amber": return [Color(rgb: 0xF4E5C6), Color(rgb: 0xC9A05F), Color(rgb: 0x725334)]
        default: return [Color(rgb: 0xDDE7C8), Color(rgb: 0x76AB9F), Color(rgb: 0x244D50)]
        }
    }
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
                Ellipse()
                    .fill(LinearGradient(colors: [colors[0], colors[1]], startPoint: .top, endPoint: .bottom))
                    .frame(width: geometry.size.width * 1.8, height: geometry.size.height * 0.65)
                    .rotationEffect(.degrees(-35))
                    .offset(x: -geometry.size.width * 0.3, y: -geometry.size.height * 0.3)
                Ellipse()
                    .fill(LinearGradient(colors: [colors[1], colors[2]], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: geometry.size.width * 1.9, height: geometry.size.height * 0.75)
                    .rotationEffect(.degrees(-35))
                    .offset(x: geometry.size.width * 0.3, y: geometry.size.height * 0.37)
            }
        }
    }
}
