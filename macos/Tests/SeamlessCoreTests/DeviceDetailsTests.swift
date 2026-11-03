import Testing
@testable import SeamlessCore

struct DeviceDetailsTests {
    @Test
    func olderPhoneStatusHasSafeUnavailableDetails() {
        let details = DeviceDetails(payload: .null)
        #expect(details.operatingSystemName == "Android")
        #expect(details.processorName == nil)
        #expect(details.storageTotalBytes == nil)
    }

    @Test
    func rejectsImpossibleOrUnboundedHardwareValues() {
        let details = DeviceDetails(payload: .object([
            "processorName": .string(String(repeating: "x", count: 300)),
            "ramTotalBytes": .number(-1), "storageTotalBytes": .number(100), "storageUsedBytes": .number(101)
        ]))
        #expect(details.processorName?.count == 120)
        #expect(details.ramTotalBytes == nil)
        #expect(details.storageUsedBytes == nil)
        let empty = DeviceDetails(payload: .object(["storageTotalBytes": .number(0)]))
        #expect(empty.storageTotalBytes == nil)
    }
}
