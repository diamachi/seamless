import Foundation
import Testing
@testable import SeamlessApp

struct CallingPreferencesTests {
    @Test func existingBluetoothMatchSurvivesNewReconnectPreference() throws {
        let data = Data("""
        {"bluetoothAddress":"00:11:22:33:44:55","microphoneUID":"test-mic","speakerUID":"test-speaker"}
        """.utf8)
        let options = try JSONDecoder().decode(PhoneCallingOptions.self, from: data)
        #expect(options.bluetoothAddress == "00:11:22:33:44:55")
        #expect(options.microphoneUID == "test-mic")
        #expect(!options.reconnectOnLaunch)
    }
}
