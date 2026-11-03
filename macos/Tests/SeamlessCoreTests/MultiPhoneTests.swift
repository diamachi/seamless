import Foundation
import Testing
@testable import SeamlessCore

struct MultiPhoneTests {
    @Test
    func switchingPreservesIndependentPreferencesAndPairingIdentity() throws {
        var preferences = AppPreferences()
        try preferences.rememberPhone(id: "phone-one", displayName: "Test Phone")
        try preferences.rememberPhone(id: "phone-two", displayName: "Other phone")
        var firstPhoneSettings = try preferences.featurePreferences(for: "phone-one")
        firstPhoneSettings.camera.facing = .front
        firstPhoneSettings.camera.resolutionHeight = 720
        firstPhoneSettings.notifications.isPaused = true
        try preferences.updateFeaturePreferences(firstPhoneSettings, for: "phone-one")
        try preferences.selectPhone(id: "phone-two")
        #expect(preferences.selectedPhone?.displayName == "Other phone")
        #expect(try preferences.featurePreferences(for: "phone-two") == PhonePreferences())
        try preferences.selectPhone(id: "phone-one")
        #expect(try preferences.featurePreferences(for: "phone-one") == firstPhoneSettings)
        try preferences.rememberPhone(id: "phone-one", displayName: "Renamed phone")
        #expect(preferences.rememberedPhones.count == 2)
        #expect(try preferences.featurePreferences(for: "phone-one") == firstPhoneSettings)
    }

    @Test
    func registryAndSelectionSurviveSerialization() throws {
        var preferences = AppPreferences()
        try preferences.rememberPhone(id: "a", displayName: "Same name")
        try preferences.rememberPhone(id: "b", displayName: "Same name")
        try preferences.selectPhone(id: "b")
        let data = try JSONEncoder().encode(preferences)
        let restored = try JSONDecoder().decode(AppPreferences.self, from: data)
        #expect(restored == preferences)
        #expect(restored.selectedPhoneID == "b")
    }

    @Test
    func legacySettingsMigrateWithoutCreatingAPairedPhone() throws {
        let data = Data("""
        {"schemaVersion":1,"notifications":{"isPaused":true,"allowedApplications":[]},
         "camera":{"facing":"front","resolutionHeight":720,"framesPerSecond":30,"automaticallyAdjustQuality":false},
         "screenFramesPerSecond":120}
        """.utf8)
        let migrated = try JSONDecoder().decode(AppPreferences.self, from: data)
        #expect(migrated.schemaVersion == 2)
        #expect(migrated.rememberedPhones.isEmpty)
        #expect(migrated.selectedPhoneID == nil)
        #expect(migrated.defaultPhonePreferences.camera.facing == .front)
        #expect(migrated.defaultPhonePreferences.screenFramesPerSecond == 60)
        #expect(migrated.defaultPhonePreferences.notifications.isPaused)
    }

    @Test
    func removingSelectedPhoneDoesNotRedirectActions() throws {
        var preferences = AppPreferences()
        try preferences.rememberPhone(id: "a", displayName: "First")
        try preferences.rememberPhone(id: "b", displayName: "Second")
        preferences.removePhoneMetadata(id: "a")
        #expect(preferences.selectedPhoneID == nil)
        #expect(throws: PreferencesError.self) { try preferences.selectPhone(id: "a") }
        #expect(throws: PreferencesError.self) {
            try preferences.updateFeaturePreferences(PhonePreferences(), for: "a")
        }
    }

    @Test
    func disconnectingSelectedPhoneNeverFallsBackToAnotherConnection() throws {
        var sessions = PhoneSessionDirectory()
        sessions.update(.connected, for: "a")
        sessions.update(.connected, for: "b")
        #expect(try sessions.requireConnectedPhone(id: "a") == "a")
        sessions.update(.disconnected, for: "a")
        #expect(sessions.state(for: "b") == .connected)
        #expect(throws: PhoneRoutingError.self) { try sessions.requireConnectedPhone(id: "a") }
        #expect(throws: PhoneRoutingError.self) { try sessions.requireConnectedPhone(id: nil) }
    }
}
