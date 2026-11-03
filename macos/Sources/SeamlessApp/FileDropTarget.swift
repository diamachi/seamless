import SwiftUI
import UniformTypeIdentifiers

struct FileDropTarget: ViewModifier {
    let phoneID: String?
    @ObservedObject var bulk: BulkTransfers

    func body(content: Content) -> some View {
        content.onDrop(of: [UTType.fileURL], isTargeted: nil) { providers in
            guard let phoneID, bulk.supportedPhones.contains(phoneID) else { return false }
            for provider in providers.prefix(8) {
                provider.loadDataRepresentation(forTypeIdentifier: UTType.fileURL.identifier) { data, _ in
                    guard let data, let url = URL(dataRepresentation: data, relativeTo: nil), url.isFileURL else { return }
                    Task { @MainActor in bulk.offer(url: url, phoneID: phoneID) }
                }
            }
            return true
        }
    }
}
