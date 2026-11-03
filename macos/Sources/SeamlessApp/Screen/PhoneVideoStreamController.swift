import AVFoundation
import CoreMedia
import Foundation
import SwiftUI
import SeamlessCore

enum VideoStreamPurpose: String { case screen, camera }

@MainActor
final class PhoneVideoStreamController: ObservableObject {
    @Published private(set) var message: String
    @Published private(set) var receivedFramesPerSecond = 0.0
    @Published private(set) var isStreaming = false
    @Published private(set) var encoderName = ""
    let displayLayer = AVSampleBufferDisplayLayer()
    let webcamOutput = DirectWebcamOutput()
    var send: ((String, ControlPacket) -> Void)?
    private let media = PhoneMediaClient()
    private var phoneID: String?
    private var externalStop: (() -> Void)?
    private var externalInput: ((String, [String: Double], String) -> Void)?
    private var formatDescription: CMVideoFormatDescription?
    private var waitingForKeyFrame = true
    private var frameCounter = 0
    private var intervalStart = Date()
    private var statisticsTimer: Timer?
    @Published var isDetached = false
    @Published private(set) var videoSize = CGSize(width: 1, height: 1)
    let purpose: VideoStreamPurpose
    var sourcePhoneID: String? { phoneID }

    init(purpose: VideoStreamPurpose = .screen) {
        self.purpose = purpose
        if purpose == .camera {
            message = "Choose a quality profile, then request your phone camera."
        } else {
            message = "Request screen sharing, then approve it on your phone."
        }
        displayLayer.videoGravity = .resizeAspect
        media.onRecord = { [weak self] record in try self?.receive(record) }
        media.onFailure = { [weak self] error in
            self?.stop()
            self?.message = error
        }
    }

    func request(phoneID: String, framesPerSecond: Int, application: PhoneApplication? = nil) {
        stop()
        self.phoneID = phoneID
        send?(phoneID, ControlPacket(type: "screenRequest", payload: .object(["captureEntireDisplay": .bool(application == nil), "framesPerSecond": .number(Double(framesPerSecond)), "applicationName": .string(application?.name ?? ""), "applicationPackage": .string(application?.identity.packageName ?? "")])))
        message = "On your phone, tap Approve screen sharing and confirm Android's sharing prompt."
    }

    func requestCamera(phoneID: String, preferences: CameraPreferences) {
        stop()
        self.phoneID = phoneID
        send?(phoneID, ControlPacket(type: "cameraRequest", payload: .object([
            "facing": .string(preferences.facing.rawValue), "resolutionHeight": .number(Double(preferences.resolutionHeight)),
            "framesPerSecond": .number(Double(preferences.framesPerSecond)),
            "exposureEV": .number(preferences.exposureEV), "zoom": .number(preferences.zoom),
            "torch": .bool(preferences.torch), "whiteBalance": .string(preferences.whiteBalance)
        ])))
        message = "On the phone, approve camera sharing."
    }

    func updateCameraControls(phoneID: String, preferences: CameraPreferences) {
        guard purpose == .camera, isStreaming, self.phoneID == phoneID else { return }
        send?(phoneID, ControlPacket(type: "cameraControls", payload: .object([
            "exposureEV": .number(preferences.exposureEV), "zoom": .number(preferences.zoom),
            "torch": .bool(preferences.torch), "whiteBalance": .string(preferences.whiteBalance)
        ])))
    }

