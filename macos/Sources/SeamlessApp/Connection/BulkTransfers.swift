import AppKit
import CryptoKit
import Foundation
import SeamlessCore

struct BulkOffer: Identifiable {
    let id: String
    let phoneID: String
    let name: String
    let size: Int64
    let hash: String
}

struct BulkActivity: Identifiable {
    let id: String
    let phoneID: String
    let name: String
    let size: Int64
    var completed: Int64 = 0
    var status: String
}

struct ReceivedDownload: Identifiable {
    let id = UUID()
    let phoneID: String
    let url: URL
}

private struct BrowserDownloadRequest {
    let phoneID: String
    let entry: PhoneStorageEntry
    let directory: URL
}

@MainActor
final class BulkTransfers: ObservableObject {
    @Published private(set) var activities: [BulkActivity] = []
    @Published private(set) var offers: [BulkOffer] = []
    @Published private(set) var downloads: [ReceivedDownload] = []
    @Published var message = "Direct encrypted transfers. No fixed file-size cap."
    var send: ((String, ControlPacket) -> Void)?
    var automaticallyAccept: ((String) -> Bool)?
    var authentication: ((String, String, String) throws -> (ConnectionProfile, ControlPacket))?
    @Published var supportedPhones: Set<String> = []
    private var browserQueue: [BrowserDownloadRequest] = []
    private var browserRequest: BrowserDownloadRequest?
    private var browserTransferID: String?
    private var browserDeadline: Task<Void, Never>?
    private var promiseCompletions: [String: (Error?) -> Void] = [:]
    private var sources: [String: URL] = [:]
    private var tasks: [String: Task<Void, Never>] = [:]
    private var sockets: [String: BulkSocket] = [:]
    private var lastProgress: [String: Date] = [:]
    private var expirations: [String: Task<Void, Never>] = [:]
    nonisolated static let maximumBytes: Int64 = 9_007_199_254_740_991

    func enqueueBrowserDownloads(phoneID: String, entries: [PhoneStorageEntry], directory: URL) {
        guard browserQueue.count + entries.count <= 100_000 else { message = "Download queue is full. Let queued files finish first."; return }
        browserQueue.append(contentsOf: entries.filter { !$0.isDirectory }.map {
            BrowserDownloadRequest(phoneID: phoneID, entry: $0, directory: directory)
        })
        startNextBrowserDownload()
    }

    func cancelBrowserDownloads(phoneID: String) {
        browserQueue.removeAll { $0.phoneID == phoneID }
        if browserRequest?.phoneID == phoneID {
            browserDeadline?.cancel()
            if let id = browserTransferID { reject(id: id, phoneID: phoneID) }
            browserRequest = nil
            browserTransferID = nil
        }
    }

    private func startNextBrowserDownload() {
        guard browserRequest == nil, !browserQueue.isEmpty else { return }
        let request = browserQueue.removeFirst()
        browserRequest = request
        send?(request.phoneID, ControlPacket(type: "browseDownload", payload: .object(["entry": .string(request.entry.id)])))
        browserDeadline = Task {
            do { try await Task.sleep(for: .seconds(300)) } catch { return }
            browserRequest = nil
            message = "A requested download expired."
            startNextBrowserDownload()
        }
    }

