// macOS application presentation and coordination for workspace text field style.
// See docs/ARCHITECTURE.md for the owning subsystem and cross-platform call flow.

import SwiftUI

struct WorkspaceTextFieldStyle: TextFieldStyle {
    /// Performs body for workspace text field style.
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.phoneThemeColor) private var phoneThemeColor

    /// Handles _body callback by translating the native window event into the owning app action.
    func _body(configuration: TextField<Self._Label>) -> some View {
        let palette = InterfacePalette(scheme: colorScheme, colorName: phoneThemeColor)
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
