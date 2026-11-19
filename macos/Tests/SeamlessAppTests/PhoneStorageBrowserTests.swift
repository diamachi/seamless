import Testing
import SeamlessCore
@testable import SeamlessApp

@MainActor
struct PhoneStorageBrowserTests {
    @Test func refreshAfterLateCapabilityUsesSelectedPhone() {
        let browser = PhoneStorageBrowser()
        var requestedPhone: String?
        browser.send = { phoneID, _ in requestedPhone = phoneID }
        browser.load(phoneID: "test-phone", media: false)
        #expect(requestedPhone == nil)
        browser.supportedPhones.insert("test-phone")
        browser.refresh()
        #expect(requestedPhone == "test-phone")
        #expect(browser.isLoading)
        browser.disconnected(phoneID: "test-phone")
    }

    @Test func reconnectRefreshStartsAtRoot() {
        let browser = PhoneStorageBrowser()
        browser.supportedPhones.insert("test-phone")
        var request: ControlPacket?
        browser.send = { _, packet in request = packet }
        browser.load(phoneID: "test-phone", media: false)
        browser.open(PhoneStorageEntry(id: "expired-folder", name: "Folder", mime: "", isDirectory: true, size: 0))
        browser.disconnected(phoneID: "test-phone")
        browser.supportedPhones.insert("test-phone")
        browser.refresh()
        #expect(request?.payload["directory"].string == "")
        browser.disconnected(phoneID: "test-phone")
    }
}
