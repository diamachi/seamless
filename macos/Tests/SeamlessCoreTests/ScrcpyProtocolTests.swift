// Tests for ScrcpyProtocolTests and the behavior owned by its target module.
// Keep assertions focused on externally visible results and failure boundaries.

import Foundation
import Testing
@testable import SeamlessCore

struct ScrcpyProtocolTests {
    /// Exercises fragmented version five stream preserves session and frame flags through the expected result and relevant rejection assertions.
    @Test func fragmentedVersionFiveStreamPreservesSessionAndFrameFlags() throws {
        var bytes = Data(repeating: 0, count: 64)
        bytes.append(contentsOf: [0x68, 0x32, 0x36, 0x34])
        bytes.append(contentsOf: [0x80, 0, 0, 0, 0, 0, 4, 56, 0, 0, 7, 128])
        bytes.append(contentsOf: [0x40, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 4, 0, 0, 1, 0x67])
        bytes.append(contentsOf: [0x20, 0, 0, 0, 0, 0, 0, 42, 0, 0, 0, 4, 0, 0, 1, 0x65])
        var decoder = ScrcpyVideoDecoder()
        var records: [MediaRecord] = []
        var sizes: [Int] = []
        for byte in bytes {
            for event in try decoder.append(Data([byte])) {
                switch event {
                case let .dimensions(width, height): sizes = [width, height]
                case let .record(record): records.append(record)
                }
            }
        }
        #expect(sizes == [1080, 1920])
        #expect(records.map(\.kind) == [0, 2])
        #expect(records.last?.presentationTimeMicroseconds == 42)
        let configuration = try JSONDecoder().decode(JSONValue.self, from: records[0].data)
        #expect(configuration["csd-0"].string == Data([0, 0, 1, 0x67]).base64EncodedString())
    }

    /// Exercises oversized frame is rejected before allocating payload through the expected result and relevant rejection assertions.
    @Test func oversizedFrameIsRejectedBeforeAllocatingPayload() throws {
        var bytes = Data(repeating: 0, count: 64)
        bytes.append(contentsOf: [0x68, 0x32, 0x36, 0x34])
        bytes.append(contentsOf: [0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0])
        var decoder = ScrcpyVideoDecoder()
        #expect(throws: ConnectionProtocolError.self) { try decoder.append(bytes) }
    }

    /// Exercises touch packets use the video coordinate space and stay bounded through the expected result and relevant rejection assertions.
    @Test func touchPacketsUseTheVideoCoordinateSpaceAndStayBounded() throws {
        let touch = try ScrcpyControlMessage.touch(action: 0, x: 2, y: -1, width: 1080, height: 1920)
        #expect(touch.count == 32)
        #expect(Array(touch[10..<18]) == [0, 0, 4, 55, 0, 0, 0, 0])
        #expect(throws: ConnectionProtocolError.self) { try ScrcpyControlMessage.touch(action: 0, x: .nan, y: 0, width: 1080, height: 1920) }
        #expect(ScrcpyControlMessage.key(code: 4, isDown: true).count == 14)
        #expect(ScrcpyControlMessage.text(String(repeating: "🌸", count: 100)).count == 305)
    }
}
