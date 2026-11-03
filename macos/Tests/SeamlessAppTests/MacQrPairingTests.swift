import AppKit
import CoreImage
import Darwin
import Foundation
import SeamlessCore
import Testing
import Vision
@testable import SeamlessApp

@MainActor
struct MacQrPairingTests {
    @Test func renderedQrReceivesOneAuthenticatedInvitationAndRejectsOldSession() async throws {
        let coordinator = MacQrPairingCoordinator()
        defer { coordinator.stop() }
        var received: [String] = []
        coordinator.onInvitation = { received.append($0) }
        coordinator.create()
        let first = try await readOffer(coordinator)
        coordinator.create()
        let second = try await readOffer(coordinator)
        #expect(first.sessionID != second.sessionID)
        let invitation = try phoneInvitation()
        let oldRequest = try packet(offer: first, invitation: invitation)
        let rejected = try await Self.exchange(port: second.port, request: oldRequest)
        #expect(rejected.isEmpty)
        #expect(received.isEmpty)
        #expect(coordinator.image != nil)
        let reply = try await Self.exchange(port: second.port, request: packet(offer: second, invitation: invitation))
        let fields = try #require(JSONSerialization.jsonObject(with: reply) as? [String: String])
        let sealedAck = try #require(fields["sealedAcknowledgement"].flatMap { Data(base64Encoded: $0) })
        #expect(try second.open(sealedAck, purpose: "ack") == Data("accepted".utf8))
        #expect(received == [invitation])
        #expect(coordinator.image == nil)
        #expect(coordinator.expiresAt == nil)
    }

    private func readOffer(_ coordinator: MacQrPairingCoordinator) async throws -> MacQrPairingOffer {
        let deadline = Date().addingTimeInterval(5)
        while coordinator.image == nil && Date() < deadline { try await Task.sleep(for: .milliseconds(20)) }
        let image = try #require(coordinator.image)
        let source = try #require(image.cgImage(forProposedRect: nil, context: nil, hints: nil))
        let scaled = CIImage(cgImage: source).transformed(by: CGAffineTransform(scaleX: 8, y: 8))
        let context = CIContext(options: [.useSoftwareRenderer: true])
        let enlarged = try #require(context.createCGImage(scaled, from: scaled.extent))
        let request = VNDetectBarcodesRequest()
        request.symbologies = [.qr]
        try VNImageRequestHandler(cgImage: enlarged).perform([request])
        let text = try #require(request.results?.first?.payloadStringValue)
        #expect(text.hasPrefix("seamlessmac1:"))
        let data = try #require(Data(base64Encoded: String(text.dropFirst("seamlessmac1:".count))))
        return try JSONDecoder().decode(MacQrPairingOffer.self, from: data)
    }

    private func phoneInvitation() throws -> String {
        let fields: [String: Any] = ["version": 1, "phoneID": UUID().uuidString, "name": "Test phone",
            "addresses": ["192.0.2.1"], "port": 48763, "certificatePin": String(repeating: "ab", count: 32),
            "secret": Data(repeating: 7, count: 32).base64EncodedString()]
        return "seamless1:" + (try JSONSerialization.data(withJSONObject: fields)).base64EncodedString()
    }

    private func packet(offer: MacQrPairingOffer, invitation: String) throws -> Data {
        let encrypted = try offer.seal(Data(invitation.utf8), purpose: "request")
        var data = try JSONSerialization.data(withJSONObject: ["version": 1, "sessionID": offer.sessionID,
            "sealedInvitation": encrypted.base64EncodedString()])
        data.append(10)
        return data
    }

    nonisolated private static func exchange(port: UInt16, request: Data) async throws -> Data {
        try await Task.detached {
            let socket = Darwin.socket(AF_INET, SOCK_STREAM, 0)
            guard socket >= 0 else { throw CocoaError(.fileReadUnknown) }
            defer { Darwin.close(socket) }
            var timeout = timeval(tv_sec: 5, tv_usec: 0)
            setsockopt(socket, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
            var address = sockaddr_in()
            address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
            address.sin_family = sa_family_t(AF_INET)
            address.sin_port = port.bigEndian
            inet_pton(AF_INET, "127.0.0.1", &address.sin_addr)
            let result = withUnsafePointer(to: &address) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    Darwin.connect(socket, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
            guard result == 0 else { throw CocoaError(.fileReadUnknown) }
            var sent = 0
            while sent < request.count {
                let count = request.withUnsafeBytes { bytes in Darwin.send(socket, bytes.baseAddress!.advanced(by: sent), request.count - sent, 0) }
                guard count > 0 else { throw CocoaError(.fileWriteUnknown) }
                sent += count
            }
            var response = Data()
            var buffer = [UInt8](repeating: 0, count: 1024)
            while response.count < 2048 {
                let count = Darwin.recv(socket, &buffer, buffer.count, 0)
                guard count >= 0 else { throw CocoaError(.fileReadUnknown) }
                if count == 0 { break }
                response.append(contentsOf: buffer.prefix(count))
                if response.contains(10) { break }
            }
            return response
        }.value
    }
}
