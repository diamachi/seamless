import Foundation
import Testing
@testable import SeamlessCore

struct MediaProtocolTests {
    @Test
    func mediaRecordsHandleSplitHeadersAndPayloads() throws {
        var wire = Data([2, 0, 0, 0, 3, 0, 0, 0, 0, 0, 0, 0, 42])
        wire.append(contentsOf: [7, 8, 9])
        var decoder = MediaRecordDecoder()
        #expect(try decoder.append(Data(wire.prefix(8))).isEmpty)
        let records = try decoder.append(Data(wire.dropFirst(8)))
        #expect(records.count == 1)
        #expect(records[0].kind == 2)
        #expect(records[0].presentationTimeMicroseconds == 42)
        #expect(records[0].data == Data([7, 8, 9]))
    }

    @Test
    func oversizedMediaIsRejectedBeforeWaitingForPayload() throws {
        var decoder = MediaRecordDecoder()
        let header = Data([1, 127, 255, 255, 255, 0, 0, 0, 0, 0, 0, 0, 0])
        #expect(throws: ConnectionProtocolError.self) { _ = try decoder.append(header) }
    }

    @Test
    func annexBHandlesBothStartCodesWithoutIncludingThemInSamples() throws {
        let source = Data([0, 0, 0, 1, 0x67, 5, 0, 0, 1, 0x68, 9])
        #expect(H264ByteStream.nalUnits(in: source) == [Data([0x67, 5]), Data([0x68, 9])])
        #expect(try H264ByteStream.lengthPrefixed(source) == Data([0, 0, 0, 2, 0x67, 5, 0, 0, 0, 2, 0x68, 9]))
        #expect(throws: ConnectionProtocolError.self) { _ = try H264ByteStream.lengthPrefixed(Data([5, 6, 7])) }
    }
}
