// Shared protocol/model rules for notification policy.
// See docs/ARCHITECTURE.md for the owning subsystem and cross-platform call flow.

import Foundation

public struct AndroidApplicationIdentity: Codable, Hashable, Sendable {
    public let packageName: String
    public let profileIdentifier: String

    /// Constructs NotificationPolicy with the dependencies and initial values supplied by its caller.
    public init(packageName: String, profileIdentifier: String) {
        self.packageName = packageName
        self.profileIdentifier = profileIdentifier
    }
}

public struct NotificationPolicy: Codable, Equatable, Sendable {
    public var isPaused: Bool
    public var allowedApplications: Set<AndroidApplicationIdentity>

    /// Constructs NotificationPolicy with the dependencies and initial values supplied by its caller.
    public init(
        isPaused: Bool = false,
        allowedApplications: Set<AndroidApplicationIdentity> = []
    ) {
        self.isPaused = isPaused
        self.allowedApplications = allowedApplications
    }

    /// Evaluates permits against the current model or supplied input.
    public func permits(_ application: AndroidApplicationIdentity) -> Bool {
        if isPaused {
            return false
        }
        return allowedApplications.contains(application)
    }
}
