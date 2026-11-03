import Foundation
import Testing
import SeamlessCore
@testable import SeamlessApp

@MainActor
struct FolderDownloadsTests {
    @Test
    func folderListingPreservesStructureAndRejectsOtherPeers() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let downloads = FolderDownloads()
        let transfers = BulkTransfers()
        var listings: [ControlPacket] = []
        var fileRequests: [ControlPacket] = []
        downloads.send = { _, packet in listings.append(packet) }
        transfers.send = { _, packet in fileRequests.append(packet) }
        let folder = PhoneStorageEntry(id: "folder-token", name: "Album", mime: "", isDirectory: true, size: 0)
        downloads.save(entries: [folder], phoneID: "phone-a", bulk: transfers, destinationDirectory: root)
        let request = try #require(listings.first)
        let result = ControlPacket(type: "browseResult", payload: .object([
            "entries": .array([
                entry(id: "file-token", name: "clip.mp4", directory: false),
                entry(id: "child-token", name: "Nested", directory: true),
                entry(id: "unsafe-token", name: "../escape", directory: true)
            ]), "nextOffset": .number(-1)
        ]), id: request.id)
        #expect(!downloads.receive(result, phoneID: "phone-b"))
        #expect(fileRequests.isEmpty)
        #expect(downloads.receive(result, phoneID: "phone-a"))
        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("Album/Nested").path))
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("escape").path))
        #expect(fileRequests.first?.payload["entry"].string == "file-token")
        #expect(listings.last?.payload["directory"].string == "child-token")
        downloads.cancel()
        transfers.disconnected(phoneID: "phone-a")
    }

    private func entry(id: String, name: String, directory: Bool) -> JSONValue {
        .object(["id": .string(id), "name": .string(name), "directory": .bool(directory), "size": .number(1)])
    }
}
