import AppKit
import CryptoKit
import Foundation
import SeamlessCore

struct FileOffer: Identifiable {
    let id: String
    let phoneID: String
    let name: String
    let size: Int
    let sha256: String
}

struct FileTransferActivity: Identifiable {
    let id: String
    let phoneID: String
    let name: String
    let totalBytes: Int
    var completedBytes = 0
    var status: String
}

private struct IncomingTransfer {
    let offer: FileOffer
    let destination: URL
    var data = Data()
}

private struct OutgoingTransfer {
    let phoneID: String
    let data: Data
}

@MainActor
final class FileTransfers: ObservableObject {
    @Published private(set) var activities: [FileTransferActivity] = []
    @Published private(set) var offers: [FileOffer] = []
    @Published private(set) var message = "Files up to 20 MiB are supported in this development build."
    var send: ((String, ControlPacket) -> Void)?
    var sendAndWait: ((String, ControlPacket) async throws -> Void)?
    private var incoming: [String: IncomingTransfer] = [:]
    private var outgoing: [String: OutgoingTransfer] = [:]
    private var sendingTasks: [String: Task<Void, Never>] = [:]
    private var expirationTasks: [String: Task<Void, Never>] = [:]
    private let transferTimeout: Duration
    private static let maximumBytes = 20 * 1024 * 1024

    init(transferTimeout: Duration = .seconds(120)) {
        self.transferTimeout = transferTimeout
    }

