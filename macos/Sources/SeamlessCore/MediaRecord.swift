// Shared protocol/model rules for media record.
// See docs/ARCHITECTURE.md for the owning subsystem and cross-platform call flow.

import Foundation

public struct MediaRecord: Sendable {
    public let kind: UInt8
    public let presentationTimeMicroseconds: Int64
    public let data: Data
}

public struct MediaRecordDecoder: Sendable {
    private var bufferedData = Data()
    /// Constructs MediaRecord with the dependencies and initial values supplied by its caller.
    public init() {}

    /// Performs append for media record.
    public mutating func append(_ data: Data) throws -> [MediaRecord] {
        guard data.count <= 65_536 else { throw ConnectionProtocolError.oversizedMessage }
        bufferedData.append(data)
        var records: [MediaRecord] = []
        while bufferedData.count >= 13 {
            let header = Array(bufferedData.prefix(13))
            let size = Int(header[1]) << 24 | Int(header[2]) << 16 | Int(header[3]) << 8 | Int(header[4])
            guard header[0] <= 2, size <= 4 * 1024 * 1024,
                  header[0] != 0 || size <= 65_536 else { throw ConnectionProtocolError.invalidMessage }
            guard bufferedData.count >= size + 13 else { break }
            var timestamp: UInt64 = 0
            for byte in header[5..<13] { timestamp = timestamp << 8 | UInt64(byte) }
            guard timestamp <= UInt64(Int64.max) else { throw ConnectionProtocolError.invalidMessage }
            let payload = Data(bufferedData.dropFirst(13).prefix(size))
            records.append(MediaRecord(kind: header[0], presentationTimeMicroseconds: Int64(timestamp), data: payload))
            bufferedData.removeFirst(size + 13)
        }
        guard bufferedData.count <= 4 * 1024 * 1024 + 13 else { throw ConnectionProtocolError.oversizedMessage }
        return records
    }
}

public enum H264ByteStream {
    /// Splits an Annex B H.264 byte stream at valid start-code boundaries.
    public static func nalUnits(in data: Data) -> [Data] {
        let bytes = Array(data)
        var starts: [(offset: Int, length: Int)] = []
        var position = 0
        while position + 2 < bytes.count {
            if bytes[position] == 0 && bytes[position + 1] == 0 {
                if bytes[position + 2] == 1 {
                    starts.append((position, 3))
                    position += 3
                    continue
                }
                if position + 3 < bytes.count && bytes[position + 2] == 0 && bytes[position + 3] == 1 {
                    starts.append((position, 4))
                    position += 4
                    continue
                }
            }
            position += 1
        }
        var units: [Data] = []
        for index in starts.indices {
            let begin = starts[index].offset + starts[index].length
            let end = index + 1 < starts.count ? starts[index + 1].offset : bytes.count
            if begin < end { units.append(Data(bytes[begin..<end])) }
        }
        return units
    }

    /// Converts H.264 NAL units into the length-prefixed representation expected by the decoder.
    public static func lengthPrefixed(_ data: Data) throws -> Data {
        let units = nalUnits(in: data)
        guard !units.isEmpty else { throw ConnectionProtocolError.invalidMessage }
        var result = Data()
        for unit in units {
            var size = UInt32(unit.count).bigEndian
            withUnsafeBytes(of: &size) { result.append(contentsOf: $0) }
            result.append(unit)
        }
        return result
    }
}
