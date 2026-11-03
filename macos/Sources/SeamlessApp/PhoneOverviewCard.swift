import SwiftUI
import SeamlessCore

struct PhoneOverviewCard: View {
    let phone: RememberedPhone
    let status: ConnectedPhoneStatus?
    let isConnected: Bool
    let reconnect: () -> Void
    let openScreen: () -> Void
    var isRinging = false
    var ringPhone: (() -> Void)?
    private var ringButtonTitle: String {
        if isRinging { return "Stop ringing" }
        return "Ring phone"
    }
    @Binding var colorName: String

    var body: some View {
        WorkspaceCard {
            HStack(spacing: 28) {
                PhoneIllustration(wallpaper: nil, colorName: colorName).frame(width: 88, height: 188)
                VStack(alignment: .leading, spacing: 16) {
                    Text(phone.displayName).font(.system(size: 26, weight: .semibold, design: .rounded)).lineLimit(2)
                    if let status {
                        Label("Android \(status.androidVersion)", systemImage: "square.stack.3d.up")
                            .foregroundStyle(.secondary)
                    }
                    HStack(spacing: 12) {
                        Button(ringButtonTitle) { ringPhone?() }
                            .buttonStyle(WorkspaceButtonStyle())
                            .disabled(!isConnected)
                    }
                    HStack(spacing: 10) {
                        ForEach(["sage", "ocean", "lavender", "rose", "amber"], id: \.self) { color in
                            Button { colorName = color } label: {
                                PhoneIllustration(wallpaper: nil, colorName: color)
                                    .frame(width: 122, height: 260).scaleEffect(0.10).frame(width: 18, height: 30)
                                    .padding(5).background {
                                        if color == colorName { RoundedRectangle(cornerRadius: 4).stroke(.tint, lineWidth: 2) }
                                    }
                            }.buttonStyle(.plain).accessibilityLabel("\(color) phone background")
                                .accessibilityAddTraits(color == colorName ? .isSelected : [])
                        }
                    }
                }
                Spacer(minLength: 0)
                VStack(alignment: .leading, spacing: 18) {
                    if let status {
                        batterySummary(status)
                    }
                    if isConnected {
                        Button(action: openScreen) { Label("Open phone", systemImage: "rectangle.on.rectangle") }
                            .buttonStyle(WorkspaceButtonStyle(prominent: true))
                    } else {
                        Button("Reconnect", action: reconnect).buttonStyle(WorkspaceButtonStyle(prominent: true))
                    }
                }.frame(maxWidth: 220, alignment: .leading)
            }
        }
    }
    private func batterySummary(_ status: ConnectedPhoneStatus) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(status.batteryPercent)%").font(.system(size: 30, weight: .medium, design: .rounded))
                Text(status.isCharging ? "Charging" : "Battery").font(.caption).foregroundStyle(.secondary)
            }
            ProgressView(value: Double(status.batteryPercent), total: 100)
            HStack(spacing: 4) {
                Text("Updated")
                Text(status.receivedAt, style: .relative)
                Text("ago")
            }.font(.caption2).foregroundStyle(.secondary)
        }
    }

}
