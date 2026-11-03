import CryptoKit
import Foundation
import Testing
import SeamlessCore
@testable import SeamlessApp

struct BulkTransferTests {
    @Test
    func rejectsPathTraversalAndAllowsLargeOfferMetadata() async {
        #expect(!BulkTransfers.validName("../private"))
        #expect(!BulkTransfers.validName(".."))
        #expect(!BulkTransfers.validName("folder\\file"))
        #expect(BulkTransfers.validName("Movie 100 GB.mov"))
        #expect(BulkTransfers.maximumBytes > 100_000_000_000)
        await MainActor.run {
            let transfers = BulkTransfers()
            transfers.receive(ControlPacket(type: "bulkOffer", payload: .object([
                "transferID": .string("large-file"), "name": .string("Movie.mov"),
                "size": .number(100_000_000_000), "sha256": .string(String(repeating: "a", count: 64))
            ])), phoneID: "phone-a")
            #expect(transfers.offers.first?.size == 100_000_000_000)
            transfers.receive(ControlPacket(type: "bulkCancel", payload: .object(["transferID": .string("large-file")])), phoneID: "phone-b")
            #expect(transfers.offers.count == 1)
            transfers.reject(id: "large-file", phoneID: "phone-a")
            #expect(transfers.offers.isEmpty)
        }
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["SEAMLESS_BULK_LOOPBACK"] == "1"))
    func binaryTLSStreamsExceedOldLimitAndRejectCorruption() async throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let certificate = directory.appendingPathComponent("cert.pem")
        let key = directory.appendingPathComponent("key.pem")
        let openssl = Process()
        openssl.executableURL = URL(fileURLWithPath: "/usr/bin/openssl")
        openssl.arguments = ["req", "-x509", "-newkey", "rsa:2048", "-nodes", "-keyout", key.path, "-out", certificate.path, "-days", "1", "-subj", "/CN=localhost"]
        openssl.standardError = FileHandle.nullDevice
        try openssl.run()
        openssl.waitUntilExit()
        #expect(openssl.terminationStatus == 0)
        let pem = try String(contentsOf: certificate, encoding: .utf8)
        let base64 = pem.components(separatedBy: .newlines).filter { !$0.hasPrefix("---") }.joined()
        let certificateBytes = try #require(Data(base64Encoded: base64))
        let pin = SHA256.hash(data: certificateBytes).map { String(format: "%02x", $0) }.joined()
        let peer = Process()
        let output = Pipe()
        peer.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        peer.arguments = [root.appendingPathComponent("scripts/fixtures/bulk_tls_peer.py").path, certificate.path, key.path]
        peer.standardOutput = output
        try peer.run()
        defer { if peer.isRunning { peer.terminate() } }
        var portLine = Data()
        while let byte = try output.fileHandleForReading.read(upToCount: 1), !byte.isEmpty, byte != Data([10]) { portLine.append(byte) }
        let port = try #require(UInt16(String(decoding: portLine, as: UTF8.self)))
        let profile = ConnectionProfile(host: "127.0.0.1", port: port, certificatePin: pin)
        let block = Data((0...255).map(UInt8.init))
        var data = Data()
        for _ in 0..<(96 * 1024 + 3) { data.append(block) }
        let expectedHash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        let source = directory.appendingPathComponent("source")
        try data.write(to: source)
        for direction in ["upload", "download", "corrupt"] {
            let socket = try BulkSocket(profile: profile)
            try await socket.open(authentication: ControlPacket(type: "bulkAuthenticate", payload: .object(["direction": .string(direction == "upload" ? "upload" : "download")])))
            if direction == "upload" {
                try await socket.upload(url: source, size: Int64(data.count)) { _ in }
            } else {
                let destination = directory.appendingPathComponent(direction)
                if direction == "corrupt" {
                    await #expect(throws: (any Error).self) {
                        try await socket.download(to: destination, size: Int64(data.count), hash: String(repeating: "0", count: 64)) { _ in }
                    }
                } else {
                    try await socket.download(to: destination, size: Int64(data.count), hash: expectedHash) { _ in }
                    #expect(try Data(contentsOf: destination) == data)
                }
            }
            await socket.close()
        }
        peer.waitUntilExit()
        #expect(peer.terminationStatus == 0)
    }
}
