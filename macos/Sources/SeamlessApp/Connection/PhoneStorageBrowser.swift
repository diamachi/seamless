import AppKit
import Foundation
import ImageIO
import SeamlessCore

struct PhoneStorageEntry: Identifiable {
    let id: String
    let name: String
    let mime: String
    let isDirectory: Bool
    let size: Int64

    static func decode(_ payload: JSONValue) -> [PhoneStorageEntry] {
        payload.array.prefix(100).compactMap { value in
            guard let id = value["id"].string, id.count <= 64,
                  let name = value["name"].string, BulkTransfers.validName(name) else { return nil }
            return PhoneStorageEntry(id: id, name: name, mime: value["mime"].string ?? "", isDirectory: value["directory"].boolean ?? false,
                size: Int64(max(0, min(Double(BulkTransfers.maximumBytes), value["size"].number ?? 0))))
        }
    }
}

@MainActor
final class PhoneStorageBrowser: ObservableObject {
    @Published private(set) var entries: [PhoneStorageEntry] = []
    @Published private(set) var thumbnails: [String: NSImage] = [:]
    @Published private(set) var message = "Enable storage access on your phone, then refresh."
    @Published private(set) var isLoading = false
    @Published private(set) var nextOffset = -1
    @Published private(set) var breadcrumbs: [(String, String)] = [("", "Phone storage")]
    let folderDownloads = FolderDownloads()
    var supportedPhones: Set<String> = []
    var send: ((String, ControlPacket) -> Void)?
    private var phoneID: String?
    private var requestID: String?
    private var media = false
    private var appendResults = false
    private var thumbnailRequests: Set<String> = []

    func load(phoneID: String, media: Bool, directory: String = "", append: Bool = false) {
        guard supportedPhones.contains(phoneID) else {
            message = "Install the latest companion to browse phone storage."
            isLoading = false
            return
        }
        if !append {
            thumbnails = [:]
            thumbnailRequests = []
        }
        if self.phoneID != phoneID || self.media != media {
            entries = []
            thumbnails = [:]
            thumbnailRequests = []
            breadcrumbs = [("", media ? "Photos and videos" : "Phone storage")]
        }
        self.phoneID = phoneID
        self.media = media
        appendResults = append
        let packet = ControlPacket(type: "browseList", payload: .object([
            "directory": .string(directory), "media": .bool(media), "offset": .number(Double(append ? max(0, nextOffset) : 0))
        ]))
        requestID = packet.id
        isLoading = true
        message = "Loading…"
        send?(phoneID, packet)
    }

    func open(_ entry: PhoneStorageEntry) {
        guard let phoneID, entry.isDirectory else { return }
        breadcrumbs.append((entry.id, entry.name))
        load(phoneID: phoneID, media: media, directory: entry.id)
    }

    func back() {
        guard let phoneID, breadcrumbs.count > 1 else { return }
        breadcrumbs.removeLast()
        load(phoneID: phoneID, media: media, directory: breadcrumbs.last!.0)
    }

    func refresh() {
        guard let phoneID else { return }
        load(phoneID: phoneID, media: media, directory: breadcrumbs.last?.0 ?? "")
    }

    func more() {
        guard let phoneID, nextOffset >= 0 else { return }
        load(phoneID: phoneID, media: media, directory: breadcrumbs.last?.0 ?? "", append: true)
    }

    func saveToDownloads(_ entries: [PhoneStorageEntry], bulk: BulkTransfers) {
        guard let phoneID else { return }
        folderDownloads.save(entries: entries, phoneID: phoneID, bulk: bulk)
    }

    func download(_ entry: PhoneStorageEntry) {
        guard let phoneID, !entry.isDirectory else { return }
        send?(phoneID, ControlPacket(type: "browseDownload", payload: .object(["entry": .string(entry.id)])))
        message = "Requested \(entry.name). Accept the incoming transfer to save it."
    }

    func thumbnail(_ entry: PhoneStorageEntry) {
        guard let phoneID, !entry.isDirectory, entry.mime.hasPrefix("image/") || entry.mime.hasPrefix("video/"),
              thumbnailRequests.insert(entry.id).inserted else { return }
        send?(phoneID, ControlPacket(type: "browseThumbnail", payload: .object(["entry": .string(entry.id)])))
    }

    func receive(_ packet: ControlPacket, phoneID: String) {
        if folderDownloads.receive(packet, phoneID: phoneID) { return }
        guard self.phoneID == phoneID else { return }
        if packet.type == "browseThumbnail" {
            guard let id = packet.payload["entry"].string, thumbnailRequests.contains(id),
                  let encoded = packet.payload["image"].string, encoded.count < 80_000,
                  let data = Data(base64Encoded: encoded),
                  let source = CGImageSourceCreateWithData(data as CFData, nil),
                  let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
                  let width = properties[kCGImagePropertyPixelWidth] as? Int, width > 0, width <= 512,
                  let height = properties[kCGImagePropertyPixelHeight] as? Int, height > 0, height <= 512,
                  let image = NSImage(data: data) else { return }
            if thumbnails.count >= 200, let oldest = thumbnails.keys.first { thumbnails.removeValue(forKey: oldest) }
            thumbnails[id] = image
            return
        }
        guard packet.id == requestID else { return }
        isLoading = false
        if packet.type == "browseError" { message = packet.payload["message"].string ?? "Storage unavailable"; return }
        let page = PhoneStorageEntry.decode(packet.payload["entries"])
        if appendResults { entries.append(contentsOf: page) } else { entries = page }
        nextOffset = Int(packet.payload["nextOffset"].number ?? -1)
        message = entries.isEmpty ? "No files here. Check storage access on the phone." : "\(entries.count) items"
    }

    func disconnected(phoneID: String) {
        folderDownloads.disconnected(phoneID: phoneID)
        supportedPhones.remove(phoneID)
        guard self.phoneID == phoneID else { return }
        requestID = nil
        isLoading = false
        entries = []
        thumbnails = [:]
        thumbnailRequests = []
        message = "Phone disconnected. Reconnect and refresh."
    }
}
