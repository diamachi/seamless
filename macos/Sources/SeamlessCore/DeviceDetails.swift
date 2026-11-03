import Foundation

public struct DeviceDetails: Equatable, Sendable {
    public let processorName: String?
    public let operatingSystemName: String
    public let buildName: String?
    public let ramTotalBytes: Int64?
    public let storageTotalBytes: Int64?
    public let storageUsedBytes: Int64?
    public let storageLabel: String

    public init(payload: JSONValue) {
        processorName = Self.boundedText(payload["processorName"])
        operatingSystemName = Self.boundedText(payload["operatingSystemName"]) ?? "Android"
        buildName = Self.boundedText(payload["buildName"])
        ramTotalBytes = Self.byteCount(payload["ramTotalBytes"], allowsZero: false)
        storageTotalBytes = Self.byteCount(payload["storageTotalBytes"], allowsZero: false)
        let used = Self.byteCount(payload["storageUsedBytes"], allowsZero: true)
        if let total = storageTotalBytes, let used, used <= total {
            storageUsedBytes = used
        } else {
            storageUsedBytes = nil
        }
        storageLabel = Self.boundedText(payload["storageLabel"]) ?? "Internal storage"
    }

    private static func boundedText(_ value: JSONValue) -> String? {
        guard let text = value.string?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        return String(text.prefix(120))
    }

    private static func byteCount(_ value: JSONValue, allowsZero: Bool) -> Int64? {
        guard let number = value.number, number.isFinite, number.rounded() == number,
              number >= 0, number <= 1_000_000_000_000_000 else { return nil }
        if number == 0 && !allowsZero { return nil }
        return Int64(number)
    }
}
