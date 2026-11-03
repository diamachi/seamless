import AppKit
import CryptoKit
import ImageIO
import UniformTypeIdentifiers

@MainActor
final class PhoneWallpaperStore: ObservableObject {
    @Published private(set) var images: [String: NSImage] = [:]
    @Published private(set) var errors: [String: String] = [:]
    private var loadedPhoneIDs: Set<String> = []
    private let directory: URL

    init(directory: URL = URL.applicationSupportDirectory.appending(path: "Seamless/Wallpapers", directoryHint: .isDirectory)) {
        self.directory = directory
    }

    func load(phoneID: String) {
        guard loadedPhoneIDs.insert(phoneID).inserted else { return }
        let url = imageURL(phoneID: phoneID)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        do {
            let data = try Data(contentsOf: url)
            images[phoneID] = try thumbnail(from: data)
        } catch {
            errors[phoneID] = "Choose the wallpaper again to restore its preview."
        }
    }

    func choose(phoneID: String) {
        let panel = NSOpenPanel()
        panel.title = "Choose this phone’s wallpaper"
        panel.prompt = "Use wallpaper"
        panel.allowedContentTypes = [.image]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let source = panel.url else { return }
        do {
            try importImage(from: source, phoneID: phoneID)
        } catch {
            errors[phoneID] = "Choose a readable image smaller than 20 MiB."
        }
    }

    func importImage(from source: URL, phoneID: String) throws {
        let size = try source.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size > 0, size <= 20 * 1024 * 1024 else { throw WallpaperError.invalidImage }
        let data = try Data(contentsOf: source)
        guard data.count <= 20 * 1024 * 1024 else { throw WallpaperError.invalidImage }
        let image = try thumbnail(from: data)
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let jpeg = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.9]) else {
            throw WallpaperError.invalidImage
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try jpeg.write(to: imageURL(phoneID: phoneID), options: .atomic)
        loadedPhoneIDs.insert(phoneID)
        images[phoneID] = image
        errors.removeValue(forKey: phoneID)
    }

    func remove(phoneID: String) {
        do {
            let url = imageURL(phoneID: phoneID)
            if FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.removeItem(at: url)
            }
            images.removeValue(forKey: phoneID)
            errors.removeValue(forKey: phoneID)
            loadedPhoneIDs.remove(phoneID)
        } catch {
            errors[phoneID] = "The saved preview could not be removed."
        }
    }

    private func imageURL(phoneID: String) -> URL {
        let name = SHA256.hash(data: Data(phoneID.utf8)).map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent(name).appendingPathExtension("jpg")
    }

    private func thumbnail(from data: Data) throws -> NSImage {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { throw WallpaperError.invalidImage }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 1200
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw WallpaperError.invalidImage
        }
        return NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
    }
}

private enum WallpaperError: Error {
    case invalidImage
}