    func acceptGrant(phoneID: String, profile: ConnectionProfile, macID: String, credential: String, token: String) {
        guard self.phoneID == phoneID else { return }
        do {
            try media.connect(profile: profile, authentication: ControlPacket(type: "mediaAuthenticate", payload: .object([
                "macID": .string(macID), "credential": .string(credential), "token": .string(token)
            ])))
            intervalStart = Date()
            frameCounter = 0
            statisticsTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.publishStatistics() }
            }
        } catch { message = error.localizedDescription }
    }

    func stop() {
        let stopExternal = externalStop
        externalStop = nil
        externalInput = nil
        let previousPhoneID = phoneID
        phoneID = nil
        if let stopExternal { stopExternal() }
        else if let previousPhoneID { send?(previousPhoneID, ControlPacket(type: purpose.rawValue + "Stop")) }
        media.disconnect()
        statisticsTimer?.invalidate()
        statisticsTimer = nil
        displayLayer.flushAndRemoveImage()
        if purpose == .camera { webcamOutput.stop() }
        formatDescription = nil
        waitingForKeyFrame = true
        isStreaming = false
        receivedFramesPerSecond = 0
        encoderName = ""
        message = "Video sharing stopped."
    }

    func ended(phoneID: String) {
        if self.phoneID == phoneID { stop() }
    }

    func reportError(phoneID: String, description: String) {
        guard self.phoneID == phoneID else { return }
        stop()
        message = description
    }

    var supportsContinuousTouch: Bool { externalInput != nil }

    func input(kind: String, coordinates: [String: Double] = [:], text: String = "") {
        guard purpose == .screen, isStreaming, let phoneID else { return }
        if let externalInput { externalInput(kind, coordinates, text); return }
        var payload: [String: JSONValue] = [
            "kind": .string(kind), "text": .string(String(text.prefix(4000))),
            "expiresAt": .number(Date().addingTimeInterval(10).timeIntervalSince1970 * 1000)
        ]
        for (key, value) in coordinates { payload[key] = .number(value) }
        send?(phoneID, ControlPacket(type: "input", payload: .object(payload)))
    }

    func beginExternal(phoneID: String, stop: @escaping () -> Void, input: @escaping (String, [String: Double], String) -> Void) {
        self.stop()
        self.phoneID = phoneID
        externalStop = stop
        externalInput = input
        intervalStart = Date()
        frameCounter = 0
        statisticsTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.publishStatistics() }
        }
        message = "Preparing ADB app sharing…"
    }

    func receiveExternal(_ record: MediaRecord) {
        guard externalInput != nil else { return }
        do { try receive(record) }
        catch { stop(); message = error.localizedDescription }
    }

    private func receive(_ record: MediaRecord) throws {
        if record.kind == 0 {
            try configure(record.data)
            return
        }
        let isKeyFrame = record.kind == 2
        if waitingForKeyFrame && !isKeyFrame { return }
        guard let formatDescription else { return }
        if displayLayer.status == .failed || !displayLayer.isReadyForMoreMediaData {
            displayLayer.flushAndRemoveImage()
            waitingForKeyFrame = true
            if !isKeyFrame { return }
        }
        if isKeyFrame { waitingForKeyFrame = false }
        let bytes = try H264ByteStream.lengthPrefixed(record.data)
        let sample = try makeSample(bytes: bytes, timestamp: record.presentationTimeMicroseconds, format: formatDescription)
        if purpose == .camera { webcamOutput.submit(sample, isKeyFrame: isKeyFrame) }
        displayLayer.enqueue(sample)
        frameCounter += 1
        if !isStreaming {
            isStreaming = true
            message = "Video sharing is active."
        }
    }

    private func configure(_ data: Data) throws {
        let value = try JSONDecoder().decode(JSONValue.self, from: data)
        let reportedEncoder = value["encoder"].string ?? ""
        if encoderName != reportedEncoder { encoderName = reportedEncoder }
        var parameters = Data()
        for key in ["csd-0", "csd-1"] {
            if let text = value[key].string, let bytes = Data(base64Encoded: text) { parameters.append(bytes) }
        }
        let units = H264ByteStream.nalUnits(in: parameters)
        guard let sps = units.first(where: { ($0.first ?? 0) & 31 == 7 }),
              let pps = units.first(where: { ($0.first ?? 0) & 31 == 8 }) else { throw ConnectionProtocolError.invalidMessage }
        var description: CMFormatDescription?
        let status = sps.withUnsafeBytes { spsBytes in
            pps.withUnsafeBytes { ppsBytes in
                let pointers = [spsBytes.baseAddress!.assumingMemoryBound(to: UInt8.self), ppsBytes.baseAddress!.assumingMemoryBound(to: UInt8.self)]
                let sizes = [sps.count, pps.count]
                return pointers.withUnsafeBufferPointer { parameterPointers in
                    sizes.withUnsafeBufferPointer { parameterSizes in
                        CMVideoFormatDescriptionCreateFromH264ParameterSets(allocator: kCFAllocatorDefault,
                            parameterSetCount: 2, parameterSetPointers: parameterPointers.baseAddress!,
                            parameterSetSizes: parameterSizes.baseAddress!, nalUnitHeaderLength: 4, formatDescriptionOut: &description)
                    }
                }
            }
        }
        guard status == noErr, let description else { throw ConnectionProtocolError.invalidMessage }
        formatDescription = description
        let dimensions = CMVideoFormatDescriptionGetDimensions(description)
        guard dimensions.width > 0, dimensions.height > 0, dimensions.width <= 4096, dimensions.height <= 4096 else {
            throw ConnectionProtocolError.invalidMessage
        }
        videoSize = CGSize(width: Int(dimensions.width), height: Int(dimensions.height))
    }

    private func makeSample(bytes: Data, timestamp: Int64, format: CMFormatDescription) throws -> CMSampleBuffer {
        var block: CMBlockBuffer?
        let creation = CMBlockBufferCreateWithMemoryBlock(allocator: kCFAllocatorDefault, memoryBlock: nil,
            blockLength: bytes.count, blockAllocator: kCFAllocatorDefault, customBlockSource: nil,
            offsetToData: 0, dataLength: bytes.count, flags: 0, blockBufferOut: &block)
        guard creation == noErr, let block else { throw ConnectionProtocolError.invalidMessage }
        let copied = bytes.withUnsafeBytes { pointer in
            CMBlockBufferReplaceDataBytes(with: pointer.baseAddress!, blockBuffer: block, offsetIntoDestination: 0, dataLength: bytes.count)
        }
        guard copied == noErr else { throw ConnectionProtocolError.invalidMessage }
        var timing = CMSampleTimingInfo(duration: .invalid, presentationTimeStamp: CMTime(value: timestamp, timescale: 1_000_000), decodeTimeStamp: .invalid)
        var size = bytes.count
        var sample: CMSampleBuffer?
        let result = CMSampleBufferCreateReady(allocator: kCFAllocatorDefault, dataBuffer: block, formatDescription: format,
            sampleCount: 1, sampleTimingEntryCount: 1, sampleTimingArray: &timing,
            sampleSizeEntryCount: 1, sampleSizeArray: &size, sampleBufferOut: &sample)
        guard result == noErr, let sample else { throw ConnectionProtocolError.invalidMessage }
        if let attachments = CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: true) {
            let dictionary = unsafeBitCast(CFArrayGetValueAtIndex(attachments, 0), to: CFMutableDictionary.self)
            CFDictionarySetValue(dictionary, Unmanaged.passUnretained(kCMSampleAttachmentKey_DisplayImmediately).toOpaque(), Unmanaged.passUnretained(kCFBooleanTrue).toOpaque())
        }
        return sample
    }

    private func publishStatistics() {
        let now = Date()
        receivedFramesPerSecond = Double(frameCounter) / max(now.timeIntervalSince(intervalStart), 0.001)
        frameCounter = 0
        intervalStart = now
    }
}
