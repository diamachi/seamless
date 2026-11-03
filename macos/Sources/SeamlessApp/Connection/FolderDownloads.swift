import Foundation
import SeamlessCore

private struct DirectoryDownload {
    let phoneID: String
    let token: String
    let destination: URL
    let depth: Int
    var offset = 0
}

@MainActor
final class FolderDownloads: ObservableObject {
    @Published private(set) var message = ""
    @Published private(set) var isListing = false
    var send: ((String, ControlPacket) -> Void)?
    private weak var bulk: BulkTransfers?
    private var queue: [DirectoryDownload] = []
    private var active: DirectoryDownload?
    private var requestID: String?
    private var deadline: Task<Void, Never>?
    private var listedEntries = 0

    func save(entries: [PhoneStorageEntry], phoneID: String, bulk: BulkTransfers, destinationDirectory: URL? = nil) {
        guard let downloads = destinationDirectory ?? FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first else { return }
        self.bulk = bulk
        do {
            let files = entries.filter { !$0.isDirectory }
            bulk.enqueueBrowserDownloads(phoneID: phoneID, entries: files, directory: downloads)
            for entry in entries where entry.isDirectory {
                let destination = try makeDirectory(parent: downloads, name: entry.name)
                queue.append(DirectoryDownload(phoneID: phoneID, token: entry.id, destination: destination, depth: 0))
            }
            if !queue.isEmpty { next() }
            else { message = "Selected files queued for Downloads." }
        } catch { message = error.localizedDescription }
    }

    func receive(_ packet: ControlPacket, phoneID: String) -> Bool {
        guard packet.id == requestID, let directory = active, directory.phoneID == phoneID else { return false }
        deadline?.cancel()
        if packet.type == "browseError" { stop(message: "Folder listing stopped. Check phone access; already queued files may continue."); return true }
        do {
            let entries = PhoneStorageEntry.decode(packet.payload["entries"])
            listedEntries += entries.count
            guard listedEntries <= 100_000 else { throw ConnectionProtocolError.oversizedMessage }
            bulk?.enqueueBrowserDownloads(phoneID: phoneID, entries: entries.filter { !$0.isDirectory }, directory: directory.destination)
            for entry in entries where entry.isDirectory {
                guard directory.depth < 64 else { throw ConnectionProtocolError.invalidMessage }
                let destination = try makeDirectory(parent: directory.destination, name: entry.name)
                queue.append(DirectoryDownload(phoneID: phoneID, token: entry.id, destination: destination, depth: directory.depth + 1))
            }
            let offset = Int(packet.payload["nextOffset"].number ?? -1)
            if offset >= 0 {
                guard offset > directory.offset else { throw ConnectionProtocolError.invalidMessage }
                var page = directory
                page.offset = offset
                queue.insert(page, at: 0)
            }
            active = nil
            requestID = nil
            message = "\(listedEntries) folder entries queued. Files save to Downloads as they arrive."
            next()
        } catch { stop(message: "Folder listing stopped at a provider/size/depth limit. Already queued files may continue.") }
        return true
    }

    func cancel() {
        let phoneIDs = Set(queue.map(\.phoneID) + [active?.phoneID].compactMap { $0 })
        for phoneID in phoneIDs { bulk?.cancelBrowserDownloads(phoneID: phoneID) }
        stop(message: "Folder listing cancelled.")
    }

    func disconnected(phoneID: String) {
        queue.removeAll { $0.phoneID == phoneID }
        if active?.phoneID == phoneID { stop(message: "Folder listing interrupted by disconnect. Downloaded files remain in Downloads.") }
    }

    private func next() {
        guard active == nil else { return }
        guard !queue.isEmpty else { isListing = false; listedEntries = 0; return }
        let directory = queue.removeFirst()
        active = directory
        isListing = true
        let packet = ControlPacket(type: "browseList", payload: .object([
            "directory": .string(directory.token), "media": .bool(false), "offset": .number(Double(directory.offset))
        ]))
        requestID = packet.id
        send?(directory.phoneID, packet)
        deadline = Task {
            do { try await Task.sleep(for: .seconds(120)) } catch { return }
            stop(message: "Folder listing timed out; already queued files may continue.")
        }
    }

    private func stop(message: String) {
        deadline?.cancel()
        active = nil
        requestID = nil
        queue = []
        listedEntries = 0
        isListing = false
        self.message = message
    }

    private func makeDirectory(parent: URL, name: String) throws -> URL {
        guard BulkTransfers.validName(name) else { throw ConnectionProtocolError.invalidMessage }
        var destination = parent.appendingPathComponent(name, isDirectory: true)
        if FileManager.default.fileExists(atPath: destination.path) { destination = parent.appendingPathComponent(String(UUID().uuidString.prefix(8)) + "-" + name, isDirectory: true) }
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: false)
        return destination
    }
}
