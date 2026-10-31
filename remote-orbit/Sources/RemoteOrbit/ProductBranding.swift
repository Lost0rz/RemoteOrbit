// ProductBranding.swift — RemoteOrbit product identity and shared UI

import AppKit
import SwiftUI

enum ProductIdentity {
    static let name = "RemoteOrbit"
    static let shortName = "RemoteOrbit"
    static let tagline = "Your remote. Your actions. Your Mac."
    static let defaultVersion = "0.2.10"
    static let defaultBuild = "36"
    static let bundleIdentifier = "com.lost0rz.RemoteOrbit"

    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            ?? defaultVersion
    }

    static var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
            ?? defaultBuild
    }

    static var versionLabel: String {
        "Version \(version) · Build \(build)"
    }
}

/// Canonical small-size RemoteOrbit mark used by the macOS menu bar.
/// Geometry matches `remote-orbit/Brand/RemoteOrbitMark.svg`: one tilted orbit
/// with a compact vertical remote passing in front of it.
enum ProductBrandMark {
    static func menuBarTemplateImage(size: CGFloat = 18) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }

            context.saveGState()
            defer { context.restoreGState() }

            let scale = min(rect.width, rect.height) / 256.0
            context.translateBy(x: rect.midX - 128 * scale, y: rect.midY - 128 * scale)
            context.scaleBy(x: scale, y: scale)

            context.setStrokeColor(NSColor.black.cgColor)
            context.setFillColor(NSColor.black.cgColor)
            context.setLineCap(.round)
            context.setLineJoin(.round)

            // Orbit ring.
            context.saveGState()
            context.translateBy(x: 128, y: 128)
            context.rotate(by: -18 * .pi / 180)
            context.setLineWidth(18)
            context.strokeEllipse(in: CGRect(x: -102, y: -58, width: 204, height: 116))
            context.restoreGState()

            // Remote body. Drawing it after the orbit gives a clear front/back
            // relationship at menu-bar sizes.
            let remoteRect = CGRect(x: 91, y: 47, width: 74, height: 162)
            let remotePath = CGPath(
                roundedRect: remoteRect,
                cornerWidth: 37,
                cornerHeight: 37,
                transform: nil
            )
            context.addPath(remotePath)
            context.fillPath()

            // Transparent control cut-outs preserve recognizability in template
            // rendering without introducing a second color.
            context.setBlendMode(.clear)
            context.fillEllipse(in: CGRect(x: 116, y: 83, width: 24, height: 24))
            context.fillEllipse(in: CGRect(x: 121, y: 136, width: 14, height: 14))

            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = ProductIdentity.name
        return image
    }
}

struct ProductTitleBar: View {
    var body: some View {
        HStack(spacing: 12) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .interpolation(.high)
                .frame(width: 42, height: 42)
                .accessibilityLabel(ProductIdentity.name)

            VStack(alignment: .leading, spacing: 2) {
                Text(ProductIdentity.name)
                    .font(.headline.weight(.semibold))
                Text(ProductIdentity.tagline)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text("Independent control center")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.primary)
                Text(ProductIdentity.versionLabel)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}
