import SwiftUI
import UniformTypeIdentifiers

struct FileSharingView: View {
    @ObservedObject var transfers: FileTransfers
    let phoneID: String?
    let isConnected: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                WorkspaceHeading(title: "Files", subtitle: "A simple way to move files between your devices.")
                WorkspaceCard {
                    Image(systemName: "arrow.up.arrow.down.doc").font(.system(size: 32, weight: .light)).foregroundStyle(.tint)
                    Text("Drop a file here").font(.title3.weight(.semibold))
                    Text("Or choose a file. Up to 20 MiB per transfer.").foregroundStyle(.secondary)
                    Button("Choose file…") {
                        if let phoneID { transfers.chooseAndOffer(phoneID: phoneID) }
                    }
                    .buttonStyle(WorkspaceButtonStyle(prominent: true))
                    .disabled(!isConnected)
                }
                .onDrop(of: [UTType.fileURL], isTargeted: nil, perform: receiveDrop)
                Text(transfers.message).font(.callout).foregroundStyle(.secondary)
                    .accessibilityLabel("Transfer status: \(transfers.message)")
                ForEach(transfers.activities.filter { $0.phoneID == phoneID }) { activity in
                    WorkspaceCard {
                        HStack {
                            Label(activity.name, systemImage: "doc").font(.headline)
                            Spacer()
                            Button("Cancel") { transfers.cancelTransfer(activity) }
                        }
                        ProgressView(value: Double(activity.completedBytes), total: Double(max(activity.totalBytes, 1)))
                        Text(activity.status).font(.caption).foregroundStyle(.secondary)
                    }
                }
                ForEach(transfers.offers.filter { $0.phoneID == phoneID }) { offer in
                    WorkspaceCard {
                        Label(offer.name, systemImage: "arrow.down.doc").font(.headline)
                        Text(ByteCountFormatter.string(fromByteCount: Int64(offer.size), countStyle: .file)).foregroundStyle(.secondary)
                        HStack {
                            Button("Accept and save…") { transfers.accept(offer) }.buttonStyle(WorkspaceButtonStyle(prominent: true))
                            Button("Decline") { transfers.reject(offer) }
                        }
                    }
                }
                Text("Every file is checked before saving. Transfers stay with their original phone when you switch devices.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func receiveDrop(_ providers: [NSItemProvider]) -> Bool {
        guard isConnected, let targetPhoneID = phoneID, let provider = providers.first else { return false }
        provider.loadDataRepresentation(forTypeIdentifier: UTType.fileURL.identifier) { data, _ in
            guard let data, let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
            Task { @MainActor in
                transfers.offer(url: url, phoneID: targetPhoneID)
            }
        }
        return true
    }
}
