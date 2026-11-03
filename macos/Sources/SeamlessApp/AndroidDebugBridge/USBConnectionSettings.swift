import SwiftUI
import SeamlessCore

struct USBConnectionSettings: View {
    @ObservedObject var connections: PhoneConnections
    @ObservedObject var usb: USBConnectionController
    let phone: RememberedPhone?

    var body: some View {
        WorkspaceCard {
            HStack {
                Label("USB connection · optional ADB", systemImage: "cable.connector").font(.headline)
                Spacer()
                Button("Find USB phones") { usb.refresh() }.disabled(usb.isBusy)
            }
            Text("Requires USB debugging while connected. The existing encrypted pairing is verified over the cable; this does not grant access to another phone.")
                .font(.callout).foregroundStyle(.secondary)
            Menu {
                ForEach(usb.devices) { device in
                    Button("\(device.model) · \(device.serial) · \(device.state)") { usb.selectedSerial = device.serial }
                }
            } label: {
                Label(usb.devices.first(where: { $0.serial == usb.selectedSerial })?.model ?? "Choose USB phone", systemImage: "iphone")
                    .padding(10).frame(maxWidth: .infinity, alignment: .leading)
            }.menuStyle(.borderlessButton)
            HStack {
                Text(usb.message).font(.caption).foregroundStyle(.secondary)
                Spacer()
                if let phone {
                    if usb.hasTunnel(phoneID: phone.id) {
                        Button("Use Wi-Fi") { usb.useWiFi(phoneID: phone.id) }
                    } else {
                        Button("Connect over USB") { usb.connect(phone) }
                            .buttonStyle(WorkspaceButtonStyle(prominent: true)).disabled(usb.isBusy || usb.selectedSerial.isEmpty)
                    }
                }
            }
        }
    }
}
