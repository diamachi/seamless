import Foundation

public enum PhoneConnectionState: String, Equatable, Sendable {
    case disconnected
    case connecting
    case connected
}

public struct PhoneSessionDirectory: Sendable {
    private var connectionStates: [String: PhoneConnectionState] = [:]

    public init() {}

    public func state(for phoneID: String) -> PhoneConnectionState {
        connectionStates[phoneID] ?? .disconnected
    }

    public mutating func update(_ state: PhoneConnectionState, for phoneID: String) {
        connectionStates[phoneID] = state
    }

    public mutating func remove(phoneID: String) {
        connectionStates.removeValue(forKey: phoneID)
    }

    public func requireConnectedPhone(id: String?) throws -> String {
        guard let id else { throw PhoneRoutingError.noPhoneSelected }
        guard state(for: id) == .connected else { throw PhoneRoutingError.phoneUnavailable }
        return id
    }
}

public enum PhoneRoutingError: Error {
    case noPhoneSelected
    case phoneUnavailable
}
