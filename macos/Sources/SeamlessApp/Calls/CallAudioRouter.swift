import AVFoundation
import Combine
import Foundation

@MainActor
final class CallAudioRouter: ObservableObject {
    @Published private(set) var isRunning = false
    @Published private(set) var isStarting = false
    @Published private(set) var message = "Select microphone and speaker before routing a call."
    @Published private(set) var isMuted = false
    private var uplink: CallAudioPipe?
    private var downlink: CallAudioPipe?
    private var generation = UUID()
    private(set) var deviceUIDs: Set<String> = []

    func start(microphone: CallAudioDevice, speaker: CallAudioDevice, phoneInput: CallAudioDevice, phoneOutput: CallAudioDevice) async {
        guard !isStarting else { return }
        stop()
        let phoneDevices = Set([phoneInput.uid, phoneOutput.uid])
        guard !phoneDevices.contains(microphone.uid), !phoneDevices.contains(speaker.uid) else {
            message = "Choose a Mac microphone and speaker distinct from the phone audio endpoint."
            return
        }
        isStarting = true
        let expected = generation
        let permission = await AVCaptureDevice.requestAccess(for: .audio)
        guard generation == expected else { return }
        guard permission else { isStarting = false; message = "Microphone access is needed to send your voice to the phone."; return }
        let uplink = CallAudioPipe()
        let downlink = CallAudioPipe()
        do {
            try await Task.detached(priority: .userInitiated) {
                do {
                    try downlink.start(input: phoneInput.id, output: speaker.id)
                    try uplink.start(input: microphone.id, output: phoneOutput.id)
                } catch {
                    uplink.stop()
                    downlink.stop()
                    throw error
                }
            }.value
            guard generation == expected else { uplink.stop(); downlink.stop(); return }
            self.uplink = uplink
            self.downlink = downlink
            deviceUIDs = Set([microphone.uid, speaker.uid, phoneInput.uid, phoneOutput.uid])
            isStarting = false
            isRunning = true
            isMuted = false
            message = "Selected-device audio bridge running. Verify both directions with your call partner."
        } catch {
            guard generation == expected else { return }
            isStarting = false
            message = error.localizedDescription
        }
    }

    func toggleMute() {
        guard isRunning else { return }
        isMuted.toggle()
        uplink?.setMuted(isMuted)
    }

    func stop(reason: String = "Selected-device audio stopped.") {
        generation = UUID()
        uplink?.stop()
        downlink?.stop()
        uplink = nil
        downlink = nil
        isStarting = false
        isRunning = false
        isMuted = false
        deviceUIDs = []
        message = reason
    }
}
