import Foundation
import Testing
@testable import SeamlessCore

struct ConnectionProtocolTests {
    @Test
    func invitationRequiresCompleteTrustMaterial() throws {
        let valid: [String: Any] = [
            "version": 1, "phoneID": UUID().uuidString, "name": "Test phone",
            "addresses": ["192.0.2.1"], "port": 48763,
            "certificatePin": String(repeating: "ab", count: 32),
            "secret": Data(repeating: 7, count: 32).base64EncodedString()
        ]
        let invitation = try PairingInvitation.parse(code(valid))
        #expect(invitation.port == 48763)
        var missingSecret = valid
        missingSecret["secret"] = "short"
        #expect(throws: (any Error).self) { try PairingInvitation.parse(code(missingSecret)) }
        var invalidPin = valid
        invalidPin["certificatePin"] = String(repeating: "z", count: 64)
        #expect(throws: (any Error).self) { try PairingInvitation.parse(code(invalidPin)) }
        var noEndpoint = valid
        noEndpoint["addresses"] = [] as [String]
        #expect(throws: (any Error).self) { try PairingInvitation.parse(code(noEndpoint)) }
        #expect(throws: (any Error).self) { try PairingInvitation.parse(String(repeating: "x", count: 20_000)) }
    }

    @Test
    func controlValuesKeepBooleansDistinctFromNumbers() throws {
        let packet = ControlPacket(type: "notificationPolicy", payload: .object([
            "isPaused": .bool(false), "allowedApplications": .array([]), "revision": .number(1)
        ]))
        let restored = try JSONDecoder().decode(ControlPacket.self, from: JSONEncoder().encode(packet))
        #expect(restored.payload["isPaused"].boolean == false)
        #expect(restored.payload["revision"].number == 1)
        #expect(restored.payload["missing"].string == nil)
    }

    private func code(_ fields: [String: Any]) throws -> String {
        "seamless1:" + (try JSONSerialization.data(withJSONObject: fields)).base64EncodedString()
    }

    @Test
    func framingHandlesSplitAndCoalescedPackets() throws {
        let first = ControlPacket(type: "status")
        let second = ControlPacket(type: "pong")
        var wire = try JSONEncoder().encode(first)
        wire.append(10)
        wire.append(try JSONEncoder().encode(second))
        wire.append(10)
        var decoder = ControlFrameDecoder()
        #expect(try decoder.append(Data(wire.prefix(7))).isEmpty)
        let packets = try decoder.append(Data(wire.dropFirst(7)))
        #expect(packets.map(\.type) == ["status", "pong"])
    }

    @Test
    func framingRejectsUnboundedPartialMessagesAndUnknownVersions() throws {
        var decoder = ControlFrameDecoder()
        for _ in 0..<3 { _ = try decoder.append(Data(repeating: 65, count: 65_536)) }
        #expect(throws: ConnectionProtocolError.self) {
            _ = try decoder.append(Data(repeating: 65, count: 65_536))
        }
        var incompatible = ControlFrameDecoder()
        let data = Data("{\"version\":9,\"id\":\"a\",\"type\":\"status\",\"payload\":{}}\n".utf8)
        #expect(throws: ConnectionProtocolError.self) { _ = try incompatible.append(data) }
    }
}
