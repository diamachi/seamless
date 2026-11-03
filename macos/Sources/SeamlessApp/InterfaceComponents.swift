import SwiftUI

struct WorkspaceHeading: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 29, weight: .semibold, design: .rounded))
            Text(subtitle).foregroundStyle(.secondary)
        }
    }
}

struct WorkspaceCard<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    private let content: Content
    private let fillsHeight: Bool

    init(fillsHeight: Bool = false, @ViewBuilder content: () -> Content) {
        self.fillsHeight = fillsHeight
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            content
        }
        .frame(maxWidth: .infinity, maxHeight: fillsHeight ? .infinity : nil, alignment: .topLeading)
        .padding(22)
        .background(InterfacePalette(scheme: colorScheme).surface, in: RoundedRectangle(cornerRadius: 20))
        .overlay {
            RoundedRectangle(cornerRadius: 20)
                .stroke(InterfacePalette(scheme: colorScheme).border.opacity(0.7), lineWidth: 1)
        }
    }
}

struct ConnectionBadge: View {
    let isConnected: Bool
    var connectionName = "Connected"
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(isConnected ? InterfacePalette(scheme: colorScheme).accent : Color.secondary)
                .frame(width: 8, height: 8)
            Text(isConnected ? connectionName : "Offline")
                .font(.system(size: 13, weight: .semibold))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.primary.opacity(0.05), in: Capsule())
        .accessibilityElement(children: .combine)
    }
}

struct WorkspaceButtonStyle: ButtonStyle {
    var prominent = false
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let palette = InterfacePalette(scheme: colorScheme)
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .foregroundStyle(prominent ? palette.canvas : palette.accent)
            .background(prominent ? palette.accent : palette.accentWash,
                        in: RoundedRectangle(cornerRadius: 10))
            .opacity(isEnabled ? (configuration.isPressed ? 0.7 : 1) : 0.4)
            .contentShape(RoundedRectangle(cornerRadius: 10))
    }
}

struct WorkspaceSegments<Value: Hashable>: View {
    let options: [(Value, String)]
    @Binding var selection: Value
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let palette = InterfacePalette(scheme: colorScheme)
        HStack(spacing: 4) {
            ForEach(options.indices, id: \.self) { index in
                let option = options[index]
                Button { selection = option.0 } label: {
                    Text(option.1).font(.system(size: 12, weight: .semibold))
                        .padding(.horizontal, 16).padding(.vertical, 10)
                        .foregroundStyle(selection == option.0 ? palette.text : palette.secondaryText)
                        .background {
                            if selection == option.0 { RoundedRectangle(cornerRadius: 9).fill(palette.surface) }
                        }
                }.buttonStyle(.plain).accessibilityAddTraits(selection == option.0 ? .isSelected : [])
            }
        }.padding(4).background(palette.raisedSurface, in: RoundedRectangle(cornerRadius: 12))
    }
}
