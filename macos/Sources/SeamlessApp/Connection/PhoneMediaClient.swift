import Foundation
import Network
import SeamlessCore

@MainActor
final class PhoneMediaClient {
    var onRecord: ((MediaRecord) throws -> Void)?
    var onFailure: ((String) -> Void)?
    private var connection: NWConnection?
    private var generation = UUID()
    private var helloBuffer = Data()
    private var hasReceivedHello = false
    private var decoder = MediaRecordDecoder()

    func connect(profile: ConnectionProfile, authentication: ControlPacket) throws {
        disconnect()
        let currentGeneration = UUID()
        generation = currentGeneration
        let socket = try PinnedTLSConnection.make(profile: profile, interactive: true)
        connection = socket
        var packet = try JSONEncoder().encode(authentication)
        packet.append(10)
        let authenticationData = packet
        socket.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                guard let self, self.generation == currentGeneration else { return }
                switch state {
                case .ready:
                    socket.send(content: authenticationData, completion: .contentProcessed { _ in })
                    self.receive(generation: currentGeneration)
                case .failed(let error): self.fail(error.localizedDescription)
                default: break
                }
            }
        }
        socket.start(queue: .global(qos: .userInteractive))
    }

    func disconnect() {
        generation = UUID()
        connection?.cancel()
        connection = nil
        hasReceivedHello = false
        helloBuffer.removeAll()
        decoder = MediaRecordDecoder()
    }

    private func receive(generation currentGeneration: UUID) {
        connection?.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, complete, error in
            Task { @MainActor in
                guard let self, self.generation == currentGeneration else { return }
                do {
                    if let data { try self.consume(data) }
                    if let error { self.fail(error.localizedDescription) }
                    else if complete { self.fail("Video stream ended") }
                    else { self.receive(generation: currentGeneration) }
                } catch { self.fail(error.localizedDescription) }
            }
        }
    }

    private func consume(_ data: Data) throws {
        var mediaData = data
        if !hasReceivedHello {
            helloBuffer.append(data)
            guard let newline = helloBuffer.firstIndex(of: 10) else {
                guard helloBuffer.count <= 4096 else { throw ConnectionProtocolError.invalidMessage }
                return
            }
            guard helloBuffer.distance(from: helloBuffer.startIndex, to: newline) <= 4096 else { throw ConnectionProtocolError.invalidMessage }
            let hello = try JSONDecoder().decode(ControlPacket.self, from: helloBuffer[..<newline])
            guard hello.version == 1, hello.type == "mediaReady" else { throw ConnectionProtocolError.invalidMessage }
            mediaData = Data(helloBuffer[helloBuffer.index(after: newline)...])
            helloBuffer.removeAll()
            hasReceivedHello = true
        }
        for record in try decoder.append(mediaData) { try onRecord?(record) }
    }

    private func fail(_ message: String) {
        disconnect()
        onFailure?(message)
    }
}
