@preconcurrency import AVFoundation
import AudioToolbox
import CoreAudio
import Foundation

struct CallAudioFailure: LocalizedError {
    let description: String
    var errorDescription: String? { description }
}

// A pipe has its own capture unit and playback engine: input and output may use different clocks/devices.
final class CallAudioPipe: @unchecked Sendable {
    private let worker = DispatchQueue(label: "dev.seamless.calls.audio", qos: .userInteractive)
    private let admission = NSLock()
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private var capture: AudioUnit?
    private var captureFormat: AVAudioFormat?
    private var running = false
    private var queuedBuffers = 0
    private var muted = false
    private var generation = UUID()

    func setMuted(_ muted: Bool) {
        admission.withLock { self.muted = muted }
        worker.async { [self] in
            if muted { player.volume = 0 }
            else { player.volume = 1 }
        }
    }

    func start(input: AudioDeviceID, output: AudioDeviceID) throws {
        try worker.sync {
            do {
                let format = try makeCapture(device: input)
                try engine.outputNode.auAudioUnit.setDeviceID(output)
                engine.attach(player)
                engine.connect(player, to: engine.mainMixerNode, format: format)
                try engine.start()
                player.play()
                admission.withLock { running = true; generation = UUID() }
                try check(AudioOutputUnitStart(capture!), operation: "Start audio input")
            } catch {
                stopOnWorker()
                throw error
            }
        }
    }

    func stop() { worker.sync { stopOnWorker() } }

    private func makeCapture(device: AudioDeviceID) throws -> AVAudioFormat {
        var componentDescription = AudioComponentDescription(componentType: kAudioUnitType_Output,
            componentSubType: kAudioUnitSubType_HALOutput, componentManufacturer: kAudioUnitManufacturer_Apple,
            componentFlags: 0, componentFlagsMask: 0)
        guard let component = AudioComponentFindNext(nil, &componentDescription) else {
            throw CallAudioFailure(description: "The Mac audio input component is unavailable.")
        }
        try check(AudioComponentInstanceNew(component, &capture), operation: "Create audio input")
        var enabled: UInt32 = 1
        var disabled: UInt32 = 0
        try setProperty(kAudioOutputUnitProperty_EnableIO, scope: kAudioUnitScope_Input, element: 1, value: &enabled)
        try setProperty(kAudioOutputUnitProperty_EnableIO, scope: kAudioUnitScope_Output, element: 0, value: &disabled)
        var identifier = device
        try setProperty(kAudioOutputUnitProperty_CurrentDevice, scope: kAudioUnitScope_Global, element: 0, value: &identifier)
        let format = try readCaptureFormat()
        captureFormat = format
        var streamDescription = format.streamDescription.pointee
        try setProperty(kAudioUnitProperty_StreamFormat, scope: kAudioUnitScope_Output, element: 1, value: &streamDescription)
        var callback = AURenderCallbackStruct(inputProc: { context, flags, timestamp, _, frameCount, _ in
            return Unmanaged<CallAudioPipe>.fromOpaque(context).takeUnretainedValue()
                .captureFrames(flags: flags, timestamp: timestamp, count: frameCount)
        }, inputProcRefCon: Unmanaged.passUnretained(self).toOpaque())
        try setProperty(kAudioOutputUnitProperty_SetInputCallback, scope: kAudioUnitScope_Global, element: 0, value: &callback)
        try check(AudioUnitInitialize(capture!), operation: "Initialize audio input")
        return format
    }

    private func readCaptureFormat() throws -> AVAudioFormat {
        var hardware = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout.size(ofValue: hardware))
        try check(AudioUnitGetProperty(capture!, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, 1, &hardware, &size), operation: "Read audio format")
        guard hardware.mSampleRate >= 8000, hardware.mSampleRate <= 192000,
              hardware.mChannelsPerFrame > 0, hardware.mChannelsPerFrame <= 8,
              let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: hardware.mSampleRate,
                  channels: hardware.mChannelsPerFrame, interleaved: false) else {
            throw CallAudioFailure(description: "This audio device uses an unsupported voice format.")
        }
        return format
    }

    private func captureFrames(flags: UnsafeMutablePointer<AudioUnitRenderActionFlags>, timestamp: UnsafePointer<AudioTimeStamp>, count: UInt32) -> OSStatus {
        guard admission.try() else { return noErr }
        let accepted = running && !muted && queuedBuffers < 4 && count <= 8192
        let expected = generation
        if accepted { queuedBuffers += 1 }
        admission.unlock()
        guard accepted, let capture, let format = captureFormat else { return noErr }
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: count) else {
            releaseBuffer()
            return noErr
        }
        buffer.frameLength = count
        let result = AudioUnitRender(capture, flags, timestamp, 1, count, buffer.mutableAudioBufferList)
        guard result == noErr else { releaseBuffer(); return result }
        worker.async { [self] in
            guard admission.withLock({ running && generation == expected && !muted }) else { releaseBuffer(); return }
            player.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { [weak self] _ in self?.releaseBuffer() }
        }
        return noErr
    }

    private func releaseBuffer() { admission.withLock { queuedBuffers = max(0, queuedBuffers - 1) } }

    private func stopOnWorker() {
        admission.withLock { running = false; generation = UUID() }
        if let capture {
            AudioOutputUnitStop(capture)
            AudioUnitUninitialize(capture)
            AudioComponentInstanceDispose(capture)
        }
        capture = nil
        captureFormat = nil
        player.stop()
        engine.stop()
    }

    private func setProperty<T>(_ property: AudioUnitPropertyID, scope: AudioUnitScope, element: AudioUnitElement, value: inout T) throws {
        try withUnsafePointer(to: &value) { pointer in
            try check(AudioUnitSetProperty(capture!, property, scope, element, pointer, UInt32(MemoryLayout<T>.size)), operation: "Configure audio device")
        }
    }

    private func check(_ status: OSStatus, operation: String) throws {
        if status != noErr { throw CallAudioFailure(description: "\(operation) failed (\(status)). Return audio to the phone and check the selected devices.") }
    }
}
