import Foundation

public struct PhoneCallState: Equatable, Sendable {
    public var isConnected = false
    public var isActive = false
    public var setupMode = 0
    public var heldMode = 0
    public var caller = ""
    public var hasCall: Bool { isActive || setupMode != 0 || heldMode != 0 }
    public var canAnswer: Bool { isConnected && setupMode == 1 && !isActive }

    public init() {}

    public var title: String {
        if !isConnected { return "Calls disconnected" }
        if isActive { return "Call in progress" }
        if setupMode == 1 { return "Incoming call" }
        if setupMode == 2 { return "Dialing…" }
        if setupMode == 3 { return "Ringing…" }
        if heldMode != 0 { return "Call on hold" }
        return "Ready for calls"
    }

    public mutating func disconnect() { self = PhoneCallState() }

    public static func dialNumber(_ text: String) -> String? {
        let separators = CharacterSet(charactersIn: " ()-")
        let cleaned = text.components(separatedBy: separators).joined()
        guard !cleaned.isEmpty, cleaned.count <= 32 else { return nil }
        let digits = cleaned.hasPrefix("+") ? String(cleaned.dropFirst()) : cleaned
        // Do not accept raw AT commands, USSD or supplementary-service strings as phone numbers.
        guard !digits.isEmpty, digits.utf8.allSatisfy({ $0 >= 48 && $0 <= 57 }) else { return nil }
        return cleaned
    }

    public static func normalizedBluetoothAddress(_ address: String) -> String? {
        let compact = address.replacingOccurrences(of: ":", with: "").replacingOccurrences(of: "-", with: "").uppercased()
        guard compact.count == 12, compact.utf8.allSatisfy({ (48...57).contains($0) || (65...70).contains($0) }) else { return nil }
        return compact
    }
}
