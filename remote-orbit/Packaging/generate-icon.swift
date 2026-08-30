import AppKit
import CoreGraphics
import Foundation

guard CommandLine.arguments.count == 2 else {
    FileHandle.standardError.write(Data("usage: generate-icon.swift OUTPUT.png\n".utf8))
    exit(64)
}

let outputURL = URL(fileURLWithPath: CommandLine.arguments[1])
let size = 1_024
let width = size
let height = size
let colorSpace = CGColorSpaceCreateDeviceRGB()

guard let context = CGContext(
    data: nil,
    width: width,
    height: height,
    bitsPerComponent: 8,
    bytesPerRow: width * 4,
    space: colorSpace,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else {
    FileHandle.standardError.write(Data("unable to create bitmap context\n".utf8))
    exit(1)
}

let bounds = CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height))
let cyan = CGColor(red: 0.20, green: 0.86, blue: 1.00, alpha: 1.0)
let violet = CGColor(red: 0.45, green: 0.34, blue: 1.00, alpha: 1.0)
let indigo = CGColor(red: 0.10, green: 0.08, blue: 0.27, alpha: 1.0)
let graphite = CGColor(red: 0.035, green: 0.045, blue: 0.09, alpha: 1.0)
let white = CGColor(red: 0.97, green: 0.99, blue: 1.00, alpha: 1.0)

func withAlpha(_ color: CGColor, _ alpha: CGFloat) -> CGColor {
    color.copy(alpha: alpha)!
}

// Dark rounded tile, designed to remain legible in both light and dark menu bars.
let tile = bounds.insetBy(dx: 24, dy: 24)
let tilePath = CGPath(
    roundedRect: tile,
    cornerWidth: 206,
    cornerHeight: 206,
    transform: nil
)
context.addPath(tilePath)
context.clip()
let background = CGGradient(
    colorsSpace: colorSpace,
    colors: [graphite, indigo] as CFArray,
    locations: [0.0, 1.0]
)
context.drawLinearGradient(
    background!,
    start: CGPoint(x: 120, y: 920),
    end: CGPoint(x: 920, y: 120),
    options: []
)
context.resetClip()

// A soft accent glow behind the orbit.
context.saveGState()
context.setShadow(offset: .zero, blur: 54, color: withAlpha(cyan, 0.26))
context.setStrokeColor(withAlpha(cyan, 0.15))
context.setLineWidth(18)
context.strokeEllipse(in: CGRect(x: 128, y: 232, width: 768, height: 560))
context.restoreGState()

// Orbit ring: the visual cue for a remote that can switch between modes/apps.
context.saveGState()
context.translateBy(x: 512, y: 512)
context.rotate(by: -0.34)
context.setStrokeColor(withAlpha(cyan, 0.94))
context.setLineWidth(38)
context.setLineCap(.round)
context.strokeEllipse(in: CGRect(x: -360, y: -208, width: 720, height: 416))
context.restoreGState()

// Secondary arc gives the icon a sense of motion without becoming a waveform logo.
context.saveGState()
context.translateBy(x: 512, y: 512)
context.rotate(by: 0.62)
context.setStrokeColor(withAlpha(violet, 0.96))
context.setLineWidth(26)
context.setLineCap(.round)
context.addArc(
    center: .zero,
    radius: 318,
    startAngle: .pi * 0.14,
    endAngle: .pi * 0.72,
    clockwise: false
)
context.strokePath()
context.restoreGState()

func fillCircle(at center: CGPoint, radius: CGFloat, color: CGColor) {
    context.setFillColor(color)
    context.fillEllipse(in: CGRect(
        x: center.x - radius,
        y: center.y - radius,
        width: radius * 2,
        height: radius * 2
    ))
}

// Three orbit nodes represent shortcuts, app templates, and future modes.
fillCircle(at: CGPoint(x: 228, y: 365), radius: 34, color: violet)
fillCircle(at: CGPoint(x: 796, y: 676), radius: 34, color: cyan)
fillCircle(at: CGPoint(x: 810, y: 324), radius: 27, color: violet)
fillCircle(at: CGPoint(x: 228, y: 365), radius: 11, color: white)
fillCircle(at: CGPoint(x: 796, y: 676), radius: 11, color: white)
fillCircle(at: CGPoint(x: 810, y: 324), radius: 9, color: white)

// Central control surface: a compact remote/command node.
let remoteRect = CGRect(x: 397, y: 250, width: 230, height: 524)
let remotePath = CGPath(
    roundedRect: remoteRect,
    cornerWidth: 108,
    cornerHeight: 108,
    transform: nil
)
context.setShadow(offset: CGSize(width: 0, height: -10), blur: 26, color: .black.copy(alpha: 0.42))
context.addPath(remotePath)
context.setFillColor(white)
context.fillPath()
context.setShadow(offset: .zero, blur: 0, color: nil)

fillCircle(at: CGPoint(x: 512, y: 626), radius: 55, color: indigo)
fillCircle(at: CGPoint(x: 512, y: 626), radius: 19, color: cyan)
fillCircle(at: CGPoint(x: 512, y: 436), radius: 16, color: violet)
context.setStrokeColor(withAlpha(indigo, 0.22))
context.setLineWidth(16)
context.strokeEllipse(in: CGRect(x: 445, y: 340, width: 134, height: 134))

guard let image = context.makeImage() else {
    FileHandle.standardError.write(Data("unable to create icon image\n".utf8))
    exit(1)
}
let bitmap = NSBitmapImageRep(cgImage: image)
guard let data = bitmap.representation(using: .png, properties: [:]) else {
    FileHandle.standardError.write(Data("unable to encode PNG\n".utf8))
    exit(1)
}
try data.write(to: outputURL, options: .atomic)
