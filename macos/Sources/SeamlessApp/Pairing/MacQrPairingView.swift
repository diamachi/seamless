import SwiftUI

struct MacQrPairingView: View {
    @ObservedObject var pairing: MacQrPairingCoordinator

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("Scan with your Android phone", systemImage: "qrcode").font(.headline)
                Spacer()
                Button(pairing.image == nil ? "Create pairing QR" : "New QR code", systemImage: "qrcode") { pairing.create() }
                    .buttonStyle(WorkspaceButtonStyle(prominent: true))
                    .disabled(pairing.isCreating)
            }
            Text("On Android, open Seamless → Pair a Mac → Scan Mac QR code. Point the phone camera at this screen, then approve the trust request on your phone.")
                .font(.callout).foregroundStyle(.secondary)
            if pairing.isCreating { ProgressView("Creating QR code…") }
            if let image = pairing.image {
                HStack(alignment: .center, spacing: 24) {
                    Image(nsImage: image).interpolation(.none).resizable().scaledToFit()
                        .frame(width: 240, height: 240).padding(18).background(.white, in: RoundedRectangle(cornerRadius: 12))
                        .privacySensitive().accessibilityLabel("Private, one-use Seamless pairing QR code")
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Keep both devices on the same local network.").font(.headline)
                        Text("The QR securely hands setup to this Mac. Your phone still asks you to approve access.")
                            .foregroundStyle(.secondary)
                        if let expiry = pairing.expiresAt {
                            TimelineView(.periodic(from: .now, by: 1)) { context in
                                let seconds = max(0, Int(expiry.timeIntervalSince(context.date)))
                                Text("Expires in \(seconds / 60):\(String(format: "%02d", seconds % 60))").font(.callout.monospacedDigit())
                            }
                        }
                        Button("Hide QR") { pairing.stop() }
                    }
                }
            }
            Text(pairing.message).font(.callout).foregroundStyle(.secondary)
        }
    }
}
