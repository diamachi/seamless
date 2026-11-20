// Shared protocol/model rules for remembered phone.
// See docs/ARCHITECTURE.md for the owning subsystem and cross-platform call flow.

import Foundation

public struct RememberedPhone: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public var displayName: String
    public var preferences: PhonePreferences
    public var connection: ConnectionProfile?

    /// Constructs RememberedPhone with the dependencies and initial values supplied by its caller.
    public init(id: String, displayName: String, preferences: PhonePreferences = PhonePreferences()) {
        self.id = id
        self.displayName = displayName
        self.preferences = preferences
    }
}
