import Foundation
import Testing
@testable import SeamlessApp

@MainActor
struct OfflinePhoneRemovalTests {
    @Test func offlinePhoneCanBeRemovedWithoutNetworkAcknowledgement() async throws {
        let connections = PhoneConnections()
        defer { connections.shutdown() }
        let phoneID = "offline-test-" + UUID().uuidString
        var forgottenPhone: String?
        connections.onForgotten = { forgottenPhone = $0 }
        connections.forget(phoneID: phoneID)
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(3))
        while forgottenPhone == nil && clock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(forgottenPhone == phoneID)
        #expect(connections.message.contains("removed from this Mac"))
    }
}
