import AppKit
import Combine
import CoreImage
import Network
import SeamlessCore

@MainActor
final class MacQrPairingCoordinator: ObservableObject {
    @Published private(set) var image: NSImage?
    @Published private(set) var message = "Create a QR code, then scan it with Seamless on Android."
    @Published private(set) var expiresAt: Date?
    @Published private(set) var isCreating = false
    var onInvitation: ((String) -> Void)?
    private var listener: NWListener?
    private var offer: MacQrPairingOffer?
    private var generation = UUID()
    private var startupDeadline: Task<Void, Never>?
    private var expiryTask: Task<Void, Never>?
    private var clients: [UUID: NWConnection] = [:]
    private var clientDeadlines: [UUID: Task<Void, Never>] = [:]

    func create() {
        stop()
        let addresses = LocalPairingAddresses.available()
        guard !addresses.isEmpty else { message = "Connect this Mac to Wi-Fi or Ethernet, then try again."; return }
        isCreating = true
        message = "Creating your private QR code…"
        let attempt = generation
        do {
            let listener = try NWListener(using: .tcp, on: .any)
            self.listener = listener
            listener.stateUpdateHandler = { [weak self, weak listener] state in
                Task { @MainActor in
                    guard let self, self.generation == attempt else { return }
                    switch state {
                    case .ready:
                        guard let port = listener?.port?.rawValue else { return }
                        self.presentOffer(addresses: addresses, port: port)
                    case .failed(let error):
                        self.stop()
                        self.message = "Could not start pairing: " + error.localizedDescription
                    default: break
                    }
                }
            }
            listener.newConnectionHandler = { [weak self] connection in
                Task { @MainActor in
                    guard let self, self.generation == attempt else { connection.cancel(); return }
                    self.accept(connection)
                }
            }
            listener.start(queue: .global(qos: .userInitiated))
            startupDeadline = Task { [weak self] in
                do { try await Task.sleep(for: .seconds(15)) } catch { return }
                guard let self, self.generation == attempt, self.isCreating else { return }
                self.stop()
                self.message = "Local pairing could not start. Check Seamless's local network access and try again."
            }
        } catch {
            stop()
            message = error.localizedDescription
        }
    }

    func stop() {
        generation = UUID()
        listener?.cancel()
        listener = nil
        offer = nil
        image = nil
        expiresAt = nil
        isCreating = false
        message = "Create a QR code, then scan it with Seamless on Android."
        startupDeadline?.cancel()
        startupDeadline = nil
        expiryTask?.cancel()
        expiryTask = nil
        for task in clientDeadlines.values { task.cancel() }
        clientDeadlines.removeAll()
        for connection in clients.values { connection.cancel() }
        clients.removeAll()
    }

    private func presentOffer(addresses: [String], port: UInt16) {
        startupDeadline?.cancel()
        startupDeadline = nil
        do {
            let offer = MacQrPairingOffer(name: Host.current().localizedName ?? "Mac", addresses: addresses, port: port)
            let text = try offer.qrText()
            guard let filter = CIFilter(name: "CIQRCodeGenerator") else { throw ConnectionProtocolError.invalidInvitation }
            filter.setValue(Data(text.utf8), forKey: "inputMessage")
            filter.setValue("M", forKey: "inputCorrectionLevel")
            guard let output = filter.outputImage,
                  let cgImage = CIContext().createCGImage(output, from: output.extent) else { throw ConnectionProtocolError.invalidInvitation }
            self.offer = offer
            image = NSImage(cgImage: cgImage, size: output.extent.size)
            expiresAt = Date().addingTimeInterval(300)
            isCreating = false
            message = "On Android, tap Scan Mac QR code. Keep this page open."
            expiryTask = Task { [weak self] in
                do { try await Task.sleep(for: .seconds(300)) } catch { return }
                self?.stop()
                self?.message = "QR code expired. Create a new one."
            }
        } catch {
            stop()
            message = "Could not create QR code. Use the full-code fallback below."
        }
    }

    private func accept(_ connection: NWConnection) {
        guard offer != nil, clients.count < 3 else { connection.cancel(); return }
        let identifier = UUID()
        clients[identifier] = connection
        connection.start(queue: .global(qos: .userInitiated))
        clientDeadlines[identifier] = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(10)) } catch { return }
            self?.close(identifier)
        }
        receive(identifier, buffer: Data())
    }

    private func receive(_ identifier: UUID, buffer: Data) {
        guard let connection = clients[identifier] else { return }
        connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] data, _, finished, error in
            Task { @MainActor in
                guard let self, self.clients[identifier] != nil else { return }
                var collected = buffer
                if let data { collected.append(data) }
                guard collected.count <= 32_768 else { self.close(identifier); return }
                if let end = collected.firstIndex(of: 10) {
                    self.process(Data(collected[..<end]), identifier: identifier)
                } else if finished || error != nil { self.close(identifier) }
                else { self.receive(identifier, buffer: collected) }
            }
        }
    }

    private func process(_ data: Data, identifier: UUID) {
        do {
            guard let offer, let connection = clients[identifier] else { return }
            let invitation = try offer.openInvitationPacket(data)
            let acknowledgement = try offer.seal(Data("accepted".utf8), purpose: "ack")
            var reply = try JSONSerialization.data(withJSONObject: ["sealedAcknowledgement": acknowledgement.base64EncodedString()])
            reply.append(10)
            clients.removeValue(forKey: identifier)
            clientDeadlines.removeValue(forKey: identifier)?.cancel()
            stop()
            message = "QR scanned. Approve this Mac on your Android phone."
            connection.send(content: reply, completion: .contentProcessed { _ in connection.cancel() })
            onInvitation?(invitation)
        } catch {
            close(identifier)
            // Invalid network traffic never consumes the QR or changes pairing trust.
        }
    }

    private func close(_ identifier: UUID) {
        clients.removeValue(forKey: identifier)?.cancel()
        clientDeadlines.removeValue(forKey: identifier)?.cancel()
    }
}
