import SwiftUI
import SeamlessCore

@MainActor
private final class PhonePickerState: ObservableObject { @Published var isPresented = false }

struct PhoneSwitcherView: View {
    @ObservedObject var preferencesStore: PreferencesStore
    @StateObject private var state = PhonePickerState()
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let palette = InterfacePalette(scheme: colorScheme)
        Button { state.isPresented.toggle() } label: {
            VStack(alignment: .leading, spacing: 14) {
                Text("SELECTED PHONE").font(.system(size: 9, weight: .semibold)).tracking(1.2).foregroundStyle(palette.secondaryText)
                HStack(spacing: 13) {
                    miniature(preferencesStore.preferences.selectedPhoneID)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(preferencesStore.preferences.selectedPhone?.displayName ?? "Choose a phone")
                            .font(.system(size: 13, weight: .semibold)).fixedSize(horizontal: false, vertical: true)
                        Text(preferencesStore.preferences.selectedPhoneID.flatMap { preferencesStore.connections.statuses[$0] }.map { "Battery \($0.batteryPercent)%" } ?? "Choose your device")
                            .font(.system(size: 10)).foregroundStyle(palette.secondaryText)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.up.chevron.down").font(.system(size: 10, weight: .semibold)).foregroundStyle(palette.accent)
                }
            }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
                .background(palette.surface, in: RoundedRectangle(cornerRadius: 16))
                .overlay { RoundedRectangle(cornerRadius: 16).stroke(palette.border, lineWidth: 1) }
                .foregroundStyle(palette.text)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Choose active phone")
        .popover(isPresented: $state.isPresented, arrowEdge: .trailing) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Your phones").font(.headline).padding(.bottom, 4)
                if preferencesStore.preferences.rememberedPhones.isEmpty {
                    Text("Add your first phone in Devices.").foregroundStyle(.secondary)
                }
                ForEach(preferencesStore.preferences.rememberedPhones) { phone in
                    Button {
                        preferencesStore.selectPhone(id: phone.id)
                        state.isPresented = false
                    } label: {
                        HStack(spacing: 16) {
                            miniature(phone.id)
                            VStack(alignment: .leading, spacing: 6) {
                                Text(phone.displayName).font(.system(size: 13, weight: .semibold))
                                Text(connectionText(phone.id)).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if preferencesStore.preferences.selectedPhoneID == phone.id {
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(palette.accent)
                            }
                        }.padding(14).background(palette.raisedSurface, in: RoundedRectangle(cornerRadius: 13))
                    }.buttonStyle(.plain)
                }
            }.padding(20).frame(width: 310).background(palette.canvas)
        }
    }

    private func miniature(_ phoneID: String?) -> some View {
        PhoneIllustration(wallpaper: nil, colorName: preferencesStore.preferences.rememberedPhones.first { $0.id == phoneID }?.preferences.previewColor ?? "sage")
            .frame(width: 122, height: 260).scaleEffect(0.24)
            .frame(width: 30, height: 63).accessibilityHidden(true)
    }

    private func connectionText(_ phoneID: String?) -> String {
        guard let phoneID else { return "Add a device to get started" }
        if preferencesStore.sessions.state(for: phoneID) == .connected {
            if let status = preferencesStore.connections.statuses[phoneID] { return "Connected · \(status.batteryPercent)%" }
            return "Connected"
        }
        return "Offline"
    }
}
