import Testing
@testable import SeamlessCore

struct AndroidDebugBridgePlanTests {
    @Test func deviceListKeepsAuthorizationAndTransportSeparate() {
        let devices = AndroidDebugDevice.parseList("""
        List of devices attached
        TESTDEVICE123 device usb:1-2 product:spacewar model:Test_Phone transport_id:1
        OTHER123 unauthorized usb:1-3 transport_id:2
        192.0.2.2:5555 device model:Wireless_Phone transport_id:3
        * daemon started successfully
        """)
        #expect(devices.count == 3)
        #expect(devices[0].model == "Test Phone")
        #expect(devices[0].isUSB)
        #expect(devices[1].state == "unauthorized")
        #expect(!devices[2].isUSB)
    }

    @Test func plansRejectDeviceAndPackageInjection() throws {
        #expect(throws: AndroidDebugBridgePlan.PlanError.self) {
            try AndroidDebugBridgePlan.forward(serial: "--tcpip", remotePort: 48763)
        }
        #expect(throws: AndroidDebugBridgePlan.PlanError.self) {
            try AndroidDebugBridgePlan.validatePackageName("com.example;reboot")
        }
        try AndroidDebugBridgePlan.validatePackageName("com.example.app")
        #expect(try AndroidDebugBridgePlan.removeForward(serial: "TESTDEVICE123", localPort: 54321) == ["-s", "TESTDEVICE123", "forward", "--remove", "tcp:54321"])
    }
}
