import Foundation
import Testing
@testable import SeamlessCore

@Test func reconnectRequestsRejectReplaysAndThrottleDiscoveryNoise() {
    var gate = ReconnectRequestGate()
    let firstRequest = UUID().uuidString
    let now = Date(timeIntervalSince1970: 100)
    let result1 = gate.accept(phoneID: "phone", requestID: firstRequest, now: now)
    #expect(result1)
    let result2 = !gate.accept(phoneID: "phone", requestID: firstRequest, now: now.addingTimeInterval(20))
    #expect(result2)
    let result3 = !gate.accept(phoneID: "phone", requestID: UUID().uuidString, now: now.addingTimeInterval(2))
    #expect(result3)
    let result4 = gate.accept(phoneID: "phone", requestID: UUID().uuidString, now: now.addingTimeInterval(20))
    #expect(result4)
    let result5 = !gate.accept(phoneID: "phone", requestID: "invalid", now: now.addingTimeInterval(40))
    #expect(result5)
    let result6 = gate.accept(phoneID: "other-phone", requestID: UUID().uuidString, now: now)
    #expect(result6)
}

@Test func discoveryAcceptsAndroidNameCollisionSuffixWithoutChangingPhoneIdentity() {
    let phoneID = UUID().uuidString.lowercased()
    #expect(DiscoveredPhoneEndpoint.phoneIdentifier(serviceName: "Seamless-" + phoneID + " (2)") == phoneID)
    #expect(DiscoveredPhoneEndpoint.phoneIdentifier(serviceName: "Seamless-" + phoneID + "-other") == nil)
}
