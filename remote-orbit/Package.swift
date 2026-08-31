// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "RemoteOrbit",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "RemoteOrbit",
            path: "Sources/RemoteOrbit"
        ),
        .testTarget(
            name: "RemoteOrbitTests",
            dependencies: ["RemoteOrbit"],
            path: "Tests/RemoteOrbitTests"
        )
    ]
)
