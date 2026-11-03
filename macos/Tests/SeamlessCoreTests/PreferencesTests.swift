import Foundation
import Testing
@testable import SeamlessCore

struct PreferencesTests {
    @Test
    func testNotificationSelectionDoesNotLeakAcrossProfiles() {
        let personal = AndroidApplicationIdentity(packageName: "org.example.chat", profileIdentifier: "personal")
        let work = AndroidApplicationIdentity(packageName: "org.example.chat", profileIdentifier: "work")
        var policy = NotificationPolicy(allowedApplications: [personal])
        #expect(policy.permits(personal))
        #expect(!policy.permits(work))
        policy.isPaused = true
        #expect(!policy.permits(personal))
    }

    @Test
    func testSavedPreferencesSurviveReload() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = PreferencesRepository(fileURL: directory.appending(path: "settings.json"))
        var preferences = AppPreferences()
        preferences.defaultPhonePreferences.screenFramesPerSecond = 120
        preferences.defaultPhonePreferences.camera.facing = .front
        preferences.defaultPhonePreferences.notifications.allowedApplications.insert(
            AndroidApplicationIdentity(packageName: "org.example.chat", profileIdentifier: "personal")
        )
        try repository.save(preferences)
        #expect(try repository.load() == preferences)
    }

    @Test
    func appearancePersistsAndOlderPreferencesFollowSystem() throws {
        var preferences = AppPreferences()
        preferences.appearance = .dark
        let encoded = try JSONEncoder().encode(preferences)
        #expect(try JSONDecoder().decode(AppPreferences.self, from: encoded).appearance == .dark)
        var legacyObject = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        legacyObject.removeValue(forKey: "appearance")
        let legacyData = try JSONSerialization.data(withJSONObject: legacyObject)
        #expect(try JSONDecoder().decode(AppPreferences.self, from: legacyData).appearance == .system)
    }

    @Test
    func testNewerSettingsAreRejectedWithoutOverwriting() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = PreferencesRepository(fileURL: directory.appending(path: "settings.json"))
        try repository.save(AppPreferences())
        let original = try Data(contentsOf: repository.fileURL)
        var invalidPreferences = AppPreferences()
        invalidPreferences.schemaVersion = 3
        #expect(throws: PreferencesError.self) { try repository.save(invalidPreferences) }
        #expect(try Data(contentsOf: repository.fileURL) == original)
    }
}

@Test
func renamingAPhonePreservesItsIdentityAndProfile() throws {
    var preferences = AppPreferences()
    try preferences.rememberPhone(id: "phone-a", displayName: "A063")
    let profile = ConnectionProfile(host: "phone.local", port: 48763, certificatePin: String(repeating: "a", count: 64))
    try preferences.updateConnection(profile, for: "phone-a")
    try preferences.renamePhone(id: "phone-a", name: "  My Phone  ")
    #expect(preferences.selectedPhone?.displayName == "My Phone")
    #expect(preferences.selectedPhoneID == "phone-a")
    #expect(preferences.selectedPhone?.connection == profile)
    #expect(throws: (any Error).self) { try preferences.renamePhone(id: "phone-a", name: " ") }
}
