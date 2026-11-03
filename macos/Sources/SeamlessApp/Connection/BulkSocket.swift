import CryptoKit
import Foundation
import Network
import SeamlessCore

// File bytes have their own connection so a slow disk cannot block control messages.
actor BulkSocket {
    private let connection: NWConnection
    private var buffered = Data()

    init(profile: ConnectionProfile) throws {
        connection = try PinnedTLSConnection.make(profile: profile)
    }

    func close() { connection.cancel() }

    func open(authentication: ControlPacket) async throws {
        let socket = connection
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            socket.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    socket.stateUpdateHandler = nil
                    continuation.resume()
                case .failed(let error):
                    socket.stateUpdateHandler = nil
                    continuation.resume(throwing: error)
                case .cancelled:
                    socket.stateUpdateHandler = nil
                    continuation.resume(throwing: CancellationError())
                default: break
                }
            }
            socket.start(queue: DispatchQueue(label: "dev.seamless.bulk"))
        }
        var data = try JSONEncoder().encode(authentication)
        data.append(10)
        try await write(data)
        let response = try await readPacket()
        guard response.type == "bulkReady" else { throw ConnectionProtocolError.invalidMessage }
    }

    func upload(url: URL, size: Int64, progress: @Sendable (Int64) async -> Void) async throws {
        let input = try FileHandle(forReadingFrom: url)
        defer { try? input.close() }
        var count: Int64 = 0
        var lastReport = Date.distantPast
        while count < size {
            try Task.checkCancellation()
            let bytes = try input.read(upToCount: Int(min(262_144, size - count))) ?? Data()
            guard !bytes.isEmpty else { throw ConnectionProtocolError.invalidMessage }
            try await write(bytes)
            count += Int64(bytes.count)
            if count == size || Date().timeIntervalSince(lastReport) >= 0.1 {
                lastReport = Date()
                await progress(count)
            }
        }
        guard try await readPacket().type == "bulkComplete" else { throw ConnectionProtocolError.invalidMessage }
    }

    func download(to destination: URL, size: Int64, hash: String,
                  progress: @Sendable (Int64) async -> Void) async throws {
        FileManager.default.createFile(atPath: destination.path, contents: nil)
        let output = try FileHandle(forWritingTo: destination)
        defer { try? output.close() }
        var digest = SHA256()
        var count: Int64 = 0
        var lastReport = Date.distantPast
        while count < size {
            try Task.checkCancellation()
            let bytes = try await read(maximum: Int(min(262_144, size - count)))
            guard !bytes.isEmpty else { throw ConnectionProtocolError.invalidMessage }
            try output.write(contentsOf: bytes)
            digest.update(data: bytes)
            count += Int64(bytes.count)
            if count == size || Date().timeIntervalSince(lastReport) >= 0.1 {
                lastReport = Date()
                await progress(count)
            }
        }
        try output.synchronize()
        let actualHash = digest.finalize().map { String(format: "%02x", $0) }.joined()
        guard actualHash == hash else { throw ConnectionProtocolError.invalidMessage }
    }

    private func write(_ bytes: Data) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(content: bytes, completion: .contentProcessed { error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume() }
            })
        }
    }

    private func read(maximum: Int) async throws -> Data {
        if !buffered.isEmpty {
            let bytes = Data(buffered.prefix(maximum))
            buffered.removeFirst(bytes.count)
            return bytes
        }
        return try await withCheckedThrowingContinuation { continuation in
            connection.receive(minimumIncompleteLength: 1, maximumLength: maximum) { data, _, _, error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume(returning: data ?? Data()) }
            }
        }
    }

    private func readPacket() async throws -> ControlPacket {
        var header = Data()
        while true {
            let bytes = try await read(maximum: 4096)
            guard !bytes.isEmpty else { throw ConnectionProtocolError.invalidMessage }
            header.append(bytes)
            if let newline = header.firstIndex(of: 10) {
                guard header.distance(from: header.startIndex, to: newline) <= 4096 else { throw ConnectionProtocolError.oversizedMessage }
                buffered = Data(header[header.index(after: newline)...])
                let packet = try JSONDecoder().decode(ControlPacket.self, from: header[..<newline])
                guard packet.version == 1 else { throw ConnectionProtocolError.invalidMessage }
                return packet
            }
            guard header.count <= 4096 else { throw ConnectionProtocolError.oversizedMessage }
        }
    }
}
