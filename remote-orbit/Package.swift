// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "RemoteOrbit",
    platforms: [.macOS(.v13)],
    targets: [
        .target(
            name: "RemoteOrbitHIDBridge",
            path: "Sources/RemoteOrbitHIDBridge",
            publicHeadersPath: "include",
            cxxSettings: [
                .unsafeFlags(["-std=c++23"]),
                .headerSearchPath("vendor/upstream/include"),
                .headerSearchPath("vendor/upstream/vendor/vendor/include")
            ]
        ),
        .target(
            name: "RemoteOrbitHIDHelper",
            dependencies: ["RemoteOrbitHIDBridge"],
            path: "Sources/RemoteOrbitHIDHelper"
        ),
        .executableTarget(
            name: "RemoteOrbitHIDHelperDaemon",
            dependencies: ["RemoteOrbitHIDBridge", "RemoteOrbitHIDHelper"],
            path: "Sources/RemoteOrbitHIDHelperDaemon"
        ),
        .executableTarget(
            name: "RemoteOrbit",
            dependencies: ["RemoteOrbitHIDBridge", "RemoteOrbitHIDHelper"],
            path: "Sources/RemoteOrbit"
        ),
        .testTarget(
            name: "RemoteOrbitTests",
            dependencies: ["RemoteOrbit", "RemoteOrbitHIDBridge", "RemoteOrbitHIDHelper"],
            path: "Tests/RemoteOrbitTests"
        )
    ]
)
