// Shared protocol/model rules for discovered phone endpoint.
// See docs/ARCHITECTURE.md for the owning subsystem and cross-platform call flow.

import Foundation

public struct DiscoveredPhoneEndpoint: Equatable, Sendable {
    public let phoneID: String
    public let host: String
    public let port: UInt16

    /// Constructs DiscoveredPhoneEndpoint with the dependencies and initial values supplied by its caller.
    public init?(serviceName: String, host: String, port: Int) {
        guard let identifier = Self.phoneIdentifier(serviceName: serviceName),
              !host.isEmpty, host.count <= 253,
              !host.contains(where: { $0.isWhitespace || $0 == "\0" }),
              (1...65535).contains(port) else { return nil }
        self.phoneID = identifier
        self.host = host
        self.port = UInt16(port)
    }

    /// Performs phone identifier for discovered phone endpoint.
    public static func phoneIdentifier(serviceName: String) -> String? {
        let prefix = "Seamless-"
        guard serviceName.hasPrefix(prefix) else { return nil }
        let suffix = String(serviceName.dropFirst(prefix.count))
        guard suffix.count >= 36, let identifier = UUID(uuidString: String(suffix.prefix(36))) else { return nil }
        let collisionSuffix = String(suffix.dropFirst(36))
        // Android NSD can append a collision number while the old registration is retiring.
        if !collisionSuffix.isEmpty && collisionSuffix.range(of: #"^ ?\([0-9]{1,4}\)$"#, options: .regularExpression) == nil {
            return nil
        }
        return identifier.uuidString.lowercased()
    }

    /// Performs connection profile for discovered phone endpoint.
    public func connectionProfile(for phone: RememberedPhone) -> ConnectionProfile? {
        guard phone.id.lowercased() == phoneID, let pairedProfile = phone.connection else { return nil }
        // Network advertisements can update routing, never pairing trust.
        return ConnectionProfile(host: host, port: port, certificatePin: pairedProfile.certificatePin)
    }
}
