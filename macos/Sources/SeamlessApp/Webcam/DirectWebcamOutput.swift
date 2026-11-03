import AppKit
@preconcurrency import CoreMedia
@preconcurrency import CoreVideo
import Foundation
@preconcurrency import VideoToolbox

private struct WebcamSample: @unchecked Sendable {
    let value: CMSampleBuffer
}

private struct WebcamImage: @unchecked Sendable {
    let value: CVPixelBuffer
}

// All codec/driver state stays on worker; the lock protects only admission/backpressure.
private final class WebcamFramePipeline: @unchecked Sendable {
    private let worker = DispatchQueue(label: "dev.seamless.webcam.frames", qos: .userInteractive)
    private let lock = NSLock()
    private var enabled = false
    private var queuedFrames = 0
    private var awaitingKeyFrame = true
    private let sink = OBSCameraSink()
    private var decoder: VTDecompressionSession?
    private var currentFormat: CMVideoFormatDescription?
    private var generation = UUID()
    private var enqueuedFrameCount = 0
    private var lastReport = Date.distantPast
    var report: (@Sendable (String, Bool) -> Void)?

    func start() {
        worker.async { [self] in
            do {
                try sink.start()
                generation = UUID()
                enqueuedFrameCount = 0
                lock.withLock { enabled = true; awaitingKeyFrame = true }
                report?("Webcam ready. Choose OBS Virtual Camera in your camera app. OBS can stay closed.", true)
            } catch {
                sink.stop()
                report?(error.localizedDescription, false)
            }
        }
    }

    func stop() {
        lock.withLock { enabled = false }
        worker.async { [self] in
            lock.withLock { enabled = false }
            generation = UUID()
            invalidateDecoder()
            sink.stop()
            report?("System webcam stopped.", false)
        }
    }

    func submit(_ sample: CMSampleBuffer, isKeyFrame: Bool) {
        let accepted = lock.withLock {
            if !enabled { return false }
            if queuedFrames >= 4 {
                awaitingKeyFrame = true
                return false
            }
            if awaitingKeyFrame && !isKeyFrame { return false }
            if isKeyFrame { awaitingKeyFrame = false }
            queuedFrames += 1
            return true
        }
        guard accepted else { return }
        let wrapped = WebcamSample(value: sample)
        worker.async { [self] in
            defer { lock.withLock { queuedFrames -= 1 } }
            guard lock.withLock({ enabled }) else { return }
            do {
                try decode(wrapped.value)
            } catch {
                lock.withLock { enabled = false }
                invalidateDecoder()
                sink.stop()
                report?(error.localizedDescription, false)
            }
        }
    }

    private func decode(_ sample: CMSampleBuffer) throws {
        guard let format = CMSampleBufferGetFormatDescription(sample) else { return }
        if currentFormat == nil || !CMFormatDescriptionEqual(currentFormat!, otherFormatDescription: format) {
            invalidateDecoder()
            let attributes: [String: Any] = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                                             kCVPixelBufferIOSurfacePropertiesKey as String: [:]]
            let specification: [String: Any] = [kVTVideoDecoderSpecification_EnableHardwareAcceleratedVideoDecoder as String: true]
            let result = VTDecompressionSessionCreate(allocator: nil, formatDescription: format,
                decoderSpecification: specification as CFDictionary, imageBufferAttributes: attributes as CFDictionary,
                outputCallback: nil, decompressionSessionOut: &decoder)
            guard result == noErr else { throw WebcamOutputError(description: "Webcam decoder could not start (\(result)).") }
            currentFormat = format
            if let decoder { _ = VTSessionSetProperty(decoder, key: kVTDecompressionPropertyKey_RealTime, value: kCFBooleanTrue) }
        }
        guard let decoder else { return }
        let expectedGeneration = generation
        let result = VTDecompressionSessionDecodeFrame(decoder, sampleBuffer: sample, flags: [], infoFlagsOut: nil) { [weak self] status, _, image, _, _ in
            guard status == noErr, let image, let self else { return }
            let wrapped = WebcamImage(value: image)
            self.worker.async { [self] in
                guard generation == expectedGeneration, lock.withLock({ enabled }) else { return }
                do {
                    if try sink.write(wrapped.value) { enqueuedFrameCount += 1 }
                    if Date().timeIntervalSince(lastReport) >= 1 {
                        lastReport = Date()
                        report?("OBS Virtual Camera · \(enqueuedFrameCount) frames sent to driver · OBS app can stay closed", true)
                    }
                } catch {
                    lock.withLock { enabled = false }
                    sink.stop()
                    report?(error.localizedDescription, false)
                }
            }
        }
        if result != noErr { throw WebcamOutputError(description: "Webcam decoding failed (\(result)).") }
    }

    private func invalidateDecoder() {
        if let decoder { VTDecompressionSessionInvalidate(decoder) }
        decoder = nil
        currentFormat = nil
    }
}

@MainActor
final class DirectWebcamOutput: ObservableObject {
    @Published private(set) var isActive = false
    @Published private(set) var isStarting = false
    @Published private(set) var message = "Use the installed OBS camera driver directly, with OBS closed."
    private let pipeline = WebcamFramePipeline()

    init() {
        pipeline.report = { [weak self] message, active in
            Task { @MainActor in
                self?.isStarting = false
                self?.isActive = active
                self?.message = message
            }
        }
    }

    func start() {
        guard !isStarting, !isActive else { return }
        guard NSRunningApplication.runningApplications(withBundleIdentifier: "com.obsproject.obs-studio").isEmpty else {
            message = "Quit OBS first so only Seamless writes to its virtual camera."
            return
        }
        isStarting = true
        pipeline.start()
    }

    func stop() {
        isActive = false
        pipeline.stop()
    }

    func submit(_ sample: CMSampleBuffer, isKeyFrame: Bool) {
        if isActive { pipeline.submit(sample, isKeyFrame: isKeyFrame) }
    }
}
