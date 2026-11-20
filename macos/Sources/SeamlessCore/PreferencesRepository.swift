// Shared protocol/model rules for preferences repository.
// See docs/ARCHITECTURE.md for the owning subsystem and cross-platform call flow.

import Foundation

public struct PreferencesRepository: Sendable {
    public let fileURL: URL

    /// Constructs PreferencesRepository with the dependencies and initial values supplied by its caller.
    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    /// Loads the requested data into the component’s local model.
    public func load() throws -> AppPreferences {
        if !FileManager.default.fileExists(atPath: fileURL.path) {
            return AppPreferences()
        }
        let data = try Data(contentsOf: fileURL)
        let preferences = try JSONDecoder().decode(AppPreferences.self, from: data)
        try preferences.validate()
        return preferences
    }

    /// Persists the supplied state through the owning storage interface.
    public func save(_ preferences: AppPreferences) throws {
        try preferences.validate()
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(preferences)
        try data.write(to: fileURL, options: .atomic)
    }
}
