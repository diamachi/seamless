import Foundation

public struct AndroidApplicationIdentity: Codable, Hashable, Sendable {
    public let packageName: String
    public let profileIdentifier: String

    public init(packageName: String, profileIdentifier: String) {
        self.packageName = packageName
        self.profileIdentifier = profileIdentifier
    }
}

public struct NotificationPolicy: Codable, Equatable, Sendable {
    public var isPaused: Bool
    public var allowedApplications: Set<AndroidApplicationIdentity>

    public init(
        isPaused: Bool = false,
        allowedApplications: Set<AndroidApplicationIdentity> = []
    ) {
        self.isPaused = isPaused
        self.allowedApplications = allowedApplications
    }

    public func permits(_ application: AndroidApplicationIdentity) -> Bool {
        if isPaused {
            return false
        }
        return allowedApplications.contains(application)
    }
}
