import Foundation
import Testing
@testable import SeamlessCore

struct DiscoveryTests {
    @Test
    func addressChangesPreserveThePairedCertificate() throws {
        let phoneID = UUID().uuidString.lowercased()
        var phone = RememberedPhone(id: phoneID, displayName: "Phone")
        phone.connection = ConnectionProfile(host: "192.0.2.1", port: 48763, certificatePin: String(repeating: "a", count: 64))
        let endpoint = try #require(DiscoveredPhoneEndpoint(serviceName: "Seamless-" + phoneID, host: "phone.local.", port: 48764))
        let updated = try #require(endpoint.connectionProfile(for: phone))
        #expect(updated.host == "phone.local.")
        #expect(updated.port == 48764)
        #expect(updated.certificatePin == phone.connection?.certificatePin)
        let unrelatedPhone = RememberedPhone(id: UUID().uuidString, displayName: "Other phone")
        #expect(endpoint.connectionProfile(for: unrelatedPhone) == nil)
        phone.connection = nil
        #expect(endpoint.connectionProfile(for: phone) == nil)
    }

    @Test
    func malformedAdvertisementsCannotBecomeConnectionCandidates() {
        let serviceName = "Seamless-" + UUID().uuidString
        #expect(DiscoveredPhoneEndpoint(serviceName: "Other-" + UUID().uuidString, host: "phone.local.", port: 48763) == nil)
        #expect(DiscoveredPhoneEndpoint(serviceName: "Seamless-invalid", host: "phone.local.", port: 48763) == nil)
        #expect(DiscoveredPhoneEndpoint(serviceName: serviceName, host: "", port: 48763) == nil)
        #expect(DiscoveredPhoneEndpoint(serviceName: serviceName, host: "phone\n.local.", port: 48763) == nil)
        #expect(DiscoveredPhoneEndpoint(serviceName: serviceName, host: "phone.local.", port: 65536) == nil)
    }
}
