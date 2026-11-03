import AVFoundation

import AppKit
import Foundation

let outputDirectory = URL(fileURLWithPath: CommandLine.arguments[1])
let isLight = CommandLine.arguments.dropFirst(2).first == "light"
let sizes = [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2)]
for (size, scale) in sizes {
    let pixels = size * scale
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    let bounds = NSRect(x: 0, y: 0, width: pixels, height: pixels)
    let background = bounds.insetBy(dx: bounds.width * 0.06, dy: bounds.height * 0.06)
    let backgroundColor: NSColor
    let symbolColor: NSColor
    if isLight {
        backgroundColor = NSColor(srgbRed: 0.96, green: 0.94, blue: 0.89, alpha: 1)
        symbolColor = NSColor(srgbRed: 0.42, green: 0.31, blue: 0.15, alpha: 1)
    } else {
        backgroundColor = NSColor(srgbRed: 0.13, green: 0.13, blue: 0.12, alpha: 1)
        symbolColor = NSColor(srgbRed: 0.89, green: 0.74, blue: 0.48, alpha: 1)
    }
    backgroundColor.setFill()
    NSBezierPath(roundedRect: background, xRadius: bounds.width * 0.19, yRadius: bounds.height * 0.19).fill()
    let configuration = NSImage.SymbolConfiguration(paletteColors: [symbolColor])
    let symbol = NSImage(systemSymbolName: "point.3.connected.trianglepath.dotted", accessibilityDescription: nil)!.withSymbolConfiguration(configuration)!
    let available = bounds.insetBy(dx: bounds.width * 0.23, dy: bounds.height * 0.23)
    let fitted = AVMakeRect(aspectRatio: symbol.size, insideRect: available)
    symbol.draw(in: fitted)
    NSGraphicsContext.restoreGraphicsState()
    let suffix = scale == 2 ? "@2x" : ""
    try bitmap.representation(using: .png, properties: [:])!.write(to: outputDirectory.appendingPathComponent("icon_\(size)x\(size)\(suffix).png"))
}
