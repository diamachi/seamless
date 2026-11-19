import SwiftUI
import SeamlessCore

struct DeviceDetailsSummary: View {
    let status: ConnectedPhoneStatus?
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.phoneThemeColor) private var phoneThemeColor

    var body: some View { detailsGrid }

    private var detailsGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), alignment: .leading), count: 4), alignment: .leading, spacing: 20) {
            detail("Processor", value: status?.deviceDetails.processorName ?? "Unavailable", symbol: "cpu")
            detail("Software", value: softwareName, symbol: "square.stack.3d.up")
            detail("RAM", value: memoryText, symbol: "memorychip")
            storageDetail
        }
    }

    private var softwareName: String {
        guard let status else { return "Unavailable" }
        let name = status.deviceDetails.operatingSystemName
        if name == "Android" { return "Android \(status.androidVersion)" }
        return "\(name) · Android \(status.androidVersion)"
    }

    private var memoryText: String {
        guard let bytes = status?.deviceDetails.ramTotalBytes else { return "Unavailable" }
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .memory)
    }

    private var storageDetail: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let details = status?.deviceDetails, let total = details.storageTotalBytes, let used = details.storageUsedBytes {
                detail(details.storageLabel, value: "\(storageSize(used)) of \(storageSize(total)) used", symbol: "internaldrive")
                ProgressView(value: Double(used), total: Double(total))
                    .tint(InterfacePalette(scheme: colorScheme, colorName: phoneThemeColor).accent)
                    .accessibilityLabel("Storage used")
            } else {
                detail("Internal storage", value: "Unavailable", symbol: "internaldrive")
            }
        }
    }

    private func detail(_ title: String, value: String, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Label(title, systemImage: symbol).font(.system(size: 11)).foregroundStyle(.secondary)
            Text(value).font(.system(size: 13, weight: .medium)).fixedSize(horizontal: false, vertical: true)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private func storageSize(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
