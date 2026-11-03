import SwiftUI
import SeamlessCore

struct AppearanceSelector: View {
    @ObservedObject var preferencesStore: PreferencesStore
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let palette = InterfacePalette(scheme: colorScheme)
        HStack(spacing: 4) {
            appearanceButton(.system, title: "System", symbol: "circle.lefthalf.filled")
            appearanceButton(.light, title: "Light", symbol: "sun.max")
            appearanceButton(.dark, title: "Dark", symbol: "moon")
        }
        .padding(4)
        .background(palette.raisedSurface, in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Appearance")
    }

    private func appearanceButton(_ appearance: AppAppearance, title: String, symbol: String) -> some View {
        let isSelected = preferencesStore.preferences.appearance == appearance
        let palette = InterfacePalette(scheme: colorScheme)
        return Button {
            preferencesStore.setAppearance(appearance)
        } label: {
            VStack(spacing: 5) {
                Image(systemName: symbol).font(.system(size: 13))
                Text(title).font(.system(size: 10, weight: .medium))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
            .foregroundStyle(isSelected ? palette.accent : palette.secondaryText)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 9).fill(palette.surface)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title) appearance")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .help("\(title) appearance")
    }
}
