import Testing
import SeamlessCore
@testable import SeamlessApp

@MainActor
struct PhoneControlClientStateTests {
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
