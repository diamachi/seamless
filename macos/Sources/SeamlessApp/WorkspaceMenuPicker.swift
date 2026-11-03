import SwiftUI

@MainActor
private final class WorkspacePickerPresentation: ObservableObject {
    @Published var isPresented = false
}

struct WorkspaceMenuPicker: View {
    let title: String
    let symbol: String
    @Binding var selection: String
    let choices: [(String, String)]
    @StateObject private var presentation = WorkspacePickerPresentation()
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let palette = InterfacePalette(scheme: colorScheme)
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.caption.weight(.medium)).foregroundStyle(palette.secondaryText)
            Button { presentation.isPresented.toggle() } label: {
                HStack(spacing: 12) {
                    Image(systemName: symbol).foregroundStyle(palette.accent)
                    Text(choices.first { $0.0 == selection }?.1 ?? "Choose…").lineLimit(1)
                    Spacer(minLength: 12)
                    Image(systemName: "chevron.down").font(.caption.weight(.semibold)).foregroundStyle(palette.secondaryText)
                }
                .font(.system(size: 14)).foregroundStyle(palette.text)
                .padding(.horizontal, 16).frame(maxWidth: .infinity, minHeight: 50, alignment: .leading)
                .background(palette.canvas, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(palette.border))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain).accessibilityLabel(title)
            .accessibilityValue(choices.first { $0.0 == selection }?.1 ?? "Choose")
            .popover(isPresented: $presentation.isPresented, arrowEdge: .bottom) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(choices, id: \.0) { choice in
                            Button {
                                selection = choice.0
                                presentation.isPresented = false
                            } label: {
                                HStack(spacing: 12) {
                                    Text(choice.1).fixedSize(horizontal: false, vertical: true)
                                    Spacer(minLength: 12)
                                    if selection == choice.0 { Image(systemName: "checkmark").foregroundStyle(palette.accent) }
                                }
                                .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                                .background(selection == choice.0 ? palette.accentWash : palette.surface, in: RoundedRectangle(cornerRadius: 10))
                                .contentShape(Rectangle())
                            }.buttonStyle(.plain)
                        }
                    }.padding(12)
                }.frame(width: 340).frame(maxHeight: 320).background(palette.canvas)
            }
        }
    }
}
