import Testing
@testable import SeamlessCore

struct PhoneCallStateTests {
    @Test func callWaitingCannotBeAnsweredAsAnIdleIncomingCall() {
        var state = PhoneCallState()
        state.isConnected = true
        state.setupMode = 1
        #expect(state.canAnswer)
        state.isActive = true
        #expect(!state.canAnswer)
        #expect(state.title == "Call in progress")
        state.disconnect()
        #expect(!state.hasCall)
        #expect(!state.canAnswer)
    }

    @Test func dialingRejectsControlAndSupplementaryServiceStrings() {
        #expect(PhoneCallState.dialNumber("+1 (202) 555-0123") == "+12025550123")
        for invalid in ["+", "12\nATH", "123;456", "**21*123#", "1+23", "１２３"] {
            #expect(PhoneCallState.dialNumber(invalid) == nil)
        }
        #expect(PhoneCallState.normalizedBluetoothAddress("aa:bb:cc:11:22:33") == "AABBCC112233")
        #expect(PhoneCallState.normalizedBluetoothAddress("not a device") == nil)
    }
}
