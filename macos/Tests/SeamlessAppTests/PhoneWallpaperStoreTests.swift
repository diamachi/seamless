import AppKit
import Testing
@testable import SeamlessApp

@MainActor
struct PhoneWallpaperStoreTests {
    @Test
    func selectedWallpapersStayWithTheirPhoneAndSurviveReload() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let source = directory.appendingPathComponent("fixture.png")
        let bitmap = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 4, pixelsHigh: 8,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        for x in 0..<4 {
            for y in 0..<8 {
                bitmap.setColor(NSColor(deviceRed: 0.2, green: 0.6, blue: 0.5, alpha: 1), atX: x, y: y)
            }
        }
        try #require(bitmap.representation(using: .png, properties: [:])).write(to: source)
        let storage = directory.appendingPathComponent("wallpapers")
        let store = PhoneWallpaperStore(directory: storage)
        try store.importImage(from: source, phoneID: "phone-a")
        #expect(store.images["phone-a"] != nil)
        #expect(store.images["phone-b"] == nil)
        let restored = PhoneWallpaperStore(directory: storage)
        restored.load(phoneID: "phone-a")
        restored.load(phoneID: "phone-b")
        #expect(restored.images["phone-a"] != nil)
        #expect(restored.images["phone-b"] == nil)
        restored.remove(phoneID: "phone-a")
        #expect(FileManager.default.fileExists(atPath: source.path))
        #expect(try FileManager.default.contentsOfDirectory(atPath: storage.path).isEmpty)
    }
}
