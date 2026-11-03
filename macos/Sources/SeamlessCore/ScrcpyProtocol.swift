import Foundation

public enum ScrcpyVideoEvent: Sendable {
    case dimensions(width: Int, height: Int)
    case record(MediaRecord)
}

// This adapter intentionally supports the version-pinned scrcpy 5.0.1 server protocol.
public struct ScrcpyVideoDecoder: Sendable {
    private var buffer = Data()
    private var hasMetadata = false
    private var width = 1
    private var height = 1
    public init() {}

    public mutating func append(_ data: Data) throws -> [ScrcpyVideoEvent] {
        guard data.count <= 65_536 else { throw ConnectionProtocolError.oversizedMessage }
        buffer.append(data)
        if !hasMetadata {
            guard buffer.count >= 68 else { return [] }
            guard readInteger(offset: 64, count: 4) == 0x68323634 else { throw ConnectionProtocolError.invalidMessage }
            buffer.removeFirst(68)
            hasMetadata = true
        }
        var events: [ScrcpyVideoEvent] = []
        while buffer.count >= 12 {
            let header = readInteger(offset: 0, count: 8)
            if header & (1 << 63) != 0 {
                width = Int(readInteger(offset: 4, count: 4))
                height = Int(readInteger(offset: 8, count: 4))
                guard width > 0, height > 0, width <= 4096, height <= 4096 else { throw ConnectionProtocolError.invalidMessage }
                buffer.removeFirst(12)
                events.append(.dimensions(width: width, height: height))
                continue
            }
            let size = Int(readInteger(offset: 8, count: 4))
            let isConfiguration = header & (1 << 62) != 0
            let isKeyFrame = header & (1 << 61) != 0
            guard size > 0, size <= 4 * 1024 * 1024, !isConfiguration || size <= 65_536 else { throw ConnectionProtocolError.invalidMessage }
            guard buffer.count >= size + 12 else { break }
            let payload = Data(buffer.dropFirst(12).prefix(size))
            buffer.removeFirst(size + 12)
            if isConfiguration {
                let configuration: JSONValue = .object(["width": .number(Double(width)), "height": .number(Double(height)),
                                                        "csd-0": .string(payload.base64EncodedString())])
                events.append(.record(MediaRecord(kind: 0, presentationTimeMicroseconds: 0, data: try JSONEncoder().encode(configuration))))
            } else {
                let timestamp = Int64(header & ((1 << 61) - 1))
                events.append(.record(MediaRecord(kind: isKeyFrame ? 2 : 1, presentationTimeMicroseconds: timestamp, data: payload)))
            }
        }
        guard buffer.count <= 4 * 1024 * 1024 + 12 else { throw ConnectionProtocolError.oversizedMessage }
        return events
    }

    private func readInteger(offset: Int, count: Int) -> UInt64 {
        var value: UInt64 = 0
        for byte in buffer.dropFirst(offset).prefix(count) { value = value << 8 | UInt64(byte) }
        return value
    }
}

public enum ScrcpyControlMessage {
    public static func startApp(packageName: String) throws -> Data {
        // Reuse the launch-plan validator before a package reaches the shell-backed server.
        try AndroidDebugBridgePlan.validatePackageName(packageName)
        let bytes = Data(packageName.utf8)
        return Data([16, UInt8(bytes.count)]) + bytes
    }

    public static func key(code: UInt32, isDown: Bool) -> Data {
        var data = Data([0, isDown ? 0 : 1])
        append(code, to: &data)
        append(UInt32(0), to: &data)
        append(UInt32(0), to: &data)
        return data
    }

    public static func touch(action: UInt8, x: Double, y: Double, width: Int, height: Int) throws -> Data {
        guard [0, 1, 2].contains(action), x.isFinite, y.isFinite, (1...4096).contains(width), (1...4096).contains(height) else { throw ConnectionProtocolError.invalidMessage }
        var data = Data([2, action])
        append(UInt64.max - 1, to: &data)
        append(UInt32(max(0, min(width - 1, Int(max(0, min(1, x)) * Double(width))))), to: &data)
        append(UInt32(max(0, min(height - 1, Int(max(0, min(1, y)) * Double(height))))), to: &data)
        append(UInt16(width), to: &data)
        append(UInt16(height), to: &data)
        append(action == 1 ? UInt16(0) : UInt16.max, to: &data)
        append(UInt32(0), to: &data)
        append(UInt32(0), to: &data)
        return data
    }

    public static func text(_ text: String) -> Data {
        var bytes = Data()
        for character in text {
            let encoded = Data(String(character).utf8)
            if bytes.count + encoded.count > 300 { break }
            bytes.append(encoded)
        }
        var data = Data([1])
        append(UInt32(bytes.count), to: &data)
        data.append(bytes)
        return data
    }

    private static func append<Value: FixedWidthInteger>(_ value: Value, to data: inout Data) {
        var encoded = value.bigEndian
        withUnsafeBytes(of: &encoded) { data.append(contentsOf: $0) }
    }
}
