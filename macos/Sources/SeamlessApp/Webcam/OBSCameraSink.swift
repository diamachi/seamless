import CoreImage
import CoreMedia
import CoreMediaIO
import CoreVideo
import Foundation

struct WebcamOutputError: LocalizedError {
    let description: String
    var errorDescription: String? { description }
}

// Accessed only by WebcamFramePipeline's serial worker.
final class OBSCameraSink {
    private var deviceID: CMIODeviceID = 0
    private var streamID: CMIOStreamID = 0
    private var queue: CMSimpleQueue?
    private var format: CMVideoFormatDescription?
    private var pixelBufferPool: CVPixelBufferPool?
    private let imageContext = CIContext(options: [.cacheIntermediates: false])
    private var outputSize = CGSize(width: 1920, height: 1080)

    func start() throws {
        stop()
        let pluginURL = URL(fileURLWithPath: "/Applications/OBS.app/Contents/PlugIns/mac-virtualcam.plugin/Contents/Info.plist")
        guard let dictionary = NSDictionary(contentsOf: pluginURL), let expectedUID = dictionary["OBSCameraDeviceUUID"] as? String else {
            throw WebcamOutputError(description: "Install the official OBS app and enable its camera extension first.")
        }
        var allowVirtualDevices: UInt32 = 1
        var visibility = address(kCMIOHardwarePropertyAllowScreenCaptureDevices)
        _ = CMIOObjectSetPropertyData(CMIOObjectID(kCMIOObjectSystemObject), &visibility, 0, nil, 4, &allowVirtualDevices)
        for device in try objectIDs(CMIOObjectID(kCMIOObjectSystemObject), selector: kCMIOHardwarePropertyDevices) {
            if try stringProperty(device, selector: kCMIODevicePropertyDeviceUID).caseInsensitiveCompare(expectedUID) == .orderedSame {
                deviceID = device
                break
            }
        }
        guard deviceID != 0 else { throw WebcamOutputError(description: "OBS Virtual Camera is unavailable. Enable its camera extension in macOS Settings.") }
        for stream in try objectIDs(deviceID, selector: kCMIODevicePropertyStreams) {
            var direction: UInt32 = 1
            var property = address(kCMIOStreamPropertyDirection)
            var used: UInt32 = 0
            if CMIOObjectGetPropertyData(stream, &property, 0, nil, 4, &used, &direction) == noErr && direction == 0 {
                streamID = stream
                break
            }
        }
        guard streamID != 0 else { throw WebcamOutputError(description: "The installed OBS driver has no writable camera stream.") }
        var description: CMFormatDescription?
        var property = address(kCMIOStreamPropertyFormatDescription)
        var used: UInt32 = 0
        try check(CMIOObjectGetPropertyData(streamID, &property, 0, nil, UInt32(MemoryLayout<CMFormatDescription?>.size), &used, &description))
        guard let description, CMFormatDescriptionGetMediaSubType(description) == kCVPixelFormatType_32BGRA else {
            throw WebcamOutputError(description: "The installed OBS camera format is unsupported by this adapter.")
        }
        format = description
        let dimensions = CMVideoFormatDescriptionGetDimensions(description)
        guard dimensions.width > 0, dimensions.height > 0, dimensions.width <= 4096, dimensions.height <= 4096 else {
            throw WebcamOutputError(description: "OBS reported invalid camera dimensions.")
        }
        outputSize = CGSize(width: Int(dimensions.width), height: Int(dimensions.height))
        let attributes: [String: Any] = [
            kCVPixelBufferWidthKey as String: dimensions.width,
            kCVPixelBufferHeightKey as String: dimensions.height,
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:],
            kCVPixelBufferMetalCompatibilityKey as String: true
        ]
        try check(CVPixelBufferPoolCreate(nil, nil, attributes as CFDictionary, &pixelBufferPool))
        var retainedQueue: Unmanaged<CMSimpleQueue>?
        try check(CMIOStreamCopyBufferQueue(streamID, { _, _, _ in }, nil, &retainedQueue))
        queue = retainedQueue?.takeRetainedValue()
        try check(CMIODeviceStartStream(deviceID, streamID))
    }

    func write(_ imageBuffer: CVPixelBuffer) throws -> Bool {
        guard let queue, let format, let pixelBufferPool else { return false }
        if CMSimpleQueueGetCount(queue) >= CMSimpleQueueGetCapacity(queue) { return false }
        var destination: CVPixelBuffer?
        let allocation: [String: Any] = [kCVPixelBufferPoolAllocationThresholdKey as String: 4]
        let status = CVPixelBufferPoolCreatePixelBufferWithAuxAttributes(nil, pixelBufferPool, allocation as CFDictionary, &destination)
        if status == kCVReturnWouldExceedAllocationThreshold { return false }
        try check(status)
        guard let destination else { return false }
        let image = CIImage(cvPixelBuffer: imageBuffer)
        let scale = min(outputSize.width / image.extent.width, outputSize.height / image.extent.height)
        let scaled = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let centered = scaled.transformed(by: CGAffineTransform(translationX: (outputSize.width - scaled.extent.width) / 2 - scaled.extent.minX,
                                                                y: (outputSize.height - scaled.extent.height) / 2 - scaled.extent.minY))
        let bounds = CGRect(origin: .zero, size: outputSize)
        let canvas = centered.composited(over: CIImage(color: .black).cropped(to: bounds))
        imageContext.render(canvas, to: destination, bounds: bounds, colorSpace: CGColorSpaceCreateDeviceRGB())
        var timing = CMSampleTimingInfo(duration: CMTime(value: 1, timescale: 60), presentationTimeStamp: CMClockGetTime(CMClockGetHostTimeClock()), decodeTimeStamp: .invalid)
        var sample: CMSampleBuffer?
        try check(CMSampleBufferCreateReadyWithImageBuffer(allocator: nil, imageBuffer: destination, formatDescription: format, sampleTiming: &timing, sampleBufferOut: &sample))
        guard let sample else { return false }
        // CMSimpleQueue does not retain elements. Ownership transfers to the driver's consumer.
        let pointer = Unmanaged.passRetained(sample).toOpaque()
        let result = CMSimpleQueueEnqueue(queue, element: pointer)
        if result != noErr {
            Unmanaged<CMSampleBuffer>.fromOpaque(pointer).release()
            try check(result)
        }
        return true
    }

    func stop() {
        if deviceID != 0 && streamID != 0 { _ = CMIODeviceStopStream(deviceID, streamID) }
        if streamID != 0 {
            var unusedQueue: Unmanaged<CMSimpleQueue>?
            _ = CMIOStreamCopyBufferQueue(streamID, nil, nil, &unusedQueue)
            _ = unusedQueue?.takeRetainedValue()
        }
        if let queue {
            while let pointer = CMSimpleQueueDequeue(queue) {
                Unmanaged<CMSampleBuffer>.fromOpaque(pointer).release()
            }
        }
        queue = nil
        format = nil
        pixelBufferPool = nil
        streamID = 0
        deviceID = 0
    }

    private func address(_ selector: Int) -> CMIOObjectPropertyAddress {
        CMIOObjectPropertyAddress(mSelector: CMIOObjectPropertySelector(selector), mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal), mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain))
    }

    private func objectIDs(_ object: CMIOObjectID, selector: Int) throws -> [CMIOObjectID] {
        var property = address(selector)
        var size: UInt32 = 0
        try check(CMIOObjectGetPropertyDataSize(object, &property, 0, nil, &size))
        guard size <= 65_536, size % 4 == 0 else { throw WebcamOutputError(description: "Invalid camera device list.") }
        var values = [CMIOObjectID](repeating: 0, count: Int(size) / 4)
        var used: UInt32 = 0
        if size > 0 {
            try values.withUnsafeMutableBytes { bytes in
                try check(CMIOObjectGetPropertyData(object, &property, 0, nil, size, &used, bytes.baseAddress!))
            }
        }
        return Array(values.prefix(Int(used) / 4))
    }

    private func stringProperty(_ object: CMIOObjectID, selector: Int) throws -> String {
        var property = address(selector)
        var value: CFString?
        var used: UInt32 = 0
        try check(CMIOObjectGetPropertyData(object, &property, 0, nil, UInt32(MemoryLayout<CFString?>.size), &used, &value))
        return value as String? ?? ""
    }

    private func check(_ status: OSStatus) throws {
        if status != noErr { throw WebcamOutputError(description: "Camera driver operation failed (\(status)).") }
    }
}
