import Foundation
import Testing
import SeamlessCore
@testable import SeamlessApp

@MainActor
struct FileTransferLifecycleTests {
    @Test
    func onePhoneCannotCancelAnotherPhonesOffer() {
        let transfers = FileTransfers()
        transfers.receive(offer(id: "incoming-1"), phoneID: "phone-a")
        transfers.receive(ControlPacket(type: "fileCancel", payload: .object(["transferID": .string("incoming-1")])), phoneID: "phone-b")
        #expect(transfers.offers.count == 1)
        transfers.receive(ControlPacket(type: "fileCancel", payload: .object(["transferID": .string("incoming-1")])), phoneID: "phone-a")
        #expect(transfers.offers.isEmpty)
    }

    @Test
    func unacceptedOfferExpiresAndNotifiesItsOriginalPhone() async throws {
        let transfers = FileTransfers(transferTimeout: .milliseconds(20))
        var cancellationPhoneID: String?
        transfers.send = { phoneID, packet in
            if packet.type == "fileCancel" { cancellationPhoneID = phoneID }
        }
        transfers.receive(offer(id: "incoming-2"), phoneID: "phone-a")
        try await Task.sleep(for: .milliseconds(200))
        #expect(transfers.offers.isEmpty)
        #expect(cancellationPhoneID == "phone-a")
    }

    @Test
    func cancellingAnOutgoingFileReleasesItsMemoryAndRejectsLateAcceptance() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data("Seamless test".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let transfers = FileTransfers()
        var packets: [String] = []
        transfers.send = { _, packet in packets.append(packet.type) }
        transfers.offer(url: url, phoneID: "phone-a")
        let activity = try #require(transfers.activities.first)
        transfers.cancelTransfer(activity)
        #expect(transfers.activities.isEmpty)
        transfers.receive(ControlPacket(type: "fileAccept", payload: .object(["transferID": .string(activity.id)])), phoneID: "phone-a")
        #expect(!packets.contains("fileChunk"))
        #expect(packets.contains("fileCancel"))
    }

    private func offer(id: String) -> ControlPacket {
        ControlPacket(type: "fileOffer", payload: .object([
            "transferID": .string(id), "name": .string("fixture.txt"), "size": .number(0),
            "sha256": .string(String(repeating: "a", count: 64))
        ]))
    }
}
