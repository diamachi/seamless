import Foundation

public enum JSONValue: Codable, Equatable, Sendable {
    case object([String: JSONValue])
    case array([JSONValue])
    case string(String)
    case number(Double)
    case bool(Bool)
    case null

    public init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer()
        if value.decodeNil() { self = .null }
        else if let boolean = try? value.decode(Bool.self) { self = .bool(boolean) }
        else if let number = try? value.decode(Double.self) { self = .number(number) }
        else if let string = try? value.decode(String.self) { self = .string(string) }
        else if let array = try? value.decode([JSONValue].self) { self = .array(array) }
        else { self = .object(try value.decode([String: JSONValue].self)) }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .object(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }

    public subscript(key: String) -> JSONValue {
        if case .object(let values) = self { return values[key] ?? .null }
        return .null
    }
    public var string: String? {
        if case .string(let value) = self { return value }
        return nil
    }
    public var number: Double? {
        if case .number(let value) = self { return value }
        return nil
    }
    public var boolean: Bool? {
        if case .bool(let value) = self { return value }
        return nil
    }
    public var array: [JSONValue] {
        if case .array(let values) = self { return values }
        return []
    }
}

public struct ControlPacket: Codable, Sendable {
    public let version: Int
    public let id: String
    public let type: String
    public let payload: JSONValue

    public init(type: String, payload: JSONValue = .object([:]), id: String = UUID().uuidString) {
        version = 1
        self.id = id
        self.type = type
        self.payload = payload
    }
}

public struct ConnectionProfile: Codable, Equatable, Sendable {
    public var host: String
    public var port: UInt16
    public var certificatePin: String

    public init(host: String, port: UInt16, certificatePin: String) {
        self.host = host
        self.port = port
        self.certificatePin = certificatePin
    }
}

public struct PairingInvitation: Codable, Sendable {
    public let version: Int
    public let phoneID: String
    public let name: String
    public let addresses: [String]
    public let port: UInt16
    public let certificatePin: String
    public let secret: String

    public static func parse(_ code: String) throws -> PairingInvitation {
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
        let prefix = "seamless1:"
        guard trimmed.count <= 16_384, trimmed.hasPrefix(prefix),
              let bytes = Data(base64Encoded: String(trimmed.dropFirst(prefix.count))) else {
            throw ConnectionProtocolError.invalidInvitation
        }
        let invitation = try JSONDecoder().decode(PairingInvitation.self, from: bytes)
        guard invitation.version == 1, UUID(uuidString: invitation.phoneID) != nil,
              !invitation.name.isEmpty, invitation.name.count <= 120,
              !invitation.addresses.isEmpty, invitation.addresses.count <= 32,
              invitation.addresses.allSatisfy({ !$0.isEmpty && $0.count <= 255 }),
              invitation.port > 0,
              invitation.certificatePin.count == 64,
              invitation.certificatePin.allSatisfy({ $0.isHexDigit }),
              Data(base64Encoded: invitation.secret)?.count == 32 else {
            throw ConnectionProtocolError.invalidInvitation
        }
        return invitation
    }
}

public enum ConnectionProtocolError: LocalizedError {
    case invalidInvitation
    case oversizedMessage
    case invalidMessage

    public var errorDescription: String? {
        switch self {
        case .invalidInvitation: return "Use a fresh pairing code from the Android app on the same local network."
        case .oversizedMessage: return "The phone sent a message larger than the supported limit."
        case .invalidMessage: return "The phone sent an invalid or incompatible message."
        }
    }
}
