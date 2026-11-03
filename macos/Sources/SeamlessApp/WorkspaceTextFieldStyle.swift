import SwiftUI

struct WorkspaceTextFieldStyle: TextFieldStyle {
    @Environment(\.colorScheme) private var colorScheme

    func _body(configuration: TextField<Self._Label>) -> some View {
        let palette = InterfacePalette(scheme: colorScheme)
        configuration
            .textFieldStyle(.plain)
            .font(.system(size: 14))
            .foregroundStyle(palette.text)
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
            .background(palette.canvas, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(palette.border))
    }
}
