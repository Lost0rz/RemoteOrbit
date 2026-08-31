// ProductBranding.swift — RemoteOrbit product identity and shared UI

import AppKit
import SwiftUI

enum ProductIdentity {
    static let name = "RemoteOrbit"
    static let shortName = "RemoteOrbit"
    static let tagline = "Your remote. Your actions. Your Mac."
    static let defaultVersion = "0.2.4"
    static let defaultBuild = "7"
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

struct ProductTitleBar: View {
    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.accentColor,
                                Color.accentColor.opacity(0.72),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                Image(systemName: "circle.dotted.and.circle")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: 42, height: 42)

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
