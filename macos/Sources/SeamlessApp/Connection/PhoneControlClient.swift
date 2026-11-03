import Foundation
import Network
import Security
import CryptoKit
import SeamlessCore

@MainActor
final class PhoneControlClient {
    var onPacket: ((ControlPacket) -> Void)?
    var onState: ((PhoneConnectionState, String?) -> Void)?
    private var connection: NWConnection?
    private var generation = UUID()
    private var decoder = ControlFrameDecoder()
    private var heartbeat: Timer?
    private var connectionDeadline: Task<Void, Never>?

    func connect(profile: ConnectionProfile, authentication: ControlPacket) {
        resetConnection()
        let currentGeneration = UUID()
        generation = currentGeneration
        let socket: NWConnection
        do {
            socket = try PinnedTLSConnection.make(profile: profile)
        } catch {
            fail(error.localizedDescription)
            return
        }
        connection = socket
        onState?(.connecting, nil)
        socket.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                guard let self, self.generation == currentGeneration else { return }
                switch state {
                case .ready:
                    self.send(authentication)
                    self.receive(generation: currentGeneration)
                case .failed(let error):
                    self.fail(error.localizedDescription)
                case .waiting(let error):
                    self.onState?(.connecting, error.localizedDescription)
                case .cancelled:
                    self.onState?(.disconnected, nil)
                default: break
                }
            }
        }
        socket.start(queue: .global(qos: .userInitiated))
        connectionDeadline = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(15)) } catch { return }
            guard let self, self.generation == currentGeneration else { return }
            self.fail("Connection timed out. Check that both devices are on the same local network.")
        }
    }

    func authenticated() {
        connectionDeadline?.cancel()
        connectionDeadline = nil
        onState?(.connected, nil)
        heartbeat?.invalidate()
        let timer = Timer(timeInterval: 20, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.send(ControlPacket(type: "ping")) }
        }
        heartbeat = timer
        // File panels must not suspend the authenticated connection's keepalive.
        RunLoop.main.add(timer, forMode: .common)
    }

    func send(_ packet: ControlPacket) {
        do {
            let data = try encoded(packet)
            guard let connection else { throw ConnectionProtocolError.invalidMessage }
            let currentGeneration = generation
            connection.send(content: data, completion: .contentProcessed { [weak self] error in
                if let error {
                    Task { @MainActor in
                        guard let self, self.generation == currentGeneration else { return }
                        self.fail(error.localizedDescription)
                    }
                }
            })
        } catch {
            fail(error.localizedDescription)
        }
    }

    func disconnect() {
        resetConnection()
        onState?(.disconnected, nil)
    }

    private func resetConnection() {
        connectionDeadline?.cancel()
        connectionDeadline = nil
        generation = UUID()
        heartbeat?.invalidate()
        heartbeat = nil
        connection?.cancel()
        connection = nil
        decoder = ControlFrameDecoder()
    }

    func sendAndWait(_ packet: ControlPacket) async throws {
        let data = try encoded(packet)
        guard let connection else { throw ConnectionProtocolError.invalidMessage }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(content: data, completion: .contentProcessed { error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume() }
            })
        }
    }

    private func encoded(_ packet: ControlPacket) throws -> Data {
        var data = try JSONEncoder().encode(packet)
        guard data.count < 262_144 else { throw ConnectionProtocolError.oversizedMessage }
        data.append(10)
        return data
    }

    private func receive(generation currentGeneration: UUID) {
        connection?.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, complete, error in
            Task { @MainActor in
                guard let self, self.generation == currentGeneration else { return }
                do {
                    if let data { try self.consume(data) }
                    if let error { self.fail(error.localizedDescription) }
                    else if complete { self.fail("Phone disconnected") }
                    else { self.receive(generation: currentGeneration) }
                } catch { self.fail(error.localizedDescription) }
            }
        }
    }

    private func consume(_ data: Data) throws {
        for packet in try decoder.append(data) { onPacket?(packet) }
    }

    private func fail(_ message: String) {
        resetConnection()
        onState?(.disconnected, message)
    }
}
