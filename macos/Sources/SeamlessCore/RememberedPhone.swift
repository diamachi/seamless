import Foundation

public struct RememberedPhone: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public var displayName: String
    public var preferences: PhonePreferences
    public var connection: ConnectionProfile?

    public init(id: String, displayName: String, preferences: PhonePreferences = PhonePreferences()) {
        self.id = id
        self.displayName = displayName
        self.preferences = preferences
    }
}
