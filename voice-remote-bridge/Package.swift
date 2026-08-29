// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "VoiceRemoteBridge",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "VoiceRemoteBridge",
            path: "Sources/VoiceRemoteBridge"
        )
    ]
)