    func chooseAndOffer(phoneID: String) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        offer(url: url, phoneID: phoneID)
    }

    func offer(url: URL, phoneID: String) {
        do {
            guard outgoing.count < 2 else { throw FileTransferError.tooManyTransfers }
            let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
            guard values.isRegularFile == true, let size = values.fileSize, size <= Self.maximumBytes else { throw FileTransferError.tooLarge }
            let data = try Data(contentsOf: url)
            guard data.count <= Self.maximumBytes else { throw FileTransferError.tooLarge }
            let id = UUID().uuidString
            outgoing[id] = OutgoingTransfer(phoneID: phoneID, data: data)
            activities.append(FileTransferActivity(id: id, phoneID: phoneID, name: url.lastPathComponent,
                totalBytes: data.count, status: "Waiting for acceptance"))
            scheduleExpiration(id: id, phoneID: phoneID)
            send?(phoneID, ControlPacket(type: "fileOffer", payload: .object([
                "transferID": .string(id), "name": .string(url.lastPathComponent),
                "size": .number(Double(data.count)), "sha256": .string(hash(data))
            ])))
            message = "Waiting for the phone to accept \(url.lastPathComponent)."
        } catch { message = error.localizedDescription }
    }

    func receive(_ packet: ControlPacket, phoneID: String) {
        do {
            guard let id = packet.payload["transferID"].string, id.count <= 64 else { throw FileTransferError.invalidTransfer }
            switch packet.type {
            case "fileOffer": try receiveOffer(packet.payload, id: id, phoneID: phoneID)
            case "fileAccept": try startSending(id: id, phoneID: phoneID)
            case "fileChunk": try receiveChunk(packet.payload, id: id, phoneID: phoneID)
            case "fileFinish": try finishReceiving(id: id, phoneID: phoneID)
            case "fileComplete":
                guard outgoing[id]?.phoneID == phoneID else { throw FileTransferError.invalidTransfer }
                outgoing.removeValue(forKey: id)
                removeActivity(id: id)
                message = "File received and verified by the phone."
            case "fileCancel": cancel(id: id, phoneID: phoneID)
            default: break
            }
        } catch {
            message = error.localizedDescription
            if let id = packet.payload["transferID"].string {
                cancel(id: id, phoneID: phoneID)
                send?(phoneID, ControlPacket(type: "fileCancel", payload: .object(["transferID": .string(id)])))
            }
        }
    }

    func accept(_ offer: FileOffer) {
        guard incoming.count < 2 else { message = FileTransferError.tooManyTransfers.localizedDescription; return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = offer.name
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        guard offers.contains(where: { $0.id == offer.id && $0.phoneID == offer.phoneID }) else { return }
        incoming[offer.id] = IncomingTransfer(offer: offer, destination: destination)
        activities.append(FileTransferActivity(id: offer.id, phoneID: offer.phoneID, name: offer.name,
            totalBytes: offer.size, status: "Receiving"))
        scheduleExpiration(id: offer.id, phoneID: offer.phoneID)
        offers.removeAll { $0.id == offer.id }
        send?(offer.phoneID, ControlPacket(type: "fileAccept", payload: .object(["transferID": .string(offer.id)])))
        message = "Receiving \(offer.name)."
    }

    func reject(_ offer: FileOffer) {
        cancel(id: offer.id, phoneID: offer.phoneID)
        send?(offer.phoneID, ControlPacket(type: "fileCancel", payload: .object(["transferID": .string(offer.id)])))
    }

    func cancelTransfer(_ activity: FileTransferActivity) {
        cancel(id: activity.id, phoneID: activity.phoneID)
        send?(activity.phoneID, ControlPacket(type: "fileCancel", payload: .object(["transferID": .string(activity.id)])))
        message = "Transfer cancelled."
    }

    func disconnected(phoneID: String) {
        let expiredIDs = activities.filter { $0.phoneID == phoneID }.map(\.id)
        let offerIDs = offers.filter { $0.phoneID == phoneID }.map(\.id)
        for id in expiredIDs + offerIDs {
            removeActivity(id: id)
        }
        for (id, transfer) in outgoing where transfer.phoneID == phoneID {
            sendingTasks.removeValue(forKey: id)?.cancel()
        }
        outgoing = outgoing.filter { $0.value.phoneID != phoneID }
        incoming = incoming.filter { $0.value.offer.phoneID != phoneID }
        offers.removeAll { $0.phoneID == phoneID }
    }

    private func receiveOffer(_ payload: JSONValue, id: String, phoneID: String) throws {
        guard offers.count < 4, let name = payload["name"].string,
              !name.isEmpty, name.count <= 255, name != ".", name != "..",
              !name.contains("/"), !name.contains("\\"), !name.contains("\0"),
              let size = payload["size"].number, size >= 0, size <= Double(Self.maximumBytes), size.rounded() == size,
              let sha256 = payload["sha256"].string, sha256.count == 64, sha256.allSatisfy(\.isHexDigit),
              !offers.contains(where: { $0.id == id }), incoming[id] == nil else { throw FileTransferError.invalidTransfer }
        offers.append(FileOffer(id: id, phoneID: phoneID, name: name, size: Int(size), sha256: sha256.lowercased()))
        scheduleExpiration(id: id, phoneID: phoneID)
    }

    private func receiveChunk(_ payload: JSONValue, id: String, phoneID: String) throws {
        guard var transfer = incoming[id], transfer.offer.phoneID == phoneID,
              payload["offset"].number == Double(transfer.data.count),
              let text = payload["data"].string, text.count <= 65_536,
              let data = Data(base64Encoded: text), data.count <= 49_152,
              transfer.data.count + data.count <= transfer.offer.size else { throw FileTransferError.invalidTransfer }
        transfer.data.append(data)
        incoming[id] = transfer
        updateActivity(id: id, completedBytes: transfer.data.count, status: "Receiving")
    }

    private func finishReceiving(id: String, phoneID: String) throws {
        guard let transfer = incoming[id], transfer.offer.phoneID == phoneID,
              transfer.data.count == transfer.offer.size, hash(transfer.data) == transfer.offer.sha256 else { throw FileTransferError.invalidTransfer }
        try transfer.data.write(to: transfer.destination, options: .atomic)
        incoming.removeValue(forKey: id)
        removeActivity(id: id)
        send?(phoneID, ControlPacket(type: "fileComplete", payload: .object(["transferID": .string(id)])))
        message = "Saved and verified \(transfer.offer.name)."
    }

    private func startSending(id: String, phoneID: String) throws {
        guard let transfer = outgoing[id], transfer.phoneID == phoneID, sendingTasks[id] == nil else { throw FileTransferError.invalidTransfer }
        scheduleExpiration(id: id, phoneID: phoneID)
        updateActivity(id: id, completedBytes: 0, status: "Sending")
        sendingTasks[id] = Task { [weak self] in
            guard let self else { return }
            defer { self.sendingTasks.removeValue(forKey: id) }
            do {
                guard let sendAndWait = self.sendAndWait else { throw FileTransferError.invalidTransfer }
                var offset = 0
                while offset < transfer.data.count {
                    try Task.checkCancellation()
                    let end = min(offset + 49_152, transfer.data.count)
                    let data = transfer.data[offset..<end].base64EncodedString()
                    try await sendAndWait(phoneID, ControlPacket(type: "fileChunk", payload: .object([
                        "transferID": .string(id), "offset": .number(Double(offset)), "data": .string(data)
                    ])))
                    offset = end
                    self.updateActivity(id: id, completedBytes: offset, status: "Sending")
                }
                try await sendAndWait(phoneID, ControlPacket(type: "fileFinish", payload: .object(["transferID": .string(id)])))
                if self.outgoing[id] != nil {
                    self.updateActivity(id: id, completedBytes: transfer.data.count, status: "Verifying on phone")
                    self.message = "Sent; waiting for the phone's integrity check."
                }
            } catch {
                guard self.outgoing[id] != nil else { return }
                self.send?(phoneID, ControlPacket(type: "fileCancel", payload: .object(["transferID": .string(id)])))
                self.cancel(id: id, phoneID: phoneID)
                self.message = error.localizedDescription
            }
        }
    }

    private func cancel(id: String, phoneID: String) {
        if activities.contains(where: { $0.id == id && $0.phoneID == phoneID }) ||
            offers.contains(where: { $0.id == id && $0.phoneID == phoneID }) {
            removeActivity(id: id)
        }
        if outgoing[id]?.phoneID == phoneID {
            outgoing.removeValue(forKey: id)
            sendingTasks.removeValue(forKey: id)?.cancel()
        }
        if incoming[id]?.offer.phoneID == phoneID { incoming.removeValue(forKey: id) }
        offers.removeAll { $0.id == id && $0.phoneID == phoneID }
    }

    private func updateActivity(id: String, completedBytes: Int, status: String) {
        guard let index = activities.firstIndex(where: { $0.id == id }) else { return }
        activities[index].completedBytes = completedBytes
        activities[index].status = status
    }

    private func removeActivity(id: String) {
        activities.removeAll { $0.id == id }
        expirationTasks.removeValue(forKey: id)?.cancel()
    }

    private func scheduleExpiration(id: String, phoneID: String) {
        expirationTasks.removeValue(forKey: id)?.cancel()
        let timeout = transferTimeout
        expirationTasks[id] = Task { [weak self] in
            do {
                try await Task.sleep(for: timeout)
            } catch {
                return
            }
            guard let self else { return }
            self.cancel(id: id, phoneID: phoneID)
            self.send?(phoneID, ControlPacket(type: "fileCancel", payload: .object(["transferID": .string(id)])))
            self.message = "Transfer expired. Try sending the file again."
        }
    }

    private func hash(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

private enum FileTransferError: LocalizedError {
    case tooLarge, invalidTransfer, tooManyTransfers
    var errorDescription: String? {
        switch self {
        case .tooLarge: return "Choose a regular file no larger than 20 MiB."
        case .invalidTransfer: return "Transfer failed validation or its target phone is unavailable."
        case .tooManyTransfers: return "Finish or cancel existing transfers first."
        }
    }
}
