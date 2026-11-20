// Shared protocol/model rules for mac qr pairing offer.
// See docs/ARCHITECTURE.md for the owning subsystem and cross-platform call flow.

import CryptoKit
import Foundation

public struct MacQrPairingOffer: Codable, Sendable {
    public let version: Int
    public let sessionID: String
    public let name: String
    public let addresses: [String]
    public let port: UInt16
    public let key: String

    /// Constructs MacQrPairingOffer with the dependencies and initial values supplied by its caller.
    public init(name: String, addresses: [String], port: UInt16) {
        version = 1
        sessionID = UUID().uuidString.lowercased()
        self.name = String(name.prefix(120))
        self.addresses = Array(addresses.prefix(8))
        self.port = port
        key = SymmetricKey(size: .bits256).withUnsafeBytes { Data($0).base64EncodedString() }
    }

    /// Performs qr text for mac qr pairing offer.
    public func qrText() throws -> String {
        "seamlessmac1:" + (try JSONEncoder().encode(self)).base64EncodedString()
    }

    /// Performs open invitation packet for mac qr pairing offer.
    public func openInvitationPacket(_ data: Data) throws -> String {
        guard data.count <= 32_768 else { throw ConnectionProtocolError.oversizedMessage }
        let packet = try JSONDecoder().decode(InvitationPacket.self, from: data)
        guard packet.version == 1, packet.sessionID == sessionID,
              let combined = Data(base64Encoded: packet.sealedInvitation) else { throw ConnectionProtocolError.invalidInvitation }
        let plaintext = try open(combined, purpose: "request")
        guard let invitation = String(data: plaintext, encoding: .utf8) else { throw ConnectionProtocolError.invalidInvitation }
        _ = try PairingInvitation.parse(invitation)
        return invitation
    }

    private struct InvitationPacket: Decodable {
        let version: Int
        let sessionID: String
        let sealedInvitation: String
    }

    /// Performs open for mac qr pairing offer.
    public func open(_ combined: Data, purpose: String) throws -> Data {
        guard combined.count <= 24_000, let bytes = Data(base64Encoded: key), bytes.count == 32 else {
            throw ConnectionProtocolError.invalidInvitation
        }
        let box = try AES.GCM.SealedBox(combined: combined)
        return try AES.GCM.open(box, using: SymmetricKey(data: bytes), authenticating: context(purpose))
    }

    /// Performs seal for mac qr pairing offer.
    public func seal(_ content: Data, purpose: String) throws -> Data {
        guard let bytes = Data(base64Encoded: key), bytes.count == 32 else { throw ConnectionProtocolError.invalidInvitation }
        let box = try AES.GCM.seal(content, using: SymmetricKey(data: bytes), authenticating: context(purpose))
        guard let combined = box.combined else { throw ConnectionProtocolError.invalidInvitation }
        return combined
    }

    /// Performs context for mac qr pairing offer.
    private func context(_ purpose: String) -> Data {
        Data("Seamless QR pairing v1:\(sessionID):\(purpose)".utf8)
    }
}
