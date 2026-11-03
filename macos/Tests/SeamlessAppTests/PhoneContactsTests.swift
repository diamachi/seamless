import Testing
import SeamlessCore
@testable import SeamlessApp

@MainActor
struct PhoneContactsTests {
    @Test func contactsStayScopedToTheRequestAndPhone() throws {
        let store = PhoneContactsStore()
        var request: ControlPacket?
        store.send = { _, packet in request = packet }
        store.load(phoneID: "test-phone")
        defer { store.clear(phoneID: nil) }
        let token = try #require(request?.payload["token"].string)
        let packet = ControlPacket(type: "contactsPage", payload: .object([
            "token": .string(token), "index": .number(0), "last": .bool(true),
            "contacts": .array([.object(["id": .string("1"), "name": .string("Test contact"),
                                         "number": .string("+1 (202) 555-0123")])])
        ]))
        store.receive(packet, phoneID: "other-phone")
        #expect(store.contacts.isEmpty)
        store.receive(packet, phoneID: "test-phone")
        #expect(store.contacts.first?.number == "+12025550123")
        #expect(!store.isLoading)
        store.clear(phoneID: "other-phone")
        #expect(store.contacts.count == 1)
        store.clear(phoneID: "test-phone")
        #expect(store.contacts.isEmpty)
    }
}
