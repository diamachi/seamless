import Foundation
import Testing
@testable import SeamlessCore

struct MacQrPairingOfferTests {
    private let sessionID = "11111111-2222-3333-4444-555555555555"
    private let vector = "AAECAwQFBgcICQoLNGe3dqmAsWi8e+Ty350QCPe/5BmEHiwIFQ6L83QdYcZof8AqElQqVsbSqRwad9IFwcqg"

    @Test func interoperableEnvelopeRejectsWrongRoleAndSession() throws {
        let offer = try fixtureOffer()
        let ciphertext = try #require(Data(base64Encoded: vector))
        let plaintext = try offer.open(ciphertext, purpose: "request")
        #expect(String(data: plaintext, encoding: .utf8) == "seamless1:synthetic-test-invitation")
        #expect(throws: (any Error).self) { try offer.open(ciphertext, purpose: "ack") }
        let other = try fixtureOffer(session: UUID().uuidString.lowercased())
        #expect(throws: (any Error).self) { try other.open(ciphertext, purpose: "request") }
        var damaged = ciphertext
        damaged[20] ^= 1
        #expect(throws: (any Error).self) { try offer.open(damaged, purpose: "request") }
    }

    @Test func invitationHandoffRequiresCompleteTrustMaterial() throws {
        let offer = try fixtureOffer()
        let fields: [String: Any] = ["version": 1, "phoneID": UUID().uuidString, "name": "Test phone",
            "addresses": ["192.0.2.1"], "port": 48763, "certificatePin": String(repeating: "ab", count: 32),
            "secret": Data(repeating: 7, count: 32).base64EncodedString()]
        let invitation = "seamless1:" + (try JSONSerialization.data(withJSONObject: fields)).base64EncodedString()
        let encrypted = try offer.seal(Data(invitation.utf8), purpose: "request")
        let valid = try packet(offer: offer, sealed: encrypted)
        #expect(try offer.openInvitationPacket(valid) == invitation)
        let invalid = try packet(offer: offer, sealed: offer.seal(Data("not-an-invitation".utf8), purpose: "request"))
        #expect(throws: (any Error).self) { try offer.openInvitationPacket(invalid) }
        let wrongSession = try packet(offer: offer, sealed: encrypted, session: UUID().uuidString)
        #expect(throws: (any Error).self) { try offer.openInvitationPacket(wrongSession) }
        #expect(throws: (any Error).self) { try offer.openInvitationPacket(Data(repeating: 32, count: 32_769)) }
    }

    private func fixtureOffer(session: String? = nil) throws -> MacQrPairingOffer {
        let fields: [String: Any] = ["version": 1, "sessionID": session ?? sessionID, "name": "Test Mac",
            "addresses": ["192.0.2.2"], "port": 50000, "key": Data((0..<32).map { UInt8($0) }).base64EncodedString()]
        return try JSONDecoder().decode(MacQrPairingOffer.self, from: JSONSerialization.data(withJSONObject: fields))
    }

    private func packet(offer: MacQrPairingOffer, sealed: Data, session: String? = nil) throws -> Data {
        try JSONSerialization.data(withJSONObject: ["version": 1, "sessionID": session ?? offer.sessionID,
            "sealedInvitation": sealed.base64EncodedString()])
    }
}
