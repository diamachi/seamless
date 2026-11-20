// Tests for PhoneControlClientStateTests and the behavior owned by its target module.
// Keep assertions focused on externally visible results and failure boundaries.

import Testing
import SeamlessCore
@testable import SeamlessApp

@MainActor
struct PhoneControlClientStateTests {
    /// Exercises connection setup failure emits one actual failure through the expected result and relevant rejection assertions.
    @Test func connectionSetupFailureEmitsOneActualFailure() {
        let client = PhoneControlClient()
        var events: [(PhoneConnectionState, String?)] = []
        client.onState = { state, error in events.append((state, error)) }
        client.connect(profile: ConnectionProfile(host: "", port: 0, certificatePin: ""), authentication: ControlPacket(type: "authenticate"))
        #expect(events.count == 1)
        #expect(events.first?.0 == .disconnected)
        #expect(events.first?.1 != nil)
    }
}
