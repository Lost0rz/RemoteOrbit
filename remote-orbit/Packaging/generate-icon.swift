import AppKit
import Foundation

guard CommandLine.arguments.count == 3 else {
    FileHandle.standardError.write(
        Data("usage: generate-icon.swift OUTPUT.png SOURCE.svg\n".utf8)
    )
    exit(64)
}

let outputURL = URL(fileURLWithPath: CommandLine.arguments[1])
let sourceURL = URL(fileURLWithPath: CommandLine.arguments[2])
let size = 1_024

guard let sourceImage = NSImage(contentsOf: sourceURL) else {
    FileHandle.standardError.write(
        Data("unable to load canonical SVG: \(sourceURL.path)\n".utf8)
    )
    exit(1)
}

guard let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: size,
    pixelsHigh: size,
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bitmapFormat: [],
    bytesPerRow: size * 4,
    bitsPerPixel: 32
) else {
    FileHandle.standardError.write(Data("unable to create bitmap\n".utf8))
    exit(1)
}

guard let graphicsContext = NSGraphicsContext(bitmapImageRep: bitmap) else {
    FileHandle.standardError.write(Data("unable to create graphics context\n".utf8))
    exit(1)
}

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = graphicsContext
graphicsContext.imageInterpolation = NSImageInterpolation.high
NSColor.clear.setFill()
NSRect(x: 0, y: 0, width: size, height: size).fill()
sourceImage.draw(
    in: NSRect(x: 0, y: 0, width: size, height: size),
    from: NSRect(origin: .zero, size: sourceImage.size),
    operation: .sourceOver,
    fraction: 1.0
)
NSGraphicsContext.restoreGraphicsState()

guard let data = bitmap.representation(using: .png, properties: [:]) else {
    FileHandle.standardError.write(Data("unable to encode icon PNG\n".utf8))
    exit(1)
}
try data.write(to: outputURL, options: .atomic)