    func choose(phoneID: String) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.begin { response in
            guard response == .OK else { return }
            for url in panel.urls { self.offer(url: url, phoneID: phoneID) }
        }
    }

    func offer(url: URL, phoneID: String) {
        guard supportedPhones.contains(phoneID) else { message = "Install the latest companion to use large file transfers."; return }
        guard activities.count < 8 else { message = "Finish the current transfers first."; return }
        let id = UUID().uuidString
        activities.append(BulkActivity(id: id, phoneID: phoneID, name: url.lastPathComponent, size: 0, status: "Preparing"))
        tasks[id] = Task {
            do {
                let preparation = Task.detached { try Self.metadata(url: url) }
                let metadata = try await withTaskCancellationHandler { try await preparation.value }
                    onCancel: { preparation.cancel() }
                try Task.checkCancellation()
                guard activities.contains(where: { $0.id == id }) else { return }
                sources[id] = url
                activities.removeAll { $0.id == id }
                activities.append(BulkActivity(id: id, phoneID: phoneID, name: url.lastPathComponent, size: metadata.0, status: "Waiting for phone"))
                send?(phoneID, ControlPacket(type: "bulkOffer", payload: .object([
                    "transferID": .string(id), "name": .string(url.lastPathComponent),
                    "size": .number(Double(metadata.0)), "sha256": .string(metadata.1)
                ])))
                expire(id: id, phoneID: phoneID)
            } catch { fail(id: id, phoneID: phoneID, message: error.localizedDescription) }
            tasks.removeValue(forKey: id)
        }
    }

    func receive(_ packet: ControlPacket, phoneID: String) {
        guard let id = packet.payload["transferID"].string, id.count <= 64 else { return }
        switch packet.type {
        case "bulkOffer":
            guard offers.count < 8, !offers.contains(where: { $0.id == id }),
                  !activities.contains(where: { $0.id == id }),
                  let name = packet.payload["name"].string, Self.validName(name),
                  let size = packet.payload["size"].number, size >= 0,
                  size <= Double(Self.maximumBytes), size.rounded() == size,
                  let hash = packet.payload["sha256"].string, hash.count == 64, hash.allSatisfy(\.isHexDigit) else { return }
            offers.append(BulkOffer(id: id, phoneID: phoneID, name: name, size: Int64(size), hash: hash.lowercased()))
            expire(id: id, phoneID: phoneID)
            if let request = browserRequest, request.phoneID == phoneID,
               packet.payload["requestToken"].string == request.entry.id, name == request.entry.name,
               let offer = offers.first(where: { $0.id == id }) {
                browserTransferID = id
                browserDeadline?.cancel()
                accept(offer, directory: request.directory)
            } else if automaticallyAccept?(phoneID) == true, let offer = offers.first(where: { $0.id == id }) {
                accept(offer)
            }
        case "bulkAccepted":
            guard let source = sources[id], let activity = activities.first(where: { $0.id == id && $0.phoneID == phoneID }), sockets[id] == nil else { return }
            start(id: id, phoneID: phoneID, direction: "upload") { socket in
                try await socket.upload(url: source, size: activity.size) { count in
                    await self.progress(id: id, count: count)
                }
            }
        case "bulkCancel":
            guard owns(id: id, phoneID: phoneID) else { return }
            notifyTransfer(id: id, title: "Transfer cancelled", detail: "Cancelled by phone.")
            cleanup(id: id)
            message = String((packet.payload["reason"].string ?? "Transfer cancelled by phone.").prefix(300))
        default: break
        }
    }

    func accept(_ offer: BulkOffer, directory: URL? = nil, promisedURL: URL? = nil, completion: ((Error?) -> Void)? = nil) {
        guard offers.contains(where: { $0.id == offer.id && $0.phoneID == offer.phoneID }) else {
            completion?(CancellationError())
            return
        }
        let destination: URL
        if let promisedURL {
            destination = promisedURL
        } else if let directory {
            destination = uniqueDestination(directory: directory, name: offer.name)
        } else {
            guard let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first else {
                completion?(CancellationError())
                return
            }
            destination = uniqueDestination(directory: downloads, name: offer.name)
        }
        if let free = (try? FileManager.default.attributesOfFileSystem(forPath: destination.deletingLastPathComponent().path)[.systemFreeSize]) as? NSNumber,
           free.int64Value < offer.size + 16 * 1024 * 1024 {
            message = "Not enough space at the destination."
            completion?(NSError(domain: "SeamlessTransfer", code: 2, userInfo: [NSLocalizedDescriptionKey: message]))
            return
        }
        promiseCompletions[offer.id] = completion
        let staging = destination.deletingLastPathComponent().appendingPathComponent(".seamless-" + UUID().uuidString + ".part")
        offers.removeAll { $0.id == offer.id }
        activities.append(BulkActivity(id: offer.id, phoneID: offer.phoneID, name: offer.name, size: offer.size, status: "Receiving"))
        start(id: offer.id, phoneID: offer.phoneID, direction: "download") { socket in
            defer { try? FileManager.default.removeItem(at: staging) }
            try await socket.download(to: staging, size: offer.size, hash: offer.hash) { count in
                await self.progress(id: offer.id, count: count)
            }
            try Task.checkCancellation()
            if FileManager.default.fileExists(atPath: destination.path) {
                _ = try FileManager.default.replaceItemAt(destination, withItemAt: staging)
            } else {
                try FileManager.default.moveItem(at: staging, to: destination)
            }
            self.promiseCompletions.removeValue(forKey: offer.id)?(nil)
            self.downloads.insert(ReceivedDownload(phoneID: offer.phoneID, url: destination), at: 0)
            self.downloads = Array(self.downloads.prefix(20))
        }
    }

    func reject(id: String, phoneID: String) {
        guard owns(id: id, phoneID: phoneID) else { return }
        send?(phoneID, ControlPacket(type: "bulkCancel", payload: .object(["transferID": .string(id)])))
        cleanup(id: id)
    }

    func disconnected(phoneID: String) {
        supportedPhones.remove(phoneID)
        browserQueue.removeAll { $0.phoneID == phoneID }
        if browserRequest?.phoneID == phoneID {
            browserRequest = nil
            browserTransferID = nil
            browserDeadline?.cancel()
        }
        let identifiers = activities.filter { $0.phoneID == phoneID }.map(\.id) + offers.filter { $0.phoneID == phoneID }.map(\.id)
        for id in identifiers { cleanup(id: id) }
    }

    private func start(id: String, phoneID: String, direction: String,
                       operation: @escaping (BulkSocket) async throws -> Void) {
        do {
            guard let authentication else { throw ConnectionProtocolError.invalidMessage }
            let (profile, packet) = try authentication(phoneID, id, direction)
            let socket = try BulkSocket(profile: profile)
            sockets[id] = socket
            expire(id: id, phoneID: phoneID, seconds: 120)
            tasks[id] = Task {
                do {
                    try await withTaskCancellationHandler {
                        try await socket.open(authentication: packet)
                        try await operation(socket)
                    } onCancel: { Task { await socket.close() } }
                    try Task.checkCancellation()
                    notifyTransfer(id: id, title: "Transfer complete", detail: "Transferred and verified.")
                    message = "Transferred and verified."
                    cleanup(id: id)
                } catch { fail(id: id, phoneID: phoneID, message: error.localizedDescription) }
            }
        } catch { fail(id: id, phoneID: phoneID, message: error.localizedDescription) }
    }

    private func progress(id: String, count: Int64) {
        guard let index = activities.firstIndex(where: { $0.id == id }) else { return }
        if Date().timeIntervalSince(lastProgress[id] ?? .distantPast) > 10 {
            lastProgress[id] = Date()
            expire(id: id, phoneID: activities[index].phoneID, seconds: 120)
        }
        activities[index].completed = count
        activities[index].status = "Transferring"
    }

    private func owns(id: String, phoneID: String) -> Bool {
        activities.contains { $0.id == id && $0.phoneID == phoneID } || offers.contains { $0.id == id && $0.phoneID == phoneID }
    }

    private func fail(id: String, phoneID: String, message: String) {
        guard owns(id: id, phoneID: phoneID) else { return }
        notifyTransfer(id: id, title: "Transfer failed", detail: message)
        promiseCompletions.removeValue(forKey: id)?(NSError(domain: "SeamlessTransfer", code: 1, userInfo: [NSLocalizedDescriptionKey: message]))
        reject(id: id, phoneID: phoneID)
        self.message = message
    }

    private func notifyTransfer(id: String, title: String, detail: String, quiet: Bool = false) {
        guard let activity = activities.first(where: { $0.id == id }) else { return }
        MacNotificationDelivery.shared.deliver(identifier: "transfer-" + id, title: title,
                                               body: activity.name + " — " + detail, quiet: quiet)
    }

    private func cleanup(id: String) {
        promiseCompletions.removeValue(forKey: id)?(CancellationError())
        tasks.removeValue(forKey: id)?.cancel()
        if let socket = sockets.removeValue(forKey: id) { Task { await socket.close() } }
        expirations.removeValue(forKey: id)?.cancel()
        lastProgress.removeValue(forKey: id)
        sources.removeValue(forKey: id)
        activities.removeAll { $0.id == id }
        offers.removeAll { $0.id == id }
        if browserTransferID == id {
            browserTransferID = nil
            browserRequest = nil
            startNextBrowserDownload()
        }
    }

    private func expire(id: String, phoneID: String, seconds: Int = 300) {
        expirations.removeValue(forKey: id)?.cancel()
        expirations[id] = Task {
            do { try await Task.sleep(for: .seconds(seconds)) } catch { return }
            fail(id: id, phoneID: phoneID, message: "Transfer expired. Send it again.")
        }
    }

    private func uniqueDestination(directory: URL, name: String) -> URL {
        var destination = directory.appendingPathComponent(name)
        while FileManager.default.fileExists(atPath: destination.path) {
            destination = directory.appendingPathComponent(UUID().uuidString.prefix(8) + "-" + name)
        }
        return destination
    }

    nonisolated static func validName(_ name: String) -> Bool {
        !name.isEmpty && name.count <= 255 && name != "." && name != ".." && !name.contains("/") && !name.contains("\\") && !name.contains("\0")
    }

    nonisolated static func metadata(url: URL) throws -> (Int64, String) {
        let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
        guard values.isRegularFile == true, let size = values.fileSize, size <= maximumBytes else { throw ConnectionProtocolError.invalidMessage }
        let input = try FileHandle(forReadingFrom: url)
        defer { try? input.close() }
        var digest = SHA256()
        while let bytes = try input.read(upToCount: 262_144), !bytes.isEmpty {
            try Task.checkCancellation()
            digest.update(data: bytes)
        }
        return (Int64(size), digest.finalize().map { String(format: "%02x", $0) }.joined())
    }
}
