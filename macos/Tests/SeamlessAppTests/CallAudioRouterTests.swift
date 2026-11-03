import Testing
@testable import SeamlessApp

@MainActor
struct CallAudioRouterTests {
    @Test func feedbackEndpointIsRejectedBeforeMicrophonePermissionOrDeviceOpen() async {
        let router = CallAudioRouter()
        let phone = CallAudioDevice(id: 100, uid: "test-phone", name: "Test phone", hasInput: true, hasOutput: true, isBluetooth: true)
        let speaker = CallAudioDevice(id: 101, uid: "test-speaker", name: "Test speaker", hasInput: false, hasOutput: true, isBluetooth: false)
        await router.start(microphone: phone, speaker: speaker, phoneInput: phone, phoneOutput: phone)
        #expect(!router.isRunning)
        #expect(!router.isStarting)
        #expect(router.message.contains("distinct from the phone"))
    }
}
