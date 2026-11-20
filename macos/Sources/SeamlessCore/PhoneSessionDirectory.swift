// Shared protocol/model rules for phone session directory.
// See docs/ARCHITECTURE.md for the owning subsystem and cross-platform call flow.

import Foundation

public enum PhoneConnectionState: String, Equatable, Sendable {
    case disconnected
    case connecting
    case connected
}

public struct PhoneSessionDirectory: Sendable {
    private var connectionStates: [String: PhoneConnectionState] = [:]

    /// Constructs PhoneSessionDirectory with the dependencies and initial values supplied by its caller.
    public init() {}

    /// Performs state for phone session directory.
    public func state(for phoneID: String) -> PhoneConnectionState {
        connectionStates[phoneID] ?? .disconnected
    }

    /// Performs update for phone session directory.
    public mutating func update(_ state: PhoneConnectionState, for phoneID: String) {
        connectionStates[phoneID] = state
    }

    /// Performs remove for phone session directory.
    public mutating func remove(phoneID: String) {
        connectionStates.removeValue(forKey: phoneID)
    }

    /// Performs require connected phone for phone session directory.
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
