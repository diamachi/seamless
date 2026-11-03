import Foundation

public struct PreferencesRepository: Sendable {
    public let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public func load() throws -> AppPreferences {
        if !FileManager.default.fileExists(atPath: fileURL.path) {
            return AppPreferences()
        }
        let data = try Data(contentsOf: fileURL)
        let preferences = try JSONDecoder().decode(AppPreferences.self, from: data)
        try preferences.validate()
        return preferences
    }

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
