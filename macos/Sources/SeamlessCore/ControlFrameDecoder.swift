import Foundation

public struct ControlFrameDecoder: Sendable {
    private var bufferedData = Data()
    public static let maximumFrameBytes = 262_144

    public init() {}

    public mutating func append(_ data: Data) throws -> [ControlPacket] {
        guard data.count <= 65_536 else { throw ConnectionProtocolError.oversizedMessage }
        bufferedData.append(data)
        var packets: [ControlPacket] = []
        while let newline = bufferedData.firstIndex(of: 10) {
            let frame = bufferedData[..<newline]
            guard frame.count < Self.maximumFrameBytes else { throw ConnectionProtocolError.oversizedMessage }
            let packet = try JSONDecoder().decode(ControlPacket.self, from: frame)
            guard packet.version == 1, !packet.id.isEmpty, packet.id.count <= 128 else {
                throw ConnectionProtocolError.invalidMessage
            }
            packets.append(packet)
            bufferedData.removeSubrange(...newline)
        }
        guard bufferedData.count < Self.maximumFrameBytes else { throw ConnectionProtocolError.oversizedMessage }
        return packets
    }
}
