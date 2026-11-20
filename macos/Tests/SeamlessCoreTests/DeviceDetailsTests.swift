// Tests for DeviceDetailsTests and the behavior owned by its target module.
// Keep assertions focused on externally visible results and failure boundaries.

import Testing
@testable import SeamlessCore

struct DeviceDetailsTests {
    /// Checks older phone status has safe unavailable details by exercising its expected result and a relevant invalid or boundary input.
    @Test
    /// Builds older phone status has safe unavailable details from deterministic test inputs and returns the protocol response.
    func olderPhoneStatusHasSafeUnavailableDetails() {
        let details = DeviceDetails(payload: .null)
        #expect(details.operatingSystemName == "Android")
        #expect(details.processorName == nil)
        #expect(details.storageTotalBytes == nil)
    }
    /// Checks rejects impossible or unbounded hardware values by exercising its expected result and a relevant invalid or boundary input.
    @Test
    /// Builds rejects impossible or unbounded hardware values from deterministic test inputs and returns the protocol response.
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
